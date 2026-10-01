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

    # The 14 network mutations of `proofs/scripts/check_records.jl`, which the proved Lean
    # decoder (`Finite/JsonRecords.lean`) rejects, built inline from the reference network.
    # The body is checked against the schema before ACSets reads it (ADR 0015), so each is a
    # `FormatError` naming the table, row and column; the last two are well-shaped documents
    # of invalid networks, which `validate` reports, as the Lean check does.
    @testset "the acset body is checked against the schema" begin
        ref = reference_habitat_bn()
        base = json_bayesnet(ref)
        function mutated(f!)
            d = JSON3.read(base, Dict{String,Any})
            f!(d["acset"])
            return JSON3.write(d)
        end
        function message(str)
            try
                parse_json_bayesnet(str)
            catch e
                e isa FormatError && return e.message
                rethrow()
            end
            return error("the document was accepted")
        end
        climate = findfirst(r -> r["target"] == 1, JSON3.read(base)[:acset][:Mechanism])
        rejected = [(a -> delete!(a["State"][1], "state_position"),
                     ["State row 1", "missing the column \"state_position\""]),
                    (a -> delete!(a, "Input"), ["missing the table \"Input\""]),
                    (a -> delete!(a, "Label"), ["missing the table \"Label\""]),
                    (a -> (a["State"][1]["state_variable"] = 99),
                     ["State row 1", "column \"state_variable\"", "1:7", "99"]),
                    (a -> (a["Mechanism"][1]["target"] = 0),
                     ["Mechanism row 1", "column \"target\"", "the number 0"]),
                    (a -> (a["State"][1]["state_name"] = 5),
                     ["State row 1", "column \"state_name\" must be a string"]),
                    (a -> (a["State"][1]["state_variable"] = "1"),
                     ["State row 1", "column \"state_variable\"", "got a string"]),
                    (a -> (a["Input"][1]["input_position"] = 1.5),
                     ["Input row 1", "column \"input_position\"", "1.5"]),
                    (a -> (a["State"][1]["state_position"] = 0),
                     ["State row 1", "column \"state_position\"", "one-based"]),
                    (a -> (a["State"][2]["_id"] = 7),
                     ["State row 2", "column \"_id\" must be the row number 2"]),
                    (a -> (a["Mechanism"][1]["note"] = "x"),
                     ["Mechanism row 1", "unknown column \"note\""]),
                    (a -> (a["Mechanism"][1]["kernel_ref"] = Dict("type" => "Bogus")),
                     ["Mechanism row 1", "column \"kernel_ref\"",
                      "unknown KernelRef type \"Bogus\""])]
        for (f!, fragments) in rejected
            msg = message(mutated(f!))
            for fragment in fragments
                @test occursin(fragment, msg)
            end
        end
        # Read, then reported by `validate`.
        dup = parse_json_bayesnet(mutated(a -> (a["Input"][2]["input_position"] = a["Input"][1]["input_position"])))
        @test any(e -> e isa PositionError && e.part == :Input, validation_errors(dup))
        cyclic = parse_json_bayesnet(mutated(a -> push!(a["Input"],
                                                        Dict("_id" => length(a["Input"]) + 1,
                                                             "input_mechanism" => climate,
                                                             "input_variable" => variable_id(ref,
                                                                                             :Occupancy),
                                                             "input_position" => 1))))
        @test any(e -> e isa CyclicBayesNetError, validation_errors(cyclic))
        # More of the same rules: `null` and other `KernelRef` shapes, the attribute-type
        # tables, an unknown table and a row that is not an object.
        for (f!, fragment) in
            [(a -> (a["Mechanism"][2]["kernel_ref"] = nothing),
              "Mechanism row 2: column \"kernel_ref\" must be a KernelRef object, got null"),
             (a -> (a["Variable"][1]["variable_name"] = nothing),
              "Variable row 1: column \"variable_name\" must be a string, got null"),
             (a -> (a["Mechanism"][1]["kernel_ref"] = Dict("type" => "NoRef", "id" => "x")),
              "must be a NoRef object with exactly the keys \"type\""),
             (a -> (a["Mechanism"][1]["kernel_ref"] = Dict("type" => "NamedRef", "id" => 3)),
              "must be a NamedRef whose \"id\" is a string"),
             (a -> (a["Mechanism"][1]["kernel_ref"] = Dict("id" => "x")),
              "with a \"type\" key"),
             (a -> push!(a["Position"], Dict("_id" => 1)),
              "the attribute table \"Position\" must be empty, got 1 row"),
             (a -> (a["Extra"] = []), "unknown table \"Extra\""),
             (a -> (a["Ref"] = Dict()), "the table \"Ref\" must be an array"),
             (a -> (a["State"][3] = [1]), "State row 3 must be an object")]
            @test occursin(fragment, message(mutated(f!)))
        end
        # The columns come from the schema, and are the Lean decoder's `bnColumns`.
        cols(ob) = [c => kind
                    for (c, (kind, _)) in BayesianNetworks._json_columns(SchBayesNet, ob)]
        @test cols(:Variable) == [:_id => :id, :variable_name => :label, :space_ref => :ref]
        @test cols(:State) == [:_id => :id, :state_variable => :hom, :state_name => :label,
                               :state_position => :position]
        @test cols(:Mechanism) ==
              [:_id => :id, :target => :hom, :mechanism_name => :label, :kernel_ref => :ref]
        @test cols(:Input) == [:_id => :id, :input_mechanism => :hom,
                               :input_variable => :hom, :input_position => :position]
        # A document Julia writes is still read, references of every type included.
        @test parse_json_bayesnet(json_bayesnet(bn)) == bn
        @test read_json_bayesnet(write_json_bayesnet(joinpath(mktempdir(), "r.json"), ref)) ==
              ref
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
