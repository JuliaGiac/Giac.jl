# Low-level wrapper for libgiac-julia-wrapper
# Provides CxxWrap bindings to the GIAC library

using CxxWrap
using Libdl
using libcxxwrap_julia_jll
using libgiac_julia_jll
using GIAC_jll

# Library path storage
const _wrapper_lib_path = Ref{String}("")

"""
    find_wrapper_library()

Find the libgiac_wrapper shared library.
Checks GIAC_WRAPPER_LIB environment variable first, then common locations.
"""
function find_wrapper_library()
    # Check environment variable first
    env_path = get(ENV, "GIAC_WRAPPER_LIB", "")
    if !isempty(env_path)
        if isfile(env_path)
            return env_path
        end
        # Try as directory
        for name in ["libgiac_wrapper.so", "libgiac_wrapper.dylib", "giac_wrapper.dll"]
            full_path = joinpath(env_path, name)
            if isfile(full_path)
                return full_path
            end
        end
    end

    # Try JLL package
    if libgiac_julia_jll.is_available()
        jll_path = libgiac_julia_jll.libgiac_wrapper_path
        if isfile(jll_path)
            return jll_path
        end
    end

    # Try common locations relative to this package
    pkg_root = dirname(dirname(@__FILE__))
    possible_paths = [
        joinpath(pkg_root, "deps", "libgiac_wrapper.so"),
        joinpath(pkg_root, "deps", "lib", "libgiac_wrapper.so"),
        joinpath(pkg_root, "build", "src", "libgiac_wrapper.so"),
        # System paths
        "/usr/local/lib/libgiac_wrapper.so",
        "/usr/lib/libgiac_wrapper.so",
    ]

    # Also check the parent giac directory (for development)
    giac_root = dirname(dirname(pkg_root))  # Up from Giac.jl
    push!(possible_paths, joinpath(giac_root, "libgiac-julia-wrapper", "build", "src", "libgiac_wrapper.so"))

    for path in possible_paths
        if isfile(path)
            return path
        end
    end

    return ""
end

# Flag to track initialization state
const _initialized = Ref{Bool}(false)

# Keep references to library handles to prevent unloading
# IMPORTANT: These must remain open for the entire process lifetime
const _giac_lib_handle = Ref{Ptr{Cvoid}}(C_NULL)
const _cxxwrap_lib_handle = Ref{Ptr{Cvoid}}(C_NULL)
const _wrapper_lib_handle = Ref{Ptr{Cvoid}}(C_NULL)

# CxxWrap module for GIAC bindings
# The @wrapmodule macro must be called at compile time, so we need the library
# path available then via environment variable.
module GiacCxxBindings
    using CxxWrap
    using Libdl
    using libcxxwrap_julia_jll
    using libgiac_julia_jll
    using GIAC_jll

    # Get library path at compile time: env var first, then JLL
    const _compile_time_lib_path = let
        env_path = get(ENV, "GIAC_WRAPPER_LIB", "")
        if !isempty(env_path) && isfile(env_path)
            env_path
        elseif libgiac_julia_jll.is_available()
            libgiac_julia_jll.libgiac_wrapper_path
        else
            ""
        end
    end
    const _have_library = !isempty(_compile_time_lib_path) && isfile(_compile_time_lib_path)

    # Storage for library handles (to prevent GC/unload)
    const _giac_handle = Ref{Ptr{Cvoid}}(C_NULL)
    const _cxxwrap_handle = Ref{Ptr{Cvoid}}(C_NULL)

    # Helper function to find libgiac
    function _find_giac_lib(wrapper_path::String)
        # Try GIAC_jll first
        if GIAC_jll.is_available()
            return GIAC_jll.libgiac_path
        end
        # Search near the wrapper library
        wrapper_dir = dirname(wrapper_path)
        for giac_name in ["libgiac.so", "libgiac.so.0", "libgiac.so.1", "libgiac.dylib"]
            for parent in [wrapper_dir, dirname(wrapper_dir), dirname(dirname(wrapper_dir))]
                # Check GIAC 2.0.0 location first, then fallback locations
                for subdir in ["", "lib", "../giac-2.0.0/src/.libs", "build_julia", "../giac/build_julia"]
                    test_path = joinpath(parent, subdir, giac_name)
                    if isfile(test_path)
                        return test_path
                    end
                end
            end
        end
        return "libgiac.so"  # Fall back to system search
    end

    if _have_library
        # Pre-load dependencies with RTLD_GLOBAL AT COMPILE TIME
        # This is CRITICAL: CxxWrap's @wrapmodule internally calls dlopen to
        # introspect the library structure. Without RTLD_GLOBAL on libgiac.so,
        # the wrapper library can't resolve its GIAC symbols.

        # Find and load libgiac first
        _giac_lib_path = _find_giac_lib(_compile_time_lib_path)
        _giac_handle[] = Libdl.dlopen(_giac_lib_path, Libdl.RTLD_NOW | Libdl.RTLD_GLOBAL)

        # Load libcxxwrap_julia with RTLD_GLOBAL
        _cxxwrap_handle[] = Libdl.dlopen(libcxxwrap_julia_jll.libcxxwrap_julia, Libdl.RTLD_NOW | Libdl.RTLD_GLOBAL)

        # Now CxxWrap can load the wrapper module and introspect it
        @wrapmodule(() -> _compile_time_lib_path, :define_julia_module)

        function __init__()
            # At runtime, re-load dependencies with RTLD_GLOBAL BEFORE @initcxx
            # The compile-time handles don't persist across precompilation

            giac_lib_path = _find_giac_lib(_compile_time_lib_path)

            # Load libgiac with RTLD_GLOBAL first
            _giac_handle[] = Libdl.dlopen(giac_lib_path, Libdl.RTLD_NOW | Libdl.RTLD_GLOBAL)

            # Load libcxxwrap_julia with RTLD_GLOBAL
            _cxxwrap_handle[] = Libdl.dlopen(libcxxwrap_julia_jll.libcxxwrap_julia, Libdl.RTLD_NOW | Libdl.RTLD_GLOBAL)

            # Now initialize CxxWrap - this will load the wrapper and resolve symbols
            @initcxx
        end
    else
        # Stubs when library not available at compile time
        giac_version() = "stub"
        wrapper_version() = "stub"
        is_giac_available() = false
    end
end

"""
    _init_xcasroot(wrapper_lib_path)

Initialize the xcasroot path for GIAC help file support.
Searches for share/giac directory relative to the wrapper library location.
"""
function _init_xcasroot(wrapper_lib_path::String)
    # Try to find share/giac directory
    wrapper_dir = dirname(wrapper_lib_path)

    # Search patterns for share/giac (relative to wrapper lib)
    search_paths = [
        # Development layout: wrapper is in libgiac-julia-wrapper/build/src/
        # aide_cas is in giac-2.0.0/doc/
        joinpath(dirname(dirname(dirname(wrapper_dir))), "giac-2.0.0", "doc"),
        joinpath(dirname(dirname(dirname(wrapper_dir))), "giac-2.0.0", "install", "share", "giac"),
        # Installed layout: share/giac is sibling to lib
        joinpath(dirname(wrapper_dir), "share", "giac"),
        joinpath(dirname(dirname(wrapper_dir)), "share", "giac"),
        # JLL layout: artifact_dir/share/giac
        joinpath(dirname(dirname(dirname(wrapper_dir))), "share", "giac"),
    ]

    # Check GIAC_jll (direct dependency)
    if GIAC_jll.is_available()
        jll_aide_cas = GIAC_jll.aide_cas_path
        jll_share = dirname(jll_aide_cas)
        pushfirst!(search_paths, jll_share)
    end

    for path in search_paths
        aide_cas_path = joinpath(path, "aide_cas")
        if isfile(aide_cas_path)
            # Path must end with / for GIAC's xcasroot
            xcasroot_path = path * "/"
            GiacCxxBindings.set_xcasroot(xcasroot_path)
            # Pre-initialize help database to avoid fallback error messages
            if GiacCxxBindings.init_help(aide_cas_path)
                @debug "GIAC help initialized from $aide_cas_path"
            end
            return
        end
    end

    @warn "Could not find GIAC aide_cas help file. Help commands may not work."
end

"""
    init_giac_library()

Initialize the GIAC library. Called automatically during module __init__.

Loads the libgiac-julia-wrapper shared library using CxxWrap.

# Throws
- `GiacError`: If library loading or initialization fails
"""
function init_giac_library()
    if _initialized[]
        return
    end

    lib_path = find_wrapper_library()

    if isempty(lib_path)
        throw(GiacError("GIAC wrapper library not found. " *
              "Set GIAC_WRAPPER_LIB environment variable to the library path."))
    end

    # Store the path
    _wrapper_lib_path[] = lib_path

    # Check if CxxWrap bindings were loaded at compile time
    if GiacCxxBindings._have_library
        _initialized[] = true
        @info "GIAC wrapper library loaded from $lib_path"

        # Initialize xcasroot for help file support
        _init_xcasroot(lib_path)

        # Cache the invoke_cmd fast-path kill-switch env var (069-invoke-cmd-fastpath)
        _refresh_fastpath_flag!()
    else
        # Library found at runtime but not at compile time
        # CxxWrap requires the library at compile time for @wrapmodule
        throw(GiacError("GIAC library found at runtime but was not available at compile time. " *
              "Set GIAC_WRAPPER_LIB=$lib_path and restart Julia to enable CxxWrap bindings."))
    end
end

# ============================================================================
# Gen object storage and pointer management
# ============================================================================

# Gen object storage for CxxWrap bindings
const _gen_objects = Dict{UInt, Any}()  # CxxWrap Gen objects keyed by ID
const _gen_counter = Ref{UInt}(0)

# Shared CxxWrap context for evaluation (lazily initialized)
const _cxxwrap_context = Ref{Any}(nothing)

function _get_cxxwrap_context()
    if _cxxwrap_context[] === nothing && GiacCxxBindings._have_library
        _cxxwrap_context[] = GiacCxxBindings.GiacContext()
    end
    return _cxxwrap_context[]
end

# Store a CxxWrap Gen object and return a handle pointer
function _make_gen_ptr(gen)::Ptr{Cvoid}
    _gen_counter[] += 1
    id = _gen_counter[]
    _gen_objects[id] = gen
    return Ptr{Cvoid}(id)
end

# Retrieve a stored Gen object, or nothing if not found
function _get_gen(ptr::Ptr{Cvoid})
    return get(_gen_objects, UInt(ptr), nothing)
end

# Get string representation of the expression stored at ptr
function _get_expr_string(ptr::Ptr{Cvoid})::String
    gen = _get_gen(ptr)
    if gen !== nothing
        return String(GiacCxxBindings.to_string(gen))
    end
    return "<unknown>"
end

# ---------------------------------------------------------------------------
# Per-context evaluation
#
# A `GiacContext` used to be a sentinel: every evaluation funnelled into the
# one process-wide `giac::context` from `_get_cxxwrap_context()`, so a `:=`
# binding made through one context was visible from every other. The wrapper
# gained a context-aware entry point (libgiac-julia-wrapper#3); this is what
# passes the context through.
#
# Note which overload: `giac_eval(ctx, str)` returns a `std::string` and
# loses the gen. `giac_eval(str, ctx)` returns a `Gen`, which is what we need.
#
# `_SHARED_CONTEXT_PTR` keeps the old behaviour for `DEFAULT_CONTEXT` and for
# anything that does not name a context. That is deliberate: the tier-1 paths,
# introspection and the conversion helpers re-parse printed expressions
# through `GiacCxxBindings.giac_eval(str)`, which lands in the process-wide
# context. Moving the default elsewhere would split the package in two.
# ---------------------------------------------------------------------------

const _SHARED_CONTEXT_PTR = Ptr{Cvoid}(1)

const _context_objects = Dict{UInt, Any}()  # CxxWrap GiacContext objects by ID
const _context_counter = Ref{UInt}(1)       # 1 is _SHARED_CONTEXT_PTR

"""
    _new_giac_context() -> Ptr{Cvoid}

Create a C++ `giac::context` owned by the caller and return a handle for it.
Falls back to the shared sentinel when the library is unavailable.
"""
function _new_giac_context()::Ptr{Cvoid}
    GiacCxxBindings._have_library || return _SHARED_CONTEXT_PTR
    _context_counter[] += 1
    id = _context_counter[]
    _context_objects[id] = GiacCxxBindings.GiacContext()
    return Ptr{Cvoid}(id)
end

# The C++ context behind a handle, or `nothing` for the shared one.
function _get_context(ptr::Ptr{Cvoid})
    ptr == _SHARED_CONTEXT_PTR && return nothing
    return get(_context_objects, UInt(ptr), nothing)
end

function _giac_eval_string(expr::String, ctx_ptr::Ptr{Cvoid})::Ptr{Cvoid}
    ctx = _get_context(ctx_ptr)
    gen = ctx === nothing ? GiacCxxBindings.giac_eval(expr) :
                            GiacCxxBindings.giac_eval(expr, ctx)
    return _make_gen_ptr(gen)
end

"""
    _gen_to_ptr(gen) -> Ptr{Cvoid}

Convert a CxxWrap Gen to a pointer for GiacExpr.
Used by to_giac in Symbolics extension.
"""
function _gen_to_ptr(gen)::Ptr{Cvoid}
    return _make_gen_ptr(gen)
end

function _giac_expr_to_string(ptr::Ptr{Cvoid})::String
    return _get_expr_string(ptr)
end

function _giac_free_expr(ptr::Ptr{Cvoid})
    if ptr == C_NULL
        return
    end
    delete!(_gen_objects, UInt(ptr))
    nothing
end

function _giac_free_context(ptr::Ptr{Cvoid})
    if ptr == C_NULL || ptr == _SHARED_CONTEXT_PTR
        return
    end
    # Dropping the last reference lets CxxWrap destroy the giac::context.
    delete!(_context_objects, UInt(ptr))
    nothing
end

function _giac_expr_type(ptr::Ptr{Cvoid})::Symbol
    expr_str = _giac_expr_to_string(ptr)
    # Try to detect type from string representation
    # Integer: only digits, possibly with leading minus
    if occursin(r"^-?\d+$", expr_str)
        return :integer
    # Rational: digits/digits
    elseif occursin(r"^-?\d+/-?\d+$", expr_str)
        return :rational
    # Float: digits with decimal point
    elseif occursin(r"^-?\d+\.\d+$", expr_str)
        return :float
    # Complex: contains i or I
    elseif occursin(r"\bi\b", expr_str) || occursin(r"\bI\b", expr_str)
        return :complex
    else
        return :symbolic
    end
end

function _giac_to_int64(ptr::Ptr{Cvoid})::Int64
    expr_str = _giac_expr_to_string(ptr)
    # Handle GIAC boolean representations
    if expr_str == "true"
        return Int64(1)
    elseif expr_str == "false"
        return Int64(0)
    end
    return parse(Int64, expr_str)
end

function _giac_to_float64(ptr::Ptr{Cvoid})::Float64
    expr_str = _giac_expr_to_string(ptr)
    return parse(Float64, expr_str)
end

function _giac_complex_real(ptr::Ptr{Cvoid})::Float64
    try
        expr_str = _giac_expr_to_string(ptr)
        gen = GiacCxxBindings.giac_eval(expr_str)
        # Use cplx_re accessor
        re_gen = GiacCxxBindings.cplx_re(gen)
        re_str = GiacCxxBindings.to_string(re_gen)
        return parse(Float64, re_str)
    catch e
        @debug "Complex real extraction failed: $e"
        return 0.0
    end
end

function _giac_complex_imag(ptr::Ptr{Cvoid})::Float64
    try
        expr_str = _giac_expr_to_string(ptr)
        gen = GiacCxxBindings.giac_eval(expr_str)
        # Use cplx_im accessor
        im_gen = GiacCxxBindings.cplx_im(gen)
        im_str = GiacCxxBindings.to_string(im_gen)
        return parse(Float64, im_str)
    catch e
        @debug "Complex imag extraction failed: $e"
        return 0.0
    end
end

function _giac_rational_num(ptr::Ptr{Cvoid})::Int64
    try
        expr_str = _giac_expr_to_string(ptr)
        gen = GiacCxxBindings.giac_eval(expr_str)
        # Use frac_num accessor
        num_gen = GiacCxxBindings.frac_num(gen)
        num_str = GiacCxxBindings.to_string(num_gen)
        return parse(Int64, num_str)
    catch e
        @debug "Rational numerator extraction failed: $e"
        # Fallback to string parsing
        expr_str = _giac_expr_to_string(ptr)
        parts = split(expr_str, "/")
        if length(parts) == 2
            return parse(Int64, parts[1])
        end
    end
    return 0
end

function _giac_rational_den(ptr::Ptr{Cvoid})::Int64
    try
        expr_str = _giac_expr_to_string(ptr)
        gen = GiacCxxBindings.giac_eval(expr_str)
        # Use frac_den accessor
        den_gen = GiacCxxBindings.frac_den(gen)
        den_str = GiacCxxBindings.to_string(den_gen)
        return parse(Int64, den_str)
    catch e
        @debug "Rational denominator extraction failed: $e"
        # Fallback to string parsing
        expr_str = _giac_expr_to_string(ptr)
        parts = split(expr_str, "/")
        if length(parts) == 2
            return parse(Int64, parts[2])
        end
    end
    return 1
end

# Matrix operations
function _giac_free_matrix(ptr::Ptr{Cvoid})
    if ptr == C_NULL
        return
    end
    nothing
end

function _giac_gcd(a_ptr::Ptr{Cvoid}, b_ptr::Ptr{Cvoid}, ctx_ptr::Ptr{Cvoid})::Ptr{Cvoid}
    a_str = _giac_expr_to_string(a_ptr)
    b_str = _giac_expr_to_string(b_ptr)
    return _giac_eval_string("gcd($a_str, $b_str)", ctx_ptr)
end

# ============================================================================
# Arithmetic operations - use string-based GIAC evaluation
# ============================================================================

function _giac_add(a_ptr::Ptr{Cvoid}, b_ptr::Ptr{Cvoid}, ctx_ptr::Ptr{Cvoid})::Ptr{Cvoid}
    a_str = _giac_expr_to_string(a_ptr)
    b_str = _giac_expr_to_string(b_ptr)
    return _giac_eval_string("($a_str)+($b_str)", ctx_ptr)
end

function _giac_sub(a_ptr::Ptr{Cvoid}, b_ptr::Ptr{Cvoid}, ctx_ptr::Ptr{Cvoid})::Ptr{Cvoid}
    a_str = _giac_expr_to_string(a_ptr)
    b_str = _giac_expr_to_string(b_ptr)
    return _giac_eval_string("($a_str)-($b_str)", ctx_ptr)
end

function _giac_mul(a_ptr::Ptr{Cvoid}, b_ptr::Ptr{Cvoid}, ctx_ptr::Ptr{Cvoid})::Ptr{Cvoid}
    a_str = _giac_expr_to_string(a_ptr)
    b_str = _giac_expr_to_string(b_ptr)
    return _giac_eval_string("($a_str)*($b_str)", ctx_ptr)
end

function _giac_div(a_ptr::Ptr{Cvoid}, b_ptr::Ptr{Cvoid}, ctx_ptr::Ptr{Cvoid})::Ptr{Cvoid}
    a_str = _giac_expr_to_string(a_ptr)
    b_str = _giac_expr_to_string(b_ptr)
    return _giac_eval_string("($a_str)/($b_str)", ctx_ptr)
end

function _giac_pow(a_ptr::Ptr{Cvoid}, b_ptr::Ptr{Cvoid}, ctx_ptr::Ptr{Cvoid})::Ptr{Cvoid}
    a_str = _giac_expr_to_string(a_ptr)
    b_str = _giac_expr_to_string(b_ptr)
    return _giac_eval_string("($a_str)^($b_str)", ctx_ptr)
end

function _giac_neg(a_ptr::Ptr{Cvoid}, ctx_ptr::Ptr{Cvoid})::Ptr{Cvoid}
    a_str = _giac_expr_to_string(a_ptr)
    return _giac_eval_string("-($a_str)", ctx_ptr)
end

function _giac_equal(a_ptr::Ptr{Cvoid}, b_ptr::Ptr{Cvoid}, ctx_ptr::Ptr{Cvoid})::Bool
    a_str = _giac_expr_to_string(a_ptr)
    b_str = _giac_expr_to_string(b_ptr)
    # Use GIAC's simplify to check equality: simplify(a - b) == 0
    result = _giac_eval_string("simplify(($a_str)-($b_str))", ctx_ptr)
    result_str = _giac_expr_to_string(result)
    return result_str == "0"
end

# ============================================================================
# Matrix operations - use string-based GIAC evaluation
# ============================================================================

function _giac_matrix_mul(a_ptr::Ptr{Cvoid}, b_ptr::Ptr{Cvoid}, ctx_ptr::Ptr{Cvoid})::Ptr{Cvoid}
    a_str = _giac_expr_to_string(a_ptr)
    b_str = _giac_expr_to_string(b_ptr)
    return _giac_eval_string("($a_str)*($b_str)", ctx_ptr)
end

function _giac_matrix_add(a_ptr::Ptr{Cvoid}, b_ptr::Ptr{Cvoid}, ctx_ptr::Ptr{Cvoid})::Ptr{Cvoid}
    a_str = _giac_expr_to_string(a_ptr)
    b_str = _giac_expr_to_string(b_ptr)
    return _giac_eval_string("($a_str)+($b_str)", ctx_ptr)
end

function _giac_matrix_sub(a_ptr::Ptr{Cvoid}, b_ptr::Ptr{Cvoid}, ctx_ptr::Ptr{Cvoid})::Ptr{Cvoid}
    a_str = _giac_expr_to_string(a_ptr)
    b_str = _giac_expr_to_string(b_ptr)
    return _giac_eval_string("($a_str)-($b_str)", ctx_ptr)
end

function _giac_matrix_scalar_mul(m_ptr::Ptr{Cvoid}, scalar_ptr::Ptr{Cvoid}, ctx_ptr::Ptr{Cvoid})::Ptr{Cvoid}
    m_str = _giac_expr_to_string(m_ptr)
    s_str = _giac_expr_to_string(scalar_ptr)
    return _giac_eval_string("($s_str)*($m_str)", ctx_ptr)
end

function _giac_matrix_transpose(m_ptr::Ptr{Cvoid}, ctx_ptr::Ptr{Cvoid})::Ptr{Cvoid}
    m_str = _giac_expr_to_string(m_ptr)
    return _giac_eval_string("tran($m_str)", ctx_ptr)
end

function _giac_matrix_det(m_ptr::Ptr{Cvoid}, ctx_ptr::Ptr{Cvoid})::Ptr{Cvoid}
    m_str = _giac_expr_to_string(m_ptr)
    return _giac_eval_string("det($m_str)", ctx_ptr)
end

function _giac_matrix_inv(m_ptr::Ptr{Cvoid}, ctx_ptr::Ptr{Cvoid})::Ptr{Cvoid}
    m_str = _giac_expr_to_string(m_ptr)
    return _giac_eval_string("inv($m_str)", ctx_ptr)
end

function _giac_matrix_trace(m_ptr::Ptr{Cvoid}, ctx_ptr::Ptr{Cvoid})::Ptr{Cvoid}
    m_str = _giac_expr_to_string(m_ptr)
    return _giac_eval_string("trace($m_str)", ctx_ptr)
end

function _giac_create_matrix(expr::String, rows::Int, cols::Int, ctx_ptr::Ptr{Cvoid})::Ptr{Cvoid}
    # Evaluate the matrix expression to normalize it
    return _giac_eval_string(expr, ctx_ptr)
end

function _giac_matrix_getindex(ptr::Ptr{Cvoid}, i::Int, j::Int)::Ptr{Cvoid}
    m_str = _giac_expr_to_string(ptr)
    # GIAC uses 0-based indexing, but we receive 0-based indices from Julia (already adjusted)
    return _giac_eval_string("($m_str)[$i][$j]", C_NULL)
end

function _giac_gcd(a_ptr::Ptr{Cvoid}, b_ptr::Ptr{Cvoid})::Ptr{Cvoid}
    return _giac_gcd(a_ptr, b_ptr, DEFAULT_CONTEXT[].ptr)
end

function _giac_add(a_ptr::Ptr{Cvoid}, b_ptr::Ptr{Cvoid})::Ptr{Cvoid}
    return _giac_add(a_ptr, b_ptr, DEFAULT_CONTEXT[].ptr)
end

function _giac_sub(a_ptr::Ptr{Cvoid}, b_ptr::Ptr{Cvoid})::Ptr{Cvoid}
    return _giac_sub(a_ptr, b_ptr, DEFAULT_CONTEXT[].ptr)
end

function _giac_mul(a_ptr::Ptr{Cvoid}, b_ptr::Ptr{Cvoid})::Ptr{Cvoid}
    return _giac_mul(a_ptr, b_ptr, DEFAULT_CONTEXT[].ptr)
end

function _giac_div(a_ptr::Ptr{Cvoid}, b_ptr::Ptr{Cvoid})::Ptr{Cvoid}
    return _giac_div(a_ptr, b_ptr, DEFAULT_CONTEXT[].ptr)
end

function _giac_pow(a_ptr::Ptr{Cvoid}, b_ptr::Ptr{Cvoid})::Ptr{Cvoid}
    return _giac_pow(a_ptr, b_ptr, DEFAULT_CONTEXT[].ptr)
end

function _giac_neg(a_ptr::Ptr{Cvoid})::Ptr{Cvoid}
    return _giac_neg(a_ptr, DEFAULT_CONTEXT[].ptr)
end

function _giac_equal(a_ptr::Ptr{Cvoid}, b_ptr::Ptr{Cvoid})::Bool
    return _giac_equal(a_ptr, b_ptr, DEFAULT_CONTEXT[].ptr)
end

function _giac_matrix_det(m_ptr::Ptr{Cvoid})::Ptr{Cvoid}
    return _giac_matrix_det(m_ptr, DEFAULT_CONTEXT[].ptr)
end

function _giac_matrix_inv(m_ptr::Ptr{Cvoid})::Ptr{Cvoid}
    return _giac_matrix_inv(m_ptr, DEFAULT_CONTEXT[].ptr)
end

function _giac_matrix_trace(m_ptr::Ptr{Cvoid})::Ptr{Cvoid}
    return _giac_matrix_trace(m_ptr, DEFAULT_CONTEXT[].ptr)
end

function _giac_matrix_transpose(m_ptr::Ptr{Cvoid})::Ptr{Cvoid}
    return _giac_matrix_transpose(m_ptr, DEFAULT_CONTEXT[].ptr)
end

function _giac_matrix_mul(a_ptr::Ptr{Cvoid}, b_ptr::Ptr{Cvoid})::Ptr{Cvoid}
    return _giac_matrix_mul(a_ptr, b_ptr, DEFAULT_CONTEXT[].ptr)
end

function _giac_matrix_add(a_ptr::Ptr{Cvoid}, b_ptr::Ptr{Cvoid})::Ptr{Cvoid}
    return _giac_matrix_add(a_ptr, b_ptr, DEFAULT_CONTEXT[].ptr)
end

function _giac_matrix_sub(a_ptr::Ptr{Cvoid}, b_ptr::Ptr{Cvoid})::Ptr{Cvoid}
    return _giac_matrix_sub(a_ptr, b_ptr, DEFAULT_CONTEXT[].ptr)
end

function _giac_matrix_scalar_mul(m_ptr::Ptr{Cvoid}, scalar_ptr::Ptr{Cvoid})::Ptr{Cvoid}
    return _giac_matrix_scalar_mul(m_ptr, scalar_ptr, DEFAULT_CONTEXT[].ptr)
end

function _giac_create_matrix(expr::String, rows::Int, cols::Int)::Ptr{Cvoid}
    return _giac_create_matrix(expr, rows, cols, DEFAULT_CONTEXT[].ptr)
end

# ============================================================================
# Tier 1 High-Performance Wrappers
# These use the direct C++ Tier 1 functions (no name lookup overhead)
# ============================================================================

# Helper: retrieve stored Gen (or eval from string), apply function, store result Gen
function _tier1_unary(func::Function, expr_ptr::Ptr{Cvoid})::Ptr{Cvoid}
    try
        gen_arg = _get_gen(expr_ptr)
        if gen_arg === nothing
            gen_arg = GiacCxxBindings.giac_eval(_get_expr_string(expr_ptr))
        end
        result_gen = func(gen_arg)
        return _make_gen_ptr(result_gen)
    catch e
        @debug "Tier 1 function failed: $e"
    end
    return C_NULL
end

function _tier1_binary(func::Function, a_ptr::Ptr{Cvoid}, b_ptr::Ptr{Cvoid})::Ptr{Cvoid}
    try
        a_gen = _get_gen(a_ptr)
        if a_gen === nothing
            a_gen = GiacCxxBindings.giac_eval(_get_expr_string(a_ptr))
        end
        b_gen = _get_gen(b_ptr)
        if b_gen === nothing
            b_gen = GiacCxxBindings.giac_eval(_get_expr_string(b_ptr))
        end
        result_gen = func(a_gen, b_gen)
        return _make_gen_ptr(result_gen)
    catch e
        @debug "Tier 1 binary function failed: $e"
    end
    return C_NULL
end

function _tier1_ternary(func::Function, a_ptr::Ptr{Cvoid}, b_ptr::Ptr{Cvoid}, c_ptr::Ptr{Cvoid})::Ptr{Cvoid}
    try
        a_gen = _get_gen(a_ptr)
        if a_gen === nothing
            a_gen = GiacCxxBindings.giac_eval(_get_expr_string(a_ptr))
        end
        b_gen = _get_gen(b_ptr)
        if b_gen === nothing
            b_gen = GiacCxxBindings.giac_eval(_get_expr_string(b_ptr))
        end
        c_gen = _get_gen(c_ptr)
        if c_gen === nothing
            c_gen = GiacCxxBindings.giac_eval(_get_expr_string(c_ptr))
        end
        result_gen = func(a_gen, b_gen, c_gen)
        return _make_gen_ptr(result_gen)
    catch e
        @debug "Tier 1 ternary function failed: $e"
    end
    return C_NULL
end

# Trigonometry (Tier 1)
_giac_sin_tier1(expr_ptr::Ptr{Cvoid}) = _tier1_unary(GiacCxxBindings.giac_sin, expr_ptr)
_giac_cos_tier1(expr_ptr::Ptr{Cvoid}) = _tier1_unary(GiacCxxBindings.giac_cos, expr_ptr)
_giac_tan_tier1(expr_ptr::Ptr{Cvoid}) = _tier1_unary(GiacCxxBindings.giac_tan, expr_ptr)
_giac_asin_tier1(expr_ptr::Ptr{Cvoid}) = _tier1_unary(GiacCxxBindings.giac_asin, expr_ptr)
_giac_acos_tier1(expr_ptr::Ptr{Cvoid}) = _tier1_unary(GiacCxxBindings.giac_acos, expr_ptr)
_giac_atan_tier1(expr_ptr::Ptr{Cvoid}) = _tier1_unary(GiacCxxBindings.giac_atan, expr_ptr)

# Exponential/Logarithm (Tier 1)
_giac_exp_tier1(expr_ptr::Ptr{Cvoid}) = _tier1_unary(GiacCxxBindings.giac_exp, expr_ptr)
_giac_ln_tier1(expr_ptr::Ptr{Cvoid}) = _tier1_unary(GiacCxxBindings.giac_ln, expr_ptr)
_giac_log10_tier1(expr_ptr::Ptr{Cvoid}) = _tier1_unary(GiacCxxBindings.giac_log10, expr_ptr)
_giac_sqrt_tier1(expr_ptr::Ptr{Cvoid}) = _tier1_unary(GiacCxxBindings.giac_sqrt, expr_ptr)

# Arithmetic (Tier 1)
_giac_abs_tier1(expr_ptr::Ptr{Cvoid}) = _tier1_unary(GiacCxxBindings.giac_abs, expr_ptr)
_giac_sign_tier1(expr_ptr::Ptr{Cvoid}) = _tier1_unary(GiacCxxBindings.giac_sign, expr_ptr)
_giac_floor_tier1(expr_ptr::Ptr{Cvoid}) = _tier1_unary(GiacCxxBindings.giac_floor, expr_ptr)
_giac_ceil_tier1(expr_ptr::Ptr{Cvoid}) = _tier1_unary(GiacCxxBindings.giac_ceil, expr_ptr)

# Complex (Tier 1)
_giac_re_tier1(expr_ptr::Ptr{Cvoid}) = _tier1_unary(GiacCxxBindings.giac_re, expr_ptr)
_giac_im_tier1(expr_ptr::Ptr{Cvoid}) = _tier1_unary(GiacCxxBindings.giac_im, expr_ptr)
_giac_conj_tier1(expr_ptr::Ptr{Cvoid}) = _tier1_unary(GiacCxxBindings.giac_conj, expr_ptr)

# Algebra (Tier 1)
_giac_normal_tier1(expr_ptr::Ptr{Cvoid}) = _tier1_unary(GiacCxxBindings.giac_normal, expr_ptr)
_giac_evalf_tier1(expr_ptr::Ptr{Cvoid}) = _tier1_unary(GiacCxxBindings.giac_evalf, expr_ptr)

# Calculus (Tier 1 - binary/ternary)
_giac_diff_tier1(expr_ptr::Ptr{Cvoid}, var_ptr::Ptr{Cvoid}) = _tier1_binary(GiacCxxBindings.giac_diff, expr_ptr, var_ptr)
_giac_integrate_tier1(expr_ptr::Ptr{Cvoid}, var_ptr::Ptr{Cvoid}) = _tier1_binary(GiacCxxBindings.giac_integrate, expr_ptr, var_ptr)
_giac_subst_tier1(expr_ptr::Ptr{Cvoid}, var_ptr::Ptr{Cvoid}, val_ptr::Ptr{Cvoid}) = _tier1_ternary(GiacCxxBindings.giac_subst, expr_ptr, var_ptr, val_ptr)
_giac_solve_tier1(expr_ptr::Ptr{Cvoid}, var_ptr::Ptr{Cvoid}) = _tier1_binary(GiacCxxBindings.giac_solve, expr_ptr, var_ptr)
_giac_limit_tier1(expr_ptr::Ptr{Cvoid}, var_ptr::Ptr{Cvoid}, val_ptr::Ptr{Cvoid}) = _tier1_ternary(GiacCxxBindings.giac_limit, expr_ptr, var_ptr, val_ptr)
_giac_series_tier1(expr_ptr::Ptr{Cvoid}, var_ptr::Ptr{Cvoid}, order_ptr::Ptr{Cvoid}) = _tier1_ternary(GiacCxxBindings.giac_series, expr_ptr, var_ptr, order_ptr)

# Arithmetic binary (Tier 1)
_giac_gcd_tier1(a_ptr::Ptr{Cvoid}, b_ptr::Ptr{Cvoid}) = _tier1_binary(GiacCxxBindings.giac_gcd, a_ptr, b_ptr)
_giac_lcm_tier1(a_ptr::Ptr{Cvoid}, b_ptr::Ptr{Cvoid}) = _tier1_binary(GiacCxxBindings.giac_lcm, a_ptr, b_ptr)
_giac_pow_tier1(base_ptr::Ptr{Cvoid}, exp_ptr::Ptr{Cvoid}) = _tier1_binary(GiacCxxBindings.giac_pow, base_ptr, exp_ptr)

# ============================================================================
# Vector-argument substitution helpers (065-substitute-tier1)
# Used by substitute.jl to call giac_subst with structured Gen vector arguments
# instead of round-tripping through the GIAC parser.
# ============================================================================

# Resolve a GiacExpr to its CxxWrap Gen, falling back to giac_eval if no cached Gen.
function _get_gen_or_eval(expr::GiacExpr)
    g = _get_gen(expr.ptr)
    return g === nothing ? GiacCxxBindings.giac_eval(_get_expr_string(expr.ptr)) : g
end

# Resolve any value (GiacExpr or numeric/symbolic scalar) to a CxxWrap Gen.
# Non-GiacExpr values are routed through _arg_to_giac_string + giac_eval, matching
# the existing dict-form contract that accepts e.g. Dict(x => 2).
function _value_to_gen(v)
    return v isa GiacExpr ? _get_gen_or_eval(v) :
                            GiacCxxBindings.giac_eval(_arg_to_giac_string(v))
end

# Direct vector-argument substitution: calls GiacCxxBindings.giac_subst with
# _VECT_LIST_-typed Gen vectors built via make_vect, preserving simultaneous
# substitution semantics (e.g. swap Dict(x => y, y => x)) without going through
# the GIAC parser.
function _giac_subst_vec_tier1(expr::GiacExpr,
                               vars::AbstractVector{<:GiacExpr},
                               vals::AbstractVector)::GiacExpr
    expr_gen = _get_gen_or_eval(expr)
    var_gens = StdVector{GiacCxxBindings.Gen}()
    val_gens = StdVector{GiacCxxBindings.Gen}()
    for v in vars
        push!(var_gens, _get_gen_or_eval(v))
    end
    for w in vals
        push!(val_gens, _value_to_gen(w))
    end
    vars_vect = GiacCxxBindings.make_vect(var_gens, Int32(0))
    vals_vect = GiacCxxBindings.make_vect(val_gens, Int32(0))
    result_gen = with_giac_lock() do
        GiacCxxBindings.giac_subst(expr_gen, vars_vect, vals_vect)
    end
    return GiacExpr(_make_gen_ptr(result_gen))
end

# ============================================================================
# Direct Gen fast path for invoke_cmd (069-invoke-cmd-fastpath)
#
# Bypasses _arg_to_giac_string + _build_command_string + giac_eval when all
# arguments have a direct Gen representation. Routes to the specialized
# apply_func0/1/2/3 bindings (which return clean Gens) for arity 0-3, and to
# apply_funcN (with a StdVector{Gen}) for arity >= 4. Per empirical research
# R6, apply_funcN wraps arity-1 results in seq[...]; using the specialized
# bindings avoids that.
# ============================================================================

_has_direct_gen(::GiacExpr)        = true
_has_direct_gen(::Int32)           = true
_has_direct_gen(x::Int64)          = typemin(Int32) <= x <= typemax(Int32)
_has_direct_gen(x::Float64)        = isfinite(x)
_has_direct_gen(@nospecialize(_))  = false

_to_gen_direct(x::GiacExpr) = _get_gen_or_eval(x)
_to_gen_direct(x::Int32)    = GiacCxxBindings.Gen(x)
_to_gen_direct(x::Int64)    = GiacCxxBindings.Gen(Int32(x))
_to_gen_direct(x::Float64)  = GiacCxxBindings.Gen(x)

# Process-level kill switch. Cached at module init from GIAC_INVOKE_CMD_STRING_PATH.
const _fastpath_disabled = Ref{Bool}(false)

function _compute_fastpath_disabled()::Bool
    v = lowercase(get(ENV, "GIAC_INVOKE_CMD_STRING_PATH", ""))
    return v == "1" || v == "true" || v == "yes"
end

function _refresh_fastpath_flag!()::Bool
    _fastpath_disabled[] = _compute_fastpath_disabled()
    return _fastpath_disabled[]
end

function _invoke_cmd_direct(cmd::Symbol, args::Tuple)::GiacExpr
    name = string(cmd)
    @debug "invoke_cmd fast path" cmd=cmd nargs=length(args)
    n = length(args)
    result_gen = with_giac_lock() do
        if n == 0
            GiacCxxBindings.apply_func0(name)
        elseif n == 1
            GiacCxxBindings.apply_func1(name, _to_gen_direct(args[1]))
        elseif n == 2
            GiacCxxBindings.apply_func2(name,
                                        _to_gen_direct(args[1]),
                                        _to_gen_direct(args[2]))
        elseif n == 3
            GiacCxxBindings.apply_func3(name,
                                        _to_gen_direct(args[1]),
                                        _to_gen_direct(args[2]),
                                        _to_gen_direct(args[3]))
        else
            gens = StdVector{GiacCxxBindings.Gen}()
            for a in args
                push!(gens, _to_gen_direct(a))
            end
            GiacCxxBindings.apply_funcN(name, gens)
        end
    end
    return GiacExpr(_make_gen_ptr(result_gen))
end

# ============================================================================
# Rendering commands: argument holding (071-latex-render-form)
#
# GIAC evaluates command arguments, and some results are not fixed points of
# evaluation: `ifactor(360)` is the product `2^3*3^2*5`, which evaluates back
# to `360`. Rendering commands must typeset the expression they are handed, so
# each GiacExpr argument is wrapped in GIAC's `quote(...)` before dispatch.
# This works on both invoke_cmd paths: the fast path passes the quoted Gen
# straight to apply_func1, and the string path prints it as `'2^3*3^2*5'`,
# which the GIAC parser reads back as a quoted expression.
# ============================================================================

"""
    RENDER_COMMANDS

GIAC commands that typeset their argument instead of computing with it. Their
`GiacExpr` arguments are quoted by [`invoke_cmd`](@ref) so that GIAC renders
the expression as given rather than a re-evaluated copy of it.
"""
const RENDER_COMMANDS = (:latex, :mathml)

# Wrap a GiacExpr in GIAC's quote(...) without evaluating it.
function _quote_gen(expr::GiacExpr)::GiacExpr
    quoted_gen = with_giac_lock() do
        args = StdVector{GiacCxxBindings.Gen}()
        push!(args, _get_gen_or_eval(expr))
        GiacCxxBindings.make_symbolic_unevaluated("quote", args)
    end
    return GiacExpr(_make_gen_ptr(quoted_gen))
end

# Hold a single rendering-command argument. Only GiacExpr can carry an
# unevaluated GIAC tree; every other argument type is already a literal.
_hold_render_arg(x::GiacExpr) = _quote_gen(x)
_hold_render_arg(@nospecialize(x)) = x
