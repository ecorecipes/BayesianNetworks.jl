using BayesianNetworkInference: infer

# The vegetation-herbivore example as a plain (initial, transition) pair, so that the
# tests can perturb the templates.
function vh_templates()
    initial = bayesnet(:Vegetation => [:sparse, :dense], :Herbivores => [:low, :high];
                       mechanisms=[:Herbivores => :Vegetation])
    transition = bayesnet(:Vegetation => [:sparse, :dense], :Herbivores => [:low, :high],
                          lagged(:Vegetation, 1) => [:sparse, :dense],
                          lagged(:Herbivores, 1) => [:low, :high];
                          mechanisms=[:Vegetation => (lagged(:Vegetation, 1),
                                                      lagged(:Herbivores, 1)),
                                      :Herbivores => :Vegetation], closed=false)
    return initial, transition
end

# The first DynamicTemplateError of a template built without validation.
function template_error(initial, transition; lags=1)
    errs = validation_errors(DynamicBayesNet(initial, transition; lags=lags,
                                             validate=false))
    return isempty(errs) ? nothing : first(errs)
end

# Forward recursion by hand for the two-variable chain: the joint of (Vegetation_t,
# Herbivores_t) as a matrix, from the CPTs of `vegetation_herbivore_model`.
function forward_joints(h::Integer)
    pV0 = [0.4, 0.6]
    K = [0.7 0.3; 0.3 0.7]                    # P(H | V), rows = V
    T = zeros(2, 2, 2)                        # P(V' | V, H)
    T[1, 1, :] = [0.5, 0.5]
    T[1, 2, :] = [0.8, 0.2]
    T[2, 1, :] = [0.1, 0.9]
    T[2, 2, :] = [0.4, 0.6]
    joints = Matrix{Float64}[]
    push!(joints, pV0 .* K)
    for _ in 1:h
        J = last(joints)
        pV = [sum(J[v, h] * T[v, h, w] for v in 1:2, h in 1:2) for w in 1:2]
        push!(joints, pV .* K)
    end
    return joints
end

@testset "Dynamic networks" begin
    initial, transition = vh_templates()

    @testset "naming conventions" begin
        @test lagged(:X, 1) == Symbol("X[t-1]")
        @test lagged(:X, 0) == :X
        @test_throws ArgumentError lagged(:X, -1)
        @test lag_of(Symbol("Soil_Moisture[t-12]")) == (:Soil_Moisture, 12)
        @test lag_of(:X) == (:X, 0)
        @test is_lagged(Symbol("X[t-2]")) && !is_lagged(:X)
        @test variable_at(:X, 3) == :X_3
        @test_throws ArgumentError variable_at(:X, -1)
        @test time_index(:Soil_Moisture_12) == (:Soil_Moisture, 12)
        @test_throws ArgumentError time_index(:X)
        @test_throws ArgumentError time_index(Symbol("X_"))
    end

    @testset "template construction and accessors" begin
        dbn = DynamicBayesNet(initial, transition)
        @test lags(dbn) == 1
        @test initial_network(dbn) == initial
        @test transition_network(dbn) == transition
        @test current_variables(dbn) == [:Vegetation, :Herbivores]
        @test lagged_variables(dbn) == [lagged(:Vegetation, 1), lagged(:Herbivores, 1)]
        @test slice_variables(dbn, 2) == [:Vegetation_2, :Herbivores_2]
        @test validate(dbn) === nothing
        @test isvalid(dbn)
        @test isempty(validation_errors(dbn))
        @test dbn == vegetation_herbivore_dbn()
        @test hash(dbn) == hash(vegetation_herbivore_dbn())
        @test occursin("lags = 1", sprint(show, dbn))
        @test_throws ArgumentError DynamicBayesNet(initial, transition; lags=0)
        # lags is inferred from the largest lag in the transition.
        @test lags(DynamicBayesNet(initial, transition; lags=1)) == 1
    end

    @testset "validation errors" begin
        # A current variable without a mechanism.
        tr = deepcopy(transition)
        cascading_rem_part!(tr, :Mechanism, mechanism_id(tr, :Herbivores_mechanism))
        e = template_error(initial, tr)
        @test e isa DynamicTemplateError && e.what == :missing_mechanism &&
              e.variable == :Herbivores
        @test occursin("Herbivores", sprint(showerror, e))
        @test_throws DynamicTemplateError DynamicBayesNet(initial, tr)
        # A lagged variable with a mechanism.
        tr = deepcopy(transition)
        add_mechanism!(tr, lagged(:Herbivores, 1))
        e = template_error(initial, tr)
        @test e isa DynamicTemplateError && e.what == :lagged_mechanism
        # A lagged variable whose base is not current.
        tr = deepcopy(transition)
        add_variable!(tr, lagged(:Predators, 1); states=[:few, :many])
        e = template_error(initial, tr)
        @test e isa DynamicTemplateError && e.what == :unknown_base &&
              e.variable == lagged(:Predators, 1)
        # A lag beyond `lags`.
        tr = deepcopy(transition)
        add_variable!(tr, lagged(:Vegetation, 2); states=[:sparse, :dense])
        e = template_error(initial, tr; lags=1)
        @test e isa DynamicTemplateError && e.what == :lag
        # States of a lag disagree with the base.
        tr = bayesnet(:Vegetation => [:sparse, :dense], :Herbivores => [:low, :high],
                      lagged(:Vegetation, 1) => [:sparse, :moderate, :dense],
                      lagged(:Herbivores, 1) => [:low, :high];
                      mechanisms=[:Vegetation => (lagged(:Vegetation, 1),
                                                  lagged(:Herbivores, 1)),
                                  :Herbivores => :Vegetation], closed=false)
        e = template_error(initial, tr)
        @test e isa DynamicTemplateError && e.what == :states &&
              e.variable == lagged(:Vegetation, 1)
        # space_ref of a lag disagrees with the base.
        tr = deepcopy(transition)
        set_subpart!(tr, variable_id(tr, lagged(:Vegetation, 1)), :space_ref,
                     NamedRef("veg"))
        e = template_error(initial, tr)
        @test e isa DynamicTemplateError && e.what == :space_ref
        # The initial network must cover exactly the current variables.
        ini = bayesnet(:Vegetation => [:sparse, :dense])
        e = template_error(ini, transition)
        @test e isa DynamicTemplateError && e.what == :initial_variables &&
              e.variable == :Herbivores
        ini = bayesnet(:Vegetation => [:sparse, :dense], :Herbivores => [:low, :high],
                       :Predators => [:few, :many])
        e = template_error(ini, transition)
        @test e isa DynamicTemplateError && e.what == :initial_variables &&
              e.variable == :Predators
        # ... with the same states and space_ref.
        ini = bayesnet(:Vegetation => [:sparse, :dense], :Herbivores => [:high, :low])
        e = template_error(ini, transition)
        @test e isa DynamicTemplateError && e.what == :states && e.variable == :Herbivores
        ini = bayesnet(:Vegetation => [:sparse, :dense], :Herbivores => [:low, :high];
                       space_refs=Dict(:Vegetation => NamedRef("veg")))
        e = template_error(ini, transition)
        @test e isa DynamicTemplateError && e.what == :space_ref
        # Structural errors of the templates come first: an open initial network ...
        ini = bayesnet(:Vegetation => [:sparse, :dense], :Herbivores => [:low, :high];
                       mechanisms=[:Herbivores => :Vegetation], closed=false)
        @test template_error(ini, transition) isa MissingMechanismError
        # ... and a within-slice cycle in the transition.
        tr = deepcopy(transition)
        add_input!(tr, :Vegetation_mechanism, :Herbivores)
        @test template_error(initial, tr) isa CyclicBayesNetError
    end

    @testset "unroll" begin
        dbn = vegetation_herbivore_dbn()
        for h in (1, 3, 5)
            u = unroll(dbn, h)
            @test validate(u; closed=true, unique_names=true) === nothing
            @test nparts(u, :Variable) == 2 * (h + 1)
            @test horizon(u) == h
            for t in 0:h
                @test slice_variables(u, t) == [variable_at(:Vegetation, t),
                                                variable_at(:Herbivores, t)]
                @test states(u, variable_at(:Vegetation, t)) == [:sparse, :dense]
                @test variable_name.(Ref(u), parents(u, variable_at(:Herbivores, t))) ==
                      [variable_at(:Vegetation, t)]
                expected = t == 0 ? Symbol[] :
                           [variable_at(:Vegetation, t - 1),
                            variable_at(:Herbivores, t - 1)]
                @test variable_name.(Ref(u), parents(u, variable_at(:Vegetation, t))) ==
                      expected
            end
        end
        # Horizon 0 is the initial slice alone.
        u0 = unroll(dbn, 0)
        @test u0 == initial_slice(dbn)
        @test sort(variable_names(u0)) == [:Herbivores_0, :Vegetation_0]
        @test_throws HorizonError unroll(dbn, -1)
        @test_throws HorizonError transition_slice(dbn, 0)
        e = try
            unroll(DynamicBayesNet(initial, transition, 2), 0)
        catch err
            err
        end
        @test e isa HorizonError && e.horizon == 0 && e.minimum == 1 && e.lags == 2
        @test occursin("2 lags", sprint(showerror, e))
        # Mechanism names and references follow the slice.
        @test sort(mechanism_names(unroll(dbn, 1))) ==
              sort([:Vegetation_0_mechanism, :Herbivores_0_mechanism,
                    :Vegetation_1_mechanism, :Herbivores_1_mechanism])
        tr = soft_intervention(transition, :Herbivores => NamedRef("policy_k");
                               name=:grazing_policy)
        tr = do_intervention(tr, :Vegetation => :dense)
        u = unroll(DynamicBayesNet(initial, tr), 2)
        @test kernel_ref(u, :grazing_policy_1) == NamedRef("policy_k_1")
        @test kernel_ref(u, Symbol("do[Vegetation=dense]_2")) == PointMassRef(:dense)
        @test isempty(parents(u, :Vegetation_2))
        # The transition slice is the open piece added for slice t.
        ts = transition_slice(dbn, 2)
        @test variable_name.(Ref(ts), exogenous(ts)) == [:Vegetation_1, :Herbivores_1]
        @test sort(variable_names(ts)) ==
              [:Herbivores_1, :Herbivores_2, :Vegetation_1, :Vegetation_2]
    end

    @testset "dynamic model: binding and unrolling" begin
        dm0 = DynamicBayesModel(vegetation_herbivore_dbn())
        @test !has_semantics(dm0)
        @test missing_kernels(dm0) == [:initial => :Herbivores, :initial => :Vegetation,
                                       :transition => :Vegetation,
                                       :transition => :Herbivores]
        @test validate(dm0) === nothing
        @test_throws MissingKernelError validate(dm0; semantics=true)
        @test template(dm0) == vegetation_herbivore_dbn()
        @test lags(dm0) == 1
        @test current_variables(dm0) == [:Vegetation, :Herbivores]
        @test lagged_variables(dm0) == [lagged(:Vegetation, 1), lagged(:Herbivores, 1)]
        @test occursin("lags = 1", sprint(show, dm0))
        dm = vegetation_herbivore_model()
        @test has_semantics(dm)
        @test validate(dm; semantics=true) === nothing
        @test occursin("4 kernels", sprint(show, dm))
        @test initial_network(dm) isa BayesModel
        @test transition_network(dm) isa BayesModel
        k = kernel(dm, :Vegetation)
        @test names(k.dom) == [lagged(:Vegetation, 1), lagged(:Herbivores, 1)]
        @test names(k.codom) == [:Vegetation]
        @test probability(k, :dense, (:sparse, :low)) ≈ 0.5
        @test kernel(dm, :Vegetation; slice=:initial).table ≈ [0.4, 0.6]
        @test_throws ArgumentError kernel(dm, :Vegetation; slice=:middle)
        # bind_kernel with an explicit kernel on the initial slice.
        dm2 = bind_kernel(dm0,
                          :Vegetation => state(space(initial_network(dm0), :Vegetation),
                                               [0.4, 0.6]); slice=:initial)
        @test missing_kernels(dm2) == [:initial => :Herbivores, :transition => :Vegetation,
                                       :transition => :Herbivores]
        @test dm2 == bind_cpt(dm0, :Vegetation => [0.4, 0.6]; slice=:initial)
        @test hash(dm2) == hash(bind_cpt(dm0, :Vegetation => [0.4, 0.6]; slice=:initial))
        # A wrong table shape is caught by the template model.
        @test_throws KernelBindingError bind_cpt(dm0, :Vegetation => [0.4, 0.6])
        # Unrolled model: kernels are copied per slice with renamed axes.
        um = unroll(dm, 3)
        @test um isa BayesModel
        @test validate(um; closed=true, unique_names=true, semantics=true) === nothing
        @test has_semantics(um)
        @test isempty(evidence(um)) && isempty(history(um))
        @test names(kernel(um, :Vegetation_2).dom) == [:Vegetation_1, :Herbivores_1]
        @test kernel(um, :Vegetation_2).table == kernel(dm, :Vegetation).table
        @test kernel(um, :Vegetation_0).table ≈ [0.4, 0.6]
        @test kernel(um, :Herbivores_3).table == kernel(dm, :Herbivores).table
        @test kernel_ref(syntax(um), :Vegetation_2_mechanism) ==
              NamedRef("Vegetation_2_mechanism")
        @test sum(joint_distribution(um).table) ≈ 1
        # Missing template kernels are simply missing in the unrolled model.
        @test missing_kernels(unroll(dm2, 2)) ==
              [:Herbivores_0, :Vegetation_1, :Herbivores_1, :Vegetation_2, :Herbivores_2]
        # Point masses on the template are kept.
        dmd = DynamicBayesModel(initial_network(dm),
                                do_intervention(transition_network(dm),
                                                :Vegetation => :dense), 1)
        umd = unroll(dmd, 2)
        @test kernel(umd, :Vegetation_1).table ≈ [0.0, 1.0]
        @test marginal(umd, :Vegetation_2).table ≈ [0.0, 1.0]
        @test marginal(umd, :Vegetation_0).table ≈ [0.4, 0.6]
    end

    @testset "forward marginals against a hand recursion" begin
        dm = vegetation_herbivore_model()
        h = 4
        um = unroll(dm, h)
        joints = forward_joints(h)
        for t in 0:h
            J = marginal(um, [variable_at(:Vegetation, t), variable_at(:Herbivores, t)])
            @test J.table ≈ joints[t + 1]
            @test filter_marginal(um, :Vegetation, t).table ≈
                  vec(sum(joints[t + 1]; dims=2))
        end
        rv = rollout(um, :Vegetation)
        @test length(rv) == h + 1
        @test all(rv[t + 1].table ≈ vec(sum(joints[t + 1]; dims=2)) for t in 0:h)
        @test rv[1].table ≈ [0.4, 0.6]
        @test rv[2].table ≈ [0.422, 0.578]
        @test names(rv[3].codom) == [:Vegetation_2]
        @test rollout(dm, :Vegetation, h) == rv
        # The same recursion with kernel composition: J_t ⋅ T = P(Vegetation_{t+1}).
        T = kernel(um, :Vegetation_1)
        J0 = marginal(um, [:Vegetation_0, :Herbivores_0])
        @test compose_kernel(J0, T).table ≈ marginal(um, :Vegetation_1).table
        # Evidence: filtering and smoothing through the model's evidence.
        ume = observe(um, :Herbivores_1 => :high)
        f = filter_marginal(ume, :Vegetation, 2)
        @test f ≈ marginal(um, :Vegetation_2; evidence=Dict(:Herbivores_1 => :high))
        @test f.table[2] < rv[3].table[2]        # many herbivores lower vegetation
        s = filter_marginal(um, :Vegetation, 0; evidence=[:Herbivores_1 => :high])
        @test s.table[2] > 0.6                   # ... and are evidence of earlier growth
        @test rollout(ume, :Herbivores)[2].table ≈ [0.0, 1.0]
        # An intervention on slice 2 changes later slices only.
        umi = do_intervention(um, :Herbivores_2 => :high)
        @test marginal(umi, :Vegetation_2) ≈ marginal(um, :Vegetation_2)
        @test marginal(umi, :Vegetation_1) ≈ marginal(um, :Vegetation_1)
        @test marginal(umi, :Vegetation_3).table[2] < marginal(um, :Vegetation_3).table[2]
        # Management lowers herbivore pressure and raises vegetation.
        umm = unroll(vegetation_herbivore_model(; management=true), 3)
        @test validate(umm; closed=true, unique_names=true, semantics=true) === nothing
        @test marginal(umm, :Herbivores_3).table[2] < marginal(um, :Herbivores_3).table[2]
        @test marginal(umm, :Vegetation_3).table[2] > marginal(um, :Vegetation_3).table[2]
        @test marginal(umm, :Vegetation_3; evidence=Dict(:Management_2 => :cull)).table[2] >
              marginal(umm, :Vegetation_3).table[2]
    end

    @testset "rollout uses the recorded unrolling, not the names" begin
        dm = vegetation_herbivore_model()
        um = unroll(dm, 3)
        @test is_unrolled(um)
        @test horizon(um) == 3 == horizon(syntax(um))
        @test extras(um)[UNROLLED_EXTRA][:lags] == 1
        # The record survives every operation, because they all carry `extras` over.
        @test is_unrolled(observe(um, :Herbivores_1 => :high))
        @test horizon(do_intervention(um, :Herbivores_2 => :high)) == 3
        @test length(rollout(observe(um, :Herbivores_1 => :high), :Vegetation)) == 4
        # A model that `unroll` did not produce is refused, even when its names look
        # like slices: `horizon` on the network reads the names and finds a slice 1.
        plain = bind_cpt(BayesModel(bayesnet(Symbol("A_1") => [:lo, :hi],
                                             :B => [:lo, :hi];
                                             mechanisms=[:B => Symbol("A_1")])),
                         [Symbol("A_1") => [0.4, 0.6], :B => [0.9 0.1; 0.2 0.8]])
        @test horizon(syntax(plain)) == 1
        @test !is_unrolled(plain)
        e = try
            rollout(plain, :A)
        catch err
            err
        end
        @test e isa NotUnrolledError && e.operation == :rollout && e.variable == :A
        @test occursin("unroll", sprint(showerror, e))
        @test_throws NotUnrolledError horizon(plain)
        @test occursin("needs a model produced by",
                       sprint(showerror, NotUnrolledError(:horizon)))
        # A variable that is not one of the template's is a typed error too.
        @test_throws UnknownVariableError rollout(um, :Nope)
    end

    @testset "two lags" begin
        # Vegetation depends on the vegetation two slices back as well; the initial
        # network covers slices 0 and 1 with the lag notation relative to slice 1.
        tr = bayesnet(:Vegetation => [:sparse, :dense], :Herbivores => [:low, :high],
                      lagged(:Vegetation, 1) => [:sparse, :dense],
                      lagged(:Vegetation, 2) => [:sparse, :dense],
                      lagged(:Herbivores, 1) => [:low, :high];
                      mechanisms=[:Vegetation => (lagged(:Vegetation, 1),
                                                  lagged(:Vegetation, 2),
                                                  lagged(:Herbivores, 1)),
                                  :Herbivores => :Vegetation], closed=false)
        ini = bayesnet(lagged(:Vegetation, 1) => [:sparse, :dense],
                       lagged(:Herbivores, 1) => [:low, :high],
                       :Vegetation => [:sparse, :dense], :Herbivores => [:low, :high];
                       mechanisms=[lagged(:Herbivores, 1) => lagged(:Vegetation, 1),
                                   :Vegetation => (lagged(:Vegetation, 1),
                                                   lagged(:Herbivores, 1)),
                                   :Herbivores => :Vegetation])
        dbn = DynamicBayesNet(ini, tr)
        @test lags(dbn) == 2
        @test validate(dbn) === nothing
        # An initial network over one slice only is rejected.
        e = template_error(initial, tr; lags=2)
        @test e isa DynamicTemplateError && e.what == :initial_variables
        @test_throws HorizonError unroll(dbn, 0)
        u1 = unroll(dbn, 1)
        @test validate(u1; closed=true, unique_names=true) === nothing
        @test sort(variable_names(u1)) ==
              [:Herbivores_0, :Herbivores_1, :Vegetation_0, :Vegetation_1]
        @test variable_name.(Ref(u1), parents(u1, :Vegetation_1)) ==
              [:Vegetation_0, :Herbivores_0]
        @test sort(mechanism_names(u1)) ==
              sort([:Vegetation_0_mechanism, :Herbivores_0_mechanism,
                    :Vegetation_1_mechanism, :Herbivores_1_mechanism])
        u = unroll(dbn, 4)
        @test validate(u; closed=true, unique_names=true) === nothing
        @test horizon(u) == 4
        for t in 2:4
            @test variable_name.(Ref(u), parents(u, variable_at(:Vegetation, t))) ==
                  [variable_at(:Vegetation, t - 1), variable_at(:Vegetation, t - 2),
                   variable_at(:Herbivores, t - 1)]
        end
        # Semantics with two lags: the unrolled joint normalises and the slice-1
        # marginal agrees with the initial model alone.
        dm = DynamicBayesModel(dbn)
        veg2 = zeros(2, 2, 2, 2)
        for i in 1:2, j in 1:2, k in 1:2
            p = 0.3 + 0.2 * (i - 1) + 0.2 * (j - 1) - 0.15 * (k - 1)
            veg2[i, j, k, :] = [1 - p, p]
        end
        dm = bind_cpt(dm, [:Vegetation => veg2, :Herbivores => [0.7 0.3; 0.3 0.7]])
        veg1 = zeros(2, 2, 2)
        veg1[1, 1, :] = [0.5, 0.5]
        veg1[1, 2, :] = [0.8, 0.2]
        veg1[2, 1, :] = [0.1, 0.9]
        veg1[2, 2, :] = [0.4, 0.6]
        dm = bind_cpt(dm,
                      [lagged(:Vegetation, 1) => [0.4, 0.6],
                       lagged(:Herbivores, 1) => [0.7 0.3; 0.3 0.7],
                       :Vegetation => veg1, :Herbivores => [0.7 0.3; 0.3 0.7]];
                      slice=:initial)
        @test has_semantics(dm)
        um = unroll(dm, 3)
        @test validate(um; closed=true, unique_names=true, semantics=true) === nothing
        @test sum(joint_distribution(um).table) ≈ 1
        @test marginal(um, :Vegetation_1).table ≈ [0.422, 0.578]
        @test marginal(um, :Vegetation_0).table ≈ [0.4, 0.6]
        @test names(kernel(um, :Vegetation_3).dom) ==
              [:Vegetation_2, :Vegetation_1, :Herbivores_2]
        # Slices 0 and 1 are the initial model's joint.
        @test marginal(um,
                       [:Vegetation_0, :Herbivores_0, :Vegetation_1, :Herbivores_1]).table ≈
              marginal(initial_network(dm),
                       [lagged(:Vegetation, 1), lagged(:Herbivores, 1), :Vegetation,
                        :Herbivores]).table
    end

    @testset "variable elimination on a longer horizon" begin
        # Marginals of a prefix do not depend on the horizon, so infer on h = 8 must
        # agree with brute force on h = 4.
        dm = vegetation_herbivore_model()
        um4 = unroll(dm, 4)
        um8 = unroll(dm, 8)
        for t in 0:4, x in (:Vegetation, :Herbivores)
            p, _ = infer(um8, variable_at(x, t))
            @test p.table ≈ filter_marginal(um4, x, t).table
        end
        p, _ = infer(um8, :Vegetation_3; evidence=Dict(:Herbivores_1 => :high))
        @test p.table ≈
              marginal(um4, :Vegetation_3; evidence=Dict(:Herbivores_1 => :high)).table
        @test sum(first(infer(um8, :Vegetation_8)).table) ≈ 1
    end
end
