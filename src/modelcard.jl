"""
Model cards and per-parameter provenance (SPEC §49; the ecology review's P0 gap
"transparent model reporting and release"). A [`ModelCard`](@ref) is the reporting
record that travels with a model: what decision it was built for, which endpoint over
which spatial and temporal extent, why the graph looks the way it does and which
alternatives were considered, what the states mean, where every conditional probability
table came from ([`ParameterProvenance`](@ref)), how experts were elicited, how the
model was validated, what it may and may not be used for, and under which licence and
version it is released. [`report`](@ref) writes it as Markdown; the JSON envelope of
[`json_model`](@ref) carries it in a `"card"` section.

The card is metadata only: nothing here changes a kernel, an evaluation or the equality
of two models (SPEC §49, "provenance MUST NOT alter mathematical kernel equality").
"""

"""
    CARD_SCHEMA_VERSION

Version of the [`ModelCard`](@ref) layout written into JSON and reports.
"""
const CARD_SCHEMA_VERSION = "0.1"

"""
    SOURCE_TYPES

The source kinds a [`ParameterProvenance`](@ref) may declare: `:empirical` (estimated
from data), `:elicited` (from experts), `:literature` (taken from a publication),
`:mechanistic` (derived from a process model) and `:unknown` (not yet documented).
"""
const SOURCE_TYPES = (:empirical, :elicited, :literature, :mechanistic, :unknown)

"""
    ParameterProvenance(; source_type = :unknown, citation = "", dataset = "",
                        estimator = "", expert = "", timestamp = nothing, notes = "")

Where one mechanism's numbers came from (SPEC §49). `source_type` is one of
[`SOURCE_TYPES`](@ref); `citation` is a reference to the publication or report,
`dataset` names the data used, `estimator` the fitting or aggregation method, `expert`
the person or panel elicited, `timestamp` when the parameters were set (a `DateTime` or
`nothing`) and `notes` anything else a reader needs.

Attach one to a card with [`provenance!`](@ref) and read it back with
[`provenance`](@ref).

# Example

```jldoctest
julia> p = ParameterProvenance(; source_type = :elicited, expert = "regional panel",
                               notes = "three-point elicitation");

julia> p.source_type, p.expert
(:elicited, "regional panel")
```
"""
struct ParameterProvenance
    source_type::Symbol
    citation::String
    dataset::String
    estimator::String
    expert::String
    timestamp::Union{DateTime,Nothing}
    notes::String
end

function ParameterProvenance(; source_type::Symbol=:unknown, citation::AbstractString="",
                             dataset::AbstractString="", estimator::AbstractString="",
                             expert::AbstractString="",
                             timestamp::Union{DateTime,Nothing}=nothing,
                             notes::AbstractString="")
    source_type in SOURCE_TYPES ||
        throw(ArgumentError("source_type must be one of $(SOURCE_TYPES), got :$source_type"))
    return ParameterProvenance(source_type, String(citation), String(dataset),
                               String(estimator), String(expert), timestamp,
                               String(notes))
end

function Base.:(==)(a::ParameterProvenance, b::ParameterProvenance)
    return all(getfield(a, f) == getfield(b, f) for f in fieldnames(ParameterProvenance))
end

function Base.hash(p::ParameterProvenance, h::UInt)
    for f in fieldnames(ParameterProvenance)
        h = hash(getfield(p, f), h)
    end
    return hash(:ParameterProvenance, h)
end

"""
    ModelCard(; name, model_version, ...)
    ModelCard(m::BayesModel; kwargs...)

The reporting record of a model, following the minimum standard the ecology literature
asks for (Marcot et al. 2006; Chen and Pollino 2012; Kaikkonen et al. 2021). Fields, all
keyword arguments of the constructors:

| Field | Meaning |
|---|---|
| `name` | the model's name |
| `model_version` | the version of the model this card describes |
| `schema_version` | the card layout ([`CARD_SCHEMA_VERSION`](@ref)) |
| `decision_context` | the decision the model was built to support |
| `endpoint` | the management or ecological endpoint predicted |
| `spatial_extent`, `temporal_extent` | where and when the model is meant to apply |
| `graph_rationale` | why the structure is what it is |
| `alternative_structures` | named competing structures that were considered |
| `variables`, `states` | the variables and their states, from the syntax |
| `state_definitions` | what each variable's states mean (variable name to text) |
| `mechanisms`, `kernel_refs` | the mechanisms and the references they resolve to |
| `provenance` | mechanism name to [`ParameterProvenance`](@ref) |
| `elicitation_protocol` | how experts were selected, elicited and aggregated |
| `validation_summary` | free text on how the model was tested |
| `validation_scores` | named scores, the slot BayesianNetworkInference.jl fills |
| `intended_use`, `limitations` | what the model may and may not be used for |
| `license` | the licence the model is released under |
| `history` | the model's [`ModelEvent`](@ref) rewrites, from the model |

`ModelCard(m)` prefills `name` (from `extras(m)[:name]` when present), `variables`,
`states`, `state_definitions` (empty text per variable), `mechanisms`, `kernel_refs` and
`history` from `m`, leaving the narrative fields empty for the modeller to fill in;
every one of them can be overridden by a keyword argument. Nothing in the card is read
by the semantics.

Write it with [`report`](@ref), attach provenance with [`provenance!`](@ref), and
serialise it in the model envelope with [`json_model`](@ref)`(m; card = card)`.

# Example

```jldoctest
julia> card = ModelCard(reference_habitat_model(); decision_context = "grazing policy",
                        endpoint = "Occupancy", license = "CC BY 4.0");

julia> card.name, length(card.variables), card.states[:Occupancy]
(:model, 7, [:absent, :present])

julia> provenance!(card, :Occupancy_mechanism => ParameterProvenance(; source_type = :elicited));

julia> provenance(card, :Occupancy_mechanism).source_type
:elicited
```
"""
struct ModelCard
    name::Symbol
    model_version::String
    schema_version::String
    decision_context::String
    endpoint::String
    spatial_extent::String
    temporal_extent::String
    graph_rationale::String
    alternative_structures::Vector{String}
    variables::Vector{Symbol}
    states::Dict{Symbol,Vector{Symbol}}
    state_definitions::Dict{Symbol,String}
    mechanisms::Vector{Symbol}
    kernel_refs::Dict{Symbol,KernelRef}
    provenance::Dict{Symbol,ParameterProvenance}
    elicitation_protocol::String
    validation_summary::String
    validation_scores::Dict{Symbol,Float64}
    intended_use::String
    limitations::String
    license::String
    history::Vector{ModelEvent}
end

function ModelCard(; name::Symbol=:model, model_version::AbstractString="0.1",
                   schema_version::AbstractString=CARD_SCHEMA_VERSION,
                   decision_context::AbstractString="", endpoint::AbstractString="",
                   spatial_extent::AbstractString="", temporal_extent::AbstractString="",
                   graph_rationale::AbstractString="",
                   alternative_structures::AbstractVector{<:AbstractString}=String[],
                   variables::AbstractVector{Symbol}=Symbol[],
                   states::AbstractDict=Dict{Symbol,Vector{Symbol}}(),
                   state_definitions::AbstractDict=Dict{Symbol,String}(),
                   mechanisms::AbstractVector{Symbol}=Symbol[],
                   kernel_refs::AbstractDict=Dict{Symbol,KernelRef}(),
                   provenance::AbstractDict=Dict{Symbol,ParameterProvenance}(),
                   elicitation_protocol::AbstractString="",
                   validation_summary::AbstractString="",
                   validation_scores::AbstractDict=Dict{Symbol,Float64}(),
                   intended_use::AbstractString="", limitations::AbstractString="",
                   license::AbstractString="",
                   history::AbstractVector{ModelEvent}=ModelEvent[])
    return ModelCard(name, String(model_version), String(schema_version),
                     String(decision_context), String(endpoint), String(spatial_extent),
                     String(temporal_extent), String(graph_rationale),
                     collect(String, alternative_structures), collect(Symbol, variables),
                     Dict{Symbol,Vector{Symbol}}(states),
                     Dict{Symbol,String}(state_definitions), collect(Symbol, mechanisms),
                     Dict{Symbol,KernelRef}(kernel_refs),
                     Dict{Symbol,ParameterProvenance}(provenance),
                     String(elicitation_protocol), String(validation_summary),
                     Dict{Symbol,Float64}(validation_scores), String(intended_use),
                     String(limitations), String(license), collect(ModelEvent, history))
end

function ModelCard(m::BayesModel; kw...)
    bn = syntax(m)
    vars = variable_names(bn)
    mechs = mechanism_names(bn)
    defaults = (name=Symbol(get(extras(m), :name, :model)), variables=vars,
                states=Dict{Symbol,Vector{Symbol}}(x => states(bn, x) for x in vars),
                state_definitions=Dict{Symbol,String}(x => "" for x in vars),
                mechanisms=mechs,
                kernel_refs=Dict{Symbol,KernelRef}(k => _set_kernel_ref(bn, k)
                                                   for k in mechs),
                history=history(m))
    return ModelCard(; merge(defaults, NamedTuple(kw))...)
end

function Base.:(==)(a::ModelCard, b::ModelCard)
    return all(getfield(a, f) == getfield(b, f) for f in fieldnames(ModelCard))
end

function Base.hash(c::ModelCard, h::UInt)
    for f in fieldnames(ModelCard)
        h = hash(getfield(c, f), h)
    end
    return hash(:ModelCard, h)
end

function Base.show(io::IO, c::ModelCard)
    print(io, "ModelCard(:", c.name, " v", c.model_version, ", ", length(c.variables),
          " variables, ", length(c.provenance), "/", length(c.mechanisms),
          " mechanisms with provenance")
    isempty(c.validation_scores) ||
        print(io, ", ", length(c.validation_scores), " score",
              length(c.validation_scores) == 1 ? "" : "s")
    return print(io, ")")
end

"""
    provenance!(card::ModelCard, :Mechanism => p::ParameterProvenance) -> ModelCard
    provenance!(card, [:M1 => p1, :M2 => p2]) -> ModelCard

Record where a mechanism's numbers came from. The mechanism must be one of the card's
([`UnknownMechanismError`](@ref) otherwise), which is what keeps a card and its model
in step. The card is updated in place (its `provenance` dictionary is mutable) and
returned, so calls chain.
"""
function provenance!(card::ModelCard, p::Pair{Symbol,ParameterProvenance})
    mech, prov = p
    mech in card.mechanisms || throw(UnknownMechanismError(mech))
    card.provenance[mech] = prov
    return card
end

function provenance!(card::ModelCard,
                     ps::AbstractVector{<:Pair{Symbol,ParameterProvenance}})
    return foldl(provenance!, ps; init=card)
end

"""
    provenance(card::ModelCard, :Mechanism) -> ParameterProvenance
    provenance(card::ModelCard) -> Dict{Symbol, ParameterProvenance}

The provenance recorded for a mechanism (an [`UnknownMechanismError`](@ref) when the
mechanism is not the card's, and a `:unknown` [`ParameterProvenance`](@ref) when it is
but nothing was recorded), or the whole dictionary.
"""
function provenance(card::ModelCard, mech::Symbol)
    mech in card.mechanisms || throw(UnknownMechanismError(mech))
    return get(card.provenance, mech, ParameterProvenance())
end

provenance(card::ModelCard) = card.provenance

"""
    undocumented_mechanisms(card::ModelCard) -> Vector{Symbol}

The mechanisms of `card` with no [`ParameterProvenance`](@ref), in the card's order:
the gaps a reader of the [`report`](@ref) should be told about.
"""
function undocumented_mechanisms(card::ModelCard)
    return Symbol[m for m in card.mechanisms if !haskey(card.provenance, m)]
end

# Reporting
###########

_text(s::AbstractString) = isempty(strip(s)) ? "*Not documented.*" : String(s)

# A kernel reference as one short cell of the provenance table.
_ref_text(r::NamedRef) = string("`", r.id, "`")
_ref_text(r::PointMassRef) = string("point mass on `", r.state, "`")
_ref_text(r::PolicyRef) = string("policy of `", r.decision, "`")
_ref_text(::NoRef) = ""

function _report_provenance(io::IO, card::ModelCard, mech::Symbol)
    ref = _ref_text(get(card.kernel_refs, mech, NoRef()))
    p = get(card.provenance, mech, nothing)
    fields = p === nothing ? ("*not documented*", "", "", "", "", "", "") :
             (String(p.source_type), p.citation, p.dataset, p.estimator, p.expert,
              p.timestamp === nothing ? "" : string(p.timestamp), p.notes)
    println(io, "| `", mech, "` | ", ref, " | ", join(fields, " | "), " |")
    return nothing
end

"""
    report(io::IO, card::ModelCard) -> Nothing
    report(card::ModelCard) -> String

Write the card as Markdown (the second form returns it as a string). The sections are
those the ecology reporting standard asks for, in order: `# Model card`,
`## Decision context`, `## Endpoint and extent`, `## Graph rationale and alternatives`,
`## Variables and states`, `## Mechanisms and parameter provenance`,
`## Elicitation protocol`, `## Validation`, `## Intended use and limitations`,
`## Model history` and `## Release`. Fields that were left empty are printed as
*Not documented.*, so a report shows its own gaps rather than hiding them.

# Example

```jldoctest
julia> card = ModelCard(reference_habitat_model(); endpoint = "Occupancy");

julia> occursin("## Mechanisms and parameter provenance", report(card))
true
```
"""
function report(io::IO, card::ModelCard)
    println(io, "# Model card: ", card.name)
    println(io)
    println(io, "## Decision context")
    println(io)
    println(io, _text(card.decision_context))
    println(io)
    println(io, "## Endpoint and extent")
    println(io)
    println(io, "- Endpoint: ", _text(card.endpoint))
    println(io, "- Spatial extent: ", _text(card.spatial_extent))
    println(io, "- Temporal extent: ", _text(card.temporal_extent))
    println(io)
    println(io, "## Graph rationale and alternatives")
    println(io)
    println(io, _text(card.graph_rationale))
    println(io)
    if isempty(card.alternative_structures)
        println(io, "*No alternative structures recorded.*")
    else
        for a in card.alternative_structures
            println(io, "- ", a)
        end
    end
    println(io)
    println(io, "## Variables and states")
    println(io)
    println(io, "| Variable | States | Definition |")
    println(io, "|---|---|---|")
    for x in card.variables
        st = join(get(card.states, x, Symbol[]), ", ")
        println(io, "| `", x, "` | ", st, " | ",
                _text(get(card.state_definitions, x, "")), " |")
    end
    println(io)
    println(io, "## Mechanisms and parameter provenance")
    println(io)
    println(io,
            "| Mechanism | Reference | Source | Citation | Dataset | Estimator | Expert | Timestamp | Notes |")
    println(io, "|---|---|---|---|---|---|---|---|---|")
    for mech in card.mechanisms
        _report_provenance(io, card, mech)
    end
    println(io)
    gaps = undocumented_mechanisms(card)
    isempty(gaps) ||
        println(io, "Mechanisms without provenance: ",
                join(string.("`", gaps, "`"), ", "), ".\n")
    println(io, "## Elicitation protocol")
    println(io)
    println(io, _text(card.elicitation_protocol))
    println(io)
    println(io, "## Validation")
    println(io)
    println(io, _text(card.validation_summary))
    println(io)
    if isempty(card.validation_scores)
        println(io, "*No scores recorded.*")
    else
        println(io, "| Score | Value |")
        println(io, "|---|---|")
        for k in sort!(collect(keys(card.validation_scores)))
            println(io, "| ", k, " | ", card.validation_scores[k], " |")
        end
    end
    println(io)
    println(io, "## Intended use and limitations")
    println(io)
    println(io, "- Intended use: ", _text(card.intended_use))
    println(io, "- Limitations: ", _text(card.limitations))
    println(io)
    println(io, "## Model history")
    println(io)
    if isempty(card.history)
        println(io, "*No recorded rewrites.*")
    else
        println(io, "| When | Kind | Target | Note |")
        println(io, "|---|---|---|---|")
        for e in card.history
            println(io, "| ", e.time, " | ", e.kind, " | `", e.target, "` | ",
                    isempty(e.note) ? "" : e.note, " |")
        end
    end
    println(io)
    println(io, "## Release")
    println(io)
    println(io, "- Licence: ", _text(card.license))
    println(io, "- Model version: ", card.model_version)
    println(io, "- Card schema version: ", card.schema_version)
    return nothing
end

report(card::ModelCard) = sprint(report, card)
