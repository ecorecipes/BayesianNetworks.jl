"""
Observation and intervention (SPEC §21, §22). Observation records evidence in the
`BayesModel` wrapper and leaves the syntax untouched; interventions are local mechanism
rewrites of the ACSet (delete one `Mechanism` row with its `Input`s, add one) recorded
in the model's history. The plain ACSet methods, on any `AbstractBayesNet`, perform the
edit alone.

The distinction the module implements is Pearl's between conditioning and the `do`
operator [Pearl2009](@cite); the rewrite that realises it is the "string diagram
surgery" of [JacobsKissingerZanasi2019](@cite), presented for general causal models in
string diagrams by [LorenzTull2023](@cite).
"""

"""
    hard_intervention_name(variable, state) -> Symbol

The mechanism name used by [`do_intervention`](@ref): `Symbol("do[X=x]")`.
"""
hard_intervention_name(x::Symbol, s::Symbol) = Symbol("do[", x, "=", s, "]")

function _parent_names(bn::AbstractBayesNet, v)
    return Symbol[variable_name(bn, p) for p in parents(bn, v)]
end

function _check_state(bn::AbstractBayesNet, x::Symbol, s::Symbol)
    v = variable_id(bn, x)
    s in states(bn, v) || throw(UnknownStateError(x, s))
    return v
end

# Observation
#############

"""
    observe(m::BayesModel, :X => :x) -> BayesModel
    observe(m::BayesModel, [:X => :x, :Y => :y]) -> BayesModel

Record the evidence `X = x` (conditioning, SPEC §21.1). The syntax is unchanged: the
mechanism generating `X` stays in place; the evidence acts on the semantics, as the
restriction of the joint distribution that string-diagram conditioning describes
[ChoJacobs2019](@cite). Throws [`UnknownVariableError`](@ref) or
[`UnknownStateError`](@ref) if the variable or the state does not exist. Observing a
variable again replaces its evidence.

Evidence survives [`do_intervention`](@ref) and [`soft_intervention`](@ref), which
rewrite the syntax only; an observation of the variable that is then intervened on
contradicts the intervention and makes the next query throw an
[`ImpossibleEvidenceError`](@ref), so remove it with [`unobserve`](@ref) first.
"""
function observe(m::BayesModel, ev::Pair{Symbol,Symbol})
    x, s = ev
    _check_state(syntax(m), x, s)
    e = copy(evidence(m))
    e[x] = s
    return _with(m; evidence=e)
end

function observe(m::BayesModel, evs::AbstractVector{<:Pair{Symbol,Symbol}})
    return foldl(observe, evs; init=m)
end

"""
    unobserve(m::BayesModel, :X) -> BayesModel
    unobserve(m::BayesModel) -> BayesModel

Remove the evidence on `X` (throws [`NoEvidenceError`](@ref) if there is none), or all
evidence.
"""
function unobserve(m::BayesModel, x::Symbol)
    haskey(evidence(m), x) || throw(NoEvidenceError(x))
    e = copy(evidence(m))
    delete!(e, x)
    return _with(m; evidence=e)
end

unobserve(m::BayesModel) = _with(m; evidence=Dict{Symbol,Symbol}())

# Hard interventions
####################

"""
    do_intervention(bn::AbstractBayesNet, :X => :x) -> typeof(bn)
    do_intervention(m::BayesModel, :X => :x; note = "") -> BayesModel
    do_intervention(m, [:X => :x, :Y => :y])

The hard intervention `do(X = x)` (SPEC §21.2, §22) as a local rewrite: on a copy, the
mechanism generating `X` is removed together with its `Input` rows
(`cascading_rem_part!`) and a mechanism named [`hard_intervention_name`](@ref)`(X, x)`
with no inputs and kernel reference `PointMassRef(x)` is added. Every other mechanism
and all inputs of downstream mechanisms are untouched. An exogenous `X` simply gains
the constant mechanism. Throws [`UnknownStateError`](@ref) if `x` is not a state of
`X`.

Semantically this is Pearl's truncated factorisation [Pearl2009](@cite): the joint
distribution of the rewritten network is the product of the original conditional
probability tables with the factor for `X` replaced by the point mass at `x`. As a
diagram edit it is exactly the "cut" of [JacobsKissingerZanasi2019](@cite), whose
string-diagram surgery deletes the incoming wires of `X` and plugs in a state; see also
[LorenzTull2023](@cite).

The network may be any [`AbstractBayesNet`](@ref) (an ACSet whose schema extends
`SchBayesNet`, for example an influence diagram): the result has the same type and
keeps every part of the other objects of its schema.

On a [`BayesModel`](@ref) the rewrite is recorded as a `:hard` [`ModelEvent`](@ref)
whose `removed` record is the old mechanism (or `nothing`) and whose `added` record is
the constant mechanism.

!!! warning "Evidence is kept, including evidence on the intervened variable"
    Evidence recorded by [`observe`](@ref) is carried over unchanged, so
    `do_intervention(observe(m, :X => :a), :X => :b)` keeps the observation `X = a`
    beside the intervention `do(X = b)`. The two contradict each other -- after the
    rewrite `X` is `b` with probability one -- and the contradiction surfaces at the
    next query as an [`ImpossibleEvidenceError`](@ref), not here. Drop the observation
    first with [`unobserve`](@ref)`(m, :X)` when the intervention is meant to replace
    it; keeping it is only meaningful when the observed state is the state intervened
    on.
"""
function do_intervention(bn::AbstractBayesNet, iv::Pair{Symbol,Symbol})
    x, s = iv
    v = _check_state(bn, x, s)
    out = deepcopy(bn)
    m = mechanism_of(out, v)
    m === nothing || cascading_rem_part!(out, :Mechanism, m)
    add_part!(out, :Mechanism; target=v, mechanism_name=hard_intervention_name(x, s),
              kernel_ref=PointMassRef(s))
    return out
end

function do_intervention(bn::AbstractBayesNet, ivs::AbstractVector{<:Pair{Symbol,Symbol}})
    return foldl(do_intervention, ivs; init=bn)
end

function do_intervention(m::BayesModel, iv::Pair{Symbol,Symbol}; note::AbstractString="")
    x, s = iv
    bn = syntax(m)
    v = _check_state(bn, x, s)
    old = mechanism_of(bn, v)
    removed = old === nothing ? nothing : mechanism_record(bn, old)
    added = MechanismRecord(hard_intervention_name(x, s), PointMassRef(s), Symbol[])
    ev = ModelEvent(:hard, x, removed, added; note=note)
    return _with(m; syntax=do_intervention(bn, iv), history=vcat(history(m), [ev]))
end

function do_intervention(m::BayesModel, ivs::AbstractVector{<:Pair{Symbol,Symbol}}; kw...)
    return foldl((acc, iv) -> do_intervention(acc, iv; kw...), ivs; init=m)
end

# Soft interventions
####################

"""
    soft_intervention(bn::AbstractBayesNet, :X => ref::KernelRef; parents = parents of X, name = Symbol("soft[X]")) -> typeof(bn)
    soft_intervention(m::BayesModel, :X => ref; parents, name, kernel = nothing, note = "", atol = DEFAULT_ATOL) -> BayesModel
    soft_intervention(m, [:X => ref1, :Y => ref2]; ...)

The soft intervention replacing the mechanism of `X` by a new one with kernel reference
`ref` and the given `parents` (variable names, in order; by default the current
parents, so the intervention may keep a subset of them, SPEC §21.3). The old mechanism
and its inputs are removed on a copy, the new mechanism is added, and the result is
validated (acyclicity included). An exogenous `X` simply gains the mechanism. As for
[`do_intervention`](@ref), the network may be any [`AbstractBayesNet`](@ref) and the
result has the same type.

On a [`BayesModel`](@ref) the rewrite is recorded as a `:soft` [`ModelEvent`](@ref);
if a `kernel` object is given it is stored under `kernels(m)[ref]` (a `FiniteKernel` is
checked against the new mechanism first, with normalisation within `atol`). See also
the method taking a kernel directly, `soft_intervention(m, :X => k::FiniteKernel)`,
which assigns a fresh reference.
"""
function soft_intervention(bn::AbstractBayesNet, iv::Pair{Symbol,<:KernelRef};
                           parents::Union{Nothing,AbstractVector{Symbol}}=nothing,
                           name::Symbol=Symbol("soft[", first(iv), "]"))
    x, ref = iv
    v = variable_id(bn, x)
    ps = parents === nothing ? _parent_names(bn, v) : collect(Symbol, parents)
    out = deepcopy(bn)
    m = mechanism_of(out, v)
    m === nothing || cascading_rem_part!(out, :Mechanism, m)
    add_mechanism!(out, v; inputs=ps, name=name, kernel_ref=ref)
    validate(out)
    return out
end

function soft_intervention(m::BayesModel, iv::Pair{Symbol,<:KernelRef};
                           parents::Union{Nothing,AbstractVector{Symbol}}=nothing,
                           name::Symbol=Symbol("soft[", first(iv), "]"), kernel=nothing,
                           note::AbstractString="", atol::Real=DEFAULT_ATOL)
    x, ref = iv
    bn = syntax(m)
    v = variable_id(bn, x)
    ps = parents === nothing ? _parent_names(bn, v) : collect(Symbol, parents)
    old = mechanism_of(bn, v)
    removed = old === nothing ? nothing : mechanism_record(bn, old)
    added = MechanismRecord(name, ref, ps)
    ev = ModelEvent(:soft, x, removed, added; note=note)
    syn = soft_intervention(bn, iv; parents=ps, name=name)
    ks = copy(kernels(m))
    if kernel !== nothing
        kernel isa FiniteKernel &&
            _check_kernel(syn, mechanism_of(syn, v), kernel; atol=atol)
        ks[ref] = kernel
    end
    return _with(m; syntax=syn, kernels=ks, history=vcat(history(m), [ev]))
end

function soft_intervention(m::BayesModel, ivs::AbstractVector{<:Pair{Symbol,<:KernelRef}};
                           kw...)
    return foldl((acc, iv) -> soft_intervention(acc, iv; kw...), ivs; init=m)
end

# Provenance
############

"""
    intervened_variables(m::BayesModel) -> Vector{Symbol}

The variables whose mechanism was replaced by a hard or soft intervention, in order of
first intervention. Details are in [`history`](@ref).
"""
function intervened_variables(m::BayesModel)
    return unique!([e.target for e in history(m) if e.kind in (:hard, :soft)])
end

"""
    is_intervened(m::BayesModel, :X) -> Bool

Whether `X` is among [`intervened_variables`](@ref).
"""
is_intervened(m::BayesModel, x::Symbol) = x in intervened_variables(m)
