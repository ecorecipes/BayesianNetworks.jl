"""
The `BayesModel` wrapper: a structural network together with its semantic objects
(spaces and kernels, see `semantics.jl`), the evidence recorded by `observe`, the
provenance of every mechanism rewrite (SPEC §21.4, §49) and free-form metadata. The ACSet
itself stays purely structural.
"""

"""
    MechanismRecord(name, kernel_ref, inputs)

A snapshot of one mechanism: its name, its [`KernelRef`](@ref) and the names of its
input variables in `input_position` order. Stored in [`ModelEvent`](@ref)s so that the
mechanism removed or added by a rewrite can be read back without the network.
"""
struct MechanismRecord
    name::Symbol
    kernel_ref::KernelRef
    inputs::Vector{Symbol}
end

function Base.:(==)(a::MechanismRecord, b::MechanismRecord)
    return a.name == b.name && a.kernel_ref == b.kernel_ref && a.inputs == b.inputs
end
Base.hash(r::MechanismRecord, h::UInt) = hash(r.inputs, hash(r.kernel_ref, hash(r.name, h)))

"""
    ModelEvent(kind, target, removed, added, note, time)
    ModelEvent(kind, target, removed, added; note = "", time = now())

One entry of a model's history. `kind` is `:hard` (a hard intervention), `:soft` (a soft
intervention) or `:substitute` (a mechanism replaced by an open network); `target` is
the variable whose mechanism was rewritten; `removed` and `added` are
[`MechanismRecord`](@ref)s or `nothing` (for example `removed === nothing` when a hard
intervention acts on an exogenous variable); `note` is free text supplied by the caller
and `time` the wall-clock time of the rewrite.

`time` is deliberately excluded from `==` and `hash` (SPEC §49: "provenance MUST NOT
alter mathematical kernel equality"; SPEC §52: models are deterministic except for the
RNG), so two models built by the same sequence of operations compare equal however far
apart they were built. It is still shown, serialised and read back, and two events that
differ only in `time` are equal.
"""
struct ModelEvent
    kind::Symbol
    target::Symbol
    removed::Union{MechanismRecord,Nothing}
    added::Union{MechanismRecord,Nothing}
    note::String
    time::DateTime
end

function ModelEvent(kind::Symbol, target::Symbol, removed, added; note::AbstractString="",
                    time::DateTime=now())
    return ModelEvent(kind, target, removed, added, String(note), time)
end

# Every field but the wall-clock `time`, which records when a rewrite happened and must
# not decide whether two models are the same value.
const _EVENT_VALUE_FIELDS = (:kind, :target, :removed, :added, :note)

function Base.:(==)(a::ModelEvent, b::ModelEvent)
    return all(getfield(a, f) == getfield(b, f) for f in _EVENT_VALUE_FIELDS)
end

function Base.hash(e::ModelEvent, h::UInt)
    for f in _EVENT_VALUE_FIELDS
        h = hash(getfield(e, f), h)
    end
    return h
end

"""
    BayesModel{S<:AbstractBayesNet, Sp, K}

A Bayesian network with semantics and provenance: the structural `syntax` (an ACSet),
`spaces` (variable name to space object) and `kernels` ([`KernelRef`](@ref) to kernel
object) that give it finite-stochastic semantics, the `evidence` recorded by
[`observe`](@ref) (variable name to state name), the `history` of mechanism rewrites
([`ModelEvent`](@ref)s) and free-form `extras` (metadata such as titles and positions
read from a file; never used by the semantics).

`BayesModel(bn)` builds the spaces from the syntax: every variable with unique name and
at least one state gets the one-axis `FiniteSpace` `FiniteAxis(name, states)`
with the states in `state_position` order, and `kernels` starts empty
(`Dict{KernelRef,FiniteKernel}`). Bind kernels with [`bind_kernel`](@ref) /
[`bind_cpt`](@ref); the keyword form `BayesModel(bn; spaces, kernels, evidence, history,
extras)` accepts arbitrary space and kernel types for alternative semantics.

Models are immutable values: every operation (`observe`, `do_intervention`,
`bind_kernel`, ...) returns a new model and leaves its argument untouched. Two models
are `==` when their syntax, semantics, evidence, history and extras agree; the
wall-clock `time` of a [`ModelEvent`](@ref) is not part of that comparison, so the same
sequence of operations always gives equal models. The
read-only accessors of the structural layer ([`variables`](@ref),
[`variable_names`](@ref), [`states`](@ref), [`parents`](@ref), [`mechanism_of`](@ref),
[`topological_order`](@ref), ...) accept a model and read its syntax.

# Example

```jldoctest
julia> m = BayesModel(reference_habitat_bn());

julia> m2 = do_intervention(observe(m, :Climate => :dry), :Vegetation => :dense);

julia> evidence(m2), intervened_variables(m2)
(Dict(:Climate => :dry), [:Vegetation])

julia> length(history(m)), length(history(m2))
(0, 1)

julia> space(m, :SoilMoisture)
FiniteSpace(SoilMoisture{low,medium,high})
```
"""
struct BayesModel{S<:AbstractBayesNet,Sp,K}
    syntax::S
    spaces::Dict{Symbol,Sp}
    kernels::Dict{KernelRef,K}
    evidence::Dict{Symbol,Symbol}
    history::Vector{ModelEvent}
    extras::Dict{Symbol,Any}
end

function BayesModel(bn::S; spaces::Union{Nothing,AbstractDict{Symbol}}=nothing,
                    kernels::Union{Nothing,AbstractDict{<:KernelRef}}=nothing,
                    evidence::AbstractDict{Symbol,Symbol}=Dict{Symbol,Symbol}(),
                    history::AbstractVector{ModelEvent}=ModelEvent[],
                    extras::AbstractDict{Symbol}=Dict{Symbol,Any}()) where {S<:AbstractBayesNet}
    sp = spaces === nothing ? syntax_spaces(bn) : Dict{Symbol,valtype(spaces)}(spaces)
    ks = kernels === nothing ? Dict{KernelRef,FiniteKernel}() :
         Dict{KernelRef,valtype(kernels)}(kernels)
    return BayesModel{S,valtype(sp),valtype(ks)}(bn, sp, ks, Dict{Symbol,Symbol}(evidence),
                                                 collect(ModelEvent, history),
                                                 Dict{Symbol,Any}(extras))
end

"""
    BayesModel(m::BayesModel; syntax = syntax(m), spaces = spaces(m), kernels = kernels(m),
               evidence = evidence(m), history = history(m), extras = extras(m)) -> BayesModel

A copy of `m` with the given fields replaced. Dictionaries and the history are copied,
so the result never shares mutable state with `m`; the space and kernel types are
those of the dictionaries passed (by default those of `m`). This is how every
operation of the package derives a new model from an old one, and the hook for
wrappers built on top of `BayesModel` to do the same.
"""
function BayesModel(m::BayesModel; syntax=m.syntax, spaces=m.spaces, kernels=m.kernels,
                    evidence=m.evidence, history=m.history, extras=m.extras)
    return BayesModel(syntax; spaces=spaces, kernels=kernels, evidence=evidence,
                      history=history, extras=extras)
end

_with(m::BayesModel; kw...) = BayesModel(m; kw...)

"""
    mechanism_record(bn::AbstractBayesNet, m) -> MechanismRecord

The [`MechanismRecord`](@ref) snapshot of mechanism `m` (id or name): its name, its
`kernel_ref` and the names of its inputs in `input_position` order. Used to fill the
`removed` and `added` fields of a [`ModelEvent`](@ref).
"""
function mechanism_record(bn::AbstractBayesNet, m)
    mid = _mechanism_id(bn, m)
    return MechanismRecord(mechanism_name(bn, mid), kernel_ref(bn, mid),
                           Symbol[variable_name(bn, p) for p in inputs(bn, mid)])
end

function Base.:(==)(a::BayesModel, b::BayesModel)
    return a.syntax == b.syntax && a.spaces == b.spaces && a.kernels == b.kernels &&
           a.evidence == b.evidence && a.history == b.history && a.extras == b.extras
end

function Base.hash(m::BayesModel, h::UInt)
    return hash(m.extras,
                hash(m.history,
                     hash(m.evidence, hash(m.kernels, hash(m.spaces, hash(m.syntax, h))))))
end

"""
    syntax(m::BayesModel) -> AbstractBayesNet

The structural network wrapped by `m`.
"""
syntax(m::BayesModel) = m.syntax

"""
    spaces(m::BayesModel) -> Dict{Symbol, Sp}

The space objects bound to variable names (empty until the semantics layer fills it).
"""
spaces(m::BayesModel) = m.spaces

"""
    kernels(m::BayesModel) -> Dict{KernelRef, K}

The kernel objects bound to [`KernelRef`](@ref)s (empty until the semantics layer fills
it; [`soft_intervention`](@ref) adds entries when given a `kernel`).
"""
kernels(m::BayesModel) = m.kernels

"""
    evidence(m::BayesModel) -> Dict{Symbol, Symbol}

The observed states, variable name to state name. See [`observe`](@ref).
"""
evidence(m::BayesModel) = m.evidence

"""
    history(m::BayesModel) -> Vector{ModelEvent}

The mechanism rewrites applied to `m`, oldest first. See [`ModelEvent`](@ref).
"""
history(m::BayesModel) = m.history

"""
    extras(m::BayesModel) -> Dict{Symbol, Any}

Free-form metadata carried by the model (for example `:name`, `:titles`, `:positions`
and `:comments` filled by [`BayesModel(::NetworkIR)`](@ref)). Never consulted by the
semantics.
"""
extras(m::BayesModel) = m.extras

# Inspection and derived graphs on a model: every read-only accessor of `inspection.jl`
# and `graph.jl` applied to `syntax(m)`.
for f in (:variables, :variable_names, :variable_name, :has_variable, :state_ids,
          :states, :nstates, :space_ref, :mechanisms, :mechanism_names, :mechanism_name,
          :kernel_ref, :target, :input_ids, :inputs, :mechanism_of, :has_mechanism,
          :parents, :children, :exogenous, :roots, :variable_graph, :is_acyclic,
          :topological_order, :moral_graph, :mechanism_record)
    @eval $f(m::BayesModel, args...) = $f(m.syntax, args...)
end

"""
    validate(m::BayesModel; closed = false, unique_names = false, semantics = false, atol = DEFAULT_ATOL) -> Nothing

[`validate`](@ref) the wrapped network, check that every piece of evidence names an
existing variable and one of its states ([`UnknownVariableError`](@ref),
[`UnknownStateError`](@ref)), then check the attached semantics (SPEC section 11,
items 8 to 10): every stored space agrees with the variable's states
([`KernelBindingError`](@ref)), every kernel that a mechanism's reference resolves to has
the variable's space as codomain and the tensor of its parents' spaces as domain
([`KernelBindingError`](@ref)) and is normalised within `atol`
([`UnnormalizedKernelError`](@ref); `DEFAULT_ATOL` is FiniteKernels' `1e-8`, and
models read from files with a looser tolerance should be validated with the same one).
With `semantics = true` every mechanism's reference must resolve
([`MissingKernelError`](@ref)); by default a structural model without kernels is valid.
The first violation is thrown.
"""
function validate(m::BayesModel; closed::Bool=false, unique_names::Bool=false,
                  semantics::Bool=false, atol::Real=DEFAULT_ATOL)
    validate(m.syntax; closed=closed, unique_names=unique_names)
    for (x, s) in m.evidence
        v = variable_id(m.syntax, x)
        s in states(m.syntax, v) || throw(UnknownStateError(x, s))
    end
    errs = semantic_errors(m; semantics=semantics, atol=atol)
    isempty(errs) || throw(first(errs))
    return nothing
end

function Base.show(io::IO, m::BayesModel)
    bn = m.syntax
    print(io, "BayesModel(", nparts(bn, :Variable), " variables, ",
          nparts(bn, :Mechanism), " mechanisms")
    isempty(m.evidence) ||
        print(io, ", evidence on ", join(sort!(collect(keys(m.evidence))), ", "))
    isempty(m.history) || print(io, ", ", length(m.history), " event",
                                length(m.history) == 1 ? "" : "s")
    nk = length(m.kernels)
    nk == 0 || print(io, ", ", nk, " kernel", nk == 1 ? "" : "s")
    return print(io, ")")
end
