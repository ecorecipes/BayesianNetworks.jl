"""
JSON serialisation. Networks are written with ACSets' `generate_json_acset` inside an
envelope that records the format name and schema version (SPEC §48).
"""

const JSON_FORMAT = "bayesnet-acset"
const JSON_SCHEMA_VERSION = "0.1"

"""
    json_bayesnet(bn) -> String

Serialise `bn` as a JSON string of the form
`{"format": "bayesnet-acset", "schema_version": "0.1", "acset": ...}` where `acset` is
the ACSets.jl JSON representation. [`KernelRef`](@ref) attributes are written as
objects with a `"type"` discriminator. Inverse of [`parse_json_bayesnet`](@ref).
"""
function json_bayesnet(bn::AbstractBayesNet)
    return JSON3.write((format=JSON_FORMAT, schema_version=JSON_SCHEMA_VERSION,
                        acset=generate_json_acset(bn)))
end

"""
    parse_json_bayesnet(str; type = BayesNet) -> type

Parse a JSON string produced by [`json_bayesnet`](@ref) into a network of the given
ACSet `type`. Throws [`FormatError`](@ref) if the envelope is missing or names another
format or schema version.
"""
function parse_json_bayesnet(str::AbstractString; type::Type{<:AbstractBayesNet}=BayesNet)
    return _parse_envelope(JSON3.read(str), type)
end

function _parse_envelope(obj, type)
    obj isa AbstractDict || throw(FormatError("expected a JSON object envelope"))
    for key in (:format, :schema_version, :acset)
        haskey(obj, key) || throw(FormatError("envelope is missing the \"$key\" key"))
    end
    obj[:format] == JSON_FORMAT ||
        throw(FormatError("format is \"$(obj[:format])\", expected \"$JSON_FORMAT\""))
    obj[:schema_version] == JSON_SCHEMA_VERSION ||
        throw(FormatError("schema_version is \"$(obj[:schema_version])\", expected \"$JSON_SCHEMA_VERSION\""))
    return parse_json_acset(type, obj[:acset])
end

"""
    write_json_bayesnet(path, bn)

Write [`json_bayesnet`](@ref)`(bn)` to the file at `path`.
"""
function write_json_bayesnet(path::AbstractString, bn::AbstractBayesNet)
    open(path, "w") do io
        return write(io, json_bayesnet(bn))
    end
    return path
end

"""
    read_json_bayesnet(path; type = BayesNet) -> type

Read a network written by [`write_json_bayesnet`](@ref).
"""
function read_json_bayesnet(path::AbstractString; type::Type{<:AbstractBayesNet}=BayesNet)
    return _parse_envelope(JSON3.read(read(path, String)), type)
end

"""
    schema_json(T::Type{<:AbstractVariableSpace})
    schema_json(S::ACSets.Schema)
    schema_json(pres::GATlab.Presentation)

The ACSets.jl JSON description (`generate_json_acset_schema`) of the schema of ACSet
type `T`, of a schema such as [`SchBayesNet`](@ref), or of a Catlab schema
presentation. This is the object compared against the schema emitted by the Lean
project in `proofs/schemas/`.
"""
function schema_json(::Type{T}) where {T<:AbstractVariableSpace}
    return generate_json_acset_schema(acset_schema(T()))
end
schema_json(S::Schema) = generate_json_acset_schema(S)
schema_json(pres::Presentation) = generate_json_acset_schema(pres)

# Models with semantics
#######################

_json_axis(a::FiniteAxis) = (name=String(a.name), labels=String.(a.labels))
_json_space(X::FiniteSpace) = [_json_axis(a) for a in factors(X)]

function _json_kernel(ref::KernelRef, k::FiniteKernel)
    return (ref=StructTypes.lower(ref), dom=_json_space(k.dom), codom=_json_space(k.codom),
            size=collect(size(k.table)), table=vec(Float64.(k.table)))
end

function _json_record(r::Union{MechanismRecord,Nothing})
    r === nothing && return nothing
    return (name=String(r.name), kernel_ref=StructTypes.lower(r.kernel_ref),
            inputs=String.(r.inputs))
end

function _json_event(e::ModelEvent)
    return (kind=String(e.kind), target=String(e.target), removed=_json_record(e.removed),
            added=_json_record(e.added), note=e.note, time=string(e.time))
end

"""
    json_model(m::BayesModel; card = nothing) -> String

Serialise a model as JSON: the [`json_bayesnet`](@ref) envelope of its syntax with the
additional keys `"semantics"` (`"spaces"`, variable name to state names, and
`"kernels"`, a list of `{"ref", "dom", "codom", "size", "table"}` objects with the
table flattened in column-major order), `"evidence"`, `"history"` and `"extras"`.
Only `FiniteSpace` spaces and `FiniteKernel` kernels are written. Inverse of
[`parse_json_model`](@ref); [`parse_json_bayesnet`](@ref) reads the syntax alone.

A [`ModelCard`](@ref) passed as `card` is written as a further `"card"` section (see
[`json_card`](@ref)) and read back by [`parse_json_card`](@ref); documents without one
are read exactly as before, and the card never changes how the model itself is parsed.
"""
function json_model(m::BayesModel; card::Union{Nothing,ModelCard}=nothing)
    sp = Dict{String,Any}(String(x) => String.(only(factors(X)).labels)
                          for (x, X) in m.spaces if X isa FiniteSpace && ndims(X) == 1)
    ks = [_json_kernel(r, k) for (r, k) in m.kernels if k isa FiniteKernel]
    body = (format=JSON_FORMAT, schema_version=JSON_SCHEMA_VERSION,
            acset=generate_json_acset(m.syntax),
            semantics=(spaces=sp, kernels=ks),
            evidence=Dict(String(k) => String(v) for (k, v) in m.evidence),
            history=[_json_event(e) for e in m.history],
            extras=_json_extras(m.extras))
    return JSON3.write(card === nothing ? body :
                       merge(body, (card=_json_card(card),)))
end

# The card as a JSON-ready named tuple; `json_card` wraps it in the same envelope as a
# model so that a card can also travel on its own.
function _json_card(c::ModelCard)
    return (name=String(c.name), model_version=c.model_version,
            schema_version=c.schema_version, decision_context=c.decision_context,
            endpoint=c.endpoint, spatial_extent=c.spatial_extent,
            temporal_extent=c.temporal_extent, graph_rationale=c.graph_rationale,
            alternative_structures=c.alternative_structures,
            variables=String.(c.variables),
            states=Dict(String(x) => String.(st) for (x, st) in c.states),
            state_definitions=Dict(String(x) => t for (x, t) in c.state_definitions),
            mechanisms=String.(c.mechanisms),
            kernel_refs=Dict(String(k) => StructTypes.lower(r)
                             for (k, r) in c.kernel_refs),
            provenance=Dict(String(k) => _json_provenance(p)
                            for (k, p) in c.provenance),
            elicitation_protocol=c.elicitation_protocol,
            validation_summary=c.validation_summary,
            validation_scores=Dict(String(k) => v for (k, v) in c.validation_scores),
            intended_use=c.intended_use, limitations=c.limitations, license=c.license,
            history=[_json_event(e) for e in c.history])
end

function _json_provenance(p::ParameterProvenance)
    return (source_type=String(p.source_type), citation=p.citation, dataset=p.dataset,
            estimator=p.estimator, expert=p.expert,
            timestamp=p.timestamp === nothing ? nothing : string(p.timestamp),
            notes=p.notes)
end

function _parse_provenance(p)
    ts = _ref_field(p, :timestamp)
    return ParameterProvenance(; source_type=Symbol(_ref_field(p, :source_type)),
                               citation=String(_ref_field(p, :citation)),
                               dataset=String(_ref_field(p, :dataset)),
                               estimator=String(_ref_field(p, :estimator)),
                               expert=String(_ref_field(p, :expert)),
                               timestamp=ts === nothing ? nothing : DateTime(ts),
                               notes=String(_ref_field(p, :notes)))
end

function _parse_card(c)
    return ModelCard(; name=Symbol(_ref_field(c, :name)),
                     model_version=String(_ref_field(c, :model_version)),
                     schema_version=String(_ref_field(c, :schema_version)),
                     decision_context=String(_ref_field(c, :decision_context)),
                     endpoint=String(_ref_field(c, :endpoint)),
                     spatial_extent=String(_ref_field(c, :spatial_extent)),
                     temporal_extent=String(_ref_field(c, :temporal_extent)),
                     graph_rationale=String(_ref_field(c, :graph_rationale)),
                     alternative_structures=String[String(a)
                                                   for a in _ref_field(c,
                                                                       :alternative_structures)],
                     variables=Symbol[Symbol(x) for x in _ref_field(c, :variables)],
                     states=Dict{Symbol,Vector{Symbol}}(Symbol(x) => Symbol[Symbol(s)
                                                                            for s in st]
                                                        for (x, st) in _ref_field(c,
                                                                                  :states)),
                     state_definitions=Dict{Symbol,String}(Symbol(x) => String(t)
                                                           for (x, t) in _ref_field(c,
                                                                                    :state_definitions)),
                     mechanisms=Symbol[Symbol(x) for x in _ref_field(c, :mechanisms)],
                     kernel_refs=Dict{Symbol,KernelRef}(Symbol(k) => _kernel_ref_from(r)
                                                        for (k, r) in _ref_field(c,
                                                                                 :kernel_refs)),
                     provenance=Dict{Symbol,ParameterProvenance}(Symbol(k) => _parse_provenance(p)
                                                                 for (k, p) in
                                                                     _ref_field(c,
                                                                                :provenance)),
                     elicitation_protocol=String(_ref_field(c, :elicitation_protocol)),
                     validation_summary=String(_ref_field(c, :validation_summary)),
                     validation_scores=Dict{Symbol,Float64}(Symbol(k) => Float64(v)
                                                            for (k, v) in _ref_field(c,
                                                                                     :validation_scores)),
                     intended_use=String(_ref_field(c, :intended_use)),
                     limitations=String(_ref_field(c, :limitations)),
                     license=String(_ref_field(c, :license)),
                     history=ModelEvent[_parse_event(e) for e in _ref_field(c, :history)])
end

"""
    json_card(card::ModelCard) -> String

Serialise a [`ModelCard`](@ref) on its own, in the envelope
`{"format": "bayesnet-acset", "schema_version": "0.1", "card": ...}`. The same `"card"`
section is written into a model document by [`json_model`](@ref)`(m; card = card)`;
[`parse_json_card`](@ref) reads either.
"""
function json_card(card::ModelCard)
    return JSON3.write((format=JSON_FORMAT, schema_version=JSON_SCHEMA_VERSION,
                        card=_json_card(card)))
end

"""
    parse_json_card(str) -> Union{ModelCard, Nothing}

The [`ModelCard`](@ref) of a document written by [`json_card`](@ref) or by
[`json_model`](@ref) with a `card`, and `nothing` for a document without a `"card"`
section (every model file written before cards existed). The envelope is checked as in
[`parse_json_bayesnet`](@ref) ([`FormatError`](@ref)).
"""
function parse_json_card(str::AbstractString)
    obj = JSON3.read(str)
    obj isa AbstractDict || throw(FormatError("expected a JSON object envelope"))
    for key in (:format, :schema_version)
        haskey(obj, key) || throw(FormatError("envelope is missing the \"$key\" key"))
    end
    obj[:format] == JSON_FORMAT ||
        throw(FormatError("format is \"$(obj[:format])\", expected \"$JSON_FORMAT\""))
    haskey(obj, :card) || return nothing
    return _parse_card(obj[:card])
end

"""
    read_json_card(path) -> Union{ModelCard, Nothing}

The [`ModelCard`](@ref) stored in the file at `path`, or `nothing` when it has no
`"card"` section. Companion of [`read_json_model`](@ref), which reads the model from the
same file.
"""
read_json_card(path::AbstractString) = parse_json_card(read(path, String))

function _json_extras(x::AbstractDict)
    return Dict{String,Any}(string(k) => _json_extras(v) for (k, v) in x)
end
_json_extras(x::Union{AbstractVector,Tuple}) = Any[_json_extras(v) for v in x]
_json_extras(x::Symbol) = String(x)
_json_extras(x) = x

function _from_json_extras(x::AbstractDict)
    return Dict{Symbol,Any}(Symbol(k) => _from_json_extras(v)
                            for (k, v) in x)
end
_from_json_extras(x::AbstractVector) = Any[_from_json_extras(v) for v in x]
_from_json_extras(x) = x

function _parse_axis(a)
    return FiniteAxis(Symbol(_ref_field(a, :name)),
                      Symbol[Symbol(l) for l in _ref_field(a, :labels)])
end
_parse_space(v) = FiniteSpace(FiniteAxis[_parse_axis(a) for a in v])

function _parse_record(r)
    r === nothing && return nothing
    return MechanismRecord(Symbol(_ref_field(r, :name)),
                           _kernel_ref_from(_ref_field(r, :kernel_ref)),
                           Symbol[Symbol(s) for s in _ref_field(r, :inputs)])
end

function _parse_event(e)
    return ModelEvent(Symbol(_ref_field(e, :kind)), Symbol(_ref_field(e, :target)),
                      _parse_record(_ref_field(e, :removed)),
                      _parse_record(_ref_field(e, :added)),
                      String(_ref_field(e, :note)), DateTime(_ref_field(e, :time)))
end

"""
    parse_json_model(str; type = BayesNet) -> BayesModel

Parse a JSON string produced by [`json_model`](@ref). The envelope is checked like
[`parse_json_bayesnet`](@ref) ([`FormatError`](@ref)); a document without a
`"semantics"` key yields a model with spaces built from the syntax and no kernels.

`atol` is the normalisation tolerance each kernel is checked against, and must match the
one the model was bound with: a model read from a format file is bound at the tolerance
`read_bayesnet` used, and rounded CPTs are not renormalised, so parsing such a document
back at the default tolerance would reject it. A kernel outside the tolerance raises
[`FormatError`](@ref).
"""
function parse_json_model(str::AbstractString; type::Type{<:AbstractBayesNet}=BayesNet,
                          atol::Real=DEFAULT_ATOL)
    obj = JSON3.read(str)
    bn = _parse_envelope(obj, type)
    spaces = syntax_spaces(bn)
    kernels = Dict{KernelRef,FiniteKernel}()
    if haskey(obj, :semantics)
        sem = obj[:semantics]
        for (x, labels) in get(sem, :spaces, Dict())
            spaces[Symbol(x)] = FiniteSpace(Symbol(x), Symbol[Symbol(l) for l in labels])
        end
        for k in get(sem, :kernels, [])
            dom, codom = _parse_space(k[:dom]), _parse_space(k[:codom])
            table = reshape(Float64[Float64(v) for v in k[:table]], Tuple(Int.(k[:size])))
            ref = _kernel_ref_from(k[:ref])
            kernels[ref] = try
                FiniteKernel(dom, codom, table; atol=atol)
            catch e
                e isa FiniteKernels.KernelNormalizationError || rethrow()
                throw(FormatError("the kernel $(ref) is not normalised within atol=$(atol) " *
                                  "(largest row-mass deviation $(e.max_deviation)); pass the " *
                                  "atol the model was bound with"))
            end
        end
    end
    evidence = Dict{Symbol,Symbol}(Symbol(k) => Symbol(v)
                                   for (k, v) in get(obj, :evidence, Dict()))
    history = ModelEvent[_parse_event(e) for e in get(obj, :history, [])]
    extras = _from_json_extras(get(obj, :extras, Dict()))
    return BayesModel(bn; spaces=spaces, kernels=kernels, evidence=evidence,
                      history=history, extras=extras)
end

"""
    write_json_model(path, m::BayesModel; card = nothing)

Write [`json_model`](@ref)`(m; card = card)` to the file at `path`. Read the model back
with [`read_json_model`](@ref) and the card, when there is one, with
[`read_json_card`](@ref).
"""
function write_json_model(path::AbstractString, m::BayesModel;
                          card::Union{Nothing,ModelCard}=nothing)
    open(path, "w") do io
        return write(io, json_model(m; card=card))
    end
    return path
end

"""
    read_json_model(path; type = BayesNet) -> BayesModel

Read a model written by [`write_json_model`](@ref). `atol` is passed to
[`parse_json_model`](@ref) and must match the tolerance the model was bound with.
"""
function read_json_model(path::AbstractString; type::Type{<:AbstractBayesNet}=BayesNet,
                         atol::Real=DEFAULT_ATOL)
    return parse_json_model(read(path, String); type=type, atol=atol)
end
