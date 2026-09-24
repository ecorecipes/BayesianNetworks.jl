using JSON3

@testset "Finite-BN proof certificates" begin
    exact(w) = parse(BigInt, w.num) // parse(BigInt, w.den)
    binding(c, key) = only(filter(b -> b.key == key, c.bindings))

    bn = bayesnet(:Z => [:no, :yes], :A => [:off, :on]; mechanisms=[:A => :Z],
                  space_refs=Dict(:Z => NamedRef("binary"), :A => NamedRef("binary")))
    m = bind_cpt(bind_cpt(BayesModel(bn), :Z => [0.25, 0.75]),
                 :A => [0.5 0.5; 0.0 1.0])
    cert = proof_certificate(m)
    @test cert.version == "finite-bn-certificate-1"
    @test getproperty.(cert.variables, :name) == ["Z", "A"]
    @test all(v.space_ref == (kind="named", key="binary") for v in cert.variables)
    @test getproperty.(cert.mechanisms, :target) == [target(m, i) for i in mechanisms(m)]
    @test cert.topological_order == [1, 2]
    @test isempty(cert.evidence)
    @test length(cert.bindings) == 2
    @test only(binding(cert, "Z_mechanism").columns).parents == Int[]
    @test exact.(only(binding(cert, "Z_mechanism").columns).weights) == [1 // 4, 3 // 4]
    @test binding(cert, "A_mechanism").input_states == [["no", "yes"]]
    @test binding(cert, "A_mechanism").output_states == ["off", "on"]
    @test getproperty.(binding(cert, "A_mechanism").columns, :parents) == [[1], [2]]
    @test exact.(binding(cert, "A_mechanism").columns[2].weights) == [0, 1]
    @test JSON3.read(JSON3.write(cert)).version == cert.version
    @test proof_certificate(m) == cert

    @testset "raw row order and repeated slots" begin
        raw = BayesNet()
        y = add_variable!(raw, :Y; states=Symbol[])
        x = add_variable!(raw, :X; states=Symbol[])
        add_state!(raw, x, :x2; position=2)
        add_state!(raw, y, :y2; position=2)
        add_state!(raw, x, :x1; position=1)
        add_state!(raw, y, :y1; position=1)
        my = add_mechanism!(raw, y; kernel_ref=NamedRef("repeated"))
        add_mechanism!(raw, x; kernel_ref=NamedRef("prior"))
        add_input!(raw, my, x; position=2)
        add_input!(raw, my, x; position=1)
        table = zeros(2, 2, 2)
        table[1, 1, :] = [1.0, 0.0]
        table[1, 2, :] = [0.25, 0.75]
        table[2, 1, :] = [0.75, 0.25]
        table[2, 2, :] = [0.0, 1.0]
        repeated = bind_cpt(bind_cpt(BayesModel(raw), :X => [0.5, 0.5]), :Y => table)
        data = proof_certificate(repeated)
        @test getproperty.(data.variables, :name) == ["Y", "X"]
        @test getproperty.(data.states, :variable) == [2, 1, 2, 1]
        @test getproperty.(data.states, :position) == [2, 2, 1, 1]
        @test getproperty.(data.states, :name) == ["x2", "y2", "x1", "y1"]
        @test getproperty.(data.inputs, :position) == [2, 1]
        @test getproperty.(data.inputs, :variable) == [2, 2]
        @test data.topological_order == [2, 1]
        b = binding(data, "repeated")
        @test b.input_states == [["x1", "x2"], ["x1", "x2"]]
        @test getproperty.(b.columns, :parents) == [[1, 1], [1, 2], [2, 1], [2, 2]]
        @test exact.(b.columns[2].weights) == [1 // 4, 3 // 4]
        @test exact.(b.columns[3].weights) == [3 // 4, 1 // 4]
        for column in b.columns
            @test exact.(column.weights) ==
                  Rational{BigInt}.(table[column.parents..., :])
        end
        @test proof_certificate(observe(repeated, :X => :x1)).evidence ==
              [(variable=2, state_position=1)]
    end

    @testset "exact numbers before backend conversion" begin
        prior = bayesnet(:X => [:a, :b]; kernel_refs=Dict(:X => NamedRef("prior")))
        for weights in ([1, 0], [1 // 3, 2 // 3], Float16[0.25, 0.75],
                        Float32[0.25, 0.75], [0.25, 0.75], BigFloat[0.25, 0.75],
                        Real[1 // 4, 0.75], [-0.0, 1.0], [nextfloat(0.0), 1.0])
            source = bind_cpt(BayesModel(prior), :X => weights)
            data = proof_certificate(source)
            @test exact.(only(only(data.bindings).columns).weights) ==
                  Rational{BigInt}.(weights)
        end
        data = proof_certificate(bind_cpt(BayesModel(prior), :X => [0.1, 0.9]))
        weights = exact.(only(only(data.bindings).columns).weights)
        @test weights != [1 // 10, 9 // 10]
        @test sum(weights) == big"36028797018963969" // big"36028797018963968"
        setprecision(BigFloat, 256) do
            weights = [BigFloat(1) / 3, 1 - BigFloat(1) / 3]
            data = proof_certificate(bind_cpt(BayesModel(prior), :X => weights))
            captured = exact.(only(only(data.bindings).columns).weights)
            @test captured == Rational{BigInt}.(weights)
            @test captured != Rational{BigInt}.(Float64.(weights))
        end
        loose = bind_cpt(BayesModel(prior), :X => [0.5, 0.500001]; atol=1e-5)
        @test_throws UnnormalizedKernelError proof_certificate(loose)
        @test exact.(only(only(proof_certificate(loose; atol=1e-5).bindings).columns).weights) ==
              Rational{BigInt}.([0.5, 0.500001])
    end

    @testset "references, evidence and ownership" begin
        policy_bn = bayesnet(:X => [:a, :b], :Y => [:a, :b];
                             kernel_refs=Dict(:X => NamedRef("same"),
                                              :Y => PolicyRef(:same)),
                             space_refs=Dict(:X => PolicyRef(:space),
                                             :Y => PointMassRef(:b)))
        policy = bind_cpt(bind_cpt(BayesModel(policy_bn), :X => [1, 0]), :Y => [0, 1])
        data = proof_certificate(policy)
        @test getproperty.(data.bindings, :kind) == ["named", "policy"]
        @test getproperty.(data.bindings, :key) == ["same", "same"]
        @test data.variables[1].space_ref == (kind="policy", key="space")
        @test data.variables[2].space_ref == (kind="point_mass", state="b")
        extra = BayesModel(policy;
                           kernels=merge(kernels(policy),
                                         Dict(NamedRef("unused") => kernel(policy, :X))))
        @test proof_certificate(extra) == data

        hard = do_intervention(m, :A => :off)
        hard_data = proof_certificate(hard)
        @test length(hard_data.bindings) == 1
        @test only(filter(r -> r.target == 2, hard_data.mechanisms)).kernel_ref ==
              (kind="point_mass", state="off")
        parented = deepcopy(syntax(m))
        set_subpart!(parented, mechanism_of(parented, :A), :kernel_ref, PointMassRef(:off))
        @test length(proof_certificate(BayesModel(m; syntax=parented)).inputs) == 1
        stored = observe(policy, :X => :a)
        @test proof_certificate(stored).evidence == [(variable=1, state_position=1)]
        @test proof_certificate(stored; evidence=Dict(:Y => :b)).evidence ==
              [(variable=2, state_position=2)]
        @test isempty(proof_certificate(stored; evidence=Dict()).evidence)
        @test proof_certificate(stored; evidence=Dict(:X => :b)).evidence ==
              [(variable=1, state_position=2)]
        @test proof_certificate(stored; evidence=Dict(:Y => :b, :X => :a)).evidence ==
              [(variable=1, state_position=1), (variable=2, state_position=2)]
        @test evidence(stored) == Dict(:X => :a)
        invalid_stored = BayesModel(policy; evidence=Dict(:missing => :a))
        @test_throws UnknownVariableError proof_certificate(invalid_stored)
        @test isempty(proof_certificate(invalid_stored; evidence=Dict()).evidence)
        original = deepcopy(m)
        proof_certificate(m)
        @test m == original
        independent = proof_certificate(original)
        kernel(original, :A).table[1] = 0.125
        set_subpart!(syntax(original), 1, :state_name, :changed)
        @test independent == cert
        @test isempty(proof_certificate(BayesModel(BayesNet())).variables)
    end

    @testset "invalid data are not repaired" begin
        @test_throws MissingKernelError proof_certificate(BayesModel(bn))
        unresolved = bayesnet(:X => [:a, :b]; kernel_refs=Dict(:X => NamedRef("missing")))
        @test_throws MissingKernelError proof_certificate(BayesModel(unresolved))
        @test_throws MissingMechanismError proof_certificate(BayesModel(bayesnet(:X => [:a,
                                                                                        :b];
                                                                                 closed=false)))
        @test_throws ProofCertificateError proof_certificate(BayesModel(bayesnet(:X => Symbol[])))
        @test_throws UnknownVariableError proof_certificate(m;
                                                            evidence=Dict(:missing => :no))
        @test_throws UnknownStateError proof_certificate(m; evidence=Dict(:Z => :missing))
        @test_throws ProofCertificateError proof_certificate(m; evidence=[:Z => :no])
        @test_throws ProofCertificateError proof_certificate(m; evidence=Dict("Z" => "no"))
        for atol in (-1.0, Inf, NaN)
            @test_throws ProofCertificateError proof_certificate(m; atol=atol)
        end
        bad_position = deepcopy(syntax(m))
        set_subpart!(bad_position, 2, :state_position, 1)
        @test_throws PositionError proof_certificate(BayesModel(m; syntax=bad_position))
        bad_input = deepcopy(syntax(m))
        set_subpart!(bad_input, 1, :input_position, 2)
        @test_throws PositionError proof_certificate(BayesModel(m; syntax=bad_input))
        wrong_label = deepcopy(syntax(m))
        set_subpart!(wrong_label, 1, :state_name, :changed)
        @test_throws KernelBindingError proof_certificate(BayesModel(m; syntax=wrong_label))
        shared = deepcopy(syntax(m))
        set_subpart!(shared, mechanism_of(shared, :A), :kernel_ref,
                     kernel_ref(shared, mechanism_of(shared, :Z)))
        @test_throws KernelBindingError proof_certificate(BayesModel(m; syntax=shared))
        bad_point = deepcopy(syntax(m))
        set_subpart!(bad_point, mechanism_of(bad_point, :Z), :kernel_ref,
                     PointMassRef(:missing))
        @test_throws UnknownStateError proof_certificate(BayesModel(m; syntax=bad_point))
        for name in (Symbol("line\nbreak"), Symbol("delete\x7f"))
            bad_name = deepcopy(syntax(m))
            set_subpart!(bad_name, 1, :variable_name, name)
            @test_throws ProofCertificateError proof_certificate(BayesModel(m;
                                                                            syntax=bad_name))
        end
        bad_ref = deepcopy(syntax(m))
        set_subpart!(bad_ref, 1, :space_ref, NamedRef("bad\tref"))
        @test_throws ProofCertificateError proof_certificate(BayesModel(m; syntax=bad_ref))
        prior = bayesnet(:X => [:a, :b]; kernel_refs=Dict(:X => NamedRef("prior")))
        for values in ([NaN, 1.0], [Inf, 0.0], [-1e-12, 1.0], [pi, pi], [1 // 0, 0 // 1])
            k = state(syntax_space(prior, :X), values; check=false)
            bad = BayesModel(prior; kernels=Dict(NamedRef("prior") => k))
            @test_throws ProofCertificateError proof_certificate(bad)
        end
        @test_throws ProofCertificateError proof_certificate(BayesModel(prior;
                                                                        kernels=Dict(NamedRef("prior") => [0.5,
                                                                                                           0.5])))
        @test_throws ProofCertificateError proof_certificate(BayesModel(m;
                                                                        spaces=Dict(:Z => :not_a_space)))
        err = ProofCertificateError(:scalar_type, :Mechanism, 2, :prior, "unsupported")
        @test occursin("prior", sprint(showerror, err))
        @test occursin("scalar_type", sprint(showerror, err))
    end
end
