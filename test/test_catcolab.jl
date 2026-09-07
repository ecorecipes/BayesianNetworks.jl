using UUIDs: UUID
using ACSets: acset_schema, objects, homs, attrtypes, attrs, copy_parts!

function formal_cells(doc)
    return [doc["notebook"]["cellContents"][id]["content"]
            for id in doc["notebook"]["cellOrder"]]
end

@testset "CatColab export" begin
    S = acset_schema(BayesNet())

    @testset "identifiers" begin
        @test CATCOLAB_NAMESPACE isa UUID
        @test catcolab_uuid("a", :b, 1) == catcolab_uuid("a", "b", "1")
        @test catcolab_uuid("a", "b") != catcolab_uuid("a", "c")
        @test UUID(catcolab_uuid("x")) isa UUID
        @test UUID(catcolab_uuid("x")).value >> 76 & 0xf == 5   # version 5
    end

    @testset "catlog model shape" begin
        model = catcolab_model(BayesNet)
        @test collect(keys(model)) == ["obGenerators", "morGenerators"]
        obs, mors = model["obGenerators"], model["morGenerators"]
        @test [only(o["label"]) for o in obs] ==
              String.(vcat(collect(objects(S)), collect(attrtypes(S))))
        @test [only(m["label"]) for m in mors] ==
              String.(vcat(first.(homs(S)), first.(attrs(S))))
        @test all(collect(keys(o)) == ["id", "label", "obType"] for o in obs)
        @test all(collect(keys(m)) == ["id", "label", "morType", "dom", "cod"]
                  for m in mors)
        kinds = Dict(only(o["label"]) => o["obType"]["content"] for o in obs)
        @test kinds["Variable"] == "Entity" && kinds["Label"] == "AttrType"
        types = Dict(only(m["label"]) => m["morType"] for m in mors)
        @test types["target"] == Dict("tag" => "Hom",
                                      "content" => Dict("tag" => "Basic",
                                                        "content" => "Entity"))
        @test types["kernel_ref"] == Dict("tag" => "Basic", "content" => "Attr")
        ids = Dict(only(o["label"]) => o["id"] for o in obs)
        t = only(filter(m -> only(m["label"]) == "target", mors))
        @test t["dom"] == Dict("tag" => "Basic", "content" => ids["Mechanism"])
        @test t["cod"] == Dict("tag" => "Basic", "content" => ids["Variable"])
        @test allunique(vcat([o["id"] for o in obs], [m["id"] for m in mors]))
        @test catcolab_model(BayesNet) == model
        @test catcolab_model(BayesNet; name="Other") != model
        @test parse_catcolab_schema(model) == S
        @test parse_catcolab_schema(catcolab_model(SchBayesNet)) == S
    end

    @testset "schema document" begin
        doc = catcolab_schema_document(BayesNet)
        @test collect(keys(doc)) == ["type", "name", "theory", "version", "notebook"]
        @test doc["type"] == "model" && doc["theory"] == "simple-schema" &&
              doc["version"] == "1" && doc["name"] == "SchBayesNet"
        nb = doc["notebook"]
        @test collect(keys(nb)) == ["cellContents", "cellOrder"]
        @test Set(keys(nb["cellContents"])) == Set(nb["cellOrder"])
        @test allunique(nb["cellOrder"])
        cells = formal_cells(doc)
        @test length(cells) == 4 + 3 + 4 + 7
        @test all(nb["cellContents"][id]["tag"] == "formal" &&
                      nb["cellContents"][id]["id"] == id for id in nb["cellOrder"])
        objs = filter(c -> c["tag"] == "object", cells)
        mors = filter(c -> c["tag"] == "morphism", cells)
        @test length(objs) == 7 && length(mors) == 11
        # Shapes of model_judgment.rs: ObDecl and MorDecl.
        @test all(collect(keys(c)) == ["tag", "name", "id", "obType"] for c in objs)
        @test all(collect(keys(c)) == ["tag", "name", "id", "morType", "dom", "cod"]
                  for c in mors)
        ids = Dict(c["name"] => c["id"] for c in objs)
        iv = only(filter(c -> c["name"] == "input_variable", mors))
        @test iv["dom"]["content"] == ids["Input"] &&
              iv["cod"]["content"] == ids["Variable"]
        @test iv["morType"]["tag"] == "Hom"
        kr = only(filter(c -> c["name"] == "kernel_ref", mors))
        @test kr["morType"] == Dict("tag" => "Basic", "content" => "Attr")
        @test kr["cod"]["content"] == ids["Ref"]
        # Deterministic and JSON round trip.
        @test catcolab_schema_document(BayesNet) == doc
        @test catcolab_schema_document(BayesNet; name="X")["name"] == "X"
        js = JSON3.write(doc)
        @test parse_catcolab_schema(js) == S
        @test parse_catcolab_schema(doc) == S
        @test parse_catcolab_schema(JSON3.read(js)) == S
        @test parse_catcolab_schema(catcolab_schema_document(SchBayesNet)) == S
        vs = parse_catcolab_schema(catcolab_schema_document(VariableSpace))
        @test vs == acset_schema(VariableSpace())
        # The same generators as schema_json.
        sj = schema_json(BayesNet)
        @test Set(String.(objects(vs))) ==
              Set(d["name"] for d in schema_json(VariableSpace)["Ob"])
        parsed = parse_catcolab_schema(doc)
        @test Set(String.(objects(parsed))) == Set(d["name"] for d in sj["Ob"])
        @test Set((String(f), String(d), String(c)) for (f, d, c) in homs(parsed)) ==
              Set((d["name"], d["dom"], d["codom"]) for d in sj["Hom"])
        @test Set((String(f), String(d), String(c)) for (f, d, c) in attrs(parsed)) ==
              Set((d["name"], d["dom"], d["codom"]) for d in sj["Attr"])
        # Errors.
        @test_throws FormatError parse_catcolab_schema(Dict("type" => "diagram"))
        @test_throws FormatError parse_catcolab_schema("{\"foo\": 1}")
        bad = deepcopy(doc)
        bad["notebook"]["cellContents"][bad["notebook"]["cellOrder"][8]]["content"]["dom"]["content"] = "nope"
        @test_throws FormatError parse_catcolab_schema(bad)
        # A model document from CatColab's own examples parses, when the clone is around.
        example = joinpath(homedir(), "Projects", "catcolab", "CatColab", "packages",
                           "notebook-types", "examples", "v1", "SEIRV.json")
        if isfile(example)
            ex = JSON3.read(read(example, String))
            @test Set(String.(keys(ex))) == Set(keys(doc))
            cell = first(values(ex[:notebook][:cellContents]))
            @test Set(String.(keys(cell))) == Set(["tag", "id", "content"])
            ours = doc["notebook"]["cellContents"][doc["notebook"]["cellOrder"][1]]
            @test Set(keys(ours)) == Set(String.(keys(cell)))
        else
            @test_skip false
        end
    end

    @testset "instance document" begin
        bn = reference_habitat_bn()
        doc = catcolab_schema_document(BayesNet)
        inst = catcolab_instance_document(bn, doc)
        @test collect(keys(inst)) == ["type", "name", "diagramIn", "version", "notebook"]
        @test inst["type"] == "diagram" && inst["version"] == "1"
        @test inst["diagramIn"]["type"] == "diagram-in"
        @test inst["diagramIn"]["_id"] == catcolab_uuid("SchBayesNet", "document")
        cells = formal_cells(inst)
        objs = filter(c -> c["tag"] == "object", cells)
        mors = filter(c -> c["tag"] == "morphism", cells)
        nparts_total = sum(nparts(bn, o) for o in objects(S))
        @test length(objs) == nparts_total
        @test length(mors) == sum(nparts(bn, d) for (_, d, _) in homs(S))
        @test all(collect(keys(c)) == ["tag", "name", "id", "obType", "over"] for c in objs)
        @test all(collect(keys(c)) ==
                  ["tag", "name", "id", "morType", "over", "dom", "cod"] for c in mors)
        schema_ids = Dict(c["name"] => c["id"] for c in formal_cells(doc))
        @test all(c["over"]["content"] in values(schema_ids) for c in objs)
        @test all(c["over"]["content"] in values(schema_ids) for c in mors)
        obj_ids = Set(c["id"] for c in objs)
        @test all(c["dom"]["content"] in obj_ids && c["cod"]["content"] in obj_ids
                  for c in mors)
        @test allunique(c["id"] for c in cells)
        labels = Set(c["name"] for c in objs)
        @test "Climate" in labels && "Climate.dry" in labels &&
              "SoilMoisture_mechanism" in labels && "SoilMoisture_mechanism.2" in labels
        # A hom value: the Input part of SoilMoisture_mechanism at position 2 maps to
        # Irrigation under input_variable.
        by_id = Dict(c["id"] => c for c in objs)
        iv = filter(c -> c["over"]["content"] == schema_ids["input_variable"], mors)
        @test length(iv) == nparts(bn, :Input)
        hit = filter(c -> by_id[c["dom"]["content"]]["name"] == "SoilMoisture_mechanism.2",
                     iv)
        @test by_id[only(hit)["cod"]["content"]]["name"] == "Irrigation"
        @test catcolab_instance_document(bn, doc) == inst
        @test catcolab_instance_document(bn, JSON3.write(doc)) == inst
        @test_throws FormatError catcolab_instance_document(bn,
                                                            catcolab_schema_document(VariableSpace))
        # A network with repeated variable names has no unambiguous instance document.
        dup = abiotic_bn()
        copy_parts!(dup, abiotic_bn())
        @test_throws DuplicateNameError catcolab_instance_document(dup, doc)
        JSON3.write(inst)   # serialisable
    end

    @testset "presentation" begin
        m = reference_habitat_model()
        js = presentation_json(m)
        @test js == presentation_json(syntax(m))
        obj = JSON3.read(js)
        @test obj[:format] == "markov-presentation/0.1"
        @test [o[:name] for o in obj[:objects]] == String.(variable_names(syntax(m)))
        @test obj[:objects][3][:states] == ["low", "medium", "high"]
        gen = only(filter(g -> g[:name] == "Vegetation_mechanism", obj[:generators]))
        @test gen[:dom] == ["SoilMoisture", "GrazingPressure"] &&
              gen[:cod] == ["Vegetation"]
        @test gen[:kernel_ref][:type] == "NamedRef" &&
              gen[:kernel_ref][:id] == "Vegetation_mechanism"
        @test canonicalize(parse_presentation_json(js)) == canonicalize(syntax(m))
        hard = do_intervention(syntax(m), :Vegetation => :dense)
        @test canonicalize(parse_presentation_json(presentation_json(hard))) ==
              canonicalize(hard)
        @test_throws FormatError parse_presentation_json("{\"format\": \"other\"}")
        @test_throws FormatError parse_presentation_json("""{"format": "markov-presentation/0.1",
            "objects": [{"name": "X", "states": ["a"]}, {"name": "Y", "states": ["b"]}],
            "generators": [{"name": "f", "dom": [], "cod": ["X", "Y"],
                            "kernel_ref": {"type": "NoRef"}}]}""")
    end
end
