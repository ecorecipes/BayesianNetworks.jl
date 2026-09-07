"""
Bridge to BayesianNetworkFormats.jl: a `NetworkIR` (the intermediate representation of
Netica, GeNIe, HUGIN, BIF, DSC and UAI files) becomes a `BayesModel` with kernels bound
from its tables, and back. Only chance nodes are Bayesian-network variables; decision
and utility nodes belong to InfluenceDiagrams.jl. Titles, positions, comments, the
deterministic flags and format-specific extras are kept in `extras(m)` so that a round
trip through the IR is lossless.
"""

const _KIND_NAMES = Dict(ChanceNode => "chance", DecisionNode => "decision",
                         UtilityNode => "utility")

"""
    BayesModel(ir::NetworkIR; atol = 1e-6, renormalize = false) -> BayesModel

Build a model from a `NetworkIR`: one variable per chance node with the states as
symbols, one mechanism per node with the parents in IR order and the name
`Symbol(id, "_mechanism")`, and the kernel bound with [`bind_cpt`](@ref) from the
node's table (a missing table leaves the mechanism unbound; see
[`missing_kernels`](@ref)). Rows must sum to one within `atol` (looser than
`DEFAULT_ATOL`, since files store rounded probabilities; validate the result with the
same `atol`), or are rescaled with `renormalize = true`. Decision and utility nodes
raise [`UnsupportedNodeKindError`](@ref). The network name, format, source, titles,
positions, comments, deterministic flags and extras are stored in [`extras`](@ref)
(see [`ir_extras`](@ref)).
"""
function BayesModel(ir::NetworkIR; atol::Real=1e-6, renormalize::Bool=false)
    bn = BayesNet()
    for v in ir.variables
        v.kind == ChanceNode || throw(UnsupportedNodeKindError(v.id, _KIND_NAMES[v.kind]))
        add_variable!(bn, v.id; states=Symbol.(v.states))
    end
    for v in ir.variables
        add_mechanism!(bn, v.id; inputs=v.parents, name=Symbol(v.id, "_mechanism"))
    end
    m = BayesModel(bn; extras=ir_extras(ir))
    for v in ir.variables
        v.table === nothing && continue
        m = bind_cpt(m, v.id => v.table; atol=atol, renormalize=renormalize)
    end
    return m
end

"""
    ir_extras(ir::NetworkIR) -> Dict{Symbol,Any}

The metadata of a `NetworkIR` in the layout that [`BayesModel(::NetworkIR)`](@ref)
stores in [`extras`](@ref) and [`NetworkIR(::BayesModel)`](@ref) reads back: `:name`,
`:format`, `:source`, `:titles` (id to title), `:positions` (id to `(x, y)`, only nodes
with a position), `:comments` (only non-empty), `:deterministic` (ids),
`:variable_extras` (id to the node's extras, only non-empty) and `:network_extras` (a
copy of `ir.extras`). Wrappers that build their own model from an IR can start from
this dictionary and add their own keys.
"""
function ir_extras(ir::NetworkIR)
    titles = Dict{Symbol,String}(v.id => v.title for v in ir.variables)
    positions = Dict{Symbol,Tuple{Float64,Float64}}(v.id => v.position
                                                    for v in ir.variables
                                                    if v.position !== nothing)
    comments = Dict{Symbol,String}(v.id => v.comment
                                   for v in ir.variables if !isempty(v.comment))
    deterministic = Symbol[v.id for v in ir.variables if v.deterministic]
    vextras = Dict{Symbol,Dict{Symbol,Any}}(v.id => copy(v.extras)
                                            for v in ir.variables if !isempty(v.extras))
    return Dict{Symbol,Any}(:name => ir.name, :format => ir.format, :source => ir.source,
                            :titles => titles, :positions => positions,
                            :comments => comments, :deterministic => deterministic,
                            :variable_extras => vextras,
                            :network_extras => copy(ir.extras))
end

_extra(m::BayesModel, key::Symbol, default) = get(m.extras, key, default)

"""
    NetworkIR(m::BayesModel; name = extras(m)[:name]) -> NetworkIR

The model as a `NetworkIR` of chance nodes, variables in part-id order: states as
strings, parents in `input_position` order, the table `cpt(kernel(m, X))` for every
mechanism whose reference resolves (`nothing` otherwise, and for exogenous variables).
Titles, positions, comments, deterministic flags and extras are read back from
[`extras`](@ref). Evidence and history are not part of the IR.
"""
function NetworkIR(m::BayesModel; name::AbstractString=_extra(m, :name, "bayesnet"))
    bn = m.syntax
    titles = _extra(m, :titles, Dict{Symbol,String}())
    positions = _extra(m, :positions, Dict{Symbol,Any}())
    comments = _extra(m, :comments, Dict{Symbol,String}())
    deterministic = _extra(m, :deterministic, Symbol[])
    vextras = _extra(m, :variable_extras, Dict{Symbol,Dict{Symbol,Any}}())
    vars = IRVariable[]
    for v in variables(bn)
        id = variable_name(bn, v)
        mech = mechanism_of(bn, v)
        table = nothing
        ps = Symbol[]
        if mech !== nothing
            ps = Symbol[variable_name(bn, p) for p in inputs(bn, mech)]
            k = _resolve_kernel(bn, mech, m.kernels)
            k === nothing || (table = cpt(k))
        end
        push!(vars,
              IRVariable(id; title=get(titles, id, ""), states=string.(states(bn, v)),
                         parents=ps, table=table, deterministic=id in deterministic,
                         position=get(positions, id, nothing),
                         comment=get(comments, id, ""),
                         extras=get(vextras, id, Dict{Symbol,Any}())))
    end
    return NetworkIR(name, vars; format=_extra(m, :format, :ir),
                     source=_extra(m, :source, ""),
                     extras=_extra(m, :network_extras, Dict{Symbol,Any}()))
end

"""
    read_bayesnet(path; format = nothing, strict = true, atol = 1e-6, renormalize = false) -> BayesModel

`BayesModel(read_network(path; ...))`: read a network file in any format supported by
BayesianNetworkFormats.jl (detected from the extension unless `format` is given) and
bind its tables.

```julia
m = read_bayesnet(fixture_path("bif/asia.bif"))
marginal(m, :dysp).table   # [0.436, 0.564]
```
"""
function read_bayesnet(path::AbstractString; atol::Real=1e-6, renormalize::Bool=false,
                       kw...)
    ir = read_network(path; atol=atol, renormalize=renormalize, kw...)
    return BayesModel(ir; atol=atol, renormalize=renormalize)
end

"""
    write_bayesnet(path, m::BayesModel; format = nothing, name = extras(m)[:name]) -> path

`write_network(path, NetworkIR(m; name); format)`: write the model in the format given
or detected from the extension of `path`.
"""
function write_bayesnet(path::AbstractString, m::BayesModel; format=nothing,
                        name::AbstractString=_extra(m, :name, "bayesnet"))
    return write_network(path, NetworkIR(m; name=name); format=format)
end
