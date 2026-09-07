using JSON3

function _with_extras(m)
    return BayesModel(syntax(m); spaces=spaces(m), kernels=kernels(m),
                      evidence=evidence(m), history=history(m),
                      extras=Dict{Symbol,Any}(:name => "trial",
                                              :titles => Dict(:Climate => "Climate")))
end

@testset "Model JSON" begin
    m = reference_habitat_model()
    m1 = observe(do_intervention(m, :Irrigation => :high; note="pumps"), :Climate => :dry)
    m1 = soft_intervention(m1,
                           :Occupancy => cpt(axis(syntax(m), :HabitatQuality),
                                             axis(syntax(m), :Occupancy), [0.5 0.5; 0.1 0.9]))
    m1 = _with_extras(m1)

    @testset "string round trip" begin
        s = json_model(m1)
        obj = JSON3.read(s)
        @test obj[:format] == "bayesnet-acset" && obj[:schema_version] == "0.1"
        @test haskey(obj, :acset) && haskey(obj, :semantics)
        @test length(obj[:semantics][:kernels]) == length(kernels(m1))
        @test obj[:semantics][:spaces][:Climate] == ["dry", "normal", "wet"]
        back = parse_json_model(s)
        @test back isa BayesModel{BayesNet,FiniteSpace,FiniteKernel}
        @test canonicalize(syntax(back)) == canonicalize(syntax(m1))
        @test syntax(back) == syntax(m1)
        @test spaces(back) == spaces(m1)
        @test kernels(back) == kernels(m1)
        @test evidence(back) == evidence(m1)
        @test history(back) == history(m1)
        @test extras(back)[:name] == "trial"
        @test extras(back)[:titles][:Climate] == "Climate"
        @test back ≈ m1
        @test joint_distribution(back) ≈ joint_distribution(m1)
        # The syntax alone is still readable with the structural parser.
        @test parse_json_bayesnet(s) == syntax(m1)
        # A structural document gives a model without kernels.
        m0 = parse_json_model(json_bayesnet(syntax(m)))
        @test isempty(kernels(m0)) && spaces(m0) == syntax_spaces(syntax(m))
        @test_throws FormatError parse_json_model("{\"acset\":{}}")
    end

    @testset "file round trip" begin
        path = joinpath(mktempdir(), "habitat_model.json")
        @test write_json_model(path, m1) == path
        back = read_json_model(path)
        @test back == parse_json_model(read(path, String))
        @test kernels(back) == kernels(m1) && history(back) == history(m1)
        @test read_json_bayesnet(path) == syntax(m1)
    end
end
