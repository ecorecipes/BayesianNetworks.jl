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
    n = prod(BigInt[nstates(bn, v) for v in order]; init=big(1))
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

# The kernels of a product of mechanisms, in mechanism order: for each mechanism its
# resolved and checked kernel as bound, and the positions, in `pos`, of its target and then
# its inputs.
function _mechanism_kernels(bn::AbstractBayesNet, lookup, pos::AbstractDict{Int,Int};
                            atol::Real=DEFAULT_ATOL)
    out = Tuple{FiniteKernel,Vector{Int}}[]
    for mech in mechanisms(bn)
        k = _resolve_kernel(bn, mech, lookup)
        k === nothing &&
            throw(MissingKernelError(variable_name(bn, target(bn, mech)),
                                     kernel_ref(bn, mech)))
        _check_kernel(bn, mech, k; atol=atol)
        axes = Int[pos[target(bn, mech)]; Int[pos[p] for p in inputs(bn, mech)]]
        push!(out, (k, axes))
    end
    return out
end

# The factors of a product of mechanisms: for each mechanism the kernel table
# (outputs-first) and the positions, in `pos`, of its target and then its inputs.
function _factors(bn::AbstractBayesNet, lookup, pos::AbstractDict{Int,Int};
                  atol::Real=DEFAULT_ATOL)
    return _Factor[_Factor(k.table, axes)
                   for (k, axes) in _mechanism_kernels(bn, lookup, pos; atol=atol)]
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

# Trust (ADR 0014, ADR 0016). `marginal` and `conditional` answer first in binary64 (the
# binary64 run). A binary64 run is untrusted if its final mass is not a normal positive
# number, or if any product it computed from operands that are all nonzero has magnitude
# below `floatmin` of its element type, whether that product came out subnormal or rounded
# all the way to 0.0. A product with an exactly zero operand is a structural zero and does
# not count. An operand that is already below `floatmin` has already marked the run
# untrusted: a subnormal entry, or a nonzero entry of a kernel bound in another number type
# whose Float64 value is zero or subnormal. The check does not depend on mechanism order.
# An untrusted run decides nothing -- a positive probability that underflowed is zero too --
# so the evaluator recomputes exactly (`_exact_cells`), where only an exact zero is zero,
# and rounds each cell once. A trusted run whose configurations are all structural zeros has
# a mass of exactly zero, and needs no exact run. The rule costs a comparison per product.
_reliable_mass(t::Real) = isfinite(t) && t >= floatmin(Float64)

# Tolerated entries (ADR 0007, ADR 0011; ADR 0014 decision 4, ADR 0016 decision 4). A
# validated model may hold entries in [-atol, 0). Such an entry takes part in a posterior when
# it lies on a configuration consistent with the evidence whose entries are all nonzero: an
# entry multiplied by an exact zero contributes nothing. When one takes part, the posterior
# is indeterminate if the evidence mass is not larger than the budget `_joint_atol(atol, n)`
# (`n` mechanisms) or a cell of the queried posterior is negative. The cells of the joint
# that the query sums out do not count. The binary64 run and the exact run decide by the same
# rule, the exact run on exact values. The exact run is reached through a mass below
# binary64's normal range, far below any budget, so there an entry that takes part makes the
# posterior indeterminate (ADR 0016's rule), or through a product below `floatmin` on the
# way. A prior marginal (no evidence) is exempt: it is the model's own law, tolerance
# included. Nothing is clamped or renormalised.

# A brute-force query (SPEC §14): the variables of a closed model in topological order, the
# kernel of each mechanism as bound and as a `_Factor`, and the positions among the variables
# of the evidence (position => state index) and of the query variables.
struct _Query{B<:AbstractBayesNet}
    bn::B
    order::Vector{Int}
    dims::Vector{Int}
    kernels::Vector{FiniteKernel}
    factors::Vector{_Factor}
    fixed::Vector{Pair{Int,Int}}
    qpos::Vector{Int}
end

function _query(m::BayesModel, vars::AbstractVector{Symbol}, ev::Dict{Symbol,Symbol},
                max_states::Integer, atol::Real)
    order = _closed_semantics(m, max_states, atol)
    bn = m.syntax
    pos = Dict{Int,Int}(v => i for (i, v) in enumerate(order))
    ks = _mechanism_kernels(bn, m.kernels, pos; atol=atol)
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
    allunique(qpos) || throw(ArgumentError("the query variables $(vars) repeat"))
    return _Query(bn, order, Int[nstates(bn, v) for v in order],
                  FiniteKernel[k for (k, _) in ks],
                  _Factor[_Factor(k.table, axes) for (k, axes) in ks], fixed, qpos)
end

# The space of the variables at positions `ps`.
function _positions_space(q::_Query, ps)
    return FiniteSpace(FiniteAxis[axis(q.bn, q.order[p]) for p in ps])
end

# The configurations of all the variables that are consistent with the evidence.
function _consistent(q::_Query)
    r = UnitRange{Int}[1:d for d in q.dims]
    for (p, j) in q.fixed
        r[p] = j:j
    end
    return CartesianIndices(Tuple(r))
end

# The binary64 run over the configurations consistent with the evidence: the probability of
# each in `T` (the other cells are zero), the product of the mechanisms' entries in mechanism
# order exactly as `_product` and `joint_distribution` form it. `trusted` says that no
# product or operand fell below `floatmin` (the mass is checked apart); `nonzero` that a
# configuration has no exactly zero entry; `negative` marks the configurations where a
# tolerated negative entry takes part, and is `nothing` when no entry is negative.
struct _Run
    T::Array{Float64}
    total::Float64
    trusted::Bool
    nonzero::Bool
    negative::Union{Nothing,BitArray}
end

# One product of the run, and whether it or an operand has magnitude below `floatmin` while
# no operand is zero (`small`), whether an operand is negative (`negative`) and whether one is
# exactly zero (`zero`). A structural zero reports neither of the first two, whatever the
# mechanism order. Where nothing falls below `floatmin`, the value is `_product`'s, bit for
# bit; `_product` stops at a zero product, so this one goes on to find an exact zero.
@inline function _checked_product(factors::Vector{_Factor}, ci::CartesianIndex)
    p, small, negative = 1.0, false, false
    for f in factors
        idx = 1
        @inbounds for j in eachindex(f.axes)
            idx += f.strides[j] * (ci[f.axes[j]] - 1)
        end
        x = @inbounds f.table[idx]
        x == 0 && return p * x, false, false, true
        negative |= x < 0
        p *= x
        small |= !(abs(x) >= floatmin(Float64)) | !(abs(p) >= floatmin(Float64))
    end
    return p, small, negative, false
end

# Whether a nonzero entry of a kernel bound in another number type has no normal Float64
# value, so that the binary64 run would use a zero or subnormal operand in its place.
_lossy(::FiniteKernel{Float64}) = false
function _lossy(k::FiniteKernel)
    return any(x -> !iszero(x) && !(abs(Float64(x)) >= floatmin(Float64)), k.table)
end

function _binary64_run(q::_Query)
    T = zeros(Float64, Tuple(q.dims))
    negative = any(f -> any(<(0), f.table), q.factors) ? falses(size(T)) : nothing
    small, nonzero = _run!(T, negative, q.factors, _consistent(q))
    return _Run(T, sum(T), !small && !any(_lossy, q.kernels), nonzero, negative)
end

function _run!(T, negative, factors, configurations)
    small, nonzero = false, false
    for ci in configurations
        p, s, neg, zero = _checked_product(factors, ci)
        T[ci] = p
        zero && continue
        nonzero = true
        small |= s
        neg && (negative[ci] = true)
    end
    return small, nonzero
end

# The binary64 posterior of the query variables, as FiniteKernels' `marginal` of the joint
# gives it: normalised by the evidence mass, or the raw sums of the joint for a prior. It is
# `nothing` when the run is not trusted.
function _binary64_posterior(q::_Query, run::_Run, normalise::Bool)
    (run.trusted && _reliable_mass(run.total)) || return nothing
    T = normalise ? run.T ./ run.total : run.T
    J = FiniteKernel{Float64,ndims(T)}(FiniteSpace(),
                                       _positions_space(q, eachindex(q.order)),
                                       T; check=false)
    return marginal(J, q.qpos)
end

# For each cell of the query variables, whether `B` holds at a configuration in it.
function _cells_any(B::AbstractArray{Bool}, keep::Vector{Int})
    drop = Tuple(setdiff(1:ndims(B), keep))
    t = isempty(drop) ? B : dropdims(any(B; dims=drop); dims=drop)
    return permutedims(t, Tuple(invperm(sortperm(keep))))
end

_takes_part(negative) = negative !== nothing && any(negative)

function _indeterminate_mass(ev, mass, budget)
    return throw(IndeterminatePosteriorError(ev,
                                             "the evidence mass $(mass) is within the tolerance budget $(budget) of zero"))
end

function _indeterminate_cell(ev, v)
    return throw(IndeterminatePosteriorError(ev, "a posterior cell is negative ($(v))"))
end

# The exact value of a bound entry (ADR 0016): `(n, p, d)` with value `n * 2^p / d`, where
# `d` is a positive odd integer and `n` is odd or zero. A Float64 is its `_dyadic` value, a
# BigFloat its exact dyadic value, and a rational or an integer itself, never a Float64
# rounding of it. Zero is `(0, 0, 1)`, whatever exponent `_dyadic` gives it (`-1074`), so that
# a zero entry does not lower the common power of two of the exact run.
function _odd(n::BigInt, p::Int, d::BigInt=big(1))
    iszero(n) && return big(0), 0, big(1)
    k = trailing_zeros(n)
    return n >> k, p + k, d
end
_exact_entry(x::Float64) = _odd(_dyadic(x)...)
function _exact_entry(x::BigFloat)
    n, p, s = Base.decompose(x)
    return _odd(BigInt(n) * s, Int(p))
end
_exact_entry(x::Union{Float16,Float32}) = _exact_entry(Float64(x))
_exact_entry(x::Integer) = _odd(BigInt(x), 0)
function _exact_entry(x::Rational)
    d = BigInt(denominator(x))
    k = trailing_zeros(d)
    return _odd(BigInt(numerator(x)), -k, d >> k)
end
_exact_entry(x::Real) = _exact_entry(Rational{BigInt}(x))

# The exact run (ADR 0016): `P(query = cell, evidence)` for every cell of the query
# variables, as integers that all carry the factor `2^floor / denominator`, so that they add
# without rounding, and for each cell whether a tolerated negative entry takes part in it
# (`nothing` when no entry is negative).
struct _ExactCells
    cells::Array{BigInt}
    negative::Union{Nothing,Array{Bool}}
    floor::Int
    denominator::BigInt
end

function _exact_cells(q::_Query)
    tables = Vector{Vector{Tuple{BigInt,Int}}}(undef, length(q.kernels))
    floor, denominator, negative = 0, big(1), false
    for (i, k) in enumerate(q.kernels)
        entries = [_exact_entry(x) for x in vec(k.table)]
        d = foldl(lcm, (e for (_, _, e) in entries); init=big(1))
        tables[i] = [(n * div(d, e), p) for (n, p, e) in entries]
        # The least power of two of a nonzero entry: every shift below is nonnegative.
        floor += minimum((p for (n, p, _) in entries if !iszero(n)); init=0)
        denominator *= d
        negative |= any(e -> e[1] < 0, entries)
    end
    qdims = Tuple(q.dims[p] for p in q.qpos)
    cells = fill(big(0), qdims)
    flags = negative ? fill(false, qdims) : nothing
    _exact_run!(cells, flags, tables, q, _consistent(q), floor)
    return _ExactCells(cells, flags, floor, denominator)
end

function _exact_run!(cells, flags, tables, q::_Query, configurations, floor::Int)
    strides = Vector{Int}(undef, length(q.qpos))
    acc = 1
    for k in eachindex(q.qpos)
        strides[k] = acc
        acc *= q.dims[q.qpos[k]]
    end
    for ci in configurations
        n, p, negative = _exact_product(tables, q.factors, ci)
        iszero(n) && continue
        c = 1
        for k in eachindex(q.qpos)
            c += strides[k] * (ci[q.qpos[k]] - 1)
        end
        cells[c] += n << (p - floor)
        negative && (flags[c] = true)
    end
    return nothing
end

# One configuration's product in the exact run, `(n, p)` with value `n * 2^p` over the
# common denominator, and whether an entry is negative. An exactly zero entry gives
# `(0, 0, false)` whatever the mechanism order: a structural zero, in which no entry takes
# part.
function _exact_product(tables, factors::Vector{_Factor}, ci::CartesianIndex)
    n, p, negative = big(1), 0, false
    for (t, f) in zip(tables, factors)
        idx = 1
        @inbounds for j in eachindex(f.axes)
            idx += f.strides[j] * (ci[f.axes[j]] - 1)
        end
        a, e = @inbounds t[idx]
        iszero(a) && return big(0), 0, false
        negative |= a < 0
        n *= a
        p += e
    end
    return n, p, negative
end

# The value of an integer `c` of the exact run (a cell or a sum of cells).
function _exact_value(x::_ExactCells, c::BigInt)
    return x.floor >= 0 ? (c << x.floor) // x.denominator :
           c // (x.denominator << -x.floor)
end

# The tolerance rule on the exact run, for the posterior under `ev` whose mass is the integer
# `mass` of `x` and whose unnormalised cells are `cells`.
function _exact_tolerance(ev, x::_ExactCells, mass::BigInt, cells, atol::Real, n::Integer)
    budget = _joint_atol(atol, n)
    value = _exact_value(x, mass)
    if !(value > Rational{BigInt}(budget))
        value < Rational{BigInt}(floatmin(Float64)) &&
            throw(IndeterminatePosteriorError(ev,
                                              "a tolerated negative entry lies on a configuration consistent with evidence whose mass is below binary64's normal range"))
        _indeterminate_mass(ev, _nearest_binary64(value), budget)
    end
    v = minimum(cells; init=big(0))
    v < 0 && _indeterminate_cell(ev, _nearest_binary64(v, mass))
    return nothing
end

function _exact_marginal(q::_Query, ev::Dict{Symbol,Symbol}, prior::Bool, atol::Real)
    x = _exact_cells(q)
    total = sum(x.cells; init=big(0))
    !prior && _takes_part(x.negative) &&
        _exact_tolerance(ev, x, total, x.cells, atol, length(q.factors))
    iszero(total) && throw(ImpossibleEvidenceError(ev))
    # Each cell is the Float64 nearest the exact posterior of the model as bound; a prior is
    # the raw sum of the joint, as in the binary64 run.
    table = prior ? map(c -> _nearest_binary64(_exact_value(x, c)), x.cells) :
            map(c -> _nearest_binary64(c, total), x.cells)
    return FiniteKernel(FiniteSpace(), _positions_space(q, q.qpos), table; check=false)
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
A query variable that repeats is an `ArgumentError`.

The posterior is computed in binary64 first. A binary64 run is untrusted if its final
mass is not a normal positive number, or if any product it computed from operands that
are all nonzero has magnitude below `floatmin` of its element type, whether that product
came out subnormal or rounded all the way to 0.0. A product with an exactly zero operand
does not count. An untrusted run is recomputed by enumerating the joint in exact arithmetic
on the values as bound (a rational or `BigFloat` kernel at its exact value), and each
returned cell is the Float64 nearest the exact posterior of the model as bound (ADR 0014,
ADR 0016). So evidence whose binary64 mass underflows is answered, not treated as
impossible, and so is a cell whose products underflow on the way.
[`ImpossibleEvidenceError`](@ref) means the evidence has probability exactly zero under the
model.

A model may hold tolerated entries in `[-atol, 0)`. When such an entry lies on a
configuration consistent with the evidence whose other entries are all nonzero, and the
evidence mass is within the tolerance budget `(1 + atol)^n - 1` of zero (`n` mechanisms)
or a cell of the returned posterior comes out negative, [`IndeterminatePosteriorError`](@ref)
is raised. A negative entry that the evidence rules out, and negative cells of the joint
that the query sums out, do not count. The prior marginal (empty evidence) is the model's
own law and is returned as computed.

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
    q = _query(m, vars, ev, max_states, atol)
    run = _binary64_run(q)
    run.trusted && !run.nonzero && throw(ImpossibleEvidenceError(ev))
    prior = isempty(ev)
    P = _binary64_posterior(q, run, !prior)
    P === nothing && return _exact_marginal(q, ev, prior, atol)
    if !prior && _takes_part(run.negative)
        budget = _joint_atol(atol, length(q.factors))
        run.total > budget || _indeterminate_mass(ev, run.total, budget)
        v = minimum(P.table; init=0.0)
        v < 0 && _indeterminate_cell(ev, v)
    end
    return P
end
marginal(m::BayesModel, x::Symbol; kw...) = marginal(m, [x]; kw...)

# The evidence of the column `g` of a conditional: `ev` and the configuration of `given`.
function _column_evidence(q::_Query, ev::Dict{Symbol,Symbol}, gs, g::CartesianIndex,
                          nt::Int)
    out = copy(ev)
    for (i, x) in enumerate(gs)
        out[x] = states(q.bn, q.order[q.qpos[nt + i]])[g[nt + i]]
    end
    return out
end

# The cells of the column of the query cells at `g` (a cell of the column sums).
function _column(A, g::CartesianIndex, nt::Int)
    return view(A, ntuple(_ -> Colon(), nt)...,
                Tuple(g)[(nt + 1):end]...)
end

# The binary64 conditional: the posterior of (target, given) divided column by column, and
# whether each column of `given` has probability exactly zero; `nothing` when the run, or the
# mass of a column that is not a structural zero, is not trusted.
function _binary64_columns(q::_Query, run::_Run, nt::Int, ev, gs, atol::Real)
    normalise = !isempty(ev)
    P = _binary64_posterior(q, run, normalise)
    P === nothing && return nothing
    T = P.table
    tdims = ntuple(identity, nt)
    denom = sum(T; dims=tdims)
    # In a trusted run, a product is zero exactly when an operand is, so a column is a
    # structural zero when all its products are zero. With no negative entry that is a zero
    # column sum; otherwise a sum can cancel to zero, and the products are looked at.
    zero = run.negative === nothing ? denom .== 0 :
           .!any(_cells_any(run.T .!= 0, q.qpos); dims=tdims)
    all(g -> zero[g] || _reliable_mass(denom[g]), eachindex(denom)) || return nothing
    out = similar(T)
    for ci in CartesianIndices(T)
        g = CartesianIndex(ntuple(i -> i <= nt ? 1 : ci[i], ndims(T)))
        out[ci] = zero[g] ? 0.0 : T[ci] / denom[g]
    end
    if !(isempty(ev) && isempty(gs)) && run.negative !== nothing
        takes_part = any(_cells_any(run.negative, q.qpos); dims=tdims)
        budget = _joint_atol(atol, length(q.factors))
        for g in CartesianIndices(denom)
            takes_part[g] || continue
            column_ev = _column_evidence(q, ev, gs, g, nt)
            mass = normalise ? denom[g] * run.total : denom[g]
            mass > budget || _indeterminate_mass(column_ev, mass, budget)
            v = minimum(_column(out, g, nt); init=0.0)
            v < 0 && _indeterminate_cell(column_ev, v)
        end
    end
    return out, zero
end

# The exact conditional (ADR 0016): every column recomputed exactly, each cell the Float64
# nearest its exact conditional, and whether each column has probability exactly zero.
function _exact_columns(q::_Query, nt::Int, ev, gs, atol::Real)
    x = _exact_cells(q)
    tdims = ntuple(identity, nt)
    D = sum(x.cells; dims=tdims)
    if !(isempty(ev) && isempty(gs)) && x.negative !== nothing
        takes_part = any(x.negative; dims=tdims)
        for g in CartesianIndices(D)
            takes_part[g] || continue
            _exact_tolerance(_column_evidence(q, ev, gs, g, nt), x, D[g],
                             _column(x.cells, g, nt), atol, length(q.factors))
        end
    end
    iszero(sum(D; init=big(0))) && throw(ImpossibleEvidenceError(ev))
    out = similar(x.cells, Float64)
    for ci in CartesianIndices(x.cells)
        d = D[CartesianIndex(ntuple(i -> i <= nt ? 1 : ci[i], ndims(x.cells)))]
        out[ci] = iszero(d) ? 0.0 : _nearest_binary64(x.cells[ci], d)
    end
    return out, map(iszero, D)
end

"""
    conditional(m::BayesModel, target, given; evidence = evidence(m), on_zero = :uniform, max_states = 1_000_000, atol = DEFAULT_ATOL) -> FiniteKernel

The conditional distribution `P(target | given, evidence)` as a kernel
`⊗ given → ⊗ target` (`target` and `given` are variable names or lists of names), by
brute force from the conditioned joint. Extracting such a kernel from a joint state is
disintegration in the sense of [ChoJacobs2019](@cite). Each column, one configuration of
`given`, is the posterior given that configuration and the evidence, and is held to the
rules of [`marginal`](@ref marginal(::BayesModel, ::AbstractVector{Symbol})) with that
column's mass: a binary64 run is untrusted if its final mass is not a normal positive
number, or if any product it computed from operands that are all nonzero has magnitude
below `floatmin` of its element type, whether that product came out subnormal or rounded
all the way to 0.0. When any column is untrusted, every column is recomputed exactly and
each cell is the Float64 nearest its exact conditional (ADR 0014, ADR 0016). A column with
a tolerated entry in `[-atol, 0)` that takes part in it raises
[`IndeterminatePosteriorError`](@ref), naming the evidence and the configuration of `given`,
when its mass is within the tolerance budget of zero or one of its cells comes out
negative; with no evidence and no `given` variables the result is the prior, which is
exempt, as in [`marginal`](@ref marginal(::BayesModel, ::AbstractVector{Symbol})). The kernel
is checked at `atol`.

For a configuration of `given` that has probability zero the conditional is undefined.
"Zero" means exactly zero: every configuration of the variables in that column has an
entry that is exactly zero, or the exact recomputation gives zero; a column whose binary64
mass underflows is recomputed, never filled in. `on_zero` says what to do with such a
column: `:uniform` (the default, kept for backwards compatibility) fills it with the
uniform distribution so that the result is a normalised kernel, `:error` throws an
[`ImpossibleEvidenceError`](@ref) naming that configuration of the `given` variables, and
`:nan` fills it with `NaN` so that the undefined entries are visible downstream (the result
is then not normalised). Anything else is an `ArgumentError`. Evidence of probability
exactly zero raises [`ImpossibleEvidenceError`](@ref) whatever `on_zero` is.

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
    ev = _evidence_dict(evidence)
    q = _query(m, vcat(ts, gs), ev, max_states, atol)
    nt = length(ts)
    run = _binary64_run(q)
    run.trusted && !run.nonzero && throw(ImpossibleEvidenceError(ev))
    columns = _binary64_columns(q, run, nt, ev, gs, atol)
    T, zero = columns === nothing ? _exact_columns(q, nt, ev, gs, atol) : columns
    X = _positions_space(q, q.qpos[(nt + 1):end])
    Y = _positions_space(q, q.qpos[1:nt])
    ntarget = prod(size(T)[1:nt]; init=1)
    undefined = on_zero === :uniform ? 1 / ntarget : NaN
    out = similar(T)
    for ci in CartesianIndices(T)
        if zero[CartesianIndex(ntuple(i -> i <= nt ? 1 : ci[i], ndims(T)))]
            on_zero === :error &&
                throw(ImpossibleEvidenceError(Dict{Symbol,Symbol}(gs[i - nt] => labels(factors(X)[i - nt])[ci[i]]
                                                                  for i in
                                                                      (nt + 1):ndims(T))))
            out[ci] = undefined
        else
            out[ci] = T[ci]
        end
    end
    return FiniteKernel(X, Y, out; check=on_zero !== :nan, atol=atol)
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
