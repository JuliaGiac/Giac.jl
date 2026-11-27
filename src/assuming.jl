# Assumptions for one block (`assuming`), and the session settings that change results
# (`giac_settings`, `with_settings`).
#
# Scoped assumptions follow Kahli Burke's `ergonomics` branch. GIAC's assumptions and settings are
# global state: `assume(x > 0)` holds until `purge(x)`, and `complex_mode:=1` changes what
# `simplify(sqrt(x^2))` means for everything evaluated afterwards. Following MathInterchange's
# feedback, the block saves the state as GIAC holds it (`about(x)` for each variable, and every
# setting), and puts exactly that back when the block ends, after an error too. The GIAC lock is
# held for the whole block, so no other task sees the temporary state.

# ---------------------------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------------------------

# name in `giac_settings` => (GIAC command, Julia type)
const _SETTINGS = (
    complex_mode = (:complex_mode, Bool),
    approx_mode = (:approx_mode, Bool),
    angle_radian = (:angle_radian, Bool),
    complex_variables = (:complex_variables, Bool),
    epsilon = (:epsilon, Float64),
    digits = (:Digits, Int),
)

_read_setting(cmd::Symbol, ::Type{Bool}) = to_julia(giac_eval("$cmd()")) != 0
_read_setting(cmd::Symbol, ::Type{Float64}) = Float64(to_julia(giac_eval("$cmd()")))
_read_setting(::Symbol, ::Type{Int}) = Int(to_julia(giac_eval("Digits")))

_setting_source(v::Bool) = v ? "1" : "0"
_setting_source(v::Real) = string(v)
function _write_setting(cmd::Symbol, v)
    cmd === :Digits ? giac_eval("Digits:=$(Int(v))") : giac_eval("$cmd($(_setting_source(v)))")
    return nothing
end

"""
    giac_settings() -> NamedTuple

The GIAC session settings that change results, as one record:

* `complex_mode`: compute in ℂ (`simplify(sqrt(x^2))` is `x` with it on, `abs(x)` off);
* `approx_mode`: give approximate results;
* `angle_radian`: angles in radians (degrees when off);
* `complex_variables`: variables are complex unless assumed otherwise;
* `epsilon`: the tolerance under which a float is zero;
* `digits`: the number of significant digits of approximations (`Digits`).

Report it next to a result to say what it was computed with; set some of them for one block with
[`with_settings`](@ref).
"""
function giac_settings()
    with_giac_lock() do
        NamedTuple{keys(_SETTINGS)}(map(((cmd, T),) -> _read_setting(cmd, T), values(_SETTINGS)))
    end
end

function _restore_settings(saved::NamedTuple)
    for (k, v) in pairs(saved)
        _write_setting(_SETTINGS[k][1], v)
    end
end

"""
    with_settings(f; complex_mode, approx_mode, angle_radian, complex_variables, epsilon, digits)

Run `f()` with the given settings (see [`giac_settings`](@ref)), then put every setting back as
it was, after an error too.

```julia
@giac_var x
with_settings(complex_mode = false) do
    Giac.Commands.simplify(sqrt(x^2))       # abs(x), whatever the session's complex_mode
end
```
"""
function with_settings(f; settings...)
    for k in keys(settings)
        haskey(_SETTINGS, k) || throw(ArgumentError(
            "unknown setting `$k`; use one of $(join(keys(_SETTINGS), ", "))"))
    end
    with_giac_lock() do
        saved = giac_settings()
        try
            for (k, v) in pairs(settings)
                _write_setting(_SETTINGS[k][1], v)
            end
            return f()
        finally
            _restore_settings(saved)
        end
    end
end

# ---------------------------------------------------------------------------------------------
# Assumptions
# ---------------------------------------------------------------------------------------------

const _ASSUMING_DOMAINS = (:real, :integer, :complex, :rational)

# GIAC's state for a variable: its assumption (or value), or the name itself when it has neither
_giac_state(v::GiacExpr) = Commands.about(v)
function _set_giac_state!(v::GiacExpr, s::GiacExpr)
    Commands.purge(v)
    isequal(string(s), string(v)) || invoke_cmd(:sto, s, v)
    return nothing
end

_condition_vars(c::GiacExpr) = collect(GiacExpr, free_symbols(c))
_condition_vars(p::Pair{GiacExpr, Symbol}) = GiacExpr[first(p)]

# A relation GIAC has already decided from what it assumes evaluates to `true` or `false` before
# it reaches `assuming`: `k > 0` for a `k` declared positive.
_decided(c::GiacExpr) = is_boolean(c) ? to_julia(c) : nothing
_decided(::Pair) = nothing

function _check_condition(c)
    c isa Pair && !(last(c) in _ASSUMING_DOMAINS) && throw(ArgumentError(
        "unknown domain `$(last(c))`; use one of $(join(_ASSUMING_DOMAINS, ", "))"))
    _decided(c) === false && throw(ArgumentError(
        "a condition is false: it contradicts what is already assumed of its variables"))
    return c
end

function _apply_condition(c::GiacExpr, fresh::Bool)
    fresh ? Commands.assume(c) : Commands.additionally(c)
end
function _apply_condition(p::Pair{GiacExpr, Symbol}, fresh::Bool)
    v, domain = p
    fresh ? Commands.assume(v, string(domain)) : Commands.additionally(v, string(domain))
end

"""
    assuming(f, conditions...)

Run `f()` with GIAC assumptions in force, then undo them. A condition is a relation (`k > 0`,
`x < y`) or a domain `x => :integer` (`:real`, `:integer`, `:complex`, `:rational`). Several
conditions on one variable combine, and they add to what the variable was declared with
(`@giac_var k::real`).

When the block ends, after an error too, every variable named in the conditions gets back the
state GIAC held for it before (its declared assumptions, or none), and so does every setting of
[`giac_settings`](@ref). The GIAC lock is held for the whole block: other tasks wait, and none sees
the temporary assumptions.

```julia
@giac_var k
assuming(k > 0) do
    Giac.Commands.simplify(sqrt(k^2))       # k
end
Giac.Commands.simplify(sqrt(k^2))           # abs(k)
```
"""
function assuming(f, conditions::Union{GiacExpr, Pair{GiacExpr, Symbol}}...)
    foreach(_check_condition, conditions)
    with_giac_lock() do
        settings = giac_settings()
        vars = GiacExpr[]
        saved = GiacExpr[]
        for c in conditions, v in _condition_vars(c)
            any(u -> isequal(string(u), string(v)), vars) && continue
            push!(vars, v)
            push!(saved, _giac_state(v))
        end
        try
            touched = Set{String}()
            for c in conditions
                _decided(c) === true && continue          # already implied
                cvars = _condition_vars(c)
                # a variable already assumed something (declared, or by an earlier condition) gets more
                known = any(v -> string(v) in touched ||
                                 !isequal(string(_giac_state(v)), string(v)), cvars)
                _apply_condition(c, !known)
                foreach(v -> push!(touched, string(v)), cvars)
            end
            return f()
        finally
            foreach(_set_giac_state!, vars, saved)
            _restore_settings(settings)
        end
    end
end
