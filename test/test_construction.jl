@testset "Construction" begin
    @testset "reference network" begin
        bn = reference_habitat_bn()
        @test bn isa BayesNet
        @test nparts(bn, :Variable) == 7
        @test nparts(bn, :State) == 17
        @test nparts(bn, :Mechanism) == 7
        @test nparts(bn, :Input) == 6
        @test validate(bn; closed=true, unique_names=true) === nothing
        @test isvalid(bn; closed=true)
        @test variable_names(bn) ==
              [:Climate, :Irrigation, :SoilMoisture, :GrazingPressure, :Vegetation,
               :HabitatQuality, :Occupancy]
        @test states(bn, :SoilMoisture) == [:low, :medium, :high]
        @test variable_name.(Ref(bn), parents(bn, :SoilMoisture)) == [:Climate, :Irrigation]
        @test variable_name.(Ref(bn), parents(bn, :Vegetation)) ==
              [:SoilMoisture, :GrazingPressure]
        @test mechanism_name(bn, mechanism_of(bn, :Occupancy)) == :Occupancy_mechanism
        @test all(r -> r == NoRef(), subpart(bn, :space_ref))
        @test all(r -> r == NoRef(), subpart(bn, :kernel_ref))
    end

    @testset "add_*! builders" begin
        bn = BayesNet()
        a = add_variable!(bn, :A; states=[:a1, :a2], space_ref=NamedRef("A_space"))
        b = add_variable!(bn, :B; states=[:b1])
        @test (a, b) == (1, 2)
        @test subpart(bn, :state_position) == [1, 2, 1]
        s = add_state!(bn, :B, :b2)
        @test subpart(bn, s, :state_position) == 2
        @test states(bn, b) == [:b1, :b2]
        @test space_ref(bn, :A) == NamedRef("A_space")
        m = add_mechanism!(bn, :B; inputs=[:A], kernel_ref=NamedRef("B|A"))
        @test target(bn, m) == b
        @test inputs(bn, m) == [a]
        @test mechanism_name(bn, m) == :B_mechanism
        @test kernel_ref(bn, m) == NamedRef("B|A")
        c = add_variable!(bn, :C; states=[:c1, :c2])
        i = add_input!(bn, m, :C)
        @test subpart(bn, i, :input_position) == 2
        @test inputs(bn, :B_mechanism) == [a, c]
        m2 = add_mechanism!(bn, a; name=:prior_A)
        @test mechanism_name(bn, m2) == :prior_A
        @test isempty(inputs(bn, m2))
        @test validate(bn) === nothing
        @test_throws MissingMechanismError validate(bn; closed=true)
    end

    @testset "bayesnet DSL" begin
        open_bn = bayesnet(:X => [:x0, :x1], :Y => [:y0, :y1];
                           mechanisms=[:Y => :X], closed=false)
        @test nparts(open_bn, :Mechanism) == 1
        @test exogenous(open_bn) == [variable_id(open_bn, :X)]
        closed_bn = bayesnet(:X => [:x0, :x1], :Y => [:y0, :y1];
                             mechanisms=[:Y => [:X]],
                             space_refs=Dict(:X => NamedRef("X")),
                             kernel_refs=Dict(:X => NamedRef("P(X)"),
                                              :Y => NamedRef("P(Y|X)")))
        @test nparts(closed_bn, :Mechanism) == 2
        @test isempty(exogenous(closed_bn))
        @test space_ref(closed_bn, :X) == NamedRef("X")
        @test kernel_ref(closed_bn, mechanism_of(closed_bn, :X)) == NamedRef("P(X)")
        @test kernel_ref(closed_bn, mechanism_of(closed_bn, :Y)) == NamedRef("P(Y|X)")
        @test validate(closed_bn; closed=true) === nothing
    end

    @testset "lookups" begin
        bn = reference_habitat_bn()
        @test variable_id(bn, :Occupancy) == 7
        @test has_variable(bn, :Occupancy)
        @test !has_variable(bn, :Nope)
        @test_throws UnknownVariableError variable_id(bn, :Nope)
        @test_throws UnknownMechanismError mechanism_id(bn, :Nope)
        @test_throws UnknownVariableError add_mechanism!(bn, :Nope)
        add_variable!(bn, :Climate; states=[:x])
        @test_throws DuplicateNameError variable_id(bn, :Climate)
        err = DuplicateNameError(:Variable, :Climate, [1, 8])
        @test occursin("Climate", sprint(showerror, err))
    end
end
