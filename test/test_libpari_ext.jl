# ============================================================================
# LibPARI Extension Tests (071-libpari-bridge)
#
# Exercises `GiacLibPARIExt`: `to_giac(::LibPARI.Gen)` outward and
# `LibPARI.pari(::GiacExpr)` inward.
#
# Two rules govern every assertion here:
#
#   * Round trips are compared **by value** — `pari(to_giac(g)) == g`, where
#     `==` on a `Gen` is PARI's `gequal`. There is deliberately no
#     `string(x) == string(y)` anywhere in this file: PARI's variable
#     priority is process-global and Giac orders by its own rules, so a
#     textual comparison is red or flaky by construction.
#   * Every refusal is asserted to **name the tag** it could not translate.
#
# The file is self-contained so the dedicated CI job can run it against a
# project holding nothing but Giac and LibPARI — which is what proves the
# bridge does not quietly depend on another extension having loaded first.
# ============================================================================

using Test
using Giac
using Giac.GenTypes
using LibPARI

const PT = LibPARI.PariType
const GP = LibPARI.PARI

# ---------------------------------------------------------------------------
# Reals used to be untestable on Windows, and no longer are.
#
# `class gen` stored its tag as a bitfield — `unsigned char type:5;
# unsigned char type_unused:3;`. GCC fuses adjacent bitfield writes into one
# wider store and picks the bit placement in a version-dependent way, so
# `GIAC_jll` (GCC 8) and `libgiac_julia_jll` (GCC 10) disagreed about which
# bits held `type`: libgiac wrote a gen tagged `_REAL`, the wrapper read back
# `_DOUBLE_`, and every real crossed truncated to twelve significant digits.
#
# The assertions below were `@test_broken` on Windows for that reason.
# GIAC_jll v2.0.2 defaults to `GIAC_TYPE_ON_8BITS=1` — `type` is a plain byte
# at offset 0, a layout no compiler can rearrange — and libgiac_julia_jll
# v0.5.1 is rebuilt against it, so the two binaries now agree. `[compat]`
# requires both, which is what lets these run unqualified on every platform.
#
# See docs/src/extensions/libpari.md, "Reals once did not cross on Windows",
# Giac.jl#22, and JuliaPackaging/Yggdrasil#13717.
# ---------------------------------------------------------------------------

@testset "LibPARI Extension" begin

    @testset "Extension loads" begin
        @test !isnothing(Base.get_extension(Giac, :GiacLibPARIExt))
        @test hasmethod(Giac.to_giac, Tuple{LibPARI.Gen})
        @test hasmethod(LibPARI.pari, Tuple{GiacExpr})
    end

    # ------------------------------------------------------------------
    # Round trips by value, PARI first.
    # ------------------------------------------------------------------
    @testset "Round trip PARI -> Giac -> PARI" begin
        @testset "integers" begin
            for g in (
                LibPARI.pari(0),
                LibPARI.pari(42),
                LibPARI.pari(-7),
                LibPARI.pari(typemax(Int)),
                LibPARI.pari(typemin(Int)),
                LibPARI.pari(big(2)^200 + 1),
                LibPARI.pari(-big(3)^150),
            )
                @test LibPARI.pari(to_giac(g)) == g
            end
        end

        @testset "rationals" begin
            for g in (
                LibPARI.pari(3 // 4),
                LibPARI.pari(-22 // 7),
                LibPARI.pari(big(2)^100 // 7),
                LibPARI.pari(1 // big(3)^80),
            )
                @test LibPARI.pari(to_giac(g)) == g
            end
        end

        @testset "complex" begin
            for src in ("3+4*I", "-1+I", "3/4+5/6*I", "(2^100)+I")
                g = LibPARI.gp_eval(src)
                @test LibPARI.gentype(g) === PT.T_COMPLEX
                @test LibPARI.pari(to_giac(g)) == g
            end
        end

        @testset "polynomials" begin
            for src in (
                "x^2+1",
                "3*x^5-2*x^3+x-7",
                "Pol(5)",
                "0*x",
                "x",
                "(w+x)^2",
                "w^3*x + 2*w - x^2 + 5",
                "x^2/3 + 1/7",
                "y^7-1",
                "(a+b+c)^2",
            )
                g = LibPARI.gp_eval(src)
                @test LibPARI.pari(to_giac(g)) == g
            end
        end

        @testset "vectors" begin
            for src in ("[]", "[1,2,3]", "[7]", "[1, 3/4, x^2+1]", "[-1,0,1]")
                g = LibPARI.gp_eval(src)
                @test LibPARI.pari(to_giac(g)) == g
            end
        end

        @testset "matrices" begin
            for src in ("[1,2;3,4]", "[1,2;3,4;5,6]", "Mat(7)", "[x,1;0,x^2]", "[1,2,3]")
                g = LibPARI.gp_eval(src)
                @test LibPARI.pari(to_giac(g)) == g
            end
            # A one-row t_MAT must not collapse into a t_VEC on the way back:
            # Giac's own `makevector` unwraps a lone vector argument, and the
            # bridge compensates.
            m = LibPARI.gp_eval("Mat(7)")
            @test LibPARI.gentype(LibPARI.pari(to_giac(m))) === PT.T_MAT
        end
    end

    # ------------------------------------------------------------------
    # Round trips by value, Giac first.
    # ------------------------------------------------------------------
    @testset "Round trip Giac -> PARI -> Giac" begin
        for src in (
            "42",
            "-7",
            "2^200",
            "3/4",
            "2^100/7",
            "1.5",
            "3+4*i",
            "x",
            "x^2+1",
            "2*x*y+1",
            "(w+x)^2",
            "[1,2,3]",
            "[[1,2],[3,4]]",
        )
            e = giac_eval(src)
            p = LibPARI.pari(e)
            # `to_giac` back, then out again: the value must be a fixed point
            # of the crossing even though neither side's printed form is.
            @test LibPARI.pari(to_giac(p)) == p
        end
    end

    # ------------------------------------------------------------------
    # Reals. Precision is a scope; the bridge carries the *value's* own
    # precision, never the ambient setting.
    # ------------------------------------------------------------------
    @testset "Reals" begin
        @testset "round trip at several precisions" begin
            for bits in (64, 128, 192, 256, 384, 512, 1024)
                p = setprecision(() -> GP.mppi(), LibPARI.Gen, bits)
                @test precision(p) == bits
                @test LibPARI.pari(to_giac(p)) == p
            end
        end

        @testset "assorted magnitudes" begin
            for src in ("sqrt(2)", "1/3.", "-Pi", "Pi*2^-300", "Pi*2^300", "exp(1)")
                p = LibPARI.gp_eval(src)
                @test LibPARI.gentype(p) === PT.T_REAL
                @test LibPARI.pari(to_giac(p)) == p
            end
        end

        @testset "the value's precision, not the ambient one" begin
            # A 512-bit real crosses unchanged even while LibPARI's working
            # precision is set to 64 bits, and vice versa.
            wide = setprecision(() -> GP.mppi(), LibPARI.Gen, 512)
            narrow = setprecision(() -> GP.mppi(), LibPARI.Gen, 64)
            setprecision(LibPARI.Gen, 64) do
                @test LibPARI.pari(to_giac(wide)) == wide
            end
            setprecision(LibPARI.Gen, 512) do
                @test LibPARI.pari(to_giac(narrow)) == narrow
            end
            # The ambient `BigFloat` precision is likewise not consulted.
            setprecision(BigFloat, 53) do
                @test LibPARI.pari(to_giac(wide)) == wide
            end
        end

        @testset "a wide real survives inside a container" begin
            # The length-one container paths are the ones most likely to reach
            # for a textual detour, on either side. A 512-bit real inside a
            # one-element vector and a 1x1 matrix pins that they do not.
            wide = setprecision(() -> GP.mppi(), LibPARI.Gen, 512)
            onevec = GP.extract0(GP.gconcat(wide; x2 = wide), LibPARI.pari(1); x3 = nothing)
            onemat = GP.gtomat(; x1 = GP.gtocol0(onevec; x2 = 0))
            for g in (onevec, onemat, GP.gconcat(wide; x2 = LibPARI.pari(1)))
                @test LibPARI.pari(to_giac(g)) == g
            end
            @test precision(LibPARI.pari(to_giac(onevec))[1]) == 512
        end

        @testset "float tags are not preserved, only values" begin
            # Giac's DOUBLE is a Float64; PARI has no distinct hardware-float
            # tag, so it lands on t_REAL.
            p = LibPARI.pari(giac_eval("1.5"))
            @test LibPARI.gentype(p) === PT.T_REAL
            @test p == LibPARI.pari(1.5)

            # Coming the other way, Giac picks DOUBLE or REAL by how much
            # precision the value actually needs — a narrow t_REAL lands on
            # DOUBLE, a wide one on REAL. Either way the value survives.
            narrow = to_giac(LibPARI.pari(1.5))
            wide = to_giac(setprecision(() -> GP.mppi(), LibPARI.Gen, 512))
            @test Giac.giac_type(narrow) in (DOUBLE, REAL)
            @test Giac.giac_type(wide) == REAL
            @test LibPARI.pari(narrow) == LibPARI.pari(1.5)
        end
    end

    # ------------------------------------------------------------------
    # Names survive; representation does not.
    # ------------------------------------------------------------------
    @testset "Variable names survive" begin
        @testset "outward" begin
            for (src, want) in (
                ("x^2+1", ["x"]),
                ("(w+x)^2", ["w", "x"]),
                ("y^3-y", ["y"]),
                ("a*b*c", ["a", "b", "c"]),
            )
                g = to_giac(LibPARI.gp_eval(src))
                got = sort([string(v) for v in Giac.Commands.lvar(g)])
                @test got == sort(want)
            end
        end

        @testset "inward" begin
            # `gpolvar` takes a keyword, not a positional argument.
            for (src, want) in (("x^2+1", "x"), ("y^3-y", "y"))
                back = LibPARI.pari(to_giac(LibPARI.gp_eval(src)))
                @test string(GP.gpolvar(; x1 = back)) == want
            end
        end

        @testset "a Giac-side name reaches PARI" begin
            @giac_var zz
            p = LibPARI.pari(zz^2 + 1)
            @test LibPARI.gentype(p) === PT.T_POL
            @test string(GP.gpolvar(; x1 = p)) == "zz"
        end
    end

    # ------------------------------------------------------------------
    # Refusals — each must name the tag it could not translate.
    # ------------------------------------------------------------------
    @testset "Refusals name the tag" begin
        @testset "outward" begin
            for (tag, src) in (
                ("T_INTMOD", "Mod(3,7)"),
                ("T_PADIC", "3+O(5^4)"),
                ("T_QUAD", "quadgen(5)"),
                ("T_RFRAC", "1/(x+1)"),
                ("T_SER", "1+x+O(x^3)"),
                ("T_POLMOD", "Mod(x,x^2+1)"),
                ("T_STR", "\"hi\""),
            )
                g = LibPARI.gp_eval(src)
                err = try
                    to_giac(g)
                    nothing
                catch e
                    e
                end
                @test err isa ArgumentError
                msg = sprint(showerror, err)
                @test occursin(tag, msg)
                @test occursin("to_giac", msg)
            end
        end

        @testset "inward" begin
            for (tag, src, hint) in (
                ("MOD", "3 % 7", ""),
                ("STRNG", "\"hi\"", ""),
                ("SYMB", "sin(x)", "sin(x)"),
                ("SYMB", "sqrt(2)", "sqrt(2)"),
                ("SYMB", "exp(x)+x", "exp(x)"),
                ("SYMB", "1/x", "rational function"),
                ("SYMB", "x/(x+1)", "rational function"),
                ("IDNT", "pi", "constant"),
            )
                e = giac_eval(src)
                err = try
                    LibPARI.pari(e)
                    nothing
                catch ex
                    ex
                end
                @test err isa ArgumentError
                msg = sprint(showerror, err)
                @test occursin(tag, msg)
                @test occursin("pari", msg)
                isempty(hint) || @test occursin(hint, msg)
            end
        end

        @testset "a ragged Giac vector is refused, with its shape named" begin
            e = giac_eval("[[1,2],[3]]")
            err = try
                LibPARI.pari(e)
                nothing
            catch ex
                ex
            end
            @test err isa ArgumentError
            @test occursin("ragged", sprint(showerror, err))
        end

        @testset "a Giac vector mixing scalars and vectors is refused" begin
            e = giac_eval("[1,[2,3]]")
            err = try
                LibPARI.pari(e)
                nothing
            catch ex
                ex
            end
            @test err isa ArgumentError
            @test occursin("mixes vector and scalar", sprint(showerror, err))
        end
    end

    # ------------------------------------------------------------------
    # Documented limitations. Each is pinned by a test so that a change in
    # behaviour shows up here rather than in a user's results.
    # ------------------------------------------------------------------
    @testset "Documented limitations" begin
        @testset "T_COL, T_VECSMALL and T_LIST widen to T_VEC" begin
            for src in ("[1,2,3]~", "Vecsmall([1,2,3])", "List([1,2,3])")
                g = LibPARI.gp_eval(src)
                back = LibPARI.pari(to_giac(g))
                # The elements survive …
                @test back == LibPARI.gp_eval("[1,2,3]")
                # … the container tag does not. Giac has one vector type.
                @test LibPARI.gentype(back) === PT.T_VEC
                @test LibPARI.gentype(back) !== LibPARI.gentype(g)
                @test !(back == g)
            end
        end

        @testset "PARI's variable ordering does not cross" begin
            # `(w+x)^2` is equal by value across the bridge, but the printed
            # form depends on a process-global priority on the PARI side and
            # on Giac's own rules on the other. This is the assertion this
            # suite makes; `string` equality is never asserted anywhere.
            g = LibPARI.gp_eval("(w+x)^2")
            @test LibPARI.pari(to_giac(g)) == g
        end

        @testset "a Gen is not a Number" begin
            # Generic numeric code bounded by `T<:Number` will not accept a
            # `Gen`; callers must not assume `Number` methods apply.
            @test !(LibPARI.Gen <: Number)
            @test LibPARI.pari(42) isa LibPARI.PariObject
        end
    end

    # ------------------------------------------------------------------
    # Traps, pinned so nobody rediscovers them.
    # ------------------------------------------------------------------
    @testset "Traps" begin
        @testset "a text round trip would lose precision" begin
            # This is why the bridge never injects a PARI real into GP as a
            # decimal string: PARI prints at the ambient `realprecision`, so
            # a 512-bit real comes back as a 128-bit one with no diagnostic.
            # The bridge's structural route keeps all 512 bits.
            p = setprecision(() -> GP.mppi(), LibPARI.Gen, 512)
            viatext = LibPARI.gp_eval(string(p))
            @test precision(viatext) < precision(p)
            @test !(viatext == p)
            @test LibPARI.pari(to_giac(p)) == p
            @test precision(LibPARI.pari(to_giac(p))) == precision(p)
        end

        @testset "gpolvar takes a keyword" begin
            g = LibPARI.gp_eval("x^2+1")
            @test string(GP.gpolvar(; x1 = g)) == "x"
            @test_throws MethodError GP.gpolvar(g)
        end
    end

    # ------------------------------------------------------------------
    # The PARI stack must not grow across repeated crossings.
    # ------------------------------------------------------------------
    @testset "No PARI stack leak" begin
        # Warm up first: the first crossing of each shape allocates Julia-side
        # caches, and `_avma` is only meaningful once that has settled.
        for _ = 1:10
            LibPARI.pari(to_giac(LibPARI.gp_eval("(w+x)^2+3/4")))
        end
        GC.gc()
        GC.gc()
        before = LibPARI._avma()
        for _ = 1:500
            LibPARI.pari(to_giac(LibPARI.gp_eval("(w+x)^2+3/4")))
        end
        GC.gc()
        GC.gc()
        @test LibPARI._avma() == before
    end

    # ------------------------------------------------------------------
    # Every method the bridge adds must carry a type it owns.
    # ------------------------------------------------------------------
    @testset "No type piracy" begin
        ext = Base.get_extension(Giac, :GiacLibPARIExt)
        @test !isnothing(ext)
        for m in methods(Giac.to_giac)
            m.module === ext || continue
            @test any(t -> t === LibPARI.Gen, m.sig.parameters[2:end])
        end
        for m in methods(LibPARI.pari)
            m.module === ext || continue
            @test any(t -> t === GiacExpr, m.sig.parameters[2:end])
        end
    end
end
