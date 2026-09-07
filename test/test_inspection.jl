@testset "Inspection" begin
    bn = reference_habitat_bn()
    ids = Dict(n => variable_id(bn, n) for n in variable_names(bn))

    @test variables(bn) == 1:7
    @test mechanisms(bn) == 1:7
    @test nstates(bn, :Vegetation) == 3
    @test nstates(bn, ids[:Climate]) == 3
    @test children(bn, :SoilMoisture) == [ids[:Vegetation]]
    @test children(bn, :Climate) == [ids[:SoilMoisture]]
    @test isempty(children(bn, :Occupancy))
    @test isempty(parents(bn, :Climate))
    @test has_mechanism(bn, :Climate)
    @test isempty(exogenous(bn))
    @test roots(bn) == [ids[:Climate], ids[:Irrigation], ids[:GrazingPressure]]
    @test length(mechanism_names(bn)) == 7

    @testset "orderings follow positions, not part ids" begin
        bn2 = BayesNet()
        v = add_part!(bn2, :Variable; variable_name=:V, space_ref=NoRef())
        add_part!(bn2, :State; state_variable=v, state_name=:third, state_position=3)
        add_part!(bn2, :State; state_variable=v, state_name=:first, state_position=1)
        add_part!(bn2, :State; state_variable=v, state_name=:second, state_position=2)
        @test states(bn2, :V) == [:first, :second, :third]
        @test state_ids(bn2, :V) == [2, 3, 1]
        p = add_variable!(bn2, :P; states=[:p])
        q = add_variable!(bn2, :Q; states=[:q])
        m = add_mechanism!(bn2, :V)
        add_input!(bn2, m, q; position=2)
        add_input!(bn2, m, p; position=1)
        @test inputs(bn2, m) == [p, q]
        @test parents(bn2, :V) == [p, q]
        @test input_ids(bn2, m) == [2, 1]
        @test validate(bn2) === nothing
    end

    @testset "mechanism_of" begin
        bn3 = bayesnet(:A => [:a]; closed=false)
        @test mechanism_of(bn3, :A) === nothing
        @test !has_mechanism(bn3, :A)
        add_mechanism!(bn3, :A)
        @test mechanism_of(bn3, :A) == 1
        add_mechanism!(bn3, :A; name=:second)
        @test_throws DuplicateGeneratorError mechanism_of(bn3, :A)
        @test has_mechanism(bn3, :A)
    end
end
