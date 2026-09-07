using BayesianNetworkFormats: BayesianNetworkFormats, IRVariable, DecisionNode, UtilityNode,
                              read_network, isequivalent, differences

@testset "Formats bridge" begin
    ref = reference_habitat_model()

    @testset "habitat_reference.dne equals the Julia reference" begin
        path = fixture_path("dne/habitat_reference.dne")
        m = read_bayesnet(path)
        @test m isa BayesModel{BayesNet,FiniteSpace,FiniteKernel}
        @test validate(m; closed=true, unique_names=true, semantics=true) === nothing
        @test has_semantics(m)
        @test canonicalize(syntax(m)) == canonicalize(syntax(ref))
        @test m ≈ ref
        @test joint_distribution(m) ≈ joint_distribution(ref)
        @test marginal(m, :Occupancy) ≈ marginal(ref, :Occupancy)
        # Metadata from the file.
        ex = extras(m)
        @test ex[:name] == "habitat_reference"
        @test ex[:format] == :dne
        @test ex[:source] == path
        @test ex[:titles][:SoilMoisture] == "Soil moisture"
        @test ex[:positions][:Climate] == (100.0, 60.0)
        @test ex[:comments][:Climate] == "Regional climate regime."
        @test isempty(ex[:deterministic])
        @test ex[:network_extras][:comment] ==
              "SPEC section 45 reference ecological Bayesian network."
        # Every format of the fixture gives the same semantics.
        for f in ("bif/habitat_reference.bif", "xdsl/habitat_reference.xdsl",
                  "net/habitat_reference.net")
            @test read_bayesnet(fixture_path(f)) ≈ ref
        end
        # Brute-force oracle of the Formats package agrees.
        ir = read_network(path)
        @test BayesianNetworkFormats.marginal(ir, :Occupancy) ≈
              marginal(m, :Occupancy).table
        @test BayesModel(ir) ≈ m
    end

    @testset "asia" begin
        m = read_bayesnet(fixture_path("bif/asia.bif"))
        @test validate(m; closed=true, semantics=true) === nothing
        @test states(syntax(m), :dysp) == [:yes, :no]
        @test marginal(m, [:dysp]).table ≈ [0.4360, 0.5640] atol = 1e-4
        @test marginal(m, :dysp).table ≈
              BayesianNetworkFormats.marginal(read_network(fixture_path("bif/asia.bif")),
                                              :dysp)
        @test variable_name.(Ref(syntax(m)), parents(syntax(m), :dysp)) == [:bronc, :either]
        @test cpt(kernel(m, :dysp))[2, 1, :] ≈ [0.7, 0.3]
        @test marginal(observe(m, :asia => :yes), :tub).table ≈ [0.05, 0.95]
    end

    @testset "IR round trip" begin
        for f in ("dne/habitat_reference.dne", "bif/asia.bif", "bif/sprinkler_table.bif",
                  "dne/umbrella.dne")
            f == "dne/umbrella.dne" && continue   # influence diagram, tested below
            ir = read_network(fixture_path(f))
            back = NetworkIR(BayesModel(ir))
            @test isequivalent(back, ir)
            @test isempty(differences(back, ir))
            @test back.name == ir.name
        end
        # Julia-built model to IR: names, states, parents and tables.
        ir = NetworkIR(ref; name="habitat")
        @test ir.name == "habitat"
        @test [v.id for v in ir.variables] == variable_names(syntax(ref))
        sm = BayesianNetworkFormats.variable(ir, :SoilMoisture)
        @test sm.parents == [:Climate, :Irrigation]
        @test sm.states == ["low", "medium", "high"]
        @test sm.table == cpt(kernel(ref, :SoilMoisture))
        @test sm.title == "SoilMoisture"
        @test BayesianNetworkFormats.validate(ir) === ir
        @test isequivalent(ir, read_network(fixture_path("dne/habitat_reference.dne"));
                           name=false, titles=false, positions=false, comments=false,
                           extras=false)
        # Unbound mechanisms and exogenous variables give tables of `nothing`.
        ir0 = NetworkIR(BayesModel(reference_habitat_bn()))
        @test all(v.table === nothing for v in ir0.variables)
        iro = NetworkIR(BayesModel(biotic_bn()))
        @test BayesianNetworkFormats.variable(iro, :SoilMoisture).parents == Symbol[]
        # Interventions are written as their materialised tables.
        ird = NetworkIR(do_intervention(ref, :Vegetation => :dense))
        v = BayesianNetworkFormats.variable(ird, :Vegetation)
        @test v.parents == Symbol[] && v.table == [0.0, 0.0, 1.0]
    end

    @testset "file round trip and unsupported nodes" begin
        dir = mktempdir()
        for ext in ("dne", "xdsl", "net", "bif", "bnir.json")
            path = joinpath(dir, "habitat." * ext)
            @test write_bayesnet(path, ref) == path
            @test read_bayesnet(path) ≈ ref
        end
        # Decision and utility nodes are refused with a pointer to InfluenceDiagrams.jl.
        e = try
            read_bayesnet(fixture_path("dne/umbrella.dne"))
        catch err
            err
        end
        @test e isa UnsupportedNodeKindError
        @test e.id == :Umbrella && e.kind == "decision"
        @test occursin("InfluenceDiagrams.jl", sprint(showerror, e))
        util = NetworkIR("u",
                         [IRVariable(:X; states=["a", "b"], table=[0.5, 0.5]),
                          IRVariable(:U; kind=UtilityNode, parents=[:X], table=[1.0, 2.0])])
        @test_throws UnsupportedNodeKindError BayesModel(util)
        # Missing tables are allowed (Netica files without probabilities) and reported.
        partial = NetworkIR("p",
                            [IRVariable(:X; states=["a", "b"]),
                             IRVariable(:Y; states=["c", "d"], parents=[:X],
                                        table=[0.5 0.5; 0.1 0.9])])
        mp = BayesModel(partial)
        @test missing_kernels(mp) == [:X]
        @test kernel(mp, :Y).table == [0.5 0.1; 0.5 0.9]
        # Tolerance and renormalisation flow through.
        rough = NetworkIR("r", [IRVariable(:X; states=["a", "b"], table=[0.5, 0.5000001])])
        mr = BayesModel(rough; atol=1e-6)
        @test mr isa BayesModel
        @test_throws UnnormalizedKernelError BayesModel(rough; atol=1e-9)
        @test_throws UnnormalizedKernelError validate(mr; semantics=true)
        @test validate(mr; semantics=true, atol=1e-6) === nothing
        @test extras(mr) == ir_extras(rough)
        ex = ir_extras(partial)
        @test ex[:name] == "p"
        @test ex[:titles] == Dict(v.id => v.title for v in partial.variables)
        @test isempty(ex[:positions]) && isempty(ex[:comments]) &&
              ex[:deterministic] == Symbol[]
        @test Set(keys(ex)) ==
              Set([:name, :format, :source, :titles, :positions, :comments,
                   :deterministic, :variable_extras, :network_extras])
        @test kernel(BayesModel(rough; renormalize=true), :X).table ≈ [0.5, 0.5] atol = 1e-6
    end
end
