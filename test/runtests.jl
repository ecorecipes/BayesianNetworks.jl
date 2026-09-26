using Test
using BayesianNetworks

@testset "BayesianNetworks" begin
    include("helpers.jl")
    include("test_refs.jl")
    include("test_construction.jl")
    include("test_inspection.jl")
    include("test_graph.jl")
    include("test_validation.jl")
    include("test_canonicalize.jl")
    include("test_serialization.jl")
    include("test_interventions.jl")
    include("test_semantics.jl")
    include("test_certificates.jl")
    include("test_evaluation.jl")
    include("test_causal.jl")
    include("test_properties.jl")
    include("test_formats_bridge.jl")
    include("test_model_json.jl")
    include("test_modelcard.jl")
    include("test_graphics.jl")
    include("test_catcolab.jl")
    include("test_dynamic.jl")
    include("test_docstrings.jl")
end
