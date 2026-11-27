# Fresh identifiers: Giac names that nothing captures (MathInterchange's feedback, point 4).
#
# A Julia symbol translated to Giac under its own name can be captured: by a value given with
# `:=`, by an assumption, by a GIAC command or constant (`i`, `e`, `pi`, `D`), or, for a name
# starting with `_`, by a physical unit. A fresh identifier is checked against all of these.

# Names GIAC reads as something of its own although `about` and the command registry let them
# through (`D` is GIAC's differential operator).
const _RESERVED_NAMES = Set(["D", "i", "I", "e", "pi", "infinity", "inf", "undef", "euler_gamma",
                             "true", "false"])

const _FRESH_COUNTER = Threads.Atomic{Int}(0)

const _IDENTIFIER_PATTERN = r"^[A-Za-z][A-Za-z0-9_]*$"

"""
    is_free_identifier(name) -> Bool

Whether the Giac identifier `name` is free: a plain name (a letter, then letters, digits or `_`;
a name starting with `_` is a physical unit in Giac) that is not a GIAC command or reserved
constant (`i`, `e`, `pi`, `D`, …) and has no value or assumption (`about(name)` is `name`).
"""
function is_free_identifier(name::AbstractString)::Bool
    occursin(_IDENTIFIER_PATTERN, name) || return false
    (name in _RESERVED_NAMES || is_valid_command(name)) && return false
    return with_giac_lock() do
        g = giac_eval(name)
        is_identifier(g) && string(Commands.about(g)) == name
    end
end

"""
    fresh_identifier(prefix = "giacjl_fresh") -> GiacExpr

A Giac identifier `prefix_N` that is free (see [`is_free_identifier`](@ref)) and that no other
call returns, from any task. Purge it when done, or use [`with_fresh_identifiers`](@ref).
"""
function fresh_identifier(prefix::AbstractString = "giacjl_fresh")::GiacExpr
    occursin(_IDENTIFIER_PATTERN, prefix) || throw(ArgumentError(
        "a fresh identifier's prefix must start with a letter and hold only letters, digits and `_`, got \"$prefix\""))
    while true
        name = string(prefix, "_", Threads.atomic_add!(_FRESH_COUNTER, 1) + 1)
        is_free_identifier(name) && return giac_eval(name)
    end
end

"""
    with_fresh_identifiers(f, n; prefix = "giacjl_fresh")

Call `f(v₁, …, vₙ)` with `n` fresh identifiers, and purge them when `f` returns or throws, so
the values or assumptions given to them inside do not outlive the block.

```julia
with_fresh_identifiers(2) do u, v
    Giac.Commands.expand((u + v)^2)
end
```
"""
function with_fresh_identifiers(f, n::Integer; prefix::AbstractString = "giacjl_fresh")
    vs = GiacExpr[fresh_identifier(prefix) for _ in 1:n]
    try
        return f(vs...)
    finally
        foreach(Commands.purge, vs)
    end
end
