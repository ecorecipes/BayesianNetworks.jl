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
                                             axis(syntax(m), :Occupancy),
                                             [0.5 0.5; 0.1 0.9]))
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

@testset "JSON round trip preserves a rounded model and its IR metadata" begin
    # `parse_json_model` used to build every kernel at the default tolerance, so a model
    # bound at a looser one -- which is every model from `read_bayesnet` -- could be written
    # to JSON and then be unreadable.
    mm = bind_cpt(BayesModel(bayesnet(:A => [:a1, :a2, :a3])),
                  :A => [0.333333, 0.333333, 0.333333]; atol=1e-5)
    path = joinpath(mktempdir(), "rounded.json")
    write_json_model(path, mm)
    @test_throws FormatError read_json_model(path)          # typed, not a raw kernel error
    @test kernels(read_json_model(path; atol=1e-5)) == kernels(mm)

    # A JSON round trip turns tuples into arrays and symbols into strings, which used to
    # break `NetworkIR(::BayesModel)` (a `TypeError` on `positions`) and silently drop the
    # `deterministic` flags, so a model read from a format file could not be written back.
    m = read_bayesnet(fixture_path("dne/habitat_reference.dne"))
    jpath = joinpath(mktempdir(), "habitat.json")
    write_json_model(jpath, m)
    m2 = read_json_model(jpath; atol=1e-6)
    @test m2.extras[:positions] isa AbstractDict
    ir1, ir2 = NetworkIR(m), NetworkIR(m2)
    @test [v.title for v in ir1.variables] == [v.title for v in ir2.variables]
    @test [v.position for v in ir1.variables] == [v.position for v in ir2.variables]
    @test [v.deterministic for v in ir1.variables] ==
          [v.deterministic for v in ir2.variables]
    @test ir1.format == ir2.format
    dne = joinpath(mktempdir(), "habitat.dne")
    write_bayesnet(dne, m2)
    @test [v.title for v in NetworkIR(read_bayesnet(dne)).variables] ==
          [v.title for v in ir1.variables]

    @test_throws FormatError NetworkIR(BayesModel(syntax(m); spaces=spaces(m),
                                                  kernels=kernels(m),
                                                  extras=Dict{Symbol,Any}(:positions => Dict(:Climate => "x"))))
end
