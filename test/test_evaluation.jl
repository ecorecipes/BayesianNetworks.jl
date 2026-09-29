using Random

@testset "Evaluation" begin
    m = reference_habitat_model()
    bn = syntax(m)

    @testset "joint_distribution" begin
        J = joint_distribution(m)
        @test J isa FiniteKernel
        @test isempty(J.dom)
        @test names(J.codom) == variable_name.(Ref(bn), topological_order(bn))
        @test size(J.table) == (3, 2, 3, 2, 3, 2, 2)
        @test sum(J.table) ≈ 1
        @test all(>=(0), J.table)
        # One entry by hand: P(dry, low, low, low, sparse, poor, absent).
        @test J.table[1, 1, 1, 1, 1, 1, 1] ≈ 0.3 * 0.6 * 0.7 * 0.5 * 0.6 * 0.85 * 0.8
        # Reordered axes.
        J2 = joint_distribution(m;
                                variables=[:Occupancy, :Climate, :Irrigation, :SoilMoisture,
                                           :GrazingPressure, :Vegetation, :HabitatQuality])
        @test names(J2.codom)[1] == :Occupancy
        @test permutedims(J2.table, (2, 3, 4, 5, 6, 7, 1)) ≈ J.table
        @test_throws ArgumentError joint_distribution(m; variables=[:Occupancy])
        @test_throws MissingKernelError joint_distribution(BayesModel(reference_habitat_bn()))
        @test_throws MissingMechanismError joint_distribution(BayesModel(biotic_bn()))
        e = try
            joint_distribution(m; max_states=100)
        catch err
            err
        end
        @test e isa ModelTooLargeError && e.nstates == 432 && e.limit == 100
        @test occursin("432", sprint(showerror, e))
        # Named-axis table.
        jt = joint_table(m)
        @test jt isa JointTable
        @test jt.variables == names(J.codom)
        @test jt.states[1] == [:dry, :normal, :wet]
        @test jt[:Climate => :dry, :Irrigation => :low, :SoilMoisture => :low,
                 :GrazingPressure => :low, :Vegetation => :sparse, :HabitatQuality => :poor,
                 :Occupancy => :absent] ≈ J.table[1, 1, 1, 1, 1, 1, 1]
        @test jt[:Occupancy => :absent, :Climate => :dry, :Irrigation => :low,
                 :SoilMoisture => :low, :GrazingPressure => :low, :Vegetation => :sparse,
                 :HabitatQuality => :poor] ≈ J.table[1, 1, 1, 1, 1, 1, 1]
        @test_throws ArgumentError jt[:Climate => :dry]
        @test_throws UnknownStateError jt[:Climate => :humid, :Irrigation => :low,
                                          :SoilMoisture => :low, :GrazingPressure => :low,
                                          :Vegetation => :sparse, :HabitatQuality => :poor,
                                          :Occupancy => :absent]
        @test occursin("Climate", sprint(show, jt))
    end

    @testset "marginal and conditional" begin
        # Marginals of roots are their priors; single-variable and multi-variable forms.
        @test marginal(m, :Climate).table ≈ [0.3, 0.5, 0.2]
        @test marginal(m, [:Climate]) == marginal(m, :Climate)
        @test marginal(m, :Climate).codom == space(m, :Climate)
        pm = marginal(m, [:Irrigation, :Climate])
        @test names(pm.codom) == [:Irrigation, :Climate]
        @test pm.table ≈ [0.6, 0.4] * [0.3, 0.5, 0.2]'
        # P(HabitatQuality) by hand from P(Vegetation).
        pv = marginal(m, :Vegetation).table
        @test marginal(m, :HabitatQuality).table ≈
              [0.85 0.4 0.15; 0.15 0.6 0.85] * pv
        @test marginal(m, :Occupancy).table ≈
              [0.8 0.25; 0.2 0.75] *
              marginal(m, :HabitatQuality).table
        # Evidence: the model's own, an override, and none.
        mo = observe(m, :HabitatQuality => :good)
        @test marginal(mo, :Occupancy).table ≈ [0.25, 0.75]
        @test marginal(mo, :Occupancy; evidence=Dict{Symbol,Symbol}()).table ≈
              marginal(m, :Occupancy).table
        @test marginal(m, :Occupancy; evidence=[:HabitatQuality => :good]).table ≈
              [0.25, 0.75]
        @test marginal(m, :Occupancy; evidence=(:HabitatQuality => :good)).table ≈
              [0.25, 0.75]
        # Bayes' rule upstream: P(HabitatQuality | Occupancy = present).
        ph = marginal(m, :HabitatQuality).table
        post = ph .* [0.2, 0.75]
        @test marginal(observe(m, :Occupancy => :present), :HabitatQuality).table ≈
              post ./ sum(post)
        @test_throws UnknownVariableError marginal(m, :Weather)
        @test_throws UnknownVariableError marginal(m, :Occupancy;
                                                   evidence=[:Weather => :dry])
        @test_throws UnknownStateError marginal(m, :Occupancy;
                                                evidence=[:Climate => :humid])
        # Impossible evidence.
        zero = soft_intervention(m, :Climate => state(space(m, :Climate), [1.0, 0.0, 0.0]))
        @test_throws ImpossibleEvidenceError marginal(observe(zero, :Climate => :wet),
                                                      :Occupancy)
        @test occursin("wet",
                       sprint(showerror, ImpossibleEvidenceError(Dict(:Climate => :wet))))
        # Zero means exactly zero: underflow is recomputed, never reported (ADR 0014).
        msg = sprint(showerror, ImpossibleEvidenceError(Dict(:Climate => :wet)))
        @test occursin("probability exactly zero", msg)
        @test !occursin("underflow", msg)
        # With no evidence, the zero mass belongs to the model or factor graph itself.
        empty_msg = sprint(showerror, ImpossibleEvidenceError(Dict{Symbol,Symbol}()))
        @test startswith(empty_msg, "ImpossibleEvidenceError: ")
        @test occursin("the model or factor graph has zero total mass", empty_msg)
        @test !occursin("Dict", empty_msg)
        # Conditionals recover the mechanism kernels and Bayes' rule.
        k = conditional(m, :Occupancy, :HabitatQuality)
        @test k ≈ kernel(m, :Occupancy)
        k2 = conditional(m, [:Vegetation], [:SoilMoisture, :GrazingPressure])
        @test k2 ≈ kernel(m, :Vegetation)
        k3 = conditional(m, :Occupancy, [:HabitatQuality, :Climate])
        @test names(k3.dom) == [:HabitatQuality, :Climate]
        @test all(k3.table[:, i, j] ≈ kernel(m, :Occupancy).table[:, i]
                  for i in 1:2, j in 1:3)
        kb = conditional(m, :HabitatQuality, :Occupancy)
        @test kb.table[:, 2] ≈ post ./ sum(post)
        @test is_normalized(kb)
        @test_throws ArgumentError conditional(m, :Occupancy, :Occupancy)
        # A zero-probability configuration of `given` gives a uniform column, and
        # `on_zero` chooses what else may happen there.
        kz = conditional(zero, :SoilMoisture, :Climate)
        @test kz.table[:, 3] ≈ fill(1 / 3, 3)
        @test is_normalized(kz)
        @test conditional(zero, :SoilMoisture, :Climate; on_zero=:uniform) == kz
        e = try
            conditional(zero, :SoilMoisture, :Climate; on_zero=:error)
        catch err
            err
        end
        @test e isa ImpossibleEvidenceError && e.evidence == Dict(:Climate => :normal)
        kn = conditional(zero, :SoilMoisture, :Climate; on_zero=:nan)
        @test all(isnan, kn.table[:, 2]) && all(isnan, kn.table[:, 3])
        @test kn.table[:, 1] == kz.table[:, 1]
        @test !is_normalized(kn)
        @test_throws ArgumentError conditional(zero, :SoilMoisture, :Climate;
                                               on_zero=:whatever)
    end

    @testset "normalisation tolerance" begin
        # A model whose rows are off by 5e-8, as a file with rounded probabilities gives
        # (`read_bayesnet` reads with `atol = 1e-6`): every brute-force evaluator must
        # accept the tolerance it was built with, not only `validate`.
        rough = bind_cpt(BayesModel(bayesnet(:X => [:a, :b], :Y => [:c, :d];
                                             mechanisms=[:Y => :X])),
                         [:X => [0.5, 0.5 + 5e-8], :Y => [0.9 0.1; 0.2 0.8]];
                         atol=1e-6)
        @test_throws UnnormalizedKernelError validate(rough; closed=true, semantics=true)
        @test validate(rough; closed=true, semantics=true, atol=1e-6) === nothing
        for f in (m -> joint_distribution(m), m -> joint_table(m),
                  m -> marginal(m, :Y), m -> conditional(m, :Y, :X),
                  m -> sample(m, 2))
            @test_throws UnnormalizedKernelError f(rough)
        end
        J = joint_distribution(rough; atol=1e-6)
        @test sum(J.table) ≈ 1 atol = 1e-6
        @test J.table[1, 1] ≈ 0.5 * 0.9 atol = 1e-7
        @test joint_table(rough; atol=1e-6).table ≈ J.table
        @test marginal(rough, :Y; atol=1e-6).table ≈ [0.5 * 0.9 + 0.5 * 0.2,
                                                      0.5 * 0.1 + 0.5 * 0.8] atol = 1e-6
        @test conditional(rough, :Y, :X; atol=1e-6).table ≈ [0.9 0.2; 0.1 0.8] atol = 1e-6
        @test length(sample(rough, 4; rng=MersenneTwister(1), atol=1e-6)) == 4
    end

    @testset "sampling" begin
        rng = MersenneTwister(2024)
        s = sample(m, 4000; rng=rng)
        @test length(s) == 4000
        @test all(Set(keys(x)) == Set(variable_names(bn)) for x in s)
        @test all(x[:Climate] in [:dry, :normal, :wet] for x in s)
        freq = empirical_marginal(s, :Occupancy)
        @test freq isa Dict{Symbol,Float64}
        @test sum(values(freq)) ≈ 1
        est = empirical_marginal(s, :Occupancy, space(m, :Occupancy))
        @test est isa FiniteKernel && est.codom == space(m, :Occupancy)
        @test maximum(abs.(est.table .- marginal(m, :Occupancy).table)) < 0.03
        estv = empirical_marginal(s, :Vegetation, space(m, :Vegetation))
        @test maximum(abs.(estv.table .- marginal(m, :Vegetation).table)) < 0.03
        @test_throws UnknownVariableError empirical_marginal(s, :Weather)
        # Deterministic given the seed, and interventions are respected.
        @test sample(m, 5; rng=MersenneTwister(1)) == sample(m, 5; rng=MersenneTwister(1))
        sd = sample(do_intervention(m, :Vegetation => :dense), 200; rng=rng)
        @test all(x[:Vegetation] == :dense for x in sd)
        @test_throws MissingKernelError sample(BayesModel(reference_habitat_bn()), 3)
        # A state absent from the samples has frequency zero in the kernel form.
        @test empirical_marginal(sd, :Vegetation, space(m, :Vegetation)).table ==
              [0.0, 0.0, 1.0]
    end
end
@testset "compound kernel normalization tolerance" begin
    for (n, atol, delta) in ((3, DEFAULT_ATOL, 9e-9),
                             (2, 1e-6, prevfloat(0.500001) - 0.5))
        names_ = [Symbol(:X, i) for i in 1:n]
        bn = bayesnet((x => [:no, :yes] for x in names_)...)
        row = [0.5, 0.5 + delta]
        m = bind_cpt(BayesModel(bn), [x => row for x in names_]; atol=atol)
        J = joint_distribution(m; atol=atol)
        @test sum(J.table) ≈ sum(row)^n
        @test sum(J.table) > 1 + (n == 3 ? atol : n * atol)
        @test size(J.table) == ntuple(_ -> 2, n)
    end
    @test BayesianNetworks._joint_atol(1e-6, 2) > 2e-6
    @test BayesianNetworks._joint_atol(0.0, 3) == 0
    @test_throws ArgumentError BayesianNetworks._joint_atol(-1e-8, 2)
end
