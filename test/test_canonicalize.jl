@testset "Canonicalize" begin
    ref = reference_habitat_bn()
    # The same network built in reverse order, with states and inputs added out of order.
    other = BayesNet()
    for name in reverse(variable_names(ref))
        add_variable!(other, name; states=Symbol[])
    end
    for name in variable_names(ref)
        v = variable_id(other, name)
        sts = states(ref, name)
        for (pos, s) in reverse(collect(enumerate(sts)))
            add_state!(other, v, s; position=pos)
        end
    end
    for m in reverse(mechanisms(ref))
        t = variable_name(ref, target(ref, m))
        newm = add_mechanism!(other, t; name=mechanism_name(ref, m))
        ins = inputs(ref, m)
        for (pos, p) in reverse(collect(enumerate(ins)))
            add_input!(other, newm, variable_name(ref, p); position=pos)
        end
    end

    @test ref != other
    @test canonicalize(ref) == canonicalize(other)
    @test canonicalize(ref) == canonicalize(canonicalize(ref))
    @test is_isomorphic(ref, other)
    @test validate(canonicalize(other); closed=true) === nothing
    @test variable_names(canonicalize(ref)) == sort(variable_names(ref))
    @test states(canonicalize(other), :SoilMoisture) == [:low, :medium, :high]

    @testset "differences are detected" begin
        renamed = reference_habitat_bn()
        set_subpart!(renamed, variable_id(renamed, :Occupancy), :variable_name, :Presence)
        @test !is_isomorphic(ref, renamed)
        reordered = reference_habitat_bn()
        m = mechanism_of(reordered, :SoilMoisture)
        ids = input_ids(reordered, m)
        set_subpart!(reordered, ids[1], :input_position, 2)
        set_subpart!(reordered, ids[2], :input_position, 1)
        @test !is_isomorphic(ref, reordered)
        withref = reference_habitat_bn()
        set_subpart!(withref, 1, :kernel_ref, NamedRef("k"))
        @test !is_isomorphic(ref, withref)
    end

    @testset "duplicate names fall back to isomorphism search" begin
        a = bayesnet(:X => [:x0], :X => [:x0, :x1]; closed=false)
        b = bayesnet(:X => [:x0, :x1], :X => [:x0]; closed=false)
        @test canonicalize(a) != canonicalize(b)
        @test is_isomorphic(a, b)
        c = bayesnet(:X => [:x0, :x1], :X => [:x0, :x1]; closed=false)
        @test !is_isomorphic(a, c)
    end
end
