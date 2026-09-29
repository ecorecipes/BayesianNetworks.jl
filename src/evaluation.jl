"""
Reference evaluation of closed models (SPEC §14, §18): brute-force joint distributions,
marginals and conditionals, and ancestral sampling. Everything here enumerates joint
states and is an oracle for small models, not a scalable backend.

The categorical route to the same numbers (`to_free_expression`, `categorical_joint`)
and the semantics of an open network (`interpret`) live in
`CategoricalBayesianNetworks.jl`, which needs Catlab; the helpers they share with this
file (`_factors`, `_product`, `_joint_atol`, `DEFAULT_MAX_STATES`) stay here.
"""

const DEFAULT_MAX_STATES = 1_000_000

# Preconditions shared by the brute-force evaluators: a closed, uniquely named model
# whose every mechanism resolves and is normalised within `atol`, with at most
# `max_states` joint states. Returns the variable ids in topological order.
function _closed_semantics(m::BayesModel, max_states::Integer, atol::Real=DEFAULT_ATOL)
    validate(m; closed=true, unique_names=true, semantics=true, atol=atol)
    bn = m.syntax
    order = topological_order(bn)
    n = prod(Int128[nstates(bn, v) for v in order]; init=Int128(1))
    n <= max_states || throw(ModelTooLargeError(Int(min(n, typemax(Int))), max_states))
    return order
end

# `_Factor(table, axes, strides)`: one mechanism's kernel table flattened for the
# brute-force evaluators. `table` is the kernel's entries in column-major order (target
# axis first, then the inputs in `input_position` order), `axes[j]` is the position of
# the `j`-th axis among the enumerated variables and `strides[j]` its stride in `table`.
# Concrete field types keep `_product` type stable, which an `Array{Float64}` of unknown
# rank does not.
struct _Factor
    table::Vector{Float64}
    axes::Vector{Int}
    strides::Vector{Int}
end

function _Factor(table::AbstractArray, axes::Vector{Int})
    st = Vector{Int}(undef, length(axes))
    acc = 1
    for j in eachindex(axes)
        st[j] = acc
        acc *= size(table, j)
    end
    return _Factor(vec(convert(Array{Float64}, table)), axes, st)
end

# The factors of a product of mechanisms: for each mechanism the kernel table
# (outputs-first) and the positions, in `pos`, of its target and then its inputs.
function _factors(bn::AbstractBayesNet, lookup, pos::AbstractDict{Int,Int};
                  atol::Real=DEFAULT_ATOL)
    out = _Factor[]
    for mech in mechanisms(bn)
        k = _resolve_kernel(bn, mech, lookup)
        k === nothing &&
            throw(MissingKernelError(variable_name(bn, target(bn, mech)),
                                     kernel_ref(bn, mech)))
        _check_kernel(bn, mech, k; atol=atol)
        axes = Int[pos[target(bn, mech)]; Int[pos[p] for p in inputs(bn, mech)]]
        push!(out, _Factor(k.table, axes))
    end
    return out
end

# For nonnegative kernels, row-mass deviations compound multiplicatively.
# log1p/expm1 retain the higher-order terms even for small validation tolerances.
function _joint_atol(atol::Real, n::Integer)
    isfinite(atol) && atol >= 0 ||
        throw(ArgumentError("atol must be finite and nonnegative, got $atol"))
    n >= 0 || throw(ArgumentError("the number of kernels must be nonnegative, got $n"))
    return max(atol, expm1(n * log1p(atol)))
end

# The product of every factor's entry at the joint assignment `ci`, stopping at the
# first zero.
@inline function _product(factors::Vector{_Factor}, ci::CartesianIndex)
    p = 1.0
    for f in factors
        idx = 1
        @inbounds for j in eachindex(f.axes)
            idx += f.strides[j] * (ci[f.axes[j]] - 1)
        end
        p *= @inbounds f.table[idx]
        p == 0 && break
    end
    return p
end

# Joint distributions
#####################

"""
    joint_distribution(m::BayesModel; variables = topological order, max_states = 1_000_000, atol = DEFAULT_ATOL) -> FiniteKernel

The joint distribution of a closed model as a state `I → ⊗ variables`, by brute force:
every assignment of all variables is enumerated and its probability is the product of
the mechanisms' kernels (SPEC §14) -- the chain-rule factorisation of a Bayesian network
[KollerFriedman2009](@cite). The output axes follow `variables`, which must be a
permutation of all variable names (use [`marginal`](@ref) for a subset); evidence is
ignored (it is applied by [`marginal`](@ref) and [`conditional`](@ref)). Requires a
closed, uniquely named model with every kernel bound
([`validate`](@ref validate(::BayesModel)) with `closed = true, unique_names = true,
semantics = true`) and at most `max_states` joint states
([`ModelTooLargeError`](@ref)).

`atol` is the normalisation tolerance of that validation and of the per-mechanism kernel
check, and is forwarded by every evaluator that goes through this one
([`marginal`](@ref marginal(::BayesModel, ::AbstractVector{Symbol})),
[`conditional`](@ref), [`joint_table`](@ref)). A model read from a file with rounded
probabilities (`read_bayesnet` uses `1e-6`) must be evaluated with the same tolerance it
was read with, exactly as [`validate`](@ref validate(::BayesModel)) requires
([`UnnormalizedKernelError`](@ref) otherwise).

# Example

```jldoctest
julia> m = reference_habitat_model();

julia> J = joint_distribution(m);

julia> names(J.codom)
7-element Vector{Symbol}:
 :Climate
 :Irrigation
 :SoilMoisture
 :GrazingPressure
 :Vegetation
 :HabitatQuality
 :Occupancy

julia> sum(J.table) ≈ 1
true
```
"""
function joint_distribution(m::BayesModel; variables=nothing,
                            max_states::Integer=DEFAULT_MAX_STATES,
                            atol::Real=DEFAULT_ATOL)
    order = _closed_semantics(m, max_states, atol)
    bn = m.syntax
    ids = variables === nothing ? order : Int[variable_id(bn, x) for x in variables]
    sort(ids) == sort(order) ||
        throw(ArgumentError("variables must be a permutation of all variable names; use marginal for a subset"))
    pos = Dict{Int,Int}(v => i for (i, v) in enumerate(ids))
    dims = Tuple(nstates(bn, v) for v in ids)
    factors = _factors(bn, m.kernels, pos; atol=atol)
    T = zeros(Float64, dims)
    for ci in CartesianIndices(dims)
        T[ci] = _product(factors, ci)
    end
    # Validation tolerance compounds once per mechanism, not once per boundary port.
    return FiniteKernel(FiniteSpace(), FiniteSpace(FiniteAxis[axis(bn, v) for v in ids]),
                        T; atol=_joint_atol(atol, length(factors)))
end

"""
    JointTable(variables, states, table)

A joint distribution as a named-axis array: `table` has one axis per entry of
`variables` (state names in `states`) and sums to one. Index it with
`jt[:X => :x, :Y => :y, ...]` (one pair per variable, any order). Built by
[`joint_table`](@ref).
"""
struct JointTable
    variables::Vector{Symbol}
    states::Vector{Vector{Symbol}}
    table::Array{Float64}
end

function JointTable(k::FiniteKernel)
    isempty(k.dom) || throw(SpaceMismatchError(:JointTable, FiniteSpace(), k.dom))
    return JointTable(names(k.codom), labels(k.codom), convert(Array{Float64}, k.table))
end

"""
    joint_table(m::BayesModel; kwargs...) -> JointTable

[`joint_distribution`](@ref) as a [`JointTable`](@ref) (same keyword arguments).
"""
joint_table(m::BayesModel; kw...) = JointTable(joint_distribution(m; kw...))

function Base.getindex(jt::JointTable, assignment::Pair{Symbol,Symbol}...)
    length(assignment) == length(jt.variables) ||
        throw(ArgumentError("expected one state per variable ($(jt.variables)), got $(collect(assignment))"))
    idx = Vector{Int}(undef, length(jt.variables))
    for (x, s) in assignment
        i = findfirst(==(x), jt.variables)
        i === nothing && throw(UnknownVariableError(x))
        j = findfirst(==(s), jt.states[i])
        j === nothing && throw(UnknownStateError(x, s))
        idx[i] = j
    end
    return jt.table[idx...]
end

function Base.show(io::IO, jt::JointTable)
    return print(io, "JointTable(", join(jt.variables, " ⊗ "), "; ", length(jt.table),
                 " entries)")
end

# Conditioning and marginals
############################

_evidence_dict(ev::AbstractDict{Symbol,Symbol}) = Dict{Symbol,Symbol}(ev)
_evidence_dict(ev::AbstractVector{<:Pair{Symbol,Symbol}}) = Dict{Symbol,Symbol}(ev)
_evidence_dict(ev::Pair{Symbol,Symbol}) = Dict{Symbol,Symbol}(ev)

# Evidence mass (ADR 0014). A binary64 total is trusted only when it is a normal positive
# number. Zero, a subnormal, a negative or a non-finite total does not say whether the
# evidence is impossible -- a positive probability that underflowed is zero too -- so the
# evaluators recompute such a case in the log domain (`_log_joint_marginal`), where only an
# exact zero gives `-Inf` and so an `ImpossibleEvidenceError`.
_reliable_mass(t::Real) = isfinite(t) && t >= floatmin(Float64)

# Condition a state `I -> X1 ⊗ ... ⊗ Xn` on evidence over its axes and renormalise.
# Returns `nothing` when the conditioned total is not a trustworthy binary64 number, so the
# caller can fall back to the log domain. A joint with negative cells comes from tolerated
# entries in [-atol, 0) (ADR 0007); its posterior is indeterminate when the evidence mass is
# within the tolerance budget of zero, or when a posterior cell comes out negative.
function _condition(J::FiniteKernel, ev::Dict{Symbol,Symbol}, atol::Real)
    isempty(ev) && return J
    T = copy(convert(Array{Float64}, J.table))
    axes = factors(J.codom)
    for (x, s) in ev
        i = findfirst(a -> a.name == x, axes)
        i === nothing && throw(UnknownVariableError(x))
        j = findfirst(==(s), axes[i].labels)
        j === nothing && throw(UnknownStateError(x, s))
        for ci in CartesianIndices(T)
            ci[i] == j || (T[ci] = 0.0)
        end
    end
    total = sum(T)
    _reliable_mass(total) || return nothing
    if any(<(0), J.table)
        budget = _joint_atol(atol, ndims(J.table))
        total > budget ||
            throw(IndeterminatePosteriorError(ev,
                                              "the evidence mass $(total) is within the tolerance budget $(budget) of zero"))
        v = minimum(T)
        v < 0 &&
            throw(IndeterminatePosteriorError(ev,
                                              "a posterior cell is negative ($(v / total))"))
    end
    # Dividing by the total normalises exactly, whatever the joint's own tolerance was.
    return FiniteKernel(FiniteSpace(), J.codom, T ./ total)
end

# The log of one joint entry, the product of every mechanism's entry at the joint assignment
# `ci`. An exact zero gives `-Inf`. This is reached only when the binary64 mass was not
# trustworthy, i.e. far below any tolerance budget, so a tolerated negative entry on a
# configuration consistent with the evidence makes the posterior indeterminate.
function _log_product(factors::Vector{_Factor}, ci::CartesianIndex, ev)
    l = 0.0
    for f in factors
        idx = 1
        @inbounds for j in eachindex(f.axes)
            idx += f.strides[j] * (ci[f.axes[j]] - 1)
        end
        x = @inbounds f.table[idx]
        x < 0 &&
            throw(IndeterminatePosteriorError(ev,
                                              "a tolerated negative entry ($(x)) lies on a configuration consistent with evidence whose mass is below binary64's normal range"))
        x == 0 && return -Inf
        l += log(x)
    end
    return l
end

# `log P(vars = cell, evidence)` for every cell of `vars`, and `log P(evidence)`, by
# enumerating the joint in the log domain with a streaming log-sum-exp per cell. The
# fallback of `marginal` and `conditional` when the binary64 mass is not trustworthy.
function _log_joint_marginal(m::BayesModel, vars::AbstractVector{Symbol},
                             ev::Dict{Symbol,Symbol}; max_states::Integer, atol::Real)
    order = _closed_semantics(m, max_states, atol)
    bn = m.syntax
    pos = Dict{Int,Int}(v => i for (i, v) in enumerate(order))
    dims = Tuple(nstates(bn, v) for v in order)
    fs = _factors(bn, m.kernels, pos; atol=atol)
    fixed = Pair{Int,Int}[]
    for (x, s) in ev
        has_variable(bn, x) || throw(UnknownVariableError(x))
        v = variable_id(bn, x)
        j = findfirst(==(s), states(bn, v))
        j === nothing && throw(UnknownStateError(x, s))
        push!(fixed, pos[v] => j)
    end
    qpos = Int[]
    for x in vars
        has_variable(bn, x) || throw(UnknownVariableError(x))
        push!(qpos, pos[variable_id(bn, x)])
    end
    qdims = Tuple(dims[p] for p in qpos)
    mx = fill(-Inf, qdims)
    acc = zeros(Float64, qdims)
    for ci in CartesianIndices(dims)
        all(ci[p] == j for (p, j) in fixed) || continue
        l = _log_product(fs, ci, ev)
        l == -Inf && continue
        q = CartesianIndex(ntuple(k -> ci[qpos[k]], length(qpos)))
        if l > mx[q]
            acc[q] = acc[q] * exp(mx[q] - l) + 1.0
            mx[q] = l
        else
            acc[q] += exp(l - mx[q])
        end
    end
    logtable = mx .+ log.(acc)
    top = isempty(logtable) ? -Inf : maximum(logtable)
    logtotal = top == -Inf ? -Inf : top + log(sum(exp.(logtable .- top)))
    return logtable, logtotal
end

function _log_marginal(m::BayesModel, vars::AbstractVector{Symbol}, ev::Dict{Symbol,Symbol};
                       max_states::Integer, atol::Real)
    logtable, logtotal = _log_joint_marginal(m, vars, ev; max_states, atol)
    logtotal == -Inf && throw(ImpossibleEvidenceError(ev))
    bn = m.syntax
    Y = FiniteSpace(FiniteAxis[axis(bn, variable_id(bn, x)) for x in vars])
    return FiniteKernel(FiniteSpace(), Y, exp.(logtable .- logtotal); atol=atol)
end

function _axis_positions(X::FiniteSpace, vars)
    out = Int[]
    for x in vars
        i = findfirst(a -> a.name == x, factors(X))
        i === nothing && throw(UnknownVariableError(x))
        push!(out, i)
    end
    return out
end

"""
    marginal(m::BayesModel, vars; evidence = evidence(m), max_states = 1_000_000, atol = DEFAULT_ATOL) -> FiniteKernel
    marginal(m::BayesModel, :X; kwargs...)

The posterior marginal `P(vars | evidence)` as a state `I → ⊗ vars` (axes in the order
of `vars`), by brute force: the joint of the model is conditioned on the evidence (the
model's own by default; pass `evidence = Dict()` for the prior marginal, or any
dictionary or list of `:X => :x` pairs), renormalised and summed over the other
variables. Interventions are already in the syntax, so
`marginal(do_intervention(m, :Y => :y), [:X])` is the interventional distribution.

Evidence so improbable that its binary64 mass underflows (or is subnormal) is not treated
as impossible: the conditioned marginal is recomputed by enumerating the joint in the log
domain, and returned (ADR 0014). [`ImpossibleEvidenceError`](@ref) means the evidence has
probability exactly zero under the model. A model with tolerated entries in `[-atol, 0)`
raises [`IndeterminatePosteriorError`](@ref) when the evidence mass is within the
tolerance budget of zero or a posterior cell comes out negative.

# Example

```jldoctest
julia> m = reference_habitat_model();

julia> round.(marginal(m, [:Occupancy]).table; digits = 4)
2-element Vector{Float64}:
 0.5238
 0.4762

julia> round.(marginal(observe(m, :Vegetation => :dense), :Occupancy).table; digits = 4)
2-element Vector{Float64}:
 0.3325
 0.6675
```
"""
function marginal(m::BayesModel, vars::AbstractVector{Symbol}; evidence=m.evidence,
                  max_states::Integer=DEFAULT_MAX_STATES, atol::Real=DEFAULT_ATOL)
    ev = _evidence_dict(evidence)
    J = _condition(joint_distribution(m; max_states=max_states, atol=atol), ev, atol)
    J === nothing && return _log_marginal(m, vars, ev; max_states, atol)
    return marginal(J, _axis_positions(J.codom, vars))
end
marginal(m::BayesModel, x::Symbol; kw...) = marginal(m, [x]; kw...)

"""
    conditional(m::BayesModel, target, given; evidence = evidence(m), on_zero = :uniform, max_states = 1_000_000, atol = DEFAULT_ATOL) -> FiniteKernel

The conditional distribution `P(target | given, evidence)` as a kernel
`⊗ given → ⊗ target` (`target` and `given` are variable names or lists of names), by
brute force from the conditioned joint. Extracting such a kernel from a joint state is
disintegration in the sense of [ChoJacobs2019](@cite).

For a configuration of `given` that has probability zero the conditional is undefined. "Zero"
means exactly zero: a column whose binary64 mass underflows is recomputed in the log domain
and normalised, never filled in (ADR 0014),
and `on_zero` says what to do with that column: `:uniform` (the default, kept for
backwards compatibility) fills it with the uniform distribution so that the result is a
normalised kernel, `:error` throws an [`ImpossibleEvidenceError`](@ref) naming that
configuration of the `given` variables, and `:nan` fills it with `NaN` so that the undefined entries are
visible downstream (the result is then not normalised). Anything else is an
`ArgumentError`.

# Example

```jldoctest
julia> m = reference_habitat_model();

julia> k = conditional(m, :Occupancy, :HabitatQuality);

julia> probability(k, :present, :good)
0.75
```
"""
function conditional(m::BayesModel, target, given; evidence=m.evidence,
                     on_zero::Symbol=:uniform, max_states::Integer=DEFAULT_MAX_STATES,
                     atol::Real=DEFAULT_ATOL)
    on_zero in (:uniform, :error, :nan) ||
        throw(ArgumentError("on_zero must be :uniform, :error or :nan, got :$on_zero"))
    ts = target isa Symbol ? [target] : collect(Symbol, target)
    gs = given isa Symbol ? [given] : collect(Symbol, given)
    isempty(intersect(ts, gs)) ||
        throw(ArgumentError("target and given variables overlap: $(intersect(ts, gs))"))
    M = marginal(m, vcat(ts, gs); evidence=evidence, max_states=max_states, atol=atol)
    T = convert(Array{Float64}, M.table)
    nt = length(ts)
    tdims = ntuple(identity, nt)
    denom = sum(T; dims=tdims)
    # A column whose binary64 mass is zero or subnormal may be positive but underflowed.
    # Recompute every column in the log domain, where only an exact zero is -Inf, so that
    # `on_zero` applies to configurations of probability exactly zero and nothing else.
    if any(d -> !_reliable_mass(d), denom)
        logT, _ = _log_joint_marginal(m, vcat(ts, gs), _evidence_dict(evidence);
                                      max_states, atol)
        top = maximum(logT; dims=tdims)
        logd = top .+ log.(sum(exp.(logT .- ifelse.(isinf.(top), 0.0, top)); dims=tdims))
        T = exp.(logT .- ifelse.(isinf.(logd), 0.0, logd))
        denom = ifelse.(isinf.(logd), 0.0, 1.0)
    end
    ntarget = prod(size(T)[1:nt])
    undefined = on_zero === :uniform ? 1 / ntarget : NaN
    out = similar(T)
    for ci in CartesianIndices(T)
        d = denom[CartesianIndex(ntuple(i -> i <= nt ? 1 : ci[i], ndims(T)))]
        d > 0 || on_zero !== :error ||
            throw(ImpossibleEvidenceError(Dict{Symbol,Symbol}(gs[i - nt] =>
                                                                  labels(factors(M.codom)[i])[ci[i]]
                                                              for i in (nt + 1):ndims(T))))
        out[ci] = d > 0 ? T[ci] / d : undefined
    end
    X = FiniteSpace(factors(M.codom)[(nt + 1):end])
    Y = FiniteSpace(factors(M.codom)[1:nt])
    return FiniteKernel(X, Y, out; check=on_zero !== :nan)
end

# Ancestral sampling
####################

function _draw(rng::AbstractRNG, probs::AbstractVector)
    u = rand(rng)
    acc = 0.0
    for (i, p) in enumerate(probs)
        acc += p
        u < acc && return i
    end
    return length(probs)
end

"""
    sample(m::BayesModel, n; rng = Random.default_rng(), atol = DEFAULT_ATOL) -> Vector{Dict{Symbol,Symbol}}

`n` ancestral samples of a closed model (SPEC §18): variables are drawn in topological
order, each from its mechanism's kernel given the sampled parents (forward or ancestral
sampling, [KollerFriedman2009](@cite)). Interventions are
part of the syntax and therefore respected; evidence is ignored (this is a sample of the
prior or interventional distribution, not the posterior).
"""
function sample(m::BayesModel, n::Integer; rng::AbstractRNG=default_rng(),
                atol::Real=DEFAULT_ATOL)
    validate(m; closed=true, unique_names=true, semantics=true, atol=atol)
    bn = m.syntax
    order = topological_order(bn)
    nv = nparts(bn, :Variable)
    names_ = Symbol[variable_name(bn, v) for v in 1:nv]
    labels_ = Vector{Vector{Symbol}}(undef, nv)
    tables = Vector{Array{Float64}}(undef, nv)
    parent_ids = Vector{Vector{Int}}(undef, nv)
    for v in order
        labels_[v] = states(bn, v)
        tables[v] = convert(Array{Float64}, kernel(m, names_[v]).table)
        parent_ids[v] = parents(bn, v)
    end
    out = Vector{Dict{Symbol,Symbol}}(undef, n)
    idx = zeros(Int, nv)
    for i in 1:n
        for v in order
            col = view(tables[v], :, (idx[p] for p in parent_ids[v])...)
            idx[v] = _draw(rng, col)
        end
        out[i] = Dict{Symbol,Symbol}(names_[v] => labels_[v][idx[v]] for v in order)
    end
    return out
end

"""
    empirical_marginal(samples, :X) -> Dict{Symbol, Float64}
    empirical_marginal(samples, :X, X::FiniteSpace) -> FiniteKernel

Relative frequencies of the states of `X` in `samples` (as returned by
[`sample`](@ref)): a dictionary, or, given the variable's space, a state `I → X` with the
frequencies in state order, comparable to [`marginal`](@ref).
"""
function empirical_marginal(samples::AbstractVector{<:AbstractDict{Symbol,Symbol}},
                            x::Symbol)
    counts = Dict{Symbol,Int}()
    for s in samples
        haskey(s, x) || throw(UnknownVariableError(x))
        counts[s[x]] = get(counts, s[x], 0) + 1
    end
    n = length(samples)
    return Dict{Symbol,Float64}(k => c / n for (k, c) in counts)
end

function empirical_marginal(samples::AbstractVector{<:AbstractDict{Symbol,Symbol}},
                            x::Symbol, X::FiniteSpace)
    freq = empirical_marginal(samples, x)
    a = only(factors(X))
    return state(X, Float64[get(freq, l, 0.0) for l in a.labels])
end
