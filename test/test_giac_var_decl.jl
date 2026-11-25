# Tests for the extended @giac_var: assumptions, arrays of variables and
# renaming (PR #35). The plain and function forms are covered by
# test_macros.jl.

using Test
using Giac
using Giac.Commands: about

# GIAC's description of what is assumed about a variable, as a string.
assumed(x) = string(about(x))

# Evaluated by module-level code below: the macro must expand inside a
# module that only does `using Giac`, and evaluate ranges and bounds there.
module GiacVarHygiene
    using Giac
    vars(n) = (@giac_var hyg[1:n]; hyg)
    bounded(c) = (@giac_var hb::(>(c)); hb)
end

@testset "@giac_var declarations" begin

    @testset "domain assumptions" begin
        @giac_var dr::real di::integer dq::rational dc::complex
        @test occursin("real", assumed(dr))
        @test occursin("integer", assumed(di))
        @test occursin("rational", assumed(dq))
        @test occursin("complex", assumed(dc))
        @giac_var dR::Real dI::Integer
        @test occursin("real", assumed(dR))
        @test occursin("integer", assumed(dI))
    end

    @testset "named ranges" begin
        @giac_var np::positive nn::negative nnn::nonnegative nnp::nonpositive
        @test occursin("line[0,+infinity]", assumed(np))
        @test occursin("line[-infinity,0]", assumed(nn))
        @test occursin("line[0,+infinity]", assumed(nnn))
        @test occursin("line[-infinity,0]", assumed(nnp))
        @giac_var nf::finite
        @test occursin("line[-infinity,+infinity]", assumed(nf))
    end

    @testset "several assumptions" begin
        @giac_var ya::(integer, positive)
        @test occursin("integer", assumed(ya))
        @test occursin("line[0,+infinity]", assumed(ya))
    end

    @testset "predicates with a literal bound" begin
        @giac_var pa::(integer, >(2))
        @test occursin("line[2,+infinity]", assumed(pa))
        @giac_var pb::(<=(5))
        @test occursin("line[-infinity,5]", assumed(pb))
    end

    @testset "predicate bounds are evaluated in the caller's scope" begin
        c = 3
        @giac_var pc::(>(c))
        @test occursin("line[3,+infinity]", assumed(pc))
        @test GiacVarHygiene.bounded(7) isa GiacExpr
        @test occursin("line[7,+infinity]", assumed(GiacVarHygiene.bounded(7)))
    end

    @testset "Symbolics-style metadata" begin
        @giac_var ma [domain = Real]
        @test occursin("real", assumed(ma))
        @giac_var mb [positive, real]
        @test occursin("real", assumed(mb))
        @test occursin("line[0,+infinity]", assumed(mb))
        @giac_var mc [domain = v -> v > 0]
        @test occursin("line[0,+infinity]", assumed(mc))
    end

    @testset "redeclaring a variable resets its assumptions" begin
        @giac_var rz::positive
        @test occursin("line[0,+infinity]", assumed(rz))
        @giac_var rz
        @test !occursin("line", assumed(rz))
    end

    @testset "arrays of variables" begin
        @giac_var az[1:3]
        @test az isa Vector{GiacExpr}
        @test string.(az) == ["az₁", "az₂", "az₃"]
        @giac_var am[1:2, -1:1]
        @test size(am) == (2, 3)
        @test string(am[1, 1]) == "am₁_₋₁"
        @test string(am[2, 3]) == "am₂_₁"
        @giac_var ap[1:2]::positive
        @test all(occursin("line[0,+infinity]", assumed(v)) for v in ap)
        @giac_var ae[1:0]
        @test ae isa Vector{GiacExpr} && isempty(ae)
    end

    @testset "array bounds are evaluated in the caller's scope" begin
        n = 4
        @giac_var an[1:n]
        @test length(an) == 4
        @test string(an[end]) == "an₄"
        @test length(GiacVarHygiene.vars(2)) == 2
        # Expansion must not evaluate the range, so an undefined bound is
        # only an error when the code runs.
        @test (@macroexpand @giac_var undefined_bound_arr[1:undefined_n]) isa Expr
    end

    @testset "renaming" begin
        @giac_var rv => "𝑣"
        @test string(rv) == "𝑣"
        @giac_var rw(t) => "W"
        @test string(rw) == "W(t)"
        @giac_var (rp => "ρ")::positive
        @test string(rp) == "ρ"
        @test occursin("line[0,+infinity]", assumed(rp))
    end

    @testset "invalid declarations fail at expansion" begin
        @test_throws ArgumentError @macroexpand @giac_var bad::foo
        @test_throws ArgumentError @macroexpand @giac_var bad::Float64
        @test_throws ArgumentError @macroexpand @giac_var bad::(bad > 0)
        @test_throws ArgumentError @macroexpand @giac_var bf(t)::positive
        @test_throws ArgumentError @macroexpand @giac_var bad[]
    end

    @testset "return value" begin
        r = @giac_var ra rb::positive rc[1:2]
        @test r isa Tuple
        @test length(r) == 3
        @test r[3] isa Vector{GiacExpr}
    end
end
