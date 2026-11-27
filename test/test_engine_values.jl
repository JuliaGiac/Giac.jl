# Engine queries as Julia values, and a quiet load (MathInterchange's feedback, points 7 and 9).

@testset "purge returns what the variable held" begin
    C = Giac.Commands
    @giac_var y z w::positive
    @test string(C.purge(y)) == "y"                      # held nothing: the variable itself
    giac_eval("z:=5")
    @test string(C.purge(z)) == "5"                       # its value
    @test occursin("line[0,+infinity]", string(C.purge(w)))   # its assumption
    @test string(C.about(w)) == "w"                       # and it is purged
end

@testset "giac_version" begin
    v = giac_version()
    @test v isa VersionNumber
    @test v >= v"2.0.0"
    @test startswith(to_julia(invoke_cmd(:version)), "giac $(v.major).$(v.minor)")
end

@testset "loading Giac logs nothing at Info level" begin
    cmd = `$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) -e "using Giac"`
    err = IOBuffer()
    run(pipeline(cmd; stderr = err, stdout = devnull))
    @test !occursin("GIAC wrapper library loaded", String(take!(err)))
end
