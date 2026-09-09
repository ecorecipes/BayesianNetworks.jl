"""
Typed exceptions. Every error carries the offending names and part ids so that messages
can be read without consulting the network.
"""

"""
    BayesNetError

Abstract supertype of every exception thrown by BayesianNetworks.jl.
"""
abstract type BayesNetError <: Exception end

# Structural equality, so that errors with vector fields compare by content in tests.
function Base.:(==)(a::T, b::T) where {T<:BayesNetError}
    return all(getfield(a, f) == getfield(b, f) for f in fieldnames(T))
end

function Base.hash(e::BayesNetError, h::UInt)
    for f in fieldnames(typeof(e))
        h = hash(getfield(e, f), h)
    end
    return hash(typeof(e), h)
end

"""
    UnknownVariableError(name)

Thrown by lookups when no variable is called `name`.
"""
struct UnknownVariableError <: BayesNetError
    name::Symbol
end

"""
    UnknownMechanismError(name)

Thrown by lookups when no mechanism is called `name`.
"""
struct UnknownMechanismError <: BayesNetError
    name::Symbol
end

"""
    CyclicBayesNetError(variables)

The derived variable graph has a cycle. `variables` are the names of the variables that
could not be placed in a topological order (every one of them lies on or downstream of
a cycle); `ids` are their part ids.
"""
struct CyclicBayesNetError <: BayesNetError
    variables::Vector{Symbol}
    ids::Vector{Int}
end

"""
    MissingMechanismError(variable, id)

A closed network has a variable without a generating mechanism.
"""
struct MissingMechanismError <: BayesNetError
    variable::Symbol
    id::Int
end

"""
    DuplicateGeneratorError(variable, id, mechanisms)

More than one mechanism targets the same variable. `mechanisms` are the mechanism ids.
"""
struct DuplicateGeneratorError <: BayesNetError
    variable::Symbol
    id::Int
    mechanisms::Vector{Int}
end

"""
    DanglingReferenceError(part, id, hom, value)

The hom `hom` of part `id` (of object `part`) points at `value`, which is not a valid
part id of its codomain (0 means unset).
"""
struct DanglingReferenceError <: BayesNetError
    part::Symbol
    id::Int
    hom::Symbol
    value::Int
end

"""
    PositionError(part, owner, id, positions)

The positions of the `part`s (`:State` or `:Input`) belonging to `owner` (a variable or
mechanism name with part id `id`) are not a permutation of `1:n`.
"""
struct PositionError <: BayesNetError
    part::Symbol
    owner::Symbol
    id::Int
    positions::Vector{Int}
end

"""
    DuplicateStateError(variable, id, state)

Variable `variable` has more than one state called `state`.
"""
struct DuplicateStateError <: BayesNetError
    variable::Symbol
    id::Int
    state::Symbol
end

"""
    SelfInputError(mechanism, id, variable)

Mechanism `mechanism` lists its own target `variable` among its inputs.
"""
struct SelfInputError <: BayesNetError
    mechanism::Symbol
    id::Int
    variable::Symbol
end

"""
    DuplicateNameError(part, name, ids)

Several parts of object `part` (`:Variable` or `:Mechanism`) share `name`. Only
reported by `validate(bn; unique_names = true)`, because duplicates are legitimate after
tensoring networks.
"""
struct DuplicateNameError <: BayesNetError
    part::Symbol
    name::Symbol
    ids::Vector{Int}
end

"""
    NameClashError(part, name, other, context)

An operation would give two parts of object `part` (`:Variable` or `:Mechanism`) the
same `name`: `other` is the name of the part that is renamed or added (equal to `name`
when nothing is renamed) and `context` says which operation refused. Raised by
`CategoricalBayesianNetworks.glue`, which renames the glued inputs of `B` to the names
they have in `A`, and by `CategoricalBayesianNetworks.substitute`, whose replacement
network must not carry hidden variables or mechanisms already present in the containing
network.
"""
struct NameClashError <: BayesNetError
    part::Symbol
    name::Symbol
    other::Symbol
    context::String
end

"""
    InterfaceError(rule, variables, ids)

An open network violates rule `rule` (1 to 5) of the typed-interface rule (SPEC §13,
revision note); `variables` and `ids` are the offending variables (names and part ids,
in the apex for rules 1, 3 and 4, in the foot for rules 2 and 5). The rules:

1. every input-foot variable has no mechanism in the apex;
2. the input leg is injective on `Variable`;
3. every mechanism-free apex variable is in the image of the input leg;
4. the derived variable graph is acyclic (reported as [`CyclicBayesNetError`](@ref));
5. both legs are natural transformations that preserve names, references and the
   states with their positions.
"""
struct InterfaceError <: BayesNetError
    rule::Int
    variables::Vector{Symbol}
    ids::Vector{Int}
end

const INTERFACE_RULES = ("every input-foot variable has no mechanism in the apex",
                         "the input leg is injective on Variable",
                         "every mechanism-free apex variable is an input",
                         "the derived variable graph is acyclic",
                         "the legs are natural and preserve names, references, states and positions")

"""
    InterfaceMismatchError(what, position, left, right, context)

Two interfaces that must agree do not. `what` names the first difference found
(`:length`, `:variable_name`, `:states`, `:space_ref`, `:missing_input`,
`:missing_output`, `:duplicate` or `:missing_junction`), `position` is the index (in the
interface, in the `along` list, or the junction) where it was found, `left` and `right` are the differing values on the two
sides, and `context` says which operation compared them.
"""
struct InterfaceMismatchError <: BayesNetError
    what::Symbol
    position::Int
    left::Any
    right::Any
    context::String
end

"""
    UnknownStateError(variable, state)

Variable `variable` has no state called `state` (raised by `observe`, `do_intervention`
and friends).
"""
struct UnknownStateError <: BayesNetError
    variable::Symbol
    state::Symbol
end

"""
    NoEvidenceError(variable)

`unobserve` was asked to remove evidence on `variable`, which carries none.
"""
struct NoEvidenceError <: BayesNetError
    variable::Symbol
end

"""
    FormatError(message)

A serialised network could not be parsed: wrong envelope, format name or schema version.
"""
struct FormatError <: BayesNetError
    message::String
end

function Base.showerror(io::IO, e::UnknownVariableError)
    return print(io, "UnknownVariableError: no variable named :", e.name)
end

function Base.showerror(io::IO, e::UnknownMechanismError)
    return print(io, "UnknownMechanismError: no mechanism named :", e.name)
end

function Base.showerror(io::IO, e::CyclicBayesNetError)
    return print(io, "CyclicBayesNetError: the variable graph is not acyclic; variables ",
                 "involved in or downstream of a cycle: ", join(e.variables, ", "),
                 " (ids ", join(e.ids, ", "), ")")
end

function Base.showerror(io::IO, e::MissingMechanismError)
    return print(io, "MissingMechanismError: variable :", e.variable, " (id ", e.id,
                 ") has no generating mechanism")
end

function Base.showerror(io::IO, e::DuplicateGeneratorError)
    return print(io, "DuplicateGeneratorError: variable :", e.variable, " (id ", e.id,
                 ") is the target of ", length(e.mechanisms), " mechanisms (ids ",
                 join(e.mechanisms, ", "), ")")
end

function Base.showerror(io::IO, e::DanglingReferenceError)
    return print(io, "DanglingReferenceError: ", e.part, " ", e.id, " has ", e.hom, " = ",
                 e.value, ", which is not a valid part")
end

function Base.showerror(io::IO, e::PositionError)
    return print(io, "PositionError: ", e.part, " positions of :", e.owner, " (id ", e.id,
                 ") are ", e.positions, "; expected a permutation of 1:",
                 length(e.positions))
end

function Base.showerror(io::IO, e::DuplicateStateError)
    return print(io, "DuplicateStateError: variable :", e.variable, " (id ", e.id,
                 ") has more than one state named :", e.state)
end

function Base.showerror(io::IO, e::SelfInputError)
    return print(io, "SelfInputError: mechanism :", e.mechanism, " (id ", e.id,
                 ") lists its own target :", e.variable, " as an input")
end

function Base.showerror(io::IO, e::DuplicateNameError)
    return print(io, "DuplicateNameError: ", length(e.ids), " ", e.part, " parts named :",
                 e.name, " (ids ", join(e.ids, ", "), ")")
end

function Base.showerror(io::IO, e::NameClashError)
    print(io, "NameClashError: ", e.context, ": ")
    e.name == e.other && return print(io, e.part, " :", e.name, " is already taken")
    return print(io, "renaming ", e.part, " :", e.other, " to :", e.name,
                 " would clash with the ", e.part, " already named :", e.name)
end

"""
    WiringDiagramError(what, box, port, message)

A wiring diagram is outside the round-trip subset of `from_wiring_diagram`, or an
expression cannot be built from it. `what` names the problem (`:box`, `:box_value`,
`:outputs`, `:port_value`, `:port_mismatch`, `:wires`, `:inputs` or `:cycle`), `box`
and `port` locate it (Catlab's `input_id` / `output_id` for the outer ports, 0 when not
applicable) and `message` explains it.

Thrown by `CategoricalBayesianNetworks.jl`, which owns the wiring-diagram view; the type
stays here so that the whole `BayesNetError` hierarchy has one root (ADR 0009).
"""
struct WiringDiagramError <: BayesNetError
    what::Symbol
    box::Int
    port::Int
    message::String
end

Base.showerror(io::IO, e::FormatError) = print(io, "FormatError: ", e.message)

function Base.showerror(io::IO, e::InterfaceError)
    return print(io, "InterfaceError: rule ", e.rule, " (", INTERFACE_RULES[e.rule],
                 ") is violated by variable(s) ", join(e.variables, ", "), " (ids ",
                 join(e.ids, ", "), ")")
end

function Base.showerror(io::IO, e::InterfaceMismatchError)
    # `:missing_junction` reports a junction, not two interfaces that differ.
    e.what === :missing_junction && return print(io, "InterfaceMismatchError: ", e.context)
    return print(io, "InterfaceMismatchError: ", e.context, ": interfaces differ in ",
                 e.what, " at position ", e.position, "; left has ", repr(e.left),
                 ", right has ", repr(e.right))
end

function Base.showerror(io::IO, e::UnknownStateError)
    return print(io, "UnknownStateError: variable :", e.variable, " has no state named :",
                 e.state)
end

function Base.showerror(io::IO, e::NoEvidenceError)
    return print(io, "NoEvidenceError: no evidence is recorded on variable :", e.variable)
end

# Semantic errors (SPEC section 11, items 8 to 10, and the evaluation layer)
##########################################################################

"""
    MissingKernelError(variable, ref)

The mechanism generating `variable` carries the reference `ref`, which does not resolve
to a kernel of the model: a [`NoRef`](@ref), or a [`NamedRef`](@ref) / [`PolicyRef`](@ref)
without an entry in `kernels(m)`.
"""
struct MissingKernelError <: BayesNetError
    variable::Symbol
    ref::KernelRef
end

"""
    KernelBindingError(variable, what, expected, got)

A kernel or space bound to `variable` does not fit its mechanism. `what` is `:codom`
(the kernel's codomain is not the variable's space), `:dom` (its domain is not the tensor
of the parents' spaces in `input_position` order), `:table` (a CPT array has the wrong
size; `expected` and `got` are sizes) or `:space` (a stored space differs from the
variable's states in the syntax); `expected` and `got` are the two values compared.
"""
struct KernelBindingError <: BayesNetError
    variable::Symbol
    what::Symbol
    expected::Any
    got::Any
end

"""
    UnnormalizedKernelError(variable, max_deviation)

The kernel bound to the mechanism of `variable` is not normalised over its output axis:
some column sums to `1 + max_deviation` (in absolute value) beyond the tolerance.
"""
struct UnnormalizedKernelError <: BayesNetError
    variable::Symbol
    max_deviation::Float64
end

"""
    ProofCertificateError(what, part, id, name, message)

[`proof_certificate`](@ref) cannot represent the supplied model without changing
its data. `what` identifies the unsupported or invalid value, `part` and `id`
locate the source record, and `name` is its label when available (`nothing` for
model-wide options). `message` explains the failure. Ordinary structural,
binding and evidence violations retain their existing exception types.
"""
struct ProofCertificateError <: BayesNetError
    what::Symbol
    part::Symbol
    id::Int
    name::Union{Nothing,Symbol}
    message::String
end

"""
    OpenCertificateError(what, path, name, message)

A raw open-network certificate cannot represent its input without changing
data or exceeding its versioned profile. `what` identifies the failure,
`path` locates the record or option, and `name` is the offending variable or
mechanism when available. Ordinary structural violations retain their
existing exception types.

Thrown by `CategoricalBayesianNetworks.export_open_certificate` and
`export_open_operation_certificate`; the plain data exception stays here with
the `BayesNetError` hierarchy and introduces no categorical dependency.
"""
struct OpenCertificateError <: BayesNetError
    what::Symbol
    path::String
    name::Union{Nothing,Symbol}
    message::String
end

"""
    ImpossibleEvidenceError(evidence)

The recorded evidence has probability zero under the model, so conditioning on it is
undefined.
"""
struct ImpossibleEvidenceError <: BayesNetError
    evidence::Dict{Symbol,Symbol}
end

"""
    ModelTooLargeError(nstates, limit)

A brute-force evaluation was asked for a model with `nstates` joint states, more than
the `limit` allowed (raise it with the `max_states` keyword if you really want to
enumerate).
"""
struct ModelTooLargeError <: BayesNetError
    nstates::Int
    limit::Int
end

"""
    UnsupportedNodeKindError(id, kind)

A `NetworkIR` node of kind `kind` (`"decision"` or `"utility"`) cannot be turned into a
Bayesian-network variable; influence diagrams are handled by InfluenceDiagrams.jl.
"""
struct UnsupportedNodeKindError <: BayesNetError
    id::Symbol
    kind::String
end

function Base.showerror(io::IO, e::MissingKernelError)
    return print(io, "MissingKernelError: the mechanism of variable :", e.variable,
                 " has reference ", e.ref, ", which does not resolve to a kernel")
end

function Base.showerror(io::IO, e::KernelBindingError)
    return print(io, "KernelBindingError: variable :", e.variable, ": ", e.what,
                 " mismatch; expected ", e.expected, ", got ", e.got)
end

function Base.showerror(io::IO, e::UnnormalizedKernelError)
    return print(io, "UnnormalizedKernelError: the kernel of variable :", e.variable,
                 " is not normalised (maximum deviation from 1 is ", e.max_deviation, ")")
end

function Base.showerror(io::IO, e::ProofCertificateError)
    print(io, "ProofCertificateError (", e.what, "): ", e.part)
    e.id == 0 || print(io, " ", e.id)
    e.name === nothing || print(io, " :", e.name)
    return print(io, ": ", e.message)
end

function Base.showerror(io::IO, e::OpenCertificateError)
    print(io, "OpenCertificateError (", e.what, ") at ", e.path)
    e.name === nothing || print(io, " (", repr(e.name), ")")
    return print(io, ": ", e.message)
end

function Base.showerror(io::IO, e::ImpossibleEvidenceError)
    return print(io, "ImpossibleEvidenceError: the evidence ", e.evidence,
                 " has probability zero under the model")
end

function Base.showerror(io::IO, e::ModelTooLargeError)
    return print(io, "ModelTooLargeError: the model has ", e.nstates,
                 " joint states, more than the limit of ", e.limit,
                 " for brute-force evaluation (pass max_states to raise it)")
end

function Base.showerror(io::IO, e::UnsupportedNodeKindError)
    return print(io, "UnsupportedNodeKindError: node :", e.id, " is a ", e.kind,
                 " node; only chance nodes can be Bayesian-network variables. ",
                 "Use InfluenceDiagrams.jl for decision and utility nodes")
end

"""
    DynamicTemplateError(what, variable, message)

A [`DynamicBayesNet`](@ref) template is ill-formed. `what` names the check
(`:missing_mechanism`, `:lagged_mechanism`, `:unknown_base`, `:lag`, `:states`,
`:space_ref` or `:initial_variables`), `variable` the offending template variable and
`message` explains the problem. See [`validation_errors(::DynamicBayesNet)`](@ref).
"""
struct DynamicTemplateError <: BayesNetError
    what::Symbol
    variable::Symbol
    message::String
end

"""
    HorizonError(horizon, minimum, lags)

[`unroll`](@ref) (or [`transition_slice`](@ref)) was asked for a horizon smaller than
the `minimum` allowed by a template with `lags` lags (`lags - 1` for `unroll`, `lags`
for `transition_slice`).
"""
struct HorizonError <: BayesNetError
    horizon::Int
    minimum::Int
    lags::Int
end

"""
    NotUnrolledError(operation, variable = nothing)

`operation` (for example `rollout`) was applied to a model that [`unroll`](@ref) did not
produce, so there is no horizon to iterate over: the `X_t` naming convention alone is not
evidence that a network is an unrolled dynamic one, since an ordinary model may have a
variable called `A_1`. `variable` is the template variable the call asked for, when the
operation names one.
"""
struct NotUnrolledError <: BayesNetError
    operation::Symbol
    variable::Union{Symbol,Nothing}
end

NotUnrolledError(operation::Symbol) = NotUnrolledError(operation, nothing)

function Base.showerror(io::IO, e::NotUnrolledError)
    print(io, "NotUnrolledError: ", e.operation)
    e.variable === nothing || print(io, "(:", e.variable, ")")
    return print(io, " needs a model produced by `unroll`; this one records no ",
                 "unrolling in its extras (unroll a DynamicBayesModel, or ask for a ",
                 "named slice with `filter_marginal`)")
end

function Base.showerror(io::IO, e::DynamicTemplateError)
    return print(io, "DynamicTemplateError (", e.what, "): variable :", e.variable, ": ",
                 e.message)
end

function Base.showerror(io::IO, e::HorizonError)
    return print(io, "HorizonError: horizon ", e.horizon, " is smaller than the minimum ",
                 e.minimum, " for a template with ", e.lags, " lag",
                 e.lags == 1 ? "" : "s")
end

function Base.showerror(io::IO, e::WiringDiagramError)
    return print(io, "WiringDiagramError (", e.what, ", box ", e.box, ", port ", e.port,
                 "): ",
                 e.message)
end
