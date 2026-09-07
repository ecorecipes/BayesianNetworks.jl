using Graphs: SimpleDiGraph, SimpleGraph, nv, ne, edges, src, dst, neighbors, has_edge

@testset "Graphs" begin
    bn = reference_habitat_bn()
    ids = Dict(n => variable_id(bn, n) for n in variable_names(bn))

    @testset "variable_graph" begin
        g = variable_graph(bn)
        @test g isa SimpleDiGraph
        @test nv(g) == 7
        @test ne(g) == 6
        arcs = Set((src(e), dst(e)) for e in edges(g))
        @test arcs == Set([(ids[:Climate], ids[:SoilMoisture]),
                           (ids[:Irrigation], ids[:SoilMoisture]),
                           (ids[:SoilMoisture], ids[:Vegetation]),
                           (ids[:GrazingPressure], ids[:Vegetation]),
                           (ids[:Vegetation], ids[:HabitatQuality]),
                           (ids[:HabitatQuality], ids[:Occupancy])])
    end

    @testset "topological_order" begin
        @test is_acyclic(bn)
        order = topological_order(bn)
        @test sort(order) == 1:7
        pos = Dict(v => i for (i, v) in enumerate(order))
        for v in variables(bn), p in parents(bn, v)
            @test pos[p] < pos[v]
        end
        # Deterministic and independent of construction order.
        shuffled = bayesnet(:Occupancy => [:absent, :present],
                            :HabitatQuality => [:poor, :good],
                            :Vegetation => [:sparse, :moderate, :dense],
                            :GrazingPressure => [:low, :high],
                            :SoilMoisture => [:low, :medium, :high],
                            :Irrigation => [:none, :high],
                            :Climate => [:dry, :wet];
                            mechanisms=[:Occupancy => :HabitatQuality,
                                        :HabitatQuality => :Vegetation,
                                        :Vegetation => (:SoilMoisture, :GrazingPressure),
                                        :SoilMoisture => (:Climate, :Irrigation)])
        order2 = topological_order(shuffled)
        pos2 = Dict(v => i for (i, v) in enumerate(order2))
        for v in variables(shuffled), p in parents(shuffled, v)
            @test pos2[p] < pos2[v]
        end
        @test topological_order(shuffled) == order2
    end

    @testset "cycles" begin
        cyc = bayesnet(:A => [:a], :B => [:b], :C => [:c];
                       mechanisms=[:A => :C, :B => :A, :C => :B])
        @test !is_acyclic(cyc)
        @test_throws CyclicBayesNetError topological_order(cyc)
        err = try
            topological_order(cyc)
        catch e
            e
        end
        @test Set(err.variables) == Set([:A, :B, :C])
        @test occursin("A, B, C", sprint(showerror, err))
        # A variable downstream of a cycle is reported too.
        cyc2 = bayesnet(:A => [:a], :B => [:b], :D => [:d];
                        mechanisms=[:A => :B, :B => :A, :D => :A])
        @test_throws CyclicBayesNetError topological_order(cyc2)
    end

    @testset "moral_graph" begin
        mg = moral_graph(bn)
        @test mg isa SimpleGraph
        @test nv(mg) == 7
        undirected(g) = Set(minmax(src(e), dst(e)) for e in edges(g))
        @test undirected(mg) == Set([minmax(ids[:Climate], ids[:SoilMoisture]),
                                     minmax(ids[:Irrigation], ids[:SoilMoisture]),
                                     minmax(ids[:Climate], ids[:Irrigation]),
                                     minmax(ids[:SoilMoisture], ids[:Vegetation]),
                                     minmax(ids[:GrazingPressure], ids[:Vegetation]),
                                     minmax(ids[:SoilMoisture], ids[:GrazingPressure]),
                                     minmax(ids[:Vegetation], ids[:HabitatQuality]),
                                     minmax(ids[:HabitatQuality], ids[:Occupancy])])
        # `SimpleGraph` stores each undirected edge once, where Catlab's `SymmetricGraph`
        # stored it as a pair of involutive edges (16 there, 8 here).
        @test ne(mg) == 8
        @test has_edge(mg, ids[:Climate], ids[:Irrigation])
        @test has_edge(mg, ids[:Irrigation], ids[:Climate])
        @test Set(neighbors(mg, ids[:Occupancy])) == Set([ids[:HabitatQuality]])
    end
end
