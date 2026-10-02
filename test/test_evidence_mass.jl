# Evidence mass (ADR 0014): ImpossibleEvidenceError means probability exactly zero. Evidence
# whose binary64 mass underflows is recomputed exactly and answered, correctly rounded
# (ADR 0016); tolerated
# negative entries that leave the posterior's sign to rounding raise
# IndeterminatePosteriorError.
@testset "evidence mass (ADR 0014)" begin
    bn = bayesnet(:A => [:a, :b], :B => [:x, :y], :C => [:u, :v];
                  mechanisms=[:A => (), :B => (), :C => (:A,)])
    kernels_C = [0.3 0.7; 0.6 0.4]
    exact(x) = Rational{BigInt}(x)
    nearest = BayesianNetworks._nearest_binary64

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
        # A negative total is below binary64's normal range, so it takes the exact path,
        # where the tolerated negative entry is reported.
        mneg = bind_cpt(BayesModel(bn2),
                        [:X => [1.0 - 1e-9, 1e-9],
                         :Y => [1.0+1e-7 -1e-7; 0.5 0.5]]; atol=1e-6)
        @test_throws IndeterminatePosteriorError marginal(mneg, :X;
                                                          evidence=Dict(:Y => :y1),
                                                          atol=1e-6)
    end

    # ADR 0014 decision 4 and ADR 0016 decision 4: the tolerance rule concerns the queried
    # posterior. A tolerated negative entry counts only on a configuration consistent with
    # the evidence whose other entries are nonzero, and only the cells of the returned
    # posterior must be nonnegative.
    @testset "the tolerance rule concerns the queried posterior" begin
        bnw = bayesnet(:W => [:w1, :w2], :X => [:x0, :x1], :Y => [:y0, :y1];
                       mechanisms=[:W => (), :X => (), :Y => (:X,)])
        # W is unrelated to the query and holds an entry of -5e-9, valid at the default atol.
        mw = bind_cpt(BayesModel(bnw),
                      [:W => [1 + 5e-9, -5e-9], :X => [0.3, 0.7],
                       :Y => [0.9 0.1; 0.2 0.8]])
        w = [exact(0.3) * exact(0.1), exact(0.7) * exact(0.8)]
        p = marginal(mw, :X; evidence=Dict(:Y => :y1))
        @test p.table ≈ Float64.(w ./ sum(w))
        # Before, the joint's negative cells (W = w2) raised "a posterior cell is negative".
        @test marginal(mw, :X; evidence=Dict(:X => :x0)).table == [1.0, 0.0]
        # A posterior cell of the query that is negative still raises.
        e = try
            marginal(mw, :W; evidence=Dict(:Y => :y1))
        catch err
            err
        end
        @test e isa IndeterminatePosteriorError && occursin("negative", e.detail)
        # Evidence that rules out every negative entry: a mass of 1e-10 is answered, as the
        # exact run answers a mass of 1e-400. Before, 1e-10 raised (budget).
        for rare in (1e-10, 1e-200)
            mr = bind_cpt(mw, :X => [1 - rare, rare])
            @test marginal(mr, :Y; evidence=Dict(:W => :w1, :X => :x1)).table ≈ [0.2, 0.8]
        end
        m400 = bind_cpt(mw, [:X => [1 - 1e-200, 1e-200], :Y => [0.9 0.1; 1-1e-200 1e-200]])
        @test marginal(m400, :W; evidence=Dict(:W => :w1, :X => :x1, :Y => :y1)).table ==
              [1.0, 0.0]
        # The negative entry still takes part when the evidence leaves W free.
        @test_throws IndeterminatePosteriorError marginal(bind_cpt(mw,
                                                                   :X => [1 - 1e-10, 1e-10]),
                                                          :Y; evidence=Dict(:X => :x1))
    end

    @testset "exactly zero columns of conditional follow on_zero" begin
        bnw = bayesnet(:W => [:w1, :w2], :X => [:x0, :x1], :Y => [:y0, :y1];
                       mechanisms=[:W => (), :X => (), :Y => (:X,)])
        mz = bind_cpt(BayesModel(bnw),
                      [:W => [1 + 5e-9, -5e-9], :X => [1.0, 0.0],
                       :Y => [0.3 0.7; 0.6 0.4]])
        # X = x1 has probability exactly zero, which on_zero handles; it is not an untrusted
        # mass. Before, the exact recomputation met W's negative entry and raised.
        @test conditional(mz, :Y, :X).table == [0.3 0.5; 0.7 0.5]
        @test all(isnan, conditional(mz, :Y, :X; on_zero=:nan).table[:, 2])
        ez = try
            conditional(mz, :Y, :X; on_zero=:error)
        catch err
            err
        end
        @test ez isa ImpossibleEvidenceError && ez.evidence == Dict(:X => :x1)
        # A column of tiny positive mass is not exactly zero: it is recomputed exactly.
        mt = bind_cpt(BayesModel(bnw),
                      [:W => [0.5, 0.5], :X => [1.0, 1e-320],
                       :Y => [0.3 0.7; 0.6 0.4]])
        @test conditional(mt, :Y, :X).table == [0.3 0.6; 0.7 0.4]
        # Each column is a posterior: a negative cell in one raises, naming its
        # configuration of `given`, as `marginal` does for the same posterior.
        mc = bind_cpt(BayesModel(bnw),
                      [:W => [0.5, 0.5], :X => [0.5, 0.5],
                       :Y => [1+5e-7 -5e-7; 0.5 0.5]]; atol=1e-6)
        ec = try
            conditional(mc, :Y, :X; atol=1e-6)
        catch err
            err
        end
        @test ec isa IndeterminatePosteriorError && ec.evidence == Dict(:X => :x0)
        @test_throws IndeterminatePosteriorError marginal(mc, :Y; evidence=Dict(:X => :x0),
                                                          atol=1e-6)
    end

    @testset "conditional builds its kernel at the caller's atol" begin
        bnx = bayesnet(:X => [:x0, :x1]; mechanisms=[:X => ()])
        mx = bind_cpt(BayesModel(bnx), :X => [1 + 5e-7, -5e-7]; atol=1e-6)
        # Valid at atol = 1e-6; before, the kernel was checked at the default atol and
        # raised KernelEntryError.
        k = conditional(mx, :X, Symbol[]; atol=1e-6)
        @test k.table ≈ [1 + 5e-7, -5e-7]
        @test k ≈ marginal(mx, :X; atol=1e-6)
    end

    @testset "products below floatmin make the run untrusted" begin
        # Evidence of normal mass (about 1e-262 and 1e-260), but the cell of A = a0 is a
        # product below floatmin: subnormal (1e-60 * 1e-262) or rounded all the way to zero
        # (1e-70 * 1e-260). Before, only the final mass was tested, and the cells came out
        # as 9.88e-61 and 0.0.
        bna = bayesnet(:A => [:a0, :a1], :E => [:e0, :e1];
                       mechanisms=[:A => (), :E => (:A,)])
        for (p0, c) in ((1e-60, 1e-262), (1e-70, 1e-260))
            ma = bind_cpt(BayesModel(bna), [:A => [p0, 1 - p0], :E => [1-c c; 1-c c]])
            w = [exact(p0) * exact(c), exact(1 - p0) * exact(c)]
            want = [nearest(w[1] / sum(w)), nearest(w[2] / sum(w))]
            @test marginal(ma, :A; evidence=Dict(:E => :e1)).table == want
            @test conditional(ma, :A, :E).table[:, 2] == want
        end
        # A prior marginal is held to the rule too. The cell of C = c0 is the product
        # 3e-300 * 7e-11 * 0.3, whose first product is subnormal; rounding twice gave
        # 6.2999999999997e-311, and the exact run gives the nearest Float64.
        bnc = bayesnet(:A => [:a0, :a1], :B => [:b0, :b1], :C => [:c0, :c1];
                       mechanisms=[:A => (), :B => (:A,), :C => (:B,)])
        mp = bind_cpt(BayesModel(bnc),
                      [:A => [3e-300, 1 - 3e-300],
                       :B => [7e-11 1-7e-11; 0.0 1.0],
                       :C => [0.3 0.7; 0.0 1.0]])
        @test marginal(mp, :C; evidence=Dict{Symbol,Symbol}()).table[1] ==
              nearest(exact(3e-300) * exact(7e-11) * exact(0.3))
    end

    @testset "the exact run does not depend on mechanism order" begin
        # The evidence mass is about 1e-400, so the exact run decides. B's negative entry
        # lies only on configurations where C's entry is exactly zero, so it takes no part.
        # Before, the answer depended on whether B's or C's mechanism came first.
        for mechs in ([:A => (), :E => (), :B => (), :C => (:B,)],
                      [:A => (), :E => (), :C => (:B,), :B => ()])
            bnm = bayesnet(:A => [:a1, :a2], :E => [:e1, :e2], :B => [:b1, :b2],
                           :C => [:c1, :c2]; mechanisms=mechs)
            mm = bind_cpt(BayesModel(bnm),
                          [:A => [1 - 1e-200, 1e-200], :E => [1 - 1e-200, 1e-200],
                           :B => [1 + 5e-9, -5e-9], :C => [0.5 0.5; 1.0 0.0]])
            ev = Dict(:A => :a2, :E => :e2, :C => :c2)
            @test marginal(mm, :B; evidence=ev).table == [1.0, 0.0]
            # Where the negative entry does take part, both orders raise.
            @test_throws IndeterminatePosteriorError marginal(mm, :B;
                                                              evidence=Dict(:A => :a2,
                                                                            :E => :e2,
                                                                            :C => :c1))
        end
    end

    @testset "the exact run uses exact kernel values (ADR 0016)" begin
        bnr = bayesnet(:A => [:a1, :a2], :E => [:e1, :e2], :R => [:r1, :r2],
                       :S => [:s1, :s2];
                       mechanisms=[:A => (), :E => (:A,), :R => (), :S => ()])
        two(x) = FiniteSpace(x, [Symbol(lowercase(String(x)), i) for i in 1:2])
        rare = big(1) // big(10)^200
        function bound(T)
            m = BayesModel(bnr)
            third = T === Rational{BigInt} ? big(1) // 3 : BigFloat(1) / 3
            fifth = T === Rational{BigInt} ? big(1) // 5 : BigFloat(1) / 5
            r = T(rare)
            m = bind_kernel(m,
                            :A => FiniteKernel(FiniteSpace(), two(:A), [third, 1 - third]))
            m = bind_kernel(m,
                            :E => FiniteKernel(two(:A), two(:E),
                                               [1-fifth 1-3fifth; fifth 3fifth]))
            m = bind_kernel(m, :R => FiniteKernel(FiniteSpace(), two(:R), [1 - r, r]))
            return bind_kernel(m, :S => FiniteKernel(FiniteSpace(), two(:S), [1 - r, r]))
        end
        ev = Dict(:E => :e2, :R => :r2, :S => :s2)
        # The evidence mass is about 1e-400. P(A = a1 | e2) is exactly 1/7 for the rational
        # kernels; rounding them to Float64 first gave 0.14285714285714288.
        @test marginal(bound(Rational{BigInt}), :A; evidence=ev).table ==
              [nearest(big(1) // 7), nearest(big(6) // 7)]
        mbig = bound(BigFloat)
        a = [exact(x) for x in kernel(mbig, :A).table]
        e = [exact(x) for x in kernel(mbig, :E).table[2, :]]
        w = a .* e
        @test marginal(mbig, :A; evidence=ev).table == [nearest(w[1] / sum(w)),
                                                        nearest(w[2] / sum(w))]
        # An entry whose Float64 value is zero is not a zero: before, 1e-400 evidence was
        # impossible.
        tiny = big(1) // big(10)^400
        mt = bind_kernel(bound(Rational{BigInt}),
                         :R => FiniteKernel(FiniteSpace(), two(:R), [1 - tiny, tiny]))
        @test marginal(mt, :A; evidence=Dict(:R => :r2)).table ==
              [nearest(big(1) // 3), nearest(big(2) // 3)]
        # Zero entries do not lower the common power of two of the exact run.
        mz = bind_cpt(BayesModel(bnr),
                      [:A => [0.5, 0.5], :E => [1.0 0.0; 0.5 0.5],
                       :R => [1.0, 0.0], :S => [0.25, 0.75]])
        q = BayesianNetworks._query(mz, [:A], Dict(:E => :e1), 1_000_000, DEFAULT_ATOL)
        @test BayesianNetworks._exact_cells(q).floor == -4
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
