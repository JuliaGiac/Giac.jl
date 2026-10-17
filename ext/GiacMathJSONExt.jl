# Extension module for MathJSON.jl integration
# Provides bidirectional conversion between GiacExpr/GiacMatrix and MathJSON expression types
# Requires the GIAC C++ wrapper library

module GiacMathJSONExt

using Giac
using MathJSON
using CxxWrap: StdVector

# ============================================================================
# Bidirectional Operator Mapping: GIAC <-> MathJSON
# ============================================================================

const GIAC_TO_MATHJSON = Dict{String, Symbol}(
    # --- Arithmetic operators ---
    "+"         => :Add,
    "*"         => :Multiply,
    "-"         => :Subtract,
    "/"         => :Divide,
    "^"         => :Power,
    "mod"       => :Mod,

    # --- Arithmetic functions ---
    "abs"       => :Abs,
    "sign"      => :Sign,
    "floor"     => :Floor,
    "ceil"      => :Ceil,
    "round"     => :Round,
    "trunc"     => :Truncate,
    "max"       => :Max,
    "min"       => :Min,
    "sqrt"      => :Sqrt,
    "exp"       => :Exp,
    "factorial" => :Factorial,
    "hypot"     => :Hypot,

    # --- Logarithmic functions ---
    "ln"        => :Ln,
    "log10"     => :Log10,
    "log"       => :Ln,

    # --- Trigonometric functions ---
    "sin"       => :Sin,
    "cos"       => :Cos,
    "tan"       => :Tan,
    "cot"       => :Cot,
    "sec"       => :Sec,
    "csc"       => :Csc,

    # --- Inverse trigonometric functions ---
    "asin"      => :Arcsin,
    "acos"      => :Arccos,
    "atan"      => :Arctan,
    "acot"      => :Arccot,

    # --- Hyperbolic functions ---
    "sinh"      => :Sinh,
    "cosh"      => :Cosh,
    "tanh"      => :Tanh,
    "coth"      => :Coth,

    # --- Inverse hyperbolic functions ---
    "asinh"     => :Arsinh,
    "acosh"     => :Arcosh,
    "atanh"     => :Artanh,

    # --- Complex number functions ---
    "re"        => :Real,
    "im"        => :Imaginary,
    "conj"      => :Conjugate,
    "arg"       => :Argument,

    # --- Number theory ---
    "gcd"       => :GCD,
    "lcm"       => :LCM,
    "isprime"   => :IsPrime,
    "binomial"  => :Binomial,
    "fibonacci" => :Fibonacci,

    # --- Special functions ---
    "Gamma"     => :Gamma,
    "beta"      => :Beta,
    "erf"       => :Erf,
    "erfc"      => :Erfc,
    "zeta"      => :Zeta,
    "Ai"        => :AiryAi,
    "Bi"        => :AiryBi,
    "BesselJ"   => :BesselJ,
    "BesselY"   => :BesselY,
    "BesselI"   => :BesselI,
    "BesselK"   => :BesselK,
    "digamma"   => :Digamma,
    "Heaviside" => :Heaviside,

    # --- Linear algebra ---
    "det"       => :Determinant,
    "inv"       => :Inverse,
    "trace"     => :Trace,
    "transpose" => :Transpose,
    "tran"      => :Transpose,
    "rank"      => :Rank,
    "diag"      => :Diagonal,
    "eigenvalues"  => :Eigenvalues,
    "eigenvectors" => :Eigenvectors,
    "norm"      => :Norm,
    "kernel"    => :Kernel,

    # --- Algebra / symbolic ---
    "factor"    => :Factor,
    "expand"    => :Expand,
    "simplify"  => :Simplify,
    "normal"    => :Together,

    # --- Calculus ---
    "diff"      => :D,
    "integrate" => :Integrate,
    "limit"     => :Limit,
    "sum"       => :Sum,
    "product"   => :Product,

    # --- Relational operators ---
    "=="        => :Equal,
    "="         => :Equal,
    "!="        => :NotEqual,
    "<"         => :Less,
    "<="        => :LessEqual,
    ">"         => :Greater,
    ">="        => :GreaterEqual,

    # --- Logic ---
    "and"       => :And,
    "or"        => :Or,
    "not"       => :Not,

    # --- Statistics ---
    "mean"      => :Mean,
    "median"    => :Median,
    "variance"  => :Variance,
    "stddev"    => :StandardDeviation,
    "quartiles" => :Quartiles,

    # --- Collection operations ---
    "sort"      => :Sort,
    "reverse"   => :Reverse,
)

# Reverse mapping: MathJSON operator -> GIAC function name
const MATHJSON_TO_GIAC = Dict{Symbol, String}(
    # --- Arithmetic operators ---
    :Add        => "+",
    :Multiply   => "*",
    :Subtract   => "-",
    :Negate     => "-",
    :Divide     => "/",
    :Power      => "^",
    :Mod        => "mod",

    # --- Arithmetic functions ---
    :Abs        => "abs",
    :Sign       => "sign",
    :Floor      => "floor",
    :Ceil       => "ceil",
    :Round      => "round",
    :Truncate   => "trunc",
    :Max        => "max",
    :Min        => "min",
    :Sqrt       => "sqrt",
    :Exp        => "exp",
    :Factorial  => "factorial",
    :Hypot      => "hypot",

    # --- Logarithmic functions ---
    :Ln         => "ln",
    :Log        => "ln",
    :Log10      => "log10",

    # --- Trigonometric functions ---
    :Sin        => "sin",
    :Cos        => "cos",
    :Tan        => "tan",
    :Cot        => "cot",
    :Sec        => "sec",
    :Csc        => "csc",

    # --- Inverse trigonometric functions ---
    :Arcsin     => "asin",
    :Arccos     => "acos",
    :Arctan     => "atan",
    :Arctan2    => "atan2",
    :Arccot     => "acot",

    # --- Hyperbolic functions ---
    :Sinh       => "sinh",
    :Cosh       => "cosh",
    :Tanh       => "tanh",
    :Coth       => "coth",

    # --- Inverse hyperbolic functions ---
    :Arsinh     => "asinh",
    :Arcosh     => "acosh",
    :Artanh     => "atanh",

    # --- Complex number functions ---
    :Real       => "re",
    :Imaginary  => "im",
    :Conjugate  => "conj",
    :Argument   => "arg",

    # --- Number theory ---
    :GCD        => "gcd",
    :LCM        => "lcm",
    :IsPrime    => "isprime",
    :Binomial   => "binomial",
    :Choose     => "binomial",
    :Fibonacci  => "fibonacci",
    :Numerator  => "numerator",
    :Denominator => "denominator",

    # --- Special functions ---
    :Gamma      => "Gamma",
    :Beta       => "beta",
    :Erf        => "erf",
    :Erfc       => "erfc",
    :Zeta       => "zeta",
    :AiryAi     => "Ai",
    :AiryBi     => "Bi",
    :BesselJ    => "BesselJ",
    :BesselY    => "BesselY",
    :BesselI    => "BesselI",
    :BesselK    => "BesselK",
    :Digamma    => "digamma",
    :Heaviside  => "Heaviside",

    # --- Linear algebra ---
    :Determinant      => "det",
    :Inverse          => "inv",
    :Trace            => "trace",
    :Transpose        => "transpose",
    :Rank             => "rank",
    :Diagonal         => "diag",
    :Eigenvalues      => "eigenvalues",
    :Eigenvectors     => "eigenvectors",
    :Norm             => "norm",
    :Kernel           => "kernel",

    # --- Algebra / symbolic ---
    :Factor     => "factor",
    :Expand     => "expand",
    :ExpandAll  => "expand",
    :Simplify   => "simplify",
    :Together   => "normal",
    :Cancel     => "normal",

    # --- Calculus ---
    :D          => "diff",
    :Derivative => "diff",
    :Integrate  => "integrate",
    :Limit      => "limit",
    :Sum        => "sum",
    :Product    => "product",

    # --- Relational operators ---
    :Equal        => "=",
    :NotEqual     => "!=",
    :Less         => "<",
    :LessEqual    => "<=",
    :Greater      => ">",
    :GreaterEqual => ">=",

    # --- Logic ---
    :And        => "and",
    :Or         => "or",
    :Not        => "not",

    # --- Statistics ---
    :Mean       => "mean",
    :Median     => "median",
    :Variance   => "variance",
    :StandardDeviation => "stddev",
    :Quartiles  => "quartiles",

    # --- Collection operations ---
    :Sort       => "sort",
    :Reverse    => "reverse",

    # --- Evaluation ---
    :N          => "evalf",
)

# Constant name mapping: GIAC identifier -> MathJSON symbol name
const GIAC_CONST_TO_MATHJSON = Dict{String, String}(
    "pi" => "Pi",
    "π"  => "Pi",
    "e"  => "ExponentialE",
    "i"  => "ImaginaryUnit",
)

const MATHJSON_CONST_TO_GIAC = Dict{String, String}(
    "Pi"              => "pi",
    "ExponentialE"    => "e",
    "ImaginaryUnit"   => "i",
    "True"            => "true",
    "False"           => "false",
)

# ============================================================================
# BigInt GMP Helper Functions
# ============================================================================

"""
    _bytes_to_bigint(bytes::Vector{UInt8}, sign::Int32) -> BigInt

Construct a BigInt from raw bytes and sign using direct GMP ccall.
"""
function _bytes_to_bigint(bytes::Vector{UInt8}, sign::Int32)::BigInt
    if isempty(bytes) || sign == 0
        return BigInt(0)
    end
    result = BigInt()
    ccall((:__gmpz_import, Base.GMP.libgmp), Cvoid,
          (Ref{BigInt}, Csize_t, Cint, Csize_t, Cint, Csize_t, Ptr{UInt8}),
          result, length(bytes), 1, 1, 1, 0, bytes)
    if sign < 0
        ccall((:__gmpz_neg, Base.GMP.libgmp), Cvoid,
              (Ref{BigInt}, Ref{BigInt}), result, result)
    end
    return result
end

"""
    _bigint_to_gen(n::BigInt) -> Gen

Convert a Julia BigInt to a GIAC Gen using direct GMP binary transfer.
"""
function _bigint_to_gen(n::BigInt)
    if n == 0
        return Giac.GiacCxxBindings.Gen(Int32(0))
    end
    n_sign = Int32(Base.sign(n))
    abs_n = abs(n)
    bit_count = ccall((:__gmpz_sizeinbase, Base.GMP.libgmp), Csize_t,
                      (Ref{BigInt}, Cint), abs_n, 2)
    byte_count = div(bit_count + 7, 8)
    bytes = Vector{UInt8}(undef, byte_count)
    actual_count = Ref{Csize_t}(0)
    ccall((:__gmpz_export, Base.GMP.libgmp), Ptr{Cvoid},
          (Ptr{UInt8}, Ref{Csize_t}, Cint, Csize_t, Cint, Csize_t, Ref{BigInt}),
          bytes, actual_count, 1, 1, 1, 0, abs_n)
    if actual_count[] < byte_count
        resize!(bytes, actual_count[])
    end
    std_bytes = StdVector{UInt8}(bytes)
    return Giac.GiacCxxBindings.make_zint_from_bytes(std_bytes, n_sign)
end

# ============================================================================
# Core Conversion: GIAC Gen -> MathJSON
# ============================================================================

"""
    _gen_to_mathjson(gen) -> AbstractMathJSONExpr

Recursively convert a CxxWrap Gen object to a MathJSON expression tree.
"""
function _gen_to_mathjson(gen)::AbstractMathJSONExpr
    t = Giac.GenTypes.T(Giac.GiacCxxBindings.type(gen))

    if t == Giac.GenTypes.INT
        return NumberExpr(Int64(Giac.GiacCxxBindings.to_int64(gen)))

    elseif t == Giac.GenTypes.DOUBLE
        return NumberExpr(Float64(Giac.GiacCxxBindings.to_double(gen)))

    elseif t == Giac.GenTypes.ZINT
        bytes = Vector{UInt8}(Giac.GiacCxxBindings.zint_to_bytes(gen))
        sign = Int32(Giac.GiacCxxBindings.zint_sign(gen))
        val = _bytes_to_bigint(bytes, sign)
        # Use raw string for BigInt to preserve precision
        return NumberExpr(val)

    elseif t == Giac.GenTypes.FRAC
        num_gen = Giac.GiacCxxBindings.frac_num(gen)
        den_gen = Giac.GiacCxxBindings.frac_den(gen)
        return FunctionExpr(:Rational, AbstractMathJSONExpr[
            _gen_to_mathjson(num_gen),
            _gen_to_mathjson(den_gen),
        ])

    elseif t == Giac.GenTypes.CPLX
        re_gen = Giac.GiacCxxBindings.cplx_re(gen)
        im_gen = Giac.GiacCxxBindings.cplx_im(gen)
        return FunctionExpr(:Complex, AbstractMathJSONExpr[
            _gen_to_mathjson(re_gen),
            _gen_to_mathjson(im_gen),
        ])

    elseif t == Giac.GenTypes.IDNT
        name = String(Giac.GiacCxxBindings.idnt_name(gen))
        mathjson_name = get(GIAC_CONST_TO_MATHJSON, name, name)
        return SymbolExpr(mathjson_name)

    elseif t == Giac.GenTypes.SYMB
        op_name = String(Giac.GiacCxxBindings.symb_sommet_name(gen))
        feuille = Giac.GiacCxxBindings.symb_feuille(gen)
        feuille_type = Giac.GenTypes.T(Giac.GiacCxxBindings.type(feuille))

        # Get arguments list
        args_gen = if feuille_type == Giac.GenTypes.VECT
            n = Giac.GiacCxxBindings.vect_size(feuille)
            [Giac.GiacCxxBindings.vect_at(feuille, i - 1) for i in 1:n]
        else
            [feuille]
        end

        # Convert arguments recursively
        args_mathjson = AbstractMathJSONExpr[_gen_to_mathjson(a) for a in args_gen]

        # Handle unary minus -> Negate
        if op_name == "-" && length(args_mathjson) == 1
            return FunctionExpr(:Negate, args_mathjson)
        end

        # Handle x^(1/2) -> Sqrt(x) (GIAC represents sqrt as power)
        if op_name == "^" && length(args_mathjson) == 2
            exp_arg = args_mathjson[2]
            if exp_arg isa FunctionExpr && exp_arg.operator == :Rational &&
               length(exp_arg.arguments) == 2 &&
               exp_arg.arguments[1] isa NumberExpr && exp_arg.arguments[1].value == 1 &&
               exp_arg.arguments[2] isa NumberExpr && exp_arg.arguments[2].value == 2
                return FunctionExpr(:Sqrt, AbstractMathJSONExpr[args_mathjson[1]])
            end
        end

        # Handle inv(x) -> Power(x, -1) for scalars, Inverse(x) for matrices
        if op_name == "inv" && length(args_mathjson) == 1
            arg = args_mathjson[1]
            if arg isa FunctionExpr && arg.operator == :List
                return FunctionExpr(:Inverse, args_mathjson)
            else
                return FunctionExpr(:Power, AbstractMathJSONExpr[arg, NumberExpr(-1)])
            end
        end

        # Look up operator mapping
        mathjson_op = get(GIAC_TO_MATHJSON, op_name, nothing)
        if mathjson_op !== nothing
            return FunctionExpr(mathjson_op, args_mathjson)
        end

        # Fallback: use PascalCase version of GIAC name
        fallback_op = Symbol(uppercasefirst(op_name))
        return FunctionExpr(fallback_op, args_mathjson)

    elseif t == Giac.GenTypes.VECT
        n = Giac.GiacCxxBindings.vect_size(gen)
        elements = AbstractMathJSONExpr[
            _gen_to_mathjson(Giac.GiacCxxBindings.vect_at(gen, i - 1)) for i in 1:n
        ]
        return FunctionExpr(:List, elements)

    else
        error("Unsupported GIAC type '$(t)' (code $(Int(t))) in to_mathjson conversion")
    end
end

# ============================================================================
# Core Conversion: MathJSON -> GIAC Gen
# ============================================================================

"""
    _mathjson_to_gen(expr::NumberExpr) -> Gen

Convert a MathJSON NumberExpr to a GIAC Gen.
"""
function _mathjson_to_gen(expr::NumberExpr)
    val = expr.value
    if val isa Int64
        if typemin(Int32) <= val <= typemax(Int32)
            return Giac.GiacCxxBindings.Gen(Int32(val))
        else
            return Giac.GiacCxxBindings.Gen(string(val))
        end
    elseif val isa Float64
        return Giac.GiacCxxBindings.Gen(val)
    elseif val isa BigFloat
        return Giac.GiacCxxBindings.Gen(string(val))
    elseif val isa Rational
        num_gen = _mathjson_to_gen(NumberExpr(Int64(numerator(val))))
        den_gen = _mathjson_to_gen(NumberExpr(Int64(denominator(val))))
        return Giac.GiacCxxBindings.make_fraction(num_gen, den_gen)
    elseif val isa BigInt
        return _bigint_to_gen(val)
    else
        return Giac.GiacCxxBindings.Gen(string(val))
    end
end

"""
    _mathjson_to_gen(expr::SymbolExpr) -> Gen

Convert a MathJSON SymbolExpr to a GIAC Gen.
"""
function _mathjson_to_gen(expr::SymbolExpr)
    name = expr.name
    # Handle special constants that GIAC represents as expressions, not identifiers
    if name == "ExponentialE"
        # GIAC represents e as exp(1)
        one_gen = Giac.GiacCxxBindings.Gen(Int32(1))
        args_vec = StdVector{Giac.GiacCxxBindings.Gen}([one_gen])
        return Giac.GiacCxxBindings.make_symbolic_unevaluated("exp", args_vec)
    elseif name == "ImaginaryUnit"
        # GIAC represents i as complex(0, 1)
        zero_gen = Giac.GiacCxxBindings.Gen(Int32(0))
        one_gen = Giac.GiacCxxBindings.Gen(Int32(1))
        return Giac.GiacCxxBindings.make_complex(zero_gen, one_gen)
    end
    giac_name = get(MATHJSON_CONST_TO_GIAC, name, name)
    return Giac.GiacCxxBindings.make_identifier(giac_name)
end

"""
    _mathjson_to_gen(expr::FunctionExpr) -> Gen

Convert a MathJSON FunctionExpr to a GIAC Gen.
"""
function _mathjson_to_gen(expr::FunctionExpr)
    op = expr.operator
    args = expr.arguments

    # Handle special structural operators
    if op == :Rational && length(args) == 2
        num_gen = _mathjson_to_gen(args[1])
        den_gen = _mathjson_to_gen(args[2])
        return Giac.GiacCxxBindings.make_fraction(num_gen, den_gen)
    elseif op == :Complex && length(args) == 2
        re_gen = _mathjson_to_gen(args[1])
        im_gen = _mathjson_to_gen(args[2])
        return Giac.GiacCxxBindings.make_complex(re_gen, im_gen)
    elseif op == :List
        gen_elements = [_mathjson_to_gen(a) for a in args]
        args_vec = StdVector{Giac.GiacCxxBindings.Gen}(gen_elements)
        return Giac.GiacCxxBindings.make_vect(args_vec, 0)
    elseif op == :Negate && length(args) == 1
        # Unary minus
        arg_gen = _mathjson_to_gen(args[1])
        gen_args = [arg_gen]
        args_vec = StdVector{Giac.GiacCxxBindings.Gen}(gen_args)
        return Giac.GiacCxxBindings.make_symbolic_unevaluated("-", args_vec)
    end

    # Relational operators: build via string eval since make_symbolic_unevaluated
    # doesn't support =, ==, !=, <, <=, >, >=
    relational_ops = Dict{Symbol,String}(
        :Equal => "=", :NotEqual => "!=",
        :Less => "<", :LessEqual => "<=",
        :Greater => ">", :GreaterEqual => ">=",
    )
    if haskey(relational_ops, op) && length(args) == 2
        giac_op_str = relational_ops[op]
        lhs = Giac.GiacExpr(Giac._gen_to_ptr(_mathjson_to_gen(args[1])))
        rhs = Giac.GiacExpr(Giac._gen_to_ptr(_mathjson_to_gen(args[2])))
        return Giac.GiacCxxBindings.giac_eval("($(string(lhs)))$(giac_op_str)($(string(rhs)))")
    end

    # Look up GIAC operator name
    giac_op = get(MATHJSON_TO_GIAC, op, nothing)

    if giac_op === nothing
        # Unsupported operator: warn and fallback to string eval
        op_str = string(op)
        @warn "Unsupported MathJSON operator '$op_str' — using fallback string representation"
        arg_strs = [string(Giac.GiacExpr(Giac._gen_to_ptr(_mathjson_to_gen(a)))) for a in args]
        fallback_str = lowercase(op_str) * "(" * join(arg_strs, ",") * ")"
        return Giac.GiacCxxBindings.giac_eval(fallback_str)
    end

    # Convert arguments recursively
    gen_args = [_mathjson_to_gen(a) for a in args]
    args_vec = StdVector{Giac.GiacCxxBindings.Gen}(gen_args)
    return Giac.GiacCxxBindings.make_symbolic_unevaluated(giac_op, args_vec)
end

# ============================================================================
# Public API: to_mathjson
# ============================================================================

"""
    to_mathjson(expr::GiacExpr) -> AbstractMathJSONExpr

Convert a GiacExpr to a MathJSON expression tree.

Uses direct tree traversal via CxxWrap Gen introspection for efficient
conversion without string serialization.

# Examples
```julia
using Giac, MathJSON
@giac_var x
to_mathjson(x^2 + 1)          # FunctionExpr(:Add, ...)
to_mathjson(giac_eval("42"))   # NumberExpr(42)
to_mathjson(giac_eval("pi"))   # SymbolExpr("Pi")
```
"""
function Giac.to_mathjson(expr::GiacExpr)::AbstractMathJSONExpr
    gen = Giac._ptr_to_gen(expr)
    return _gen_to_mathjson(gen)
end

"""
    to_mathjson(m::GiacMatrix) -> AbstractMathJSONExpr

Convert a GiacMatrix to a MathJSON Matrix expression.

# Examples
```julia
using Giac, MathJSON
m = giac_matrix([[1, 2], [3, 4]])
to_mathjson(m)  # FunctionExpr(:Matrix, [FunctionExpr(:List, ...), ...])
```
"""
function Giac.to_mathjson(m::GiacMatrix)::AbstractMathJSONExpr
    rows, cols = size(m)
    row_exprs = AbstractMathJSONExpr[]
    for i in 1:rows
        elements = AbstractMathJSONExpr[]
        for j in 1:cols
            push!(elements, Giac.to_mathjson(m[i, j]))
        end
        push!(row_exprs, FunctionExpr(:List, elements))
    end
    return FunctionExpr(:Matrix, row_exprs)
end

# ============================================================================
# Public API: to_giac
# ============================================================================

"""
    to_giac(expr::NumberExpr) -> GiacExpr

Convert a MathJSON NumberExpr to a GiacExpr.
"""
function Giac.to_giac(expr::NumberExpr)::GiacExpr
    gen = _mathjson_to_gen(expr)
    ptr = Giac._gen_to_ptr(gen)
    return GiacExpr(ptr)
end

"""
    to_giac(expr::SymbolExpr) -> GiacExpr

Convert a MathJSON SymbolExpr to a GiacExpr.
"""
function Giac.to_giac(expr::SymbolExpr)::GiacExpr
    gen = _mathjson_to_gen(expr)
    ptr = Giac._gen_to_ptr(gen)
    return GiacExpr(ptr)
end

"""
    to_giac(expr::FunctionExpr) -> GiacExpr

Convert a MathJSON FunctionExpr to a GiacExpr.

# Examples
```julia
using Giac, MathJSON
expr = FunctionExpr(:Add, [SymbolExpr("x"), NumberExpr(1)])
to_giac(expr)  # GiacExpr: x+1
```
"""
function Giac.to_giac(expr::FunctionExpr)::GiacExpr
    gen = _mathjson_to_gen(expr)
    ptr = Giac._gen_to_ptr(gen)
    return GiacExpr(ptr)
end

"""
    to_giac(expr::StringExpr) -> GiacExpr

StringExpr cannot be converted to GiacExpr. Throws an error.
"""
function Giac.to_giac(expr::StringExpr)::GiacExpr
    error("StringExpr cannot be converted to GiacExpr")
end

# Export conversion functions
export to_giac, to_mathjson

end # module GiacMathJSONExt
