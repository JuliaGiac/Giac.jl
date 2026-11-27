"""
    GiacBlockArraysExt

Block matrices of expressions with BlockArrays.jl: products of conforming block matrices work, and
stay partitioned. Ported from Kahli Burke's `ergonomics` branch (the partition lines in LaTeX
come later, with the typesetting).

```julia
using Giac, BlockArrays, LinearAlgebra
@giac_matrix A[2, 2]
M = BlockArray([A I; I A'], [2, 2], [2, 2])
M[Block(1, 2)]
M * M
```
"""
module GiacBlockArraysExt

using Giac: Giac, GiacExpr
using BlockArrays: BlockArrays

# A block product starts from a lazy array of zeros, which ArrayLayouts builds only for `Number`
# element types; an expression has a `zero` too.
BlockArrays.ArrayLayouts.mulzeros(::Type{GiacExpr}, M) = BlockArrays.FillArrays.Zeros{GiacExpr}(axes(M))

end
