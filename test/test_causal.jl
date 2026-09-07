# Numeric tests of observation versus intervention (SPEC section 55.4, milestones M5/M6),
# all against the brute-force joint.

@testset "Observation versus intervention, numerically" begin
    # Chain X -> Y -> Z with a strong dependence of Y on X.
    chain = bind_cpt(BayesModel(bayesnet(:X => [:x0, :x1], :Y => [:y0, :y1],
                                         :Z => [:z0, :z1];
                                         mechanisms=[:Y => :X, :Z => :Y])),
                     [:X => [0.3, 0.7], :Y => [0.9 0.1; 0.2 0.8], :Z => [0.6 0.4; 0.1 0.9]])
    obs = observe(chain, :Y => :y1)
    doy = do_intervention(chain, :Y => :y1)

    @testset "chain" begin
        # Observing Y changes P(X); intervening on Y leaves P(X) unchanged.
        px = marginal(chain, :X).table
        px_obs = marginal(obs, :X).table
        px_do = marginal(doy, :X).table
        @test px ≈ [0.3, 0.7]
        @test px_obs ≈ [0.3 * 0.1, 0.7 * 0.8] ./ (0.3 * 0.1 + 0.7 * 0.8)
        @test !(px_obs ≈ px)
        @test px_do ≈ px
        # Downstream, P(Z | Y = y1) is the same under both.
        @test marginal(obs, :Z).table ≈ [0.1, 0.9]
        @test marginal(doy, :Z).table ≈ [0.1, 0.9]
        @test marginal(doy, :Z).table ≈ marginal(obs, :Z).table
        # The intervened joint is normalised and has no dependence of Y on X.
        J = joint_distribution(doy)
        @test sum(J.table) ≈ 1
        @test names(J.codom) == [:X, :Y, :Z]
        @test all(J.table[:, 1, :] .== 0)
        @test conditional(doy, :Y, :X).table ≈ [0.0 0.0; 1.0 1.0]
        @test conditional(chain, :Y, :X) ≈ kernel(chain, :Y)
        # The downstream mechanism is untouched: the same kernel object.
        @test kernel(doy, :Z) == kernel(chain, :Z)
        @test kernel(doy, :Y) == point_mass(space(chain, :Y), :y1)
        # Observation and intervention combine: do(Y) then observe Z tells nothing about X.
        @test marginal(observe(doy, :Z => :z1), :X).table ≈ px
        @test !(marginal(observe(chain, :Z => :z1), :X).table ≈ px)
    end

    @testset "fork (confounding)" begin
        # X -> Y, X -> Z: Y and Z are dependent through X, but do(Y) breaks the link.
        fork = bind_cpt(BayesModel(bayesnet(:X => [:x0, :x1], :Y => [:y0, :y1],
                                            :Z => [:z0, :z1];
                                            mechanisms=[:Y => :X, :Z => :X])),
                        [:X => [0.5, 0.5], :Y => [0.9 0.1; 0.1 0.9],
                         :Z => [0.8 0.2; 0.3 0.7]])
        pz = marginal(fork, :Z).table
        @test pz ≈ [0.55, 0.45]
        @test !(marginal(observe(fork, :Y => :y1), :Z).table ≈ pz)   # conditioning moves Z
        @test marginal(do_intervention(fork, :Y => :y1), :Z).table ≈ pz   # intervention does not
        @test marginal(do_intervention(fork, :Y => :y1), :X).table ≈ [0.5, 0.5]
        # Association differs from causation: P(Z | Y) vs P(Z | do(Y)).
        assoc = conditional(fork, :Z, :Y)
        causal = hcat([marginal(do_intervention(fork, :Y => y), :Z).table
                       for y in [:y0, :y1]]...)
        @test !(assoc.table ≈ causal)
        @test all(causal[:, j] ≈ pz for j in 1:2)
    end

    @testset "reference model interventions (SPEC section 45)" begin
        m = reference_habitat_model()
        # do(GrazingPressure = low) versus observing it.
        p_do = marginal(do_intervention(m, :GrazingPressure => :low), :Occupancy)
        p_obs = marginal(observe(m, :GrazingPressure => :low), :Occupancy)
        # GrazingPressure is a root, so seeing and doing coincide downstream ...
        @test p_do ≈ p_obs
        # ... but not for a non-root: do(Vegetation = dense) leaves SoilMoisture alone.
        @test marginal(do_intervention(m, :Vegetation => :dense), :SoilMoisture) ≈
              marginal(m, :SoilMoisture)
        @test !(marginal(observe(m, :Vegetation => :dense), :SoilMoisture) ≈
                marginal(m, :SoilMoisture))
        @test marginal(do_intervention(m, :Vegetation => :dense), :Occupancy) ≈
              marginal(observe(m, :Vegetation => :dense), :Occupancy)
        # do(Irrigation = high) and the example query of the SPEC.
        mi = do_intervention(m, :Irrigation => :high)
        @test sum(joint_distribution(mi).table) ≈ 1
        @test marginal(mi, :Irrigation).table ≈ [0.0, 1.0]
        @test marginal(mi, :Climate).table ≈ [0.3, 0.5, 0.2]
        q = probability(marginal(do_intervention(m, :GrazingPressure => :low), :Occupancy),
                        :present)
        @test 0 < q < 1
        @test q ≈ probability(marginal(m, :Occupancy; evidence=[:GrazingPressure => :low]),
                              :present)
        # Hard interventions yield normalised joints whichever variable is hit.
        for x in variable_names(syntax(m)), s in states(syntax(m), x)
            @test sum(joint_distribution(do_intervention(m, x => s)).table) ≈ 1
        end
    end

    @testset "soft intervention with a new kernel" begin
        m = reference_habitat_model()
        # Fenced plots: Vegetation no longer depends on GrazingPressure.
        fenced = cpt(axis(syntax(m), :SoilMoisture), axis(syntax(m), :Vegetation),
                     [0.5 0.4 0.1; 0.2 0.5 0.3; 0.05 0.25 0.7])
        ms = soft_intervention(m, :Vegetation => fenced)
        @test validate(ms; closed=true, semantics=true) === nothing
        J = joint_distribution(ms)
        @test sum(J.table) ≈ 1
        @test conditional(ms, :Vegetation, :SoilMoisture) ≈ fenced
        # Vegetation is now independent of GrazingPressure.
        pv = marginal(ms, :Vegetation).table
        @test marginal(ms, :Vegetation; evidence=[:GrazingPressure => :high]).table ≈ pv
        @test !(marginal(m, :Vegetation; evidence=[:GrazingPressure => :high]).table ≈
                marginal(m, :Vegetation).table)
        # A soft intervention that keeps the parents but changes the kernel.
        uniform_veg = cpt([axis(syntax(m), :SoilMoisture),
                           axis(syntax(m), :GrazingPressure)],
                          axis(syntax(m), :Vegetation), fill(1 / 3, 3, 2, 3))
        mu = soft_intervention(m, :Vegetation => uniform_veg)
        @test marginal(mu, :Vegetation).table ≈ fill(1 / 3, 3)
        @test marginal(mu, :SoilMoisture) ≈ marginal(m, :SoilMoisture)
        # The tolerance of the kernel check is a keyword, as for bind_kernel.
        rough = cpt(axis(syntax(m), :SoilMoisture), axis(syntax(m), :Vegetation),
                    [0.5 0.4 0.1; 0.2 0.5 0.3; 0.05 0.25 0.7] .+ 1e-7; check=false)
        @test_throws UnnormalizedKernelError soft_intervention(m, :Vegetation => rough)
        mrough = soft_intervention(m, :Vegetation => rough; atol=1e-6)
        @test validate(mrough; semantics=true, atol=1e-6) === nothing
        @test_throws UnnormalizedKernelError validate(mrough; semantics=true)
    end
end
