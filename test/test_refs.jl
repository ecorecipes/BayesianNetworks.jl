using JSON3

@testset "KernelRef" begin
    refs = KernelRef[NamedRef("cpt_1"), PointMassRef(:high), PolicyRef(:Irrigate), NoRef()]
    for r in refs
        s = JSON3.write(r)
        @test occursin("\"type\":\"$(nameof(typeof(r)))\"", s)
        @test JSON3.read(s, KernelRef) == r
        @test JSON3.read(s, typeof(r)) == r
    end
    @test JSON3.read(JSON3.write(refs), Vector{KernelRef}) == refs
    @test_throws ArgumentError BayesianNetworks.StructTypes.construct(KernelRef,
                                                                      Dict("type" => "Bogus"))
    @test_throws Exception JSON3.read("{\"type\":\"Bogus\"}", KernelRef)
    @test_throws ArgumentError JSON3.read("{\"type\":\"NoRef\"}", NamedRef)
    @test NoRef() isa KernelRef
    @test NamedRef("a") == NamedRef("a")
end
