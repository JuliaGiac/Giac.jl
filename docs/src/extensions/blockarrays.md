# BlockArrays.jl: block matrices

With [BlockArrays.jl](https://github.com/JuliaArrays/BlockArrays.jl) loaded,
block matrices of expressions work like numeric ones: their blocks can be read,
and products of conforming block matrices are computed and stay partitioned.

```julia
using Giac, BlockArrays, LinearAlgebra
@giac_matrix A[2, 2]
@giac_var b[1:2] d

M = BlockArray([A I; I A'], [2, 2], [2, 2])
M[Block(1, 2)]                 # the identity block
M * M                          # a 2×2 block matrix

K = BlockArray([A b; transpose(b) d], [2, 1], [2, 1])
K * BlockArray([b; d], [2, 1]) # a block vector
```

The extension provides the lazy zeros a block product starts from, which
ArrayLayouts builds only for `Number` element types. Scaling by a symbolic
scalar (`t .* M`) and the 5-argument `mul!` come from Giac.jl itself.
