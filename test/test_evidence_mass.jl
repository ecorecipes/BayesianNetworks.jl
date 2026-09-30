# Evidence mass (ADR 0014): ImpossibleEvidenceError means probability exactly zero. Evidence
# whose binary64 mass underflows is recomputed exactly and answered, correctly rounded
# (ADR 0016); tolerated
# negative entries that leave the posterior's sign to rounding raise
# IndeterminatePosteriorError.
@testset "evidence mass (ADR 0014)" begin
    bn = bayesnet(:A => [:a, :b], :B => [:x, :y], :C => [:u, :v];
                  mechanisms=[:A => (), :B => (), :C => (:A,)])
    kernels_C = [0.3 0.7; 0.6 0.4]

    @testset "underflowed evidence is answered, not called impossible" begin
        # Two independent observations of probability 1e-200 each: mass 1e-400.
        m = bind_cpt(BayesModel(bn),
                     [:A => [1 - 1e-200, 1e-200],
                      :B => [1 - 1e-200, 1e-200], :C => kernels_C])
        ev = Dict(:A => :b, :B => :y)
        p = marginal(m, :C; evidence=ev)
        @test isapprox(p.table, [0.6, 0.4]; rtol=1e-12)
        @test names(p.codom) == [:C]
        # A subnormal mass (about 1e-320) is also recomputed, not trusted.
        ms = bind_cpt(BayesModel(bn),
                      [:A => [1 - 1e-160, 1e-160],
                       :B => [1 - 1e-160, 1e-160], :C => kernels_C])
        @test isapprox(marginal(ms, :C; evidence=ev).table, [0.6, 0.4]; rtol=1e-12)
        # A joint query keeps the order of `vars`.
        pj = marginal(m, [:C, :A]; evidence=ev)
        @test names(pj.codom) == [:C, :A]
        @test isapprox(pj.table[:, 2], [0.6, 0.4]; rtol=1e-12)
        @test all(iszero, pj.table[:, 1])
    end

    @testset "the fallback is correctly rounded (ADR 0016)" begin
        exact(x) = Rational{BigInt}(x)
        nearest = BayesianNetworks._nearest_binary64
        # Float64(0.6) + Float64(0.4) is exactly one, so the exact posterior is representable
        # and the fallback returns it bit for bit.
        m = bind_cpt(BayesModel(bn),
                     [:A => [1 - 1e-200, 1e-200],
                      :B => [1 - 1e-200, 1e-200], :C => kernels_C])
        ev = Dict(:A => :b, :B => :y)
        @test marginal(m, :C; evidence=ev).table == [0.6, 0.4]
        # Float64(0.1) + Float64(0.9) is 1 + 2^-55, so the posterior is not a row of the
        # table: each cell is the Float64 nearest the exact quotient.
        m19 = bind_cpt(m, :C => [0.3 0.7; 0.1 0.9])
        want = [nearest(exact(0.1) / (exact(0.1) + exact(0.9))),
                nearest(exact(0.9) / (exact(0.1) + exact(0.9)))]
        @test marginal(m19, :C; evidence=ev).table == want
        # A posterior that depends on the rare numbers themselves.
        xy = bayesnet(:X => [:x0, :x1], :Y => [:n, :y], :Z => [:n, :z];
                      mechanisms=[:X => (), :Y => (:X,), :Z => ()])
        mx = bind_cpt(BayesModel(xy),
                      [:X => [0.3, 0.7], :Y => [1-1e-200 1e-200; 1-3e-200 3e-200],
                       :Z => [1 - 1e-200, 1e-200]])
        w = [exact(0.3) * exact(1e-200), exact(0.7) * exact(3e-200)]
        @test marginal(mx, :X; evidence=Dict(:Y => :y, :Z => :z)).table ==
              [nearest(w[1] / sum(w)), nearest(w[2] / sum(w))]
        # `conditional` recomputes the underflowed column exactly too.
        k = conditional(m, :C, :A; evidence=Dict(:B => :y))
        @test cpt(k)[2, :] == [0.6, 0.4]
        # The rounding: ties to even at the midpoint between 1 and its successor.
        midpoint = (exact(1.0) + exact(nextfloat(1.0))) / 2
        @test nearest(midpoint) == 1.0
        @test nearest(midpoint + big(1) // big(2)^500) == nextfloat(1.0)
        for x in (-0.5, 0.1, 1e-310, floatmax(Float64), 0.0)
            n, e = BayesianNetworks._dyadic(x)
            scale = e >= 0 ? big(2)^e // big(1) : big(1) // big(2)^-e
            @test n * scale == Rational{BigInt}(x)
        end
    end

    @testset "exact zero is still impossible" begin
        m0 = bind_cpt(BayesModel(bn), [:A => [1.0, 0.0], :B => [0.5, 0.5], :C => kernels_C])
        e = try
            marginal(m0, :C; evidence=Dict(:A => :b))
        catch err
            err
        end
        @test e isa ImpossibleEvidenceError && e.evidence == Dict(:A => :b)
    end

    @testset "conditional recomputes underflowed columns" begin
        mc = bind_cpt(BayesModel(bn),
                      [:A => [1.0, 1e-300], :B => [1 - 1e-200, 1e-200],
                       :C => kernels_C])
        k = conditional(mc, :C, :A; evidence=Dict(:B => :y))
        @test isapprox(k.table[:, 1], [0.3, 0.7]; rtol=1e-12)
        @test isapprox(k.table[:, 2], [0.6, 0.4]; rtol=1e-12)
        # A column of probability exactly zero still follows on_zero.
        mz = bind_cpt(BayesModel(bn),
                      [:A => [1.0, 0.0], :B => [1 - 1e-200, 1e-200],
                       :C => kernels_C])
        @test conditional(mz, :C, :A; evidence=Dict(:B => :y)).table[:, 2] == [0.5, 0.5]
        @test_throws ImpossibleEvidenceError conditional(mz, :C, :A;
                                                         evidence=Dict(:B => :y),
                                                         on_zero=:error)
    end

    @testset "tolerated negatives leave the posterior indeterminate" begin
        bn2 = bayesnet(:X => [:x0, :x1], :Y => [:y0, :y1];
                       mechanisms=[:X => (), :Y => (:X,)])
        mn = bind_cpt(BayesModel(bn2), [:X => [0.9, 0.1], :Y => [0.5 0.5; 1.0+5e-7 -5e-7]];
                      atol=1e-6)
        # Evidence of probability 0.1 whose posterior cell would be about -4e-6.
        e = try
            marginal(mn, :X; evidence=Dict(:Y => :y1), atol=1e-6)
        catch err
            err
        end
        @test e isa IndeterminatePosteriorError && e isa BayesNetError
        @test e.evidence == Dict(:Y => :y1)
        @test occursin("negative", e.detail)
        # Evidence that keeps every cell nonnegative is answered.
        p = marginal(mn, :X; evidence=Dict(:Y => :y0), atol=1e-6)
        @test all(>=(0), p.table) && isapprox(sum(p.table), 1.0)
        # Evidence whose mass (about 4e-7) is positive and normal but within the tolerance
        # budget (about 2e-6) of zero is indeterminate.
        mb = bind_cpt(BayesModel(bn2),
                      [:X => [1.0 - 1e-6, 1e-6],
                       :Y => [1.0+1e-7 -1e-7; 0.5 0.5]]; atol=1e-6)
        eb = try
            marginal(mb, :X; evidence=Dict(:Y => :y1), atol=1e-6)
        catch err
            err
        end
        @test eb isa IndeterminatePosteriorError
        @test occursin("budget", eb.detail)
        # A negative total is below binary64's normal range, so it takes the log-domain
        # path, where the tolerated negative entry is reported.
        mneg = bind_cpt(BayesModel(bn2),
                        [:X => [1.0 - 1e-9, 1e-9],
                         :Y => [1.0+1e-7 -1e-7; 0.5 0.5]]; atol=1e-6)
        @test_throws IndeterminatePosteriorError marginal(mneg, :X;
                                                          evidence=Dict(:Y => :y1),
                                                          atol=1e-6)
    end
end

@testset "joint state counts do not overflow" begin
    # The count was an Int128 product, which wraps past 2^127: 2^200 states came out as 0
    # and passed the max_states guard, failing later with "invalid Array dimensions".
    let v = [Symbol("X", i) for i in 1:200]
        m = BayesModel(bayesnet([x => [:a, :b] for x in v]...;
                                mechanisms=[x => () for x in v]))
        for x in v
            m = bind_cpt(m, x => [0.5, 0.5])
        end
        @test_throws ModelTooLargeError joint_distribution(m)
        @test_throws ModelTooLargeError marginal(m, :X1; evidence=Dict(:X2 => :a))
    end
end
