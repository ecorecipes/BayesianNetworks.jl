"""
A minimal abstract syntax tree and pretty printer for the subset of Graphviz's DOT
language that this ecosystem draws with, plus the binding that runs the `Graphviz_jll`
binaries. It replaces `Catlab.Graphics.Graphviz` so that drawing a network needs no
Catlab (ADR 0009); the names, fields and printed DOT are the same, so callers and
tests written against Catlab's module keep working.

References: the [DOT grammar](https://graphviz.org/doc/info/lang.html).
"""
module Graphviz

using OrderedCollections: OrderedDict
using Graphviz_jll: Graphviz_jll

export Expression, Statement, Attributes, Graph, Digraph, Subgraph, Node, NodeID, Edge,
       pprint, run_graphviz

# AST
#####

"""
    Expression

Abstract supertype of every node of the DOT abstract syntax tree.
"""
abstract type Expression end

"""
    Statement <: Expression

Abstract supertype of the statements of a graph body: [`Node`](@ref), [`Edge`](@ref)
and [`Subgraph`](@ref).
"""
abstract type Statement <: Expression end

"""
    Attributes

Graphviz attribute list: an `OrderedDict{Symbol, String}`, printed in insertion order.
"""
const Attributes = OrderedDict{Symbol,String}

_attr_value(v) = v isa AbstractString ? String(v) : string(v)
as_attributes(attrs::Attributes) = attrs
as_attributes(d::OrderedDict) = Attributes(Symbol(k) => _attr_value(v) for (k, v) in d)
# A plain dictionary has no order of its own, so its keys are sorted to keep the
# printed DOT deterministic.
function as_attributes(d::AbstractDict)
    return Attributes(Symbol(k) => _attr_value(d[k]) for k in sort!(collect(keys(d))))
end

"""
    Graph(name, stmts; prog, graph_attrs, node_attrs, edge_attrs)
    Digraph(name, stmts; ...)

A DOT graph: a name, a direction flag, the layout program to run, the body statements
and the three default attribute lists. [`Digraph`](@ref) builds a directed one.
"""
struct Graph <: Expression
    name::String
    directed::Bool
    prog::String
    stmts::Vector{Statement}
    graph_attrs::Attributes
    node_attrs::Attributes
    edge_attrs::Attributes
end

function Graph(; name::AbstractString="g", directed::Bool=false,
               prog::AbstractString="dot", stmts::Vector{Statement}=Statement[],
               graph_attrs::AbstractDict=Attributes(),
               node_attrs::AbstractDict=Attributes(),
               edge_attrs::AbstractDict=Attributes())
    return Graph(String(name), directed, String(prog), stmts, as_attributes(graph_attrs),
                 as_attributes(node_attrs), as_attributes(edge_attrs))
end

function Graph(name::AbstractString, stmts::Vector{Statement}; kw...)
    return Graph(; name=name, directed=false, stmts=stmts, kw...)
end

"""
    Digraph(name, stmts; prog, graph_attrs, node_attrs, edge_attrs) -> Graph

A directed [`Graph`](@ref), printed as `digraph name { ... }`.
"""
function Digraph(name::AbstractString, stmts::Vector{Statement}; kw...)
    return Graph(; name=name, directed=true, stmts=stmts, kw...)
end

"""
    Subgraph(name, stmts; graph_attrs, node_attrs, edge_attrs)

A nested subgraph statement. An empty name prints an anonymous `{ ... }` block.
"""
struct Subgraph <: Statement
    name::String
    stmts::Vector{Statement}
    graph_attrs::Attributes
    node_attrs::Attributes
    edge_attrs::Attributes
end

function Subgraph(name::AbstractString, stmts::Vector{Statement};
                  graph_attrs::AbstractDict=Attributes(),
                  node_attrs::AbstractDict=Attributes(),
                  edge_attrs::AbstractDict=Attributes())
    return Subgraph(String(name), stmts, as_attributes(graph_attrs),
                    as_attributes(node_attrs), as_attributes(edge_attrs))
end

"""
    Node(name, attrs)
    Node(name; attrs...)

A node statement: an identifier and its attribute list.
"""
struct Node <: Statement
    name::String
    attrs::Attributes
end
Node(name::AbstractString, attrs::AbstractDict) = Node(String(name), as_attributes(attrs))
Node(name::AbstractString; attrs...) = Node(String(name), as_attributes(Dict(attrs)))

"""
    NodeID(name, port = "", anchor = "")

A reference to a node inside an [`Edge`](@ref) path, optionally with a port and anchor.
"""
struct NodeID <: Expression
    name::String
    port::String
    anchor::String
end
function NodeID(name::AbstractString, port::AbstractString="",
                anchor::AbstractString="")
    return NodeID(String(name), String(port), String(anchor))
end

"""
    Edge(path, attrs)
    Edge(path; attrs...)

An edge statement joining the nodes of `path` in order. `path` is a vector of
[`NodeID`](@ref)s or of node names.
"""
struct Edge <: Statement
    path::Vector{NodeID}
    attrs::Attributes
end
Edge(path::Vector{NodeID}, attrs::AbstractDict) = Edge(path, as_attributes(attrs))
Edge(path::Vector{NodeID}; attrs...) = Edge(path, as_attributes(Dict(attrs)))
function Edge(path::AbstractVector{<:AbstractString}, attrs::AbstractDict)
    return Edge(map(NodeID, path),
                attrs)
end
Edge(path::AbstractVector{<:AbstractString}; attrs...) = Edge(map(NodeID, path); attrs...)

# Pretty printing
#################

_indent(io::IO, n::Int) = print(io, " "^n)

"""
    pprint([io], expr)

Print the DOT source of a [`Graph`](@ref) or of a single statement.
"""
pprint(expr::Expression) = pprint(stdout, expr)
pprint(io::IO, expr::Expression) = pprint(io, expr, 0)

function _pprint_attrs(io::IO, attrs::Attributes, n::Int=0; pre::String="",
                       post::String="")
    isempty(attrs) && return nothing
    _indent(io, n)
    print(io, pre, " [")
    for (i, (key, value)) in enumerate(attrs)
        i > 1 && print(io, ",")
        print(io, key, "=\"", value, "\"")
    end
    print(io, "]", post)
    return nothing
end

function _pprint_body(io::IO, g, n::Int, directed::Bool)
    _pprint_attrs(io, g.graph_attrs, n + 2; pre="graph", post=";\n")
    _pprint_attrs(io, g.node_attrs, n + 2; pre="node", post=";\n")
    _pprint_attrs(io, g.edge_attrs, n + 2; pre="edge", post=";\n")
    for stmt in g.stmts
        pprint(io, stmt, n + 2; directed=directed)
        println(io)
    end
    return nothing
end

function pprint(io::IO, graph::Graph, n::Int)
    _indent(io, n)
    println(io, graph.directed ? "digraph " : "graph ", graph.name, " {")
    _pprint_body(io, graph, n, graph.directed)
    _indent(io, n)
    println(io, "}")
    return nothing
end

function pprint(io::IO, sub::Subgraph, n::Int; directed::Bool=false)
    _indent(io, n)
    isempty(sub.name) ? println(io, "{") : println(io, "subgraph ", sub.name, " {")
    _pprint_body(io, sub, n, directed)
    _indent(io, n)
    print(io, "}")
    return nothing
end

function pprint(io::IO, node::Node, n::Int; directed::Bool=false)
    _indent(io, n)
    print(io, node.name)
    _pprint_attrs(io, node.attrs)
    print(io, ";")
    return nothing
end

function pprint(io::IO, node::NodeID, n::Int)
    print(io, node.name)
    isempty(node.port) || print(io, ":", node.port)
    isempty(node.anchor) || print(io, ":", node.anchor)
    return nothing
end

function pprint(io::IO, edge::Edge, n::Int; directed::Bool=false)
    _indent(io, n)
    for (i, node) in enumerate(edge.path)
        i > 1 && print(io, directed ? " -> " : " -- ")
        pprint(io, node, n)
    end
    _pprint_attrs(io, edge.attrs)
    print(io, ";")
    return nothing
end

Base.show(io::IO, graph::Graph) = pprint(io, graph)

# Rendering
###########

"""
    UnavailableGraphvizError()

Thrown by [`run_graphviz`](@ref) when the `Graphviz_jll` artifact is not available for
the current platform, so no layout program can be run.
"""
struct UnavailableGraphvizError <: Exception end

function Base.showerror(io::IO, ::UnavailableGraphvizError)
    return print(io,
                 "UnavailableGraphvizError: Graphviz_jll provides no binaries for this ",
                 "platform, so DOT sources cannot be rendered")
end

"""
    UnknownLayoutProgramError(prog)

Thrown by [`run_graphviz`](@ref) when `prog` is not one of the Graphviz layout programs
`dot`, `neato`, `fdp`, `sfdp`, `twopi`, `circo`.
"""
struct UnknownLayoutProgramError <: Exception
    prog::String
end

function Base.showerror(io::IO, e::UnknownLayoutProgramError)
    return print(io, "UnknownLayoutProgramError: ", repr(e.prog),
                 " is not a Graphviz layout program")
end

const LAYOUT_PROGRAMS = ("dot", "neato", "fdp", "sfdp", "twopi", "circo")

"""
    run_graphviz([io], graph; prog = graph.prog, format = "svg")

Lay `graph` out by running the Graphviz program `prog` from `Graphviz_jll` on its DOT
source and write the output in `format` to `io` (or return a readable `IOBuffer`).
"""
function run_graphviz(io::IO, graph::Graph; prog::Union{AbstractString,Nothing}=nothing,
                      format::AbstractString="svg")
    p = String(prog === nothing ? graph.prog : prog)
    p in LAYOUT_PROGRAMS || throw(UnknownLayoutProgramError(p))
    Graphviz_jll.is_available() || throw(UnavailableGraphvizError())
    # `Graphviz_jll.dot()` returns a `Cmd` carrying the library search path the
    # binaries need; interpolating a `Cmd` into a backtick expression keeps only its
    # arguments, so the environment and directory are copied over explicitly.
    base = getproperty(Graphviz_jll, Symbol(p))()
    cmd = Cmd(Cmd(vcat(base.exec, ["-T" * String(format)])); env=base.env, dir=base.dir)
    open(cmd, io; write=true) do gv
        return pprint(gv, graph)
    end
    return nothing
end

function run_graphviz(graph::Graph; kw...)
    io = IOBuffer()
    run_graphviz(io, graph; kw...)
    return seekstart(io)
end

Base.show(io::IO, ::MIME"image/svg+xml", g::Graph) = run_graphviz(io, g; format="svg")

end # module
