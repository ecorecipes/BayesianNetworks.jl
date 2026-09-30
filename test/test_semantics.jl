function caught_error(f)
    try
        f()
    catch err
        return err
    end
    return nothing
end
e_atol(f, args...; kw...) = caught_error(() -> f(args...; kw...)).atol

@testset "Semantics binding" begin
    ref = reference_habitat_bn()
    m0 = BayesModel(ref)
    m = reference_habitat_model()

    @testset "spaces from the syntax" begin
        @test axis(ref, :Climate) == FiniteAxis(:Climate, [:dry, :normal, :wet])
        @test axis(ref, variable_id(ref, :Occupancy)) ==
              FiniteAxis(:Occupancy, [:absent, :present])
        @test syntax_space(ref, :SoilMoisture) ==
              FiniteSpace(:SoilMoisture, [:low, :medium, :high])
        sp = syntax_spaces(ref)
        @test Set(keys(sp)) == Set(variable_names(ref))
        @test sp == spaces(m0)
        @test space(m0, :Vegetation) ==
              FiniteSpace(:Vegetation, [:sparse, :moderate, :dense])
        @test parent_space(m0, :Vegetation) ==
              tensor_space(space(m0, :SoilMoisture), space(m0, :GrazingPressure))
        @test parent_space(m0, :Climate) == FiniteSpace()
        @test_throws UnknownVariableError space(m0, :Weather)
        # Variables without states or with repeated names get no space.
        bn = bayesnet(:X => [:a, :b], :Y => Symbol[]; closed=false)
        add_variable!(bn, :X; states=[:c])
        @test isempty(syntax_spaces(bn))
        @test BayesModel(bn) isa BayesModel{BayesNet,FiniteSpace,FiniteKernel}
        # A space missing from the dictionary is read from the syntax.
        partial = BayesModel(ref; spaces=Dict{Symbol,FiniteSpace}())
        @test isempty(spaces(partial))
        @test space(partial, :Climate) == syntax_space(ref, :Climate)
    end

    @testset "bind_kernel and bind_cpt" begin
        @test isempty(kernels(m0))
        @test !has_semantics(m0)
        @test missing_kernels(m0) == [:SoilMoisture, :Vegetation, :HabitatQuality,
                                      :Occupancy, :Climate, :Irrigation, :GrazingPressure]
        @test has_semantics(m)
        @test isempty(missing_kernels(m))
        @test length(kernels(m)) == 7
        @test all(kernel_ref(syntax(m), mm) isa NamedRef for mm in mechanisms(syntax(m)))
        @test kernel_ref(syntax(m), :Occupancy_mechanism) == NamedRef("Occupancy_mechanism")
        @test syntax(m0) == ref                       # the source model is untouched
        @test isempty(history(m))
        @test canonicalize(syntax(m)) != canonicalize(ref)   # refs were assigned
        k = kernel(m, :Occupancy)
        @test k isa FiniteKernel
        @test k.dom == space(m, :HabitatQuality) && k.codom == space(m, :Occupancy)
        @test cpt(k) == [0.8 0.2; 0.25 0.75]
        @test probability(k, :present, :good) == 0.75
        @test cpt(kernel(m, :SoilMoisture))[1, 2, :] == [0.3, 0.5, 0.2]
        @test kernel(m, :Climate).table == [0.3, 0.5, 0.2]
        @test_throws MissingKernelError kernel(m0, :Occupancy)
        @test_throws UnknownVariableError kernel(m, :Weather)
        @test_throws MissingMechanismError kernel(BayesModel(biotic_bn()), :SoilMoisture)
        # Binding by mechanism name and re-binding under an existing reference.
        m1 = bind_kernel(m0, :Occupancy_mechanism => k)
        @test kernel(m1, :Occupancy) == k
        @test kernel_ref(syntax(m1), :Occupancy_mechanism) ==
              NamedRef("Occupancy_mechanism")
        k2 = cpt(axis(ref, :HabitatQuality), axis(ref, :Occupancy), [0.5 0.5; 0.1 0.9])
        m2 = bind_kernel(m1, :Occupancy => k2)
        @test syntax(m2) == syntax(m1)
        @test kernel(m2, :Occupancy) == k2 && kernel(m1, :Occupancy) == k
        @test bind_kernel(m0, [:Occupancy => k]) == m1

        # Kernels of different arity widen the comprehension's eltype to the abstract
        # `Pair{Symbol}`; binding a vector of them must still work without the caller
        # annotating the element type (FiniteKernel{T,N} carries the rank).
        full = reference_habitat_model()
        mixed = [x => kernel(full, x) for x in (:Climate, :SoilMoisture, :Vegetation)]
        @test eltype(mixed) == Pair{Symbol}
        mixed_bound = bind_kernel(BayesModel(reference_habitat_bn()), mixed)
        @test length(missing_kernels(mixed_bound)) ==
              length(missing_kernels(BayesModel(reference_habitat_bn()))) - 3
        @test_throws ArgumentError bind_kernel(m0, [:Occupancy => 3])
        # Shape errors name the variable.
        wrong_codom = cpt(axis(ref, :HabitatQuality), FiniteAxis(:Occupancy, [:no, :yes]),
                          [0.8 0.2; 0.25 0.75])
        e = try
            bind_kernel(m0, :Occupancy => wrong_codom)
        catch err
            err
        end
        @test e isa KernelBindingError && e.variable == :Occupancy && e.what == :codom
        @test occursin("Occupancy", sprint(showerror, e))
        wrong_dom = cpt(axis(ref, :Vegetation), axis(ref, :Occupancy),
                        [0.8 0.2; 0.25 0.75; 0.5 0.5])
        e = try
            bind_kernel(m0, :Occupancy => wrong_dom)
        catch err
            err
        end
        @test e isa KernelBindingError && e.what == :dom
        @test e.expected == space(m0, :HabitatQuality)
        unnorm = cpt(axis(ref, :HabitatQuality), axis(ref, :Occupancy),
                     [0.8 0.3; 0.25 0.75];
                     check=false)
        e = try
            bind_kernel(m0, :Occupancy => unnorm)
        catch err
            err
        end
        @test e isa UnnormalizedKernelError && e.variable == :Occupancy
        @test e.max_deviation ≈ 0.1
        @test occursin("Occupancy", sprint(showerror, e))
        loose = bind_kernel(m0, :Occupancy => unnorm; atol=0.2)
        @test loose isa BayesModel
        # validate and semantic_errors take the same tolerance as the binding did.
        @test_throws UnnormalizedKernelError validate(loose)
        @test only(semantic_errors(loose)) isa UnnormalizedKernelError
        @test validate(loose; atol=0.2) === nothing
        @test isempty(semantic_errors(loose; atol=0.2))
        @test DEFAULT_ATOL == 1e-8
        @test_throws UnknownMechanismError bind_kernel(m0, :Nope => k)
        # bind_cpt: table shape and renormalisation.
        e = try
            bind_cpt(m0, :Occupancy => [0.8 0.2 0.0; 0.25 0.75 0.0])
        catch err
            err
        end
        @test e isa KernelBindingError && e.what == :table && e.expected == (2, 2)
        @test_throws UnnormalizedKernelError bind_cpt(m0,
                                                      :Occupancy => [0.8 0.3; 0.25 0.75])
        mr = bind_cpt(m0, :Occupancy => [0.8 0.3; 0.25 0.75]; renormalize=true)
        @test cpt(kernel(mr, :Occupancy))[1, :] ≈ [0.8, 0.3] ./ 1.1
        @test bind_cpt(m0, :Climate => [0.3, 0.5, 0.2]) isa BayesModel
        @test_throws KernelBindingError bind_cpt(m0, :Climate => [0.5, 0.5])
        # The model boundary (ADR 0013): an invalid entry is wrapped with the variable and
        # the entry's assignment, and the tolerance is recorded on normalisation errors.
        @test e_atol(bind_cpt, m0, :Occupancy => [0.8 0.3; 0.25 0.75]) == DEFAULT_ATOL
        bad = caught_error(() -> bind_cpt(m0, :Occupancy => [1.5 -0.5; 0.25 0.75]))
        @test bad isa InvalidKernelEntryError && bad.variable == :Occupancy
        @test bad.value == -0.5
        @test bad.assignment == [:HabitatQuality => :poor, :Occupancy => :present]
        @test bad isa BayesNetError
        @test occursin("Occupancy", sprint(showerror, bad))
        nan = caught_error(() -> bind_cpt(m0, :Climate => [NaN, 1.0, 0.0]))
        @test nan isa InvalidKernelEntryError && isnan(nan.value)
        @test nan.assignment == [:Climate => :dry]
        # semantic_errors collects it rather than throwing, and validate throws the first
        # collected error in mechanism order.
        badk = cpt(axis(ref, :HabitatQuality), axis(ref, :Occupancy),
                   [1.5 -0.5; 0.25 0.75]; check=false)
        occ_ref = kernel_ref(syntax(m),
                             mechanism_of(syntax(m), variable_id(syntax(m), :Occupancy)))
        mbad = BayesModel(syntax(m); spaces=spaces(m),
                          kernels=merge(kernels(m), Dict(occ_ref => badk)))
        errs = semantic_errors(mbad)
        @test count(x -> x isa InvalidKernelEntryError, errs) == 1
        @test_throws InvalidKernelEntryError validate(mbad)
        # renormalize checks entries and rows before rescaling.
        @test_throws InvalidKernelEntryError bind_cpt(m0,
                                                      :Occupancy => [-1.0 -3.0; 0.25 0.75];
                                                      renormalize=true)
        zero_row = caught_error(() -> bind_cpt(m0, :Occupancy => [0.0 0.0; 0.25 0.75];
                                               renormalize=true))
        @test zero_row isa UnnormalizedKernelError && zero_row.max_deviation == 1.0
        # A tolerated negative entry (within -atol) is accepted.
        @test bind_cpt(m0, :Occupancy => [1.0+1e-9 -1e-9; 0.25 0.75]) isa BayesModel
        # Point-mass mechanisms are materialised and cannot be bound.
        md = do_intervention(m, :Vegetation => :dense)
        @test kernel(md, :Vegetation) == point_mass(space(m, :Vegetation), :dense)
        e = try
            bind_kernel(md, :Vegetation => kernel(m, :Vegetation))
        catch err
            err
        end
        @test e isa KernelBindingError && e.what === :intervention && e.got isa PointMassRef
        @test has_semantics(md)
        # A point-mass mechanism with inputs is `delete(parents) ⋅ point_mass`.
        bn = bayesnet(:X => [:a, :b], :Y => [:c, :d]; mechanisms=[:Y => :X],
                      kernel_refs=Dict(:Y => PointMassRef(:d)))
        my = bind_cpt(BayesModel(bn), :X => [0.5, 0.5])
        ky = kernel(my, :Y)
        @test ky.dom == space(my, :X) && ky.table == [0.0 0.0; 1.0 1.0]
        @test_throws MissingKernelError kernel(BayesModel(bn), :X)
        @test occursin("NoRef", sprint(showerror, MissingKernelError(:X, NoRef())))
    end

    @testset "validate with semantics" begin
        @test validate(m0) === nothing
        @test validate(m; closed=true, unique_names=true, semantics=true) === nothing
        @test_throws MissingKernelError validate(m0; semantics=true)
        @test isempty(semantic_errors(m0))
        @test length(semantic_errors(m0; semantics=true)) == 7
        # Reference-based soft interventions without kernels stay valid by default.
        ms = soft_intervention(m, :Vegetation => NamedRef("veg_fenced");
                               parents=[:SoilMoisture])
        @test validate(ms; closed=true) === nothing
        @test_throws MissingKernelError validate(ms; semantics=true)
        @test missing_kernels(ms) == [:Vegetation]
        # A stale kernel under a reference is caught; so is a stale space.
        bad = BayesModel(syntax(m);
                         kernels=merge(kernels(m),
                                       Dict(NamedRef("Occupancy_mechanism") => kernel(m,
                                                                                      :Climate))))
        @test_throws KernelBindingError validate(bad)
        bad2 = BayesModel(ref; spaces=Dict(:Climate => FiniteSpace(:Climate, [:dry, :wet])))
        e = try
            validate(bad2)
        catch err
            err
        end
        @test e isa KernelBindingError && e.what == :space && e.variable == :Climate
        bad3 = BayesModel(ref; spaces=Dict(:Weather => FiniteSpace(:Weather, [:dry])))
        @test_throws UnknownVariableError validate(bad3)
        # Alternative semantics (non-FiniteKernel values) are not checked.
        alt = BayesModel(ref; kernels=Dict(NamedRef("k") => [0.5 0.5]))
        @test validate(alt) === nothing
    end

    @testset "isapprox, show, rename" begin
        @test m ≈ m
        @test m ≈ reference_habitat_model()
        @test !(m ≈ m0)
        @test !(m ≈ observe(m, :Climate => :dry))
        @test !(m ≈ bind_cpt(m, :Occupancy => [0.5 0.5; 0.1 0.9]))
        @test occursin("7 kernels", sprint(show, m))
        @test !occursin("kernel", sprint(show, m0))
        # Renaming follows through spaces and kernel axes.
        mr = rename_variable(m, :Occupancy => :Presence)
        @test validate(mr; closed=true, semantics=true) === nothing
        @test kernel(mr, :Presence).codom == FiniteSpace(:Presence, [:absent, :present])
        @test kernel(mr, :Presence).table == kernel(m, :Occupancy).table
        @test !haskey(spaces(mr), :Occupancy) && haskey(spaces(mr), :Presence)
        mr2 = rename_variable(m, :HabitatQuality => :HQ)
        @test kernel(mr2, :Occupancy).dom == FiniteSpace(:HQ, [:poor, :good])
    end

    @testset "soft_intervention with a kernel" begin
        k = cpt(axis(ref, :SoilMoisture), axis(ref, :Vegetation),
                [1.0 0.0 0.0; 0.0 0.5 0.5; 0.0 0.0 1.0])
        m1 = soft_intervention(m, :Vegetation => k; note="fenced")
        @test validate(m1; closed=true, semantics=true) === nothing
        @test variable_name.(Ref(syntax(m1)), parents(syntax(m1), :Vegetation)) ==
              [:SoilMoisture]
        @test kernel(m1, :Vegetation) == k
        @test kernel_ref(syntax(m1), mechanism_of(syntax(m1), :Vegetation)) ==
              NamedRef("soft[Vegetation]")
        ev = only(history(m1))
        @test ev.kind == :soft && ev.target == :Vegetation && ev.note == "fenced"
        @test ev.added == MechanismRecord(Symbol("soft[Vegetation]"),
                                          NamedRef("soft[Vegetation]"), [:SoilMoisture])
        @test intervened_variables(m1) == [:Vegetation]
        # Explicit parents must agree with the kernel's domain.
        @test_throws KernelBindingError soft_intervention(m, :Vegetation => k;
                                                          parents=[:GrazingPressure])
        m2 = soft_intervention(m, :Vegetation => k; parents=[:SoilMoisture], name=:fence)
        @test kernel_ref(syntax(m2), mechanism_of(syntax(m2), :Vegetation)) ==
              NamedRef("fence")
        # A prior replaced by a state.
        m3 = soft_intervention(m, [:Climate => state(space(m, :Climate), [1.0, 0.0, 0.0])])
        @test isempty(parents(syntax(m3), :Climate))
        @test kernel(m3, :Climate).table == [1.0, 0.0, 0.0]
        @test m == reference_habitat_model()            # untouched
    end
end
