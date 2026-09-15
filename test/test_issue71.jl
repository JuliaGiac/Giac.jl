using Test
using Giac

@testset "Issue 71 Basic Math" begin
    @giac_var x y
    
    @test abs2(x) == abs(x)^2
    @test cis(x) == exp(Giac.Constants._i[] * x)
    @test cispi(x) == exp(Giac.Constants._i[] * pi * x)
    @test expm1(x) == exp(x) - 1
    @test sech(x) == 1 / cosh(x)
    @test csch(x) == 1 / sinh(x)
    @test coth(x) == 1 / tanh(x)
    @test asech(x) == acosh(1 / x)
    @test acsch(x) == asinh(1 / x)
    @test acoth(x) == atanh(1 / x)
    @test sinc(x) == sin(pi * x) / (pi * x)
    
    @test hypot(x, y) == sqrt(abs2(x) + abs2(y))
    @test clamp(x, 0, 1) == Giac.Commands.min(Giac.Commands.max(x, 0), 1)
end

@testset "Coverage for Issue 71" begin
    @giac_var x y
    @test string(mod2pi(x)) == string(x - 2 * pi * floor(x / (2 * pi)))
    
    if isdefined(Base, :fourthroot)
        @test fourthroot(x) == Giac.Commands.surd(x, 4)
    end
    
    @test hypot(x, 3) == hypot(x, giac_eval("3"))
    @test hypot(4, y) == hypot(giac_eval("4"), y)
end
