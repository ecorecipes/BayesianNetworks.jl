using Random

# Property tests over random small DAGs (SPEC section 56).

function random_model(rng::AbstractRNG; nvars::Integer=rand(rng, 2:5),
                      max_states::Integer=3,
                      max_parents::Integer=2)
    names_ = [Symbol("V", i) for i in 1:nvars]
    vars = [x => [Symbol(x, "_", j) for j in 1:rand(rng, 2:max_states)] for x in names_]
    mechs = Pair{Symbol,Any}[]
    for i in 2:nvars
        k = rand(rng, 0:min(max_parents, i - 1))
        ps = shuffle(rng, names_[1:(i - 1)])[1:k]   # random parent order too
        push!(mechs, names_[i] => Tuple(ps))
    end
    bn = bayesnet(vars...; mechanisms=mechs)
    m = BayesModel(bn)
    for x in names_
        m = bind_kernel(m, x => random_kernel(rng, parent_space(m, x), space(m, x)))
    end
    return m
end

@testset "Random networks" begin
    rng = MersenneTwister(20240906)
    for trial in 1:25
        m = random_model(rng)
        bn = syntax(m)
        J = joint_distribution(m)
        # 1. the joint normalises to one
        @test sum(J.table) ≈ 1
        # 4. hard interventions give normalised joints and leave non-descendants alone
        x = rand(rng, variable_names(bn))
        s = rand(rng, states(bn, x))
        md = do_intervention(m, x => s)
        Jd = joint_distribution(md)
        @test sum(Jd.table) ≈ 1
        for y in variable_names(bn)
            y == x && continue
            y in variable_name.(Ref(bn), parents(bn, x)) || continue
            @test marginal(md, y) ≈ marginal(m, y)
        end
        # marginals are consistent with conditionals: P(y, pa) = P(y | pa) P(pa)
        y = last(variable_name.(Ref(bn), topological_order(bn)))
        ps = variable_name.(Ref(bn), parents(bn, y))
        if !isempty(ps)
            @test conditional(m, y, ps) ≈ kernel(m, y)
        end
        # 2-3 (sampling only; VE lives in BayesianNetworkInference.jl)
        if trial <= 5
            smp = sample(m, 3000; rng=rng)
            for z in variable_names(bn)
                est = empirical_marginal(smp, z, space(m, z))
                @test maximum(abs.(est.table .- marginal(m, z).table)) < 0.05
            end
        end
        # JSON round trip keeps the semantics
        back = parse_json_model(json_model(m))
        @test back ≈ m
        @test joint_distribution(back) ≈ J
    end
end
