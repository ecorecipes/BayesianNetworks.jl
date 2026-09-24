"""
Graphviz drawings. `to_graphviz(bn)` draws the derived DAG of a network with the
variables as nodes (name and states) and one edge per `Input`; models add evidence
shading and a distinct style for intervened variables. Every drawing is a
[`Graphviz.Graph`](@ref BayesianNetworks.Graphviz.Graph), the DOT syntax tree of
`src/graphviz.jl`, which `show`s as SVG (`MIME"image/svg+xml"`) through Graphviz_jll,
so notebooks and quarto documents embed the figure directly.

`CategoricalBayesianNetworks.jl` adds the methods for open networks and for wiring
diagrams to the same `to_graphviz` function.
"""

"""
    to_graphviz(x; kwargs...) -> Graphviz.Graph

Draw `x` with Graphviz. This package draws networks and models;
`CategoricalBayesianNetworks.jl` and `InfluenceDiagrams.jl` add methods for the objects
they define.
"""
function to_graphviz end

const _GV_FONT = "Helvetica"

# Catlab's Graphviz_jll backend (still used by `CategoricalBayesianNetworks.jl` for
# wiring diagrams) runs the artifact binaries by their bare path, so the library search
# path that JLLWrappers sets up inside `Graphviz_jll.dot()` is lost and `dot` cannot
# find its libraries on macOS. Exporting that path to the process makes
# `show(io, MIME"image/svg+xml"(), g)` work with the bundled Graphviz everywhere.
# Called from the module's `__init__`.
function _graphviz_environment!()
    Graphviz_jll.is_available() || return nothing
    cmd = Graphviz_jll.dot()
    cmd.env === nothing && return nothing
    for kv in cmd.env
        k, v = split(kv, "="; limit=2)
        k in ("DYLD_FALLBACK_LIBRARY_PATH", "LD_LIBRARY_PATH", "PATH") || continue
        ENV[k] = v
    end
    return nothing
end

_gv_string(x) = x isa AbstractString ? String(x) : string(x)
_gv_attrs(d::AbstractDict) = Dict{Symbol,String}(Symbol(k) => _gv_string(v) for (k, v) in d)

"""
    to_graphviz(bn::AbstractBayesNet; kwargs...) -> Graphviz.Graph
    to_graphviz(m::BayesModel; kwargs...)

Draw the derived DAG of a network with Graphviz: one node per variable, labelled with
its name and (with `states = true`) its states, and one edge per `Input`, from the
input variable to the mechanism's target. A variable whose mechanism carries a
[`PointMassRef`](@ref) is drawn as a hard intervention, labelled `do(X = x)` with a
double border; the variables named in `intervened` (soft interventions, from a model's
[`history`](@ref)) get the double border too; variables with `evidence` are shaded and
labelled `X = x`; `inputs` are drawn with a dashed border and `outputs` with a bold one.
On a model, `intervened` and `evidence` default to
[`intervened_variables`](@ref)`(m)` and [`evidence`](@ref)`(m)`. The `inputs` and
`outputs` keywords are what `CategoricalBayesianNetworks.jl` fills in from the
interface of an open network.

Keyword arguments: `states`, `intervened`, `evidence`, `inputs`, `outputs`,
`edge_labels = false` (label edges with the input position), `rankdir = "TB"`, `name`,
and `graph_attrs`, `node_attrs`, `edge_attrs` (dictionaries merged over the defaults).
Render with `show(io, MIME"image/svg+xml"(), g)` or
[`Graphviz.run_graphviz`](@ref BayesianNetworks.Graphviz.run_graphviz).
"""
function to_graphviz(bn::AbstractBayesNet; states::Bool=true,
                     intervened::AbstractVector{Symbol}=Symbol[],
                     evidence::AbstractDict{Symbol,Symbol}=Dict{Symbol,Symbol}(),
                     inputs::AbstractVector{Symbol}=Symbol[],
                     outputs::AbstractVector{Symbol}=Symbol[], edge_labels::Bool=false,
                     rankdir::AbstractString="TB", name::AbstractString="G",
                     graph_attrs::AbstractDict=Dict{Symbol,String}(),
                     node_attrs::AbstractDict=Dict{Symbol,String}(),
                     edge_attrs::AbstractDict=Dict{Symbol,String}())
    stmts = Graphviz.Statement[]
    for v in variables(bn)
        x = variable_name(bn, v)
        mech = mechanism_of(bn, v)
        ref = mech === nothing ? NoRef() : kernel_ref(bn, mech)
        hard = ref isa PointMassRef
        attrs = Dict{Symbol,String}()
        label = if hard
            "do($x = $(ref.state))"
        elseif haskey(evidence, x)
            "$x = $(evidence[x])"
        else
            string(x)
        end
        if states && !hard && !haskey(evidence, x)
            label *= "\\n{" * join(BayesianNetworks.states(bn, v), ", ") * "}"
        end
        attrs[:label] = label
        style = String["filled"]
        if hard || x in intervened
            attrs[:peripheries] = "2"
            attrs[:color] = "firebrick"
        end
        haskey(evidence, x) && (attrs[:fillcolor] = "lightgrey")
        x in inputs && push!(style, "dashed")
        x in outputs && push!(style, "bold")
        attrs[:style] = join(style, ",")
        push!(stmts, Graphviz.Node("v$v", attrs))
    end
    for mech in mechanisms(bn)
        t = target(bn, mech)
        for (i, p) in enumerate(BayesianNetworks.inputs(bn, mech))
            attrs = edge_labels ? Dict{Symbol,String}(:label => string(i)) :
                    Dict{Symbol,String}()
            push!(stmts, Graphviz.Edge(["v$p", "v$t"], attrs))
        end
    end
    return Graphviz.Digraph(String(name), stmts; prog="dot",
                            graph_attrs=merge(Dict{Symbol,String}(:rankdir => String(rankdir),
                                                                  :fontname => _GV_FONT),
                                              _gv_attrs(graph_attrs)),
                            node_attrs=merge(Dict{Symbol,String}(:shape => "ellipse",
                                                                 :fontname => _GV_FONT,
                                                                 :fillcolor => "white",
                                                                 :margin => "0.1,0.05"),
                                             _gv_attrs(node_attrs)),
                            edge_attrs=merge(Dict{Symbol,String}(:arrowsize => "0.7",
                                                                 :fontname => _GV_FONT),
                                             _gv_attrs(edge_attrs)))
end

function to_graphviz(m::BayesModel; intervened=intervened_variables(m),
                     evidence=BayesianNetworks.evidence(m), kw...)
    return to_graphviz(syntax(m); intervened=intervened, evidence=evidence, kw...)
end
