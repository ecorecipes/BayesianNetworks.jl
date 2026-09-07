dot_source(g) = sprint(Graphviz.pprint, g)

@testset "Graphics" begin
    m = reference_habitat_model()
    ref = syntax(m)

    @testset "variable DAG" begin
        g = to_graphviz(ref)
        @test g isa Graphviz.Graph
        @test g.directed && g.prog == "dot"
        nodes = filter(s -> s isa Graphviz.Node, g.stmts)
        edges = filter(s -> s isa Graphviz.Edge, g.stmts)
        @test length(nodes) == nparts(ref, :Variable)
        @test length(edges) == nparts(ref, :Input)
        labels = Dict(n.name => n.attrs[:label] for n in nodes)
        @test labels["v$(variable_id(ref, :SoilMoisture))"] ==
              "SoilMoisture\\n{low, medium, high}"
        # Edges go from input variable to target, one per Input part.
        sm, veg = variable_id(ref, :SoilMoisture), variable_id(ref, :Vegetation)
        @test any(e -> [n.name for n in e.path] == ["v$sm", "v$veg"], edges)
        @test g.graph_attrs[:rankdir] == "TB"
        # Options.
        g2 = to_graphviz(ref; states=false, rankdir="LR", edge_labels=true,
                         node_attrs=Dict(:shape => "box"), name="habitat")
        @test g2.name == "habitat"
        @test all(n -> !occursin("{", n.attrs[:label]),
                  filter(s -> s isa Graphviz.Node, g2.stmts))
        @test g2.graph_attrs[:rankdir] == "LR"
        @test g2.node_attrs[:shape] == "box"
        e = first(filter(s -> s isa Graphviz.Edge, g2.stmts))
        @test e.attrs[:label] in ("1", "2")
        @test occursin("digraph habitat", dot_source(g2))
    end

    @testset "models, interventions, evidence" begin
        m2 = do_intervention(observe(m, :Climate => :dry), :Vegetation => :dense)
        m3 = soft_intervention(m2, :Occupancy => NamedRef("policy"); parents=[:Vegetation])
        g = to_graphviz(m3)
        nodes = Dict(n.name => n.attrs
                     for n in filter(s -> s isa Graphviz.Node, g.stmts))
        bn = syntax(m3)
        veg = nodes["v$(variable_id(bn, :Vegetation))"]
        @test veg[:label] == "do(Vegetation = dense)"
        @test veg[:peripheries] == "2"
        cl = nodes["v$(variable_id(bn, :Climate))"]
        @test cl[:label] == "Climate = dry" && cl[:fillcolor] == "lightgrey"
        occ = nodes["v$(variable_id(bn, :Occupancy))"]
        @test occ[:peripheries] == "2" && startswith(occ[:label], "Occupancy\\n")
        sm = nodes["v$(variable_id(bn, :SoilMoisture))"]
        @test !haskey(sm, :peripheries) && sm[:style] == "filled"
        # Explicit overrides on a plain network.
        g2 = to_graphviz(ref; evidence=Dict(:Occupancy => :present),
                         intervened=[:Climate])
        nodes = Dict(n.name => n.attrs
                     for n in filter(s -> s isa Graphviz.Node, g2.stmts))
        @test nodes["v$(variable_id(ref, :Occupancy))"][:label] == "Occupancy = present"
        @test nodes["v$(variable_id(ref, :Climate))"][:peripheries] == "2"
        # A hard intervention on the structure alone is drawn from its PointMassRef.
        g3 = to_graphviz(do_intervention(ref, :Climate => :wet))
        @test any(n -> n.attrs[:label] == "do(Climate = wet)",
                  filter(s -> s isa Graphviz.Node, g3.stmts))
    end

    @testset "SVG rendering" begin
        svg = sprint(show, MIME"image/svg+xml"(), to_graphviz(ref))
        @test occursin("<svg", svg)
        @test occursin("SoilMoisture", svg)
    end
end
