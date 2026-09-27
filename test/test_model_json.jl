using JSON3
using Dates: DateTime

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

@testset "JSON decoding failures are FormatErrors" begin
    # Every reader of a JSON document raises `FormatError` for text that is not JSON, and
    # the record decoders for a missing key, an unknown ref type, an unparsable time and a
    # bad kernel table. Each of these used to escape as a Base `ArgumentError`, `KeyError`
    # or `DimensionMismatch`, or as a FiniteKernels error.
    m = observe(do_intervention(reference_habitat_model(), :Irrigation => :high;
                                note="pumps"), :Climate => :dry)
    s = json_model(m)
    function edited(f, str)
        d = JSON3.read(str, Dict{String,Any})
        f(d)
        return JSON3.write(d)
    end
    # The kernel record of the root `GrazingPressure`, which no intervention touches, and
    # the first history record, which adds the point mass of the hard intervention.
    grazing(d) = only(filter(k -> k["ref"]["id"] == "GrazingPressure_mechanism",
                             d["semantics"]["kernels"]))
    @test grazing(JSON3.read(s, Dict{String,Any}))["size"] == [2]
    @test JSON3.read(s)[:history][1][:added][:kernel_ref][:type] == "PointMassRef"

    @testset "text that is not JSON, at every reader" begin
        path = joinpath(mktempdir(), "not.json")
        write(path, "not json")
        for f in (parse_json_bayesnet, parse_json_model, parse_json_card,
                  parse_catcolab_schema, parse_presentation_json,
                  str -> catcolab_instance_document(reference_habitat_bn(), str))
            @test_throws FormatError f("not json")
        end
        for f in (read_json_bayesnet, read_json_model, read_json_card)
            @test_throws FormatError f(path)
        end
        err = try
            parse_json_model("not json")
        catch e
            e
        end
        @test occursin("not JSON", err.message)
    end

    @testset "kernel records" begin
        @test_throws FormatError parse_json_model(edited(d -> delete!(grazing(d), "table"),
                                                         s))
        # A table shorter than its size (a `DimensionMismatch` from `reshape`).
        @test_throws FormatError parse_json_model(edited(d -> pop!(grazing(d)["table"]), s))
        # A negative entry in a normalised column (a `KernelEntryError` from FiniteKernels).
        bad = edited(d -> (grazing(d)["table"] = [1.5, -0.5]), s)
        @test_throws FormatError parse_json_model(bad)
        err = try
            parse_json_model(bad)
        catch e
            e
        end
        @test occursin("GrazingPressure_mechanism", err.message) &&
              occursin("KernelEntryError", err.message)
        # A table that does not fit its spaces (a `KernelShapeError`).
        @test_throws FormatError parse_json_model(edited(d -> (grazing(d)["size"] = [1, 2]),
                                                         s))
        @test_throws FormatError parse_json_model(edited(d -> (grazing(d)["ref"]["type"] = "Bogus"),
                                                         s))
        @test_throws FormatError parse_json_model(edited(d -> delete!(grazing(d)["ref"],
                                                                      "id"), s))
    end

    @testset "history records" begin
        added(d) = d["history"][1]["added"]
        @test_throws FormatError parse_json_model(edited(d -> (added(d)["kernel_ref"]["type"] = "Bogus"),
                                                         s))
        @test_throws FormatError parse_json_model(edited(d -> (d["history"][1]["time"] = "yesterday"),
                                                         s))
        @test_throws FormatError parse_json_model(edited(d -> delete!(d["history"][1],
                                                                      "time"),
                                                         s))
        @test_throws FormatError parse_json_model(edited(d -> delete!(added(d), "inputs"),
                                                         s))
    end

    @testset "cards" begin
        card = ModelCard(m)
        provenance!(card,
                    :Occupancy_mechanism => ParameterProvenance(; source_type=:elicited,
                                                                timestamp=DateTime(2026, 9,
                                                                                   26)))
        cs = json_card(card)
        @test parse_json_card(cs) == card
        @test_throws FormatError parse_json_card(edited(d -> delete!(d["card"], "license"),
                                                        cs))
        @test_throws FormatError parse_json_card(edited(d -> (d["card"]["kernel_refs"]["Occupancy_mechanism"]["type"] = "Bogus"),
                                                        cs))
        @test_throws FormatError parse_json_card(edited(d -> (d["card"]["provenance"]["Occupancy_mechanism"]["timestamp"] = "later"),
                                                        cs))
        @test_throws FormatError parse_json_card(edited(d -> delete!(d["card"]["provenance"]["Occupancy_mechanism"],
                                                                     "citation"), cs))
    end

    @testset "CatColab and presentation documents" begin
        doc = catcolab_schema_document(BayesNet)
        nocells = deepcopy(doc)
        delete!(nocells["notebook"], "cellContents")
        @test_throws FormatError parse_catcolab_schema(nocells)
        @test_throws FormatError parse_catcolab_schema(JSON3.write(nocells))
        @test_throws FormatError catcolab_instance_document(reference_habitat_bn(), nocells)
        # The catlog `Model` shape has no "name" to link an instance document to.
        @test_throws FormatError catcolab_instance_document(reference_habitat_bn(),
                                                            catcolab_model(BayesNet))
        js = presentation_json(m)
        @test_throws FormatError parse_presentation_json(edited(d -> delete!(d,
                                                                             "generators"),
                                                                js))
        @test_throws FormatError parse_presentation_json(edited(d -> (d["generators"][1]["kernel_ref"]["type"] = "Bogus"),
                                                                js))
    end

    @testset "selective: other errors pass through" begin
        # A typed error from building the network is not rewrapped.
        js = presentation_json(m)
        @test_throws UnknownVariableError parse_presentation_json(edited(d -> (d["generators"][1]["cod"] = ["Nope"]),
                                                                         js))
        # A JSON value of the wrong type is a known exception, not converted yet: there is
        # no catch-all, which would also turn a `MethodError` into a `FormatError`.
        @test_throws MethodError parse_json_model(edited(d -> (grazing(d)["table"][1] = "x"),
                                                         s))
        # `_kernel_ref_from` itself, and so the direct StructTypes path, keeps its
        # `ArgumentError` (test_refs.jl).
        @test_throws ArgumentError BayesianNetworks._kernel_ref_from(Dict("type" => "Bogus"))
    end
end
