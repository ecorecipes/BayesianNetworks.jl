using ACSets: BasicSchema, objects, homs, attrtypes, attrs, @acset_type, copy_parts!
using Dates: Day

# A schema extending `SchBayesNet` with one more object, as InfluenceDiagrams.jl does:
# the ACSet-level interventions must accept it and return the same type.
const SchTestNet = BasicSchema(vcat(collect(objects(SchBayesNet)), [:Note]),
                               vcat(collect(homs(SchBayesNet)),
                                    [(:note_variable, :Note, :Variable)]),
                               collect(attrtypes(SchBayesNet)),
                               vcat(collect(attrs(SchBayesNet)),
                                    [(:note_text, :Note, :Label)]))
@acset_type TestNetUntyped(SchTestNet;
                           index=[:state_variable, :variable_name, :target,
                                  :input_mechanism, :input_variable]) <: AbstractBayesNet
const TestNet = TestNetUntyped{Symbol,Int,KernelRef}

@testset "Model and interventions" begin
    ref = reference_habitat_bn()
    m = BayesModel(ref)

    record(bn, mm) = (mechanism_name(bn, mm), kernel_ref(bn, mm),
                      variable_name.(Ref(bn), inputs(bn, mm)))
    records(bn) = Dict(mechanism_name(bn, mm) => record(bn, mm) for mm in mechanisms(bn))

    @testset "BayesModel" begin
        @test syntax(m) === ref
        @test isempty(kernels(m)) && isempty(evidence(m)) && isempty(history(m)) &&
              isempty(extras(m))
        @test Set(keys(spaces(m))) == Set(variable_names(ref))
        @test spaces(m)[:Climate] == FiniteSpace(:Climate, [:dry, :normal, :wet])
        @test m isa BayesModel{BayesNet,FiniteSpace,FiniteKernel}
        @test validate(m) === nothing
        @test validate(m; closed=true, unique_names=true) === nothing
        typed = BayesModel(ref; spaces=Dict(:Climate => [:dry, :wet]),
                           kernels=Dict(NamedRef("k") => [0.5 0.5]))
        @test typed isa BayesModel{BayesNet,Vector{Symbol},Matrix{Float64}}
        @test kernels(typed)[NamedRef("k")] == [0.5 0.5]
        @test BayesModel(ref) == m
        @test hash(BayesModel(ref)) == hash(m)
        @test observe(m, :Climate => :dry) != m
        @test occursin("7 variables", sprint(show, m))
        bad = BayesModel(ref; evidence=Dict(:Climate => :humid))
        @test_throws UnknownStateError validate(bad)
        @test_throws MissingMechanismError validate(BayesModel(biotic_bn()); closed=true)
    end

    @testset "observe and unobserve" begin
        m1 = observe(m, :Climate => :dry)
        @test evidence(m1) == Dict(:Climate => :dry)
        @test isempty(evidence(m))
        @test syntax(m1) == ref
        @test isempty(history(m1))
        m2 = observe(m1, [:Climate => :wet, :Occupancy => :present])
        @test evidence(m2) == Dict(:Climate => :wet, :Occupancy => :present)
        @test evidence(m1) == Dict(:Climate => :dry)
        @test_throws UnknownStateError observe(m, :Climate => :humid)
        @test_throws UnknownVariableError observe(m, :Weather => :dry)
        @test evidence(unobserve(m2, :Climate)) == Dict(:Occupancy => :present)
        @test isempty(evidence(unobserve(m2)))
        @test_throws NoEvidenceError unobserve(m, :Climate)
        @test occursin("Climate", sprint(showerror, NoEvidenceError(:Climate)))
        @test occursin("humid", sprint(showerror, UnknownStateError(:Climate, :humid)))
    end

    @testset "do_intervention on a BayesNet" begin
        bn = do_intervention(ref, :Vegetation => :dense)
        @test bn isa BayesNet
        @test ref == reference_habitat_bn()
        @test validate(bn; closed=true, unique_names=true) === nothing
        @test nparts(bn, :Mechanism) == 7
        @test nparts(bn, :Input) == nparts(ref, :Input) - 2
        @test isempty(parents(bn, :Vegetation))
        mm = mechanism_of(bn, :Vegetation)
        @test mechanism_name(bn, mm) == Symbol("do[Vegetation=dense]") ==
              hard_intervention_name(:Vegetation, :dense)
        @test kernel_ref(bn, mm) == PointMassRef(:dense)
        # Every other mechanism, including downstream ones and their Input rows, is unchanged.
        before, after = records(ref), records(bn)
        delete!(before, :Vegetation_mechanism)
        delete!(after, Symbol("do[Vegetation=dense]"))
        @test before == after
        @test variable_name.(Ref(bn), parents(bn, :HabitatQuality)) == [:Vegetation]
        @test variable_name.(Ref(bn), children(bn, :SoilMoisture)) == Symbol[]
        @test states(bn, :Vegetation) == states(ref, :Vegetation)
        # Intervening on a root replaces its prior; on an exogenous variable it adds one.
        root = do_intervention(ref, :Climate => :wet)
        @test kernel_ref(root, mechanism_of(root, :Climate)) == PointMassRef(:wet)
        @test nparts(root, :Mechanism) == 7
        open_bn = biotic_bn()
        exo = do_intervention(open_bn, :SoilMoisture => :high)
        @test nparts(exo, :Mechanism) == nparts(open_bn, :Mechanism) + 1
        @test validate(exo; closed=true) === nothing
        # Multiple targets and errors.
        multi = do_intervention(ref, [:Climate => :dry, :Irrigation => :high])
        @test nparts(multi, :Input) == nparts(ref, :Input)
        @test kernel_ref(multi, mechanism_of(multi, :Irrigation)) == PointMassRef(:high)
        @test_throws UnknownStateError do_intervention(ref, :Vegetation => :lush)
        @test_throws UnknownVariableError do_intervention(ref, :Forest => :dense)
        # Round trips.
        @test canonicalize(parse_json_bayesnet(json_bayesnet(bn))) == canonicalize(bn)
        @test canonicalize(do_intervention(canonicalize(ref), :Vegetation => :dense)) ==
              canonicalize(bn)
    end

    @testset "do_intervention on a BayesModel" begin
        m1 = do_intervention(m, :Vegetation => :dense; note="fencing trial")
        @test syntax(m) == ref
        @test syntax(m1) == do_intervention(ref, :Vegetation => :dense)
        @test intervened_variables(m1) == [:Vegetation]
        @test is_intervened(m1, :Vegetation)
        @test !is_intervened(m1, :Climate)
        @test !is_intervened(m, :Vegetation)
        ev = only(history(m1))
        @test ev.kind == :hard
        @test ev.target == :Vegetation
        @test ev.removed == MechanismRecord(:Vegetation_mechanism, NoRef(),
                                            [:SoilMoisture, :GrazingPressure])
        @test ev.added == MechanismRecord(Symbol("do[Vegetation=dense]"),
                                          PointMassRef(:dense), Symbol[])
        @test ev.note == "fencing trial"
        @test isempty(history(m))
        # Observation and intervention differ on the syntax and agree on the wrapper.
        o1 = observe(m, :Vegetation => :dense)
        @test syntax(o1) == ref
        @test syntax(m1) != ref
        @test evidence(o1) == Dict(:Vegetation => :dense)
        @test isempty(evidence(m1))
        # Evidence survives an intervention; interventions accumulate.
        m2 = do_intervention(observe(m1, :Climate => :dry),
                             [:Climate => :wet, :Vegetation => :sparse])
        @test evidence(m2) == Dict(:Climate => :dry)
        @test length(history(m2)) == 3
        @test intervened_variables(m2) == [:Vegetation, :Climate]
        @test history(m2)[3].removed == MechanismRecord(Symbol("do[Vegetation=dense]"),
                                                        PointMassRef(:dense), Symbol[])
        exo = do_intervention(BayesModel(biotic_bn()), :SoilMoisture => :high)
        @test only(history(exo)).removed === nothing
        @test validate(exo; closed=true) === nothing
        # Evidence on the intervened variable is kept and contradicts the intervention,
        # which the docstring warns about: the contradiction surfaces at the next query.
        full = reference_habitat_model()
        contradiction = do_intervention(observe(full, :Vegetation => :sparse),
                                        :Vegetation => :dense)
        @test evidence(contradiction) == Dict(:Vegetation => :sparse)
        @test_throws ImpossibleEvidenceError marginal(contradiction, :Occupancy)
        @test marginal(unobserve(contradiction, :Vegetation), :Occupancy) ≈
              marginal(do_intervention(full, :Vegetation => :dense), :Occupancy)
        # Evidence equal to the intervened state is consistent.
        agreeing = do_intervention(observe(full, :Vegetation => :dense),
                                   :Vegetation => :dense)
        @test marginal(agreeing, :Occupancy) ≈
              marginal(do_intervention(full, :Vegetation => :dense), :Occupancy)
    end

    @testset "soft_intervention" begin
        bn = soft_intervention(ref, :Vegetation => NamedRef("veg_fenced");
                               parents=[:SoilMoisture])
        @test validate(bn; closed=true, unique_names=true) === nothing
        mm = mechanism_of(bn, :Vegetation)
        @test mechanism_name(bn, mm) == Symbol("soft[Vegetation]")
        @test kernel_ref(bn, mm) == NamedRef("veg_fenced")
        @test variable_name.(Ref(bn), parents(bn, :Vegetation)) == [:SoilMoisture]
        before, after = records(ref), records(bn)
        delete!(before, :Vegetation_mechanism)
        delete!(after, Symbol("soft[Vegetation]"))
        @test before == after
        # Default parents are the current ones; a custom name is honoured.
        same = soft_intervention(ref, :Vegetation => NamedRef("k"); name=:veg2)
        @test variable_name.(Ref(same), parents(same, :Vegetation)) ==
              [:SoilMoisture, :GrazingPressure]
        @test mechanism_name(same, mechanism_of(same, :Vegetation)) == :veg2
        # New parents must keep the graph acyclic and exclude the target.
        @test_throws CyclicBayesNetError soft_intervention(ref, :Climate => NamedRef("k");
                                                           parents=[:Occupancy])
        @test_throws SelfInputError soft_intervention(ref, :Climate => NamedRef("k");
                                                      parents=[:Climate])
        # On a model: kernel stored, event recorded.
        fenced = cpt(axis(ref, :SoilMoisture), axis(ref, :Vegetation),
                     [1.0 0.0 0.0; 0.0 0.5 0.5; 0.0 0.0 1.0])
        m1 = soft_intervention(m, :Vegetation => NamedRef("veg_fenced");
                               parents=[:SoilMoisture], kernel=fenced,
                               note="fenced plots")
        @test syntax(m1) == bn
        @test kernels(m1)[NamedRef("veg_fenced")] == fenced
        # A kernel that does not fit the new mechanism is rejected.
        @test_throws KernelBindingError soft_intervention(m,
                                                          :Vegetation => NamedRef("k");
                                                          parents=[:GrazingPressure],
                                                          kernel=fenced)
        @test isempty(kernels(m))
        ev = only(history(m1))
        @test ev.kind == :soft
        @test ev.removed == MechanismRecord(:Vegetation_mechanism, NoRef(),
                                            [:SoilMoisture, :GrazingPressure])
        @test ev.added ==
              MechanismRecord(Symbol("soft[Vegetation]"), NamedRef("veg_fenced"),
                              [:SoilMoisture])
        @test ev.note == "fenced plots"
        @test intervened_variables(m1) == [:Vegetation]
        multi = soft_intervention(m,
                                  [:Climate => NamedRef("c"), :Irrigation => NamedRef("i")])
        @test intervened_variables(multi) == [:Climate, :Irrigation]
        @test validate(multi; closed=true) === nothing
    end

    @testset "interventions on an AbstractBayesNet subtype" begin
        tn = TestNet()
        copy_parts!(tn, ref)
        note = add_part!(tn, :Note; note_variable=variable_id(tn, :Vegetation),
                         note_text=:fenced)
        @test validate(tn; closed=true, unique_names=true) === nothing
        hard = do_intervention(tn, :Vegetation => :dense)
        @test hard isa TestNet
        @test nparts(hard, :Note) == 1 && subpart(hard, note, :note_text) == :fenced
        @test nparts(tn, :Mechanism) == 7 && nparts(hard, :Mechanism) == 7
        @test kernel_ref(hard, mechanism_of(hard, :Vegetation)) == PointMassRef(:dense)
        @test isempty(parents(hard, :Vegetation))
        multi = do_intervention(tn, [:Climate => :dry, :Irrigation => :high])
        @test multi isa TestNet && nparts(multi, :Input) == nparts(tn, :Input)
        soft = soft_intervention(tn, :Vegetation => NamedRef("veg");
                                 parents=[:SoilMoisture])
        @test soft isa TestNet && nparts(soft, :Note) == 1
        @test variable_name.(Ref(soft), parents(soft, :Vegetation)) == [:SoilMoisture]
        renamed = rename_variable(tn, :Vegetation => :Plants)
        @test renamed isa TestNet && has_variable(renamed, :Plants)
        @test canonicalize(tn) isa TestNet
        @test topological_order(tn) == topological_order(ref)
        @test variable_graph(tn) == variable_graph(ref)
        # The wrapper keeps the syntax type through interventions.
        tm = BayesModel(tn)
        @test tm isa BayesModel{TestNet,FiniteSpace,FiniteKernel}
        tm1 = do_intervention(tm, :Vegetation => :dense)
        @test syntax(tm1) isa TestNet && syntax(tm1) == hard
        @test only(history(tm1)).removed == mechanism_record(tn, :Vegetation_mechanism)
        tm2 = soft_intervention(tm, :Vegetation => NamedRef("veg"); parents=[:SoilMoisture])
        @test syntax(tm2) isa TestNet && syntax(tm2) == soft
    end

    @testset "copy constructor, mechanism_record and inspection on models" begin
        m1 = BayesModel(m; evidence=Dict(:Climate => :dry))
        @test m1 isa BayesModel{BayesNet,FiniteSpace,FiniteKernel}
        @test evidence(m1) == Dict(:Climate => :dry) && isempty(evidence(m))
        @test syntax(m1) === ref && spaces(m1) == spaces(m)
        @test spaces(m1) !== spaces(m)   # copied, never shared
        @test BayesModel(m) == m
        ev = ModelEvent(:hard, :X, nothing, nothing)
        @test history(BayesModel(m; history=[ev])) == [ev]
        @test kernels(BayesModel(m; kernels=Dict{KernelRef,Any}(NamedRef("k") => 1))) ==
              Dict{KernelRef,Any}(NamedRef("k") => 1)
        @test mechanism_record(ref, :Vegetation_mechanism) ==
              MechanismRecord(:Vegetation_mechanism, NoRef(),
                              [:SoilMoisture, :GrazingPressure])
        @test mechanism_record(ref, mechanism_id(ref, :Climate_mechanism)) ==
              MechanismRecord(:Climate_mechanism, NoRef(), Symbol[])
        @test mechanism_record(m, :Vegetation_mechanism) ==
              mechanism_record(ref, :Vegetation_mechanism)
        @test_throws UnknownMechanismError mechanism_record(ref, :nope)
        # Every inspection and graph accessor delegates to the syntax.
        @test variable_names(m) == variable_names(ref)
        @test variables(m) == variables(ref) && mechanisms(m) == mechanisms(ref)
        @test variable_name(m, 1) == variable_name(ref, 1)
        @test has_variable(m, :Climate) && !has_variable(m, :Weather)
        @test states(m, :Climate) == states(ref, :Climate)
        @test state_ids(m, :Climate) == state_ids(ref, :Climate)
        @test nstates(m, :Climate) == 3
        @test space_ref(m, :Climate) == NoRef()
        @test mechanism_names(m) == mechanism_names(ref)
        @test mechanism_name(m, 1) == mechanism_name(ref, 1)
        @test kernel_ref(m, :Climate_mechanism) == NoRef()
        @test target(m, :Vegetation_mechanism) == variable_id(ref, :Vegetation)
        @test input_ids(m, :Vegetation_mechanism) == input_ids(ref, :Vegetation_mechanism)
        @test inputs(m, :Vegetation_mechanism) == inputs(ref, :Vegetation_mechanism)
        @test mechanism_of(m, :Vegetation) == mechanism_of(ref, :Vegetation)
        @test has_mechanism(m, :Vegetation)
        @test parents(m, :Vegetation) == parents(ref, :Vegetation)
        @test children(m, :SoilMoisture) == children(ref, :SoilMoisture)
        @test isempty(exogenous(m)) && roots(m) == roots(ref)
        @test topological_order(m) == topological_order(ref)
        @test is_acyclic(m)
        @test variable_graph(m) == variable_graph(ref)
        @test moral_graph(m) == moral_graph(ref)
    end

    @testset "history and events" begin
        ev = ModelEvent(:hard, :X, nothing, MechanismRecord(:m, NoRef(), Symbol[]))
        @test ev.note == ""
        @test ev == ModelEvent(:hard, :X, nothing, MechanismRecord(:m, NoRef(), Symbol[]);
                               time=ev.time)
        @test hash(ev) == hash(ModelEvent(:hard, :X, nothing,
                                          MechanismRecord(:m, NoRef(), Symbol[]);
                                          time=ev.time))
        m1 = BayesModel(ref; history=[ev])
        @test history(m1) == [ev]
        @test intervened_variables(m1) == [:X]
        # The wall-clock time is provenance, not value: it is kept and shown but plays
        # no part in equality (SPEC section 49 and section 52).
        later = ModelEvent(:hard, :X, nothing, MechanismRecord(:m, NoRef(), Symbol[]);
                           time=ev.time + Day(1))
        @test later.time != ev.time
        @test later == ev && hash(later) == hash(ev)
        @test occursin(string(ev.time), sprint(show, ev))
        @test ev != ModelEvent(:soft, :X, nothing, MechanismRecord(:m, NoRef(), Symbol[]))
        # Identical sequences of operations therefore give equal models.
        seq(x) = do_intervention(soft_intervention(observe(x, :Climate => :dry),
                                                   :SoilMoisture => NamedRef("sm");
                                                   parents=Symbol[]),
                                 :Vegetation => :dense; note="scenario")
        a, b = seq(BayesModel(ref)), seq(BayesModel(ref))
        @test a == b && hash(a) == hash(b)
        @test history(a) == history(b)
    end
end
