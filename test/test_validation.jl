@testset "Validation" begin
    ref = reference_habitat_bn()

    @testset "valid network" begin
        @test validate(ref) === nothing
        @test validate(ref; closed=true, unique_names=true) === nothing
        @test isvalid(ref)
        @test isempty(validation_errors(ref; closed=true, unique_names=true))
    end

    @testset "MissingMechanismError" begin
        bn = bayesnet(:A => [:a], :B => [:b]; mechanisms=[:B => :A], closed=false)
        @test validate(bn) === nothing
        @test_throws MissingMechanismError validate(bn; closed=true)
        @test !isvalid(bn; closed=true)
        errs = validation_errors(bn; closed=true)
        @test length(errs) == 1
        @test errs[1] == MissingMechanismError(:A, 1)
        @test occursin("A", sprint(showerror, errs[1]))
    end

    @testset "DuplicateGeneratorError" begin
        bn = reference_habitat_bn()
        add_mechanism!(bn, :Occupancy; inputs=[:Vegetation], name=:second)
        @test_throws DuplicateGeneratorError validate(bn)
        errs = validation_errors(bn)
        @test length(errs) == 1
        @test errs[1].variable == :Occupancy
        @test errs[1].mechanisms == [4, 8]
    end

    @testset "DanglingReferenceError" begin
        bn = reference_habitat_bn()
        m = add_part!(bn, :Mechanism; mechanism_name=:orphan, kernel_ref=NoRef())
        @test_throws DanglingReferenceError validate(bn)
        errs = validation_errors(bn)
        @test errs[1] == DanglingReferenceError(:Mechanism, m, :target, 0)
        bn = reference_habitat_bn()
        i = add_part!(bn, :Input; input_mechanism=1, input_position=3)
        @test validation_errors(bn)[1] ==
              DanglingReferenceError(:Input, i, :input_variable, 0)
        bn = reference_habitat_bn()
        i = add_part!(bn, :Input; input_variable=1, input_position=1)
        @test validation_errors(bn)[1] ==
              DanglingReferenceError(:Input, i, :input_mechanism, 0)
        bn = reference_habitat_bn()
        s = add_part!(bn, :State; state_name=:lost, state_position=1)
        @test validation_errors(bn)[1] ==
              DanglingReferenceError(:State, s, :state_variable, 0)
        @test occursin("state_variable", sprint(showerror, validation_errors(bn)[1]))
    end

    @testset "PositionError (states)" begin
        bn = reference_habitat_bn()
        add_state!(bn, :Climate, :extra; position=5)
        @test_throws PositionError validate(bn)
        errs = validation_errors(bn)
        @test errs[1] == PositionError(:State, :Climate, 1, [1, 2, 3, 5])
        bn = reference_habitat_bn()
        add_state!(bn, :Climate, :dup; position=2)
        @test validation_errors(bn)[1] == PositionError(:State, :Climate, 1, [1, 2, 2, 3])
    end

    @testset "PositionError (inputs)" begin
        bn = reference_habitat_bn()
        m = mechanism_of(bn, :Occupancy)
        add_input!(bn, m, :Climate; position=1)
        errs = validation_errors(bn)
        @test errs[1] == PositionError(:Input, :Occupancy_mechanism, m, [1, 1])
        bn = reference_habitat_bn()
        add_input!(bn, m, :Climate; position=3)
        @test validation_errors(bn)[1] ==
              PositionError(:Input, :Occupancy_mechanism, m, [1, 3])
        @test occursin("Occupancy_mechanism", sprint(showerror, validation_errors(bn)[1]))
    end

    @testset "DuplicateStateError" begin
        bn = reference_habitat_bn()
        add_state!(bn, :Climate, :dry)
        @test_throws DuplicateStateError validate(bn)
        @test validation_errors(bn)[1] == DuplicateStateError(:Climate, 1, :dry)
    end

    @testset "SelfInputError" begin
        bn = reference_habitat_bn()
        m = mechanism_of(bn, :Occupancy)
        add_input!(bn, m, :Occupancy)
        @test_throws SelfInputError validate(bn)
        @test validation_errors(bn)[1] ==
              SelfInputError(:Occupancy_mechanism, m, :Occupancy)
    end

    @testset "CyclicBayesNetError" begin
        bn = reference_habitat_bn()
        add_input!(bn, mechanism_of(bn, :Climate), :Occupancy)
        @test_throws CyclicBayesNetError validate(bn)
        errs = validation_errors(bn)
        @test length(errs) == 1
        @test errs[1] isa CyclicBayesNetError
        @test Set(errs[1].variables) ==
              Set([:Climate, :SoilMoisture, :Vegetation, :HabitatQuality, :Occupancy])
    end

    @testset "DuplicateNameError" begin
        bn = reference_habitat_bn()
        add_variable!(bn, :Climate; states=[:x])
        add_mechanism!(bn, 8; name=:Climate_mechanism)
        @test validate(bn) === nothing
        @test_throws DuplicateNameError validate(bn; unique_names=true)
        errs = validation_errors(bn; unique_names=true)
        @test errs == [DuplicateNameError(:Variable, :Climate, [1, 8]),
                       DuplicateNameError(:Mechanism, :Climate_mechanism, [5, 8])]
    end

    @testset "errors accumulate" begin
        bn = bayesnet(:A => [:a, :a], :B => [:b]; mechanisms=[:B => :A], closed=false)
        add_input!(bn, mechanism_of(bn, :B), :B)
        add_state!(bn, :B, :b2; position=4)
        errs = validation_errors(bn; closed=true)
        # A self input is also a self loop, so the cycle check reports it as well.
        @test map(typeof, errs) ==
              [MissingMechanismError, PositionError, DuplicateStateError, SelfInputError,
               CyclicBayesNetError]
        @test_throws MissingMechanismError validate(bn; closed=true)
        # Every error type renders a message without throwing.
        for e in errs
            @test !isempty(sprint(showerror, e))
        end
    end
end

@testset "EmptyStateSpaceError" begin
    # `validate` had no "at least one state" check, so a variable with an empty state list
    # passed and the failure surfaced much later as a `MethodError` from `FiniteAxis`
    # inside `BayesModel`. `certificates.jl` already carried the check; `validate` did not.
    bn = bayesnet(:A => [:a1, :a2])
    add_variable!(bn, :Z; states=Symbol[])
    @test_throws EmptyStateSpaceError validate(bn)
    errs = validation_errors(bn)
    @test any(e -> e isa EmptyStateSpaceError && e.variable == :Z, errs)
    msg = sprint(showerror, EmptyStateSpaceError(:Z, 2))
    @test occursin("has no states", msg)

    @test validate(bayesnet(:A => [:a1, :a2])) === nothing
end
