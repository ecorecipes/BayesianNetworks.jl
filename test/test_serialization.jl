using JSON3

@testset "Serialization" begin
    bn = reference_habitat_bn()
    set_subpart!(bn, variable_id(bn, :Climate), :space_ref, NamedRef("climate_space"))
    set_subpart!(bn, mechanism_of(bn, :Occupancy), :kernel_ref, NamedRef("P(Occ|HQ)"))
    set_subpart!(bn, mechanism_of(bn, :Irrigation), :kernel_ref, PointMassRef(:high))
    set_subpart!(bn, mechanism_of(bn, :GrazingPressure), :kernel_ref, PolicyRef(:Graze))

    @testset "string round trip" begin
        s = json_bayesnet(bn)
        obj = JSON3.read(s)
        @test obj[:format] == "bayesnet-acset"
        @test obj[:schema_version] == "0.1"
        @test haskey(obj[:acset], :Variable)
        back = parse_json_bayesnet(s)
        @test back isa BayesNet
        @test back == bn
        @test canonicalize(back) == canonicalize(bn)
        @test is_isomorphic(back, bn)
        @test space_ref(back, :Climate) == NamedRef("climate_space")
        @test kernel_ref(back, mechanism_of(back, :Occupancy)) == NamedRef("P(Occ|HQ)")
        @test kernel_ref(back, mechanism_of(back, :Irrigation)) == PointMassRef(:high)
        @test kernel_ref(back, mechanism_of(back, :GrazingPressure)) == PolicyRef(:Graze)
        @test kernel_ref(back, mechanism_of(back, :Climate)) == NoRef()
        @test subpart(back, :state_position) == subpart(bn, :state_position)
    end

    @testset "file round trip" begin
        path = joinpath(mktempdir(), "habitat.json")
        @test write_json_bayesnet(path, bn) == path
        @test isfile(path)
        @test read_json_bayesnet(path) == bn
        @test read_json_bayesnet(path; type=BayesNet) == bn
    end

    @testset "envelope errors" begin
        @test_throws FormatError parse_json_bayesnet("[]")
        @test_throws FormatError parse_json_bayesnet("{\"acset\":{}}")
        @test_throws FormatError parse_json_bayesnet("{\"format\":\"other\",\"schema_version\":\"0.1\",\"acset\":{}}")
        @test_throws FormatError parse_json_bayesnet("{\"format\":\"bayesnet-acset\",\"schema_version\":\"9\",\"acset\":{}}")
        err = FormatError("boom")
        @test sprint(showerror, err) == "FormatError: boom"
    end

    @testset "schema JSON" begin
        sj = schema_json(BayesNet)
        names(key) = Set(String[d["name"] for d in sj[key]])
        @test names("Ob") == Set(["Variable", "State", "Mechanism", "Input"])
        @test names("Hom") ==
              Set(["state_variable", "target", "input_mechanism", "input_variable"])
        @test names("AttrType") == Set(["Label", "Position", "Ref"])
        @test names("Attr") ==
              Set(["variable_name", "space_ref", "state_name", "state_position",
                   "mechanism_name", "kernel_ref", "input_position"])
        @test isempty(sj["equations"])
        homs = Dict(d["name"] => (d["dom"], d["codom"]) for d in sj["Hom"])
        @test homs["target"] == ("Mechanism", "Variable")
        @test homs["input_mechanism"] == ("Input", "Mechanism")
        @test homs["input_variable"] == ("Input", "Variable")
        @test homs["state_variable"] == ("State", "Variable")
        attrs = Dict(d["name"] => (d["dom"], d["codom"]) for d in sj["Attr"])
        @test attrs["kernel_ref"] == ("Mechanism", "Ref")
        @test attrs["input_position"] == ("Input", "Position")
        @test schema_json(SchBayesNet) == sj
        vs = schema_json(VariableSpace)
        @test Set(String[d["name"] for d in vs["Ob"]]) == Set(["Variable", "State"])
    end

    @testset "schema matches the Lean-emitted JSON" begin
        # proofs/schemas/*.json is emitted by the Lean project (`lake exe emit_schema`).
        # The comparison ignores the "version" block, which records tool versions.
        strip_version(x) = filter(kv -> kv.first != :version,
                                  copy(JSON3.read(JSON3.write(x))))
        for (file, T) in ("bayesnet" => BayesNet, "variable_space" => VariableSpace)
            lean_file = joinpath(@__DIR__, "..", "proofs", "schemas", "$file.schema.json")
            if isfile(lean_file)
                lean = strip_version(JSON3.read(read(lean_file, String)))
                julia = strip_version(schema_json(T))
                @test lean == julia
            else
                @test_skip false  # Lean schema not emitted yet
            end
        end
    end
end
