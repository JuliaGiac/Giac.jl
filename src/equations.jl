# Equations `a ~ b` as values: their sides, arithmetic on both sides, solving for a variable,
# and substitution with an equation as the rule. Ported from Kahli Burke's `ergonomics` branch.

"""
Whether `e` is an equation `a = b`. Read from the stored value, not from the printed form:
every arithmetic operation asks it of its result (see `_both_sides`).
"""
function _is_equation(e::GiacExpr)
    e.ptr == C_NULL && return false
    GiacCxxBindings._have_library || return giac_type(e) == SYMB && symb_funcname(e) == "="
    return GC.@preserve e with_giac_lock() do
        g = _get_gen(e.ptr)
        g === nothing && return giac_type(e) == SYMB && symb_funcname(e) == "="
        return T(GiacCxxBindings.type(g)) == SYMB && GiacCxxBindings.symb_sommet_name(g) == "="
    end
end
_is_equation(::Any) = false

"""
    lhs(eq)
    rhs(eq)

The left and right sides of the equation `eq` (`a ~ b`). For an array of equations, broadcast:
`rhs.(eqs)`.

```julia
@giac_var x y
eq = 2x + 3 ~ y
lhs(eq)          # 2*x+3
rhs(eq)          # y
```
"""
lhs(eq::GiacExpr) = _is_equation(eq) ? Commands.left(eq) : _not_an_equation(eq)
"The right side of an equation; see [`lhs`](@ref)."
rhs(eq::GiacExpr) = _is_equation(eq) ? Commands.right(eq) : _not_an_equation(eq)

_not_an_equation(e) = throw(ArgumentError("$e is not an equation; write one as `a ~ b`"))

# A side of an operand: an equation's side, or the operand itself.
_side(f, e) = _is_equation(e) ? f(e) : e

# Arithmetic with an equation applies to both sides: `(a ~ b) - c` is `a - c ~ b - c`, and
# `(a ~ b) + (c ~ d)` is `a + c ~ b + d`. Each side is computed by the ordinary operation, so it
# is simplified as any other result is. `r` is the result Giac gave, an equation exactly when an
# operand was one; checking only it keeps the extra cost off ordinary arithmetic.
_both_sides(op, a, b, r) = _is_equation(r) ? op(_side(lhs, a), _side(lhs, b)) ~ op(_side(rhs, a), _side(rhs, b)) : r
_both_sides(op, a, r) = _is_equation(r) ? op(lhs(a)) ~ op(rhs(a)) : r

"""
    isolate(eq, x)

Solve the equation `eq` for `x` and give the result as an equation `x ~ …`; an expression
`eq` is taken as `eq ~ 0`. With several solutions, a vector of equations, one for each.

```julia
@giac_var x y
isolate(2x + 3 ~ y, x)       # x = (y-3)/2
isolate(x^2 ~ y, x)          # [x = √y, x = -√y]
```
"""
function isolate(eq::GiacExpr, x::GiacExpr)
    sols = to_julia(Commands.solve(eq, x))
    isempty(sols) && throw(ArgumentError("$eq has no solution for $x"))
    eqs = [x ~ Commands.simplify(s) for s in sols]
    return length(eqs) == 1 ? only(eqs) : eqs
end

# ---------------------------------------------------------------------------------------------
# Equations between arrays, and solving for the free entries of a matrix unknown
# ---------------------------------------------------------------------------------------------

"""
    A ~ B

Entry-by-entry equations between arrays of expressions, with the same shape. `B` may be
another array, a `UniformScaling` such as `-I`, a symbolic multiple of the identity (`s*I`), or
one value for every entry (`f(x) ~ 0` for equilibria).
"""
function Base.:~(A::AbstractArray{GiacExpr}, B::AbstractArray)
    size(A) == size(B) || throw(DimensionMismatch("equation sides have sizes $(size(A)) and $(size(B))"))
    return map(~, A, B)
end
Base.:~(A::AbstractMatrix{GiacExpr}, J::UniformScaling) =
    A ~ _add_scaled_identity(fill(zero(GiacExpr), size(A)), J.λ)
Base.:~(A::AbstractMatrix{GiacExpr}, S::SymbolicScaling) =
    A ~ _add_scaled_identity(fill(zero(GiacExpr), size(A)), S.λ)
Base.:~(A::AbstractArray{GiacExpr}, b::Union{Number, GiacExpr}) = map(a -> a ~ b, A)

"""
    solve(eqs::AbstractArray{GiacExpr}, X::AbstractMatrix{GiacExpr}) -> Matrix{GiacExpr}

Solve the equations `eqs` (e.g. `P*A + A'*P ~ -I`) for the free entries of the matrix unknown
`X`, returning `X` with its entries replaced by the solution. Repeated equations (from a
symmetric unknown, say) count once. Throws if there is no solution or more than one.

```julia
@giac_var a11 a12 a21 a22 p11 p12 p22
A = [a11 a12; a21 a22]
P = [p11 p12; p12 p22]
P★ = solve(P*A + A'*P ~ -I, P)
```
"""
Commands.solve(eqs::AbstractArray{GiacExpr}, X::AbstractMatrix{GiacExpr}) = _solve_for_matrix(eqs, X)
# the generated `solve(::GiacMatrix, …)` and `solve(::AbstractMatrix{GiacExpr}, …)` also accept
# these arguments
Commands.solve(eqs::AbstractMatrix{GiacExpr}, X::AbstractMatrix{GiacExpr}) = _solve_for_matrix(eqs, X)
Commands.solve(eqs::GiacMatrix, X::AbstractMatrix{GiacExpr}) = _solve_for_matrix(eqs, X)

function _solve_for_matrix(eqs, X)
    unknowns = unique(string, filter(is_identifier, vec(X)))
    # linear equations with rational-function coefficients and one solution: outside GIAC when
    # an extension provides it (see `_exact` in array_algebra.jl)
    values = _exact(:linear, vec(eqs), unknowns)
    values === nothing || return map(x -> get(values, string(x), x), X)
    # the same equation can come out with its terms in a different order: compare normal forms
    equations = unique(e -> string(Commands.normal(e)), vec(eqs))
    solutions = Commands.solve(equations, unknowns)
    n = length(solutions)
    n == 1 || throw(ArgumentError(n == 0 ? "the equations have no solution for $(join(string.(unknowns), ", "))" :
                                           "the equations have $n solutions; solve them as a vector to see all of them"))
    values = Dict(string(u) => solutions[1][k] for (k, u) in enumerate(unknowns))
    return map(x -> get(values, string(x), x), X)
end
