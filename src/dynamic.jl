"""
Dynamic Bayesian networks (SPEC §43) as time-indexed templates that unroll into ordinary
networks. A [`DynamicBayesNet`](@ref) holds an initial network and a transition template,
both plain [`BayesNet`](@ref)s; lags are expressed by the variable-naming convention
[`lagged`](@ref) (`X[t-1]`, `X[t-2]`, ...) and never by new schema objects. Finite
horizons are compiled by [`unroll`](@ref) into a closed `BayesNet` (or `BayesModel`)
whose variables are named `X_t` ([`variable_at`](@ref)), so every structural,
semantic and inference facility of the package applies unchanged. Unrolled models are
large and repetitive, so exact queries on them are best left to variable elimination,
whose categorical form is the marginalisation of [LorenzinZanasi2025](@cite); the
brute-force evaluators here enumerate the full joint instead.

Boundary convention. With maximal lag `L` the transition template describes slices
`t >= L`, whose lagged parents `X[t-k]` (`1 <= k <= L`) all exist. The initial network
describes the first `L` slices `0, ..., L-1` jointly, using the same lag notation
relative to slice `L-1`: its variable `X[t-k]` is slice `L-1-k`, so for `L = 1` (the
common case) the initial network is simply a closed network over the template's variable
names, and for `L = 2` it names `X` (slice 1) and `X[t-1]` (slice 0). Unrolling is
therefore exact for every slice: no lagged parent is ever dropped or invented, and
`unroll` requires `horizon >= L - 1`.
"""

# Naming conventions
####################

const _LAG_PATTERN = r"^(.+)\[t-(\d+)\]$"
const _TIME_PATTERN = r"^(.+)_(\d+)$"

"""
    lagged(name::Symbol, k::Integer) -> Symbol

The name of variable `name` lagged by `k` slices in a transition template:
`Symbol(name, "[t-", k, "]")` for `k >= 1` and `name` itself for `k == 0`.

```jldoctest
julia> lagged(:Vegetation, 1), lagged(:Vegetation, 0)
(Symbol("Vegetation[t-1]"), :Vegetation)
```
"""
function lagged(name::Symbol, k::Integer)
    k >= 0 || throw(ArgumentError("lag must be non-negative, got $k"))
    return k == 0 ? name : Symbol(name, "[t-", k, "]")
end

"""
    lag_of(name::Symbol) -> (base::Symbol, k::Int)

Split a template variable name into its base name and lag: `lag_of(Symbol("X[t-2]"))`
is `(:X, 2)` and `lag_of(:X)` is `(:X, 0)`.
"""
function lag_of(name::Symbol)
    m = match(_LAG_PATTERN, String(name))
    m === nothing && return (name, 0)
    return (Symbol(m.captures[1]), parse(Int, m.captures[2]))
end

"""
    is_lagged(name::Symbol) -> Bool

Whether `name` follows the [`lagged`](@ref) convention with a positive lag.
"""
is_lagged(name::Symbol) = last(lag_of(name)) > 0

"""
    variable_at(name::Symbol, t::Integer) -> Symbol

The name of template variable `name` in slice `t` of an unrolled network:
`Symbol(name, "_", t)`.

```jldoctest
julia> variable_at(:Vegetation, 3)
:Vegetation_3
```
"""
function variable_at(name::Symbol, t::Integer)
    t >= 0 || throw(ArgumentError("slice index must be non-negative, got $t"))
    return Symbol(name, "_", t)
end

"""
    time_index(name::Symbol) -> (base::Symbol, t::Int)

Invert [`variable_at`](@ref): the template name and slice of an unrolled variable
(`time_index(:Vegetation_3) == (:Vegetation, 3)`). Throws an `ArgumentError` when the
name has no `_t` suffix.
"""
function time_index(name::Symbol)
    m = match(_TIME_PATTERN, String(name))
    m === nothing &&
        throw(ArgumentError("$name is not a time-indexed name of the form X_t"))
    return (Symbol(m.captures[1]), parse(Int, m.captures[2]))
end

"""
    slice_variables(bn::AbstractBayesNet, t::Integer) -> Vector{Symbol}
    slice_variables(dbn::DynamicBayesNet, t::Integer) -> Vector{Symbol}

The names of the variables of slice `t` of an unrolled network (those whose name is
`X_t`, in part-id order), or the names slice `t` will have when `dbn` is unrolled
([`variable_at`](@ref) applied to the template's current variables).

On a plain network this reads the names alone, so `X_<digits>` is a reserved shape: a
network that happens to have a variable called `A_1` is reported as having a slice 1.
The queries that must not guess ([`rollout`](@ref) and [`horizon(::BayesModel)`](@ref))
use the unrolling recorded by [`unroll`](@ref) in `extras(m)[:unrolled]` instead.
"""
function slice_variables(bn::AbstractBayesNet, t::Integer)
    out = Symbol[]
    for x in variable_names(bn)
        m = match(_TIME_PATTERN, String(x))
        m === nothing && continue
        parse(Int, m.captures[2]) == t && push!(out, x)
    end
    return out
end

"""
    horizon(bn::AbstractBayesNet) -> Int
    horizon(m::BayesModel) -> Int

The largest slice index among the time-indexed variable names of an unrolled network
(`-1` when there is none). Like [`slice_variables`](@ref) this reads the names, so
`X_<digits>` is a reserved shape on a plain network.

On a [`BayesModel`](@ref) the horizon recorded by [`unroll`](@ref) is returned instead,
and a model that `unroll` did not produce is a [`NotUnrolledError`](@ref): the names
alone cannot tell an unrolled network from one with a variable called `A_1`. The
recorded horizon survives `observe`, `do_intervention` and the other operations, which
carry `extras` over.
"""
function horizon(bn::AbstractBayesNet)
    h = -1
    for x in variable_names(bn)
        m = match(_TIME_PATTERN, String(x))
        m === nothing && continue
        h = max(h, parse(Int, m.captures[2]))
    end
    return h
end

"""
    UNROLLED_EXTRA

The key under which [`unroll`](@ref) records what it did in `extras(m)`: a
`Dict{Symbol,Any}` with `:horizon`, `:lags` and `:variables` (the template's current
variable names). [`is_unrolled`](@ref) and [`horizon(::BayesModel)`](@ref) read it.
"""
const UNROLLED_EXTRA = :unrolled

"""
    is_unrolled(m::BayesModel) -> Bool

Whether `m` was produced by [`unroll`](@ref) (or derived from such a model), that is
whether `extras(m)` records an unrolling under [`UNROLLED_EXTRA`](@ref).
"""
function is_unrolled(m::BayesModel)
    r = get(extras(m), UNROLLED_EXTRA, nothing)
    return r isa AbstractDict && haskey(r, :horizon)
end

# The recorded unrolling of `m`, or a `NotUnrolledError` naming the operation and the
# template variable that asked for it.
function _unrolling(m::BayesModel, operation::Symbol, x::Union{Symbol,Nothing}=nothing)
    is_unrolled(m) || throw(NotUnrolledError(operation, x))
    return extras(m)[UNROLLED_EXTRA]
end

horizon(m::BayesModel) = Int(_unrolling(m, :horizon)[:horizon])

# The template
##############

"""
    DynamicBayesNet(initial::BayesNet, transition::BayesNet; lags = inferred, validate = true)

A time-indexed template (SPEC §43). `transition` is a network over *current* variables
`X` (each with a mechanism) and *lagged* variables `X[t-k]` (see [`lagged`](@ref);
exogenous, that is without mechanism), whose mechanisms may read current and lagged
variables alike; the within-slice graph must be acyclic. `initial` is a closed network
describing the first `lags` slices with the same notation relative to slice `lags - 1`
(for `lags = 1`, a closed network over the current variable names). `lags` defaults to
the largest lag that appears in the transition (at least 1).

With `validate = true` the template is checked ([`validate(::DynamicBayesNet)`](@ref))
and the first problem thrown as a [`DynamicTemplateError`](@ref). Compile a finite
horizon with [`unroll`](@ref); bind kernels with a [`DynamicBayesModel`](@ref).

# Example

```jldoctest
julia> initial = bayesnet(:Vegetation => [:sparse, :dense], :Herbivores => [:low, :high];
                          mechanisms = [:Herbivores => :Vegetation]);

julia> transition = bayesnet(:Vegetation => [:sparse, :dense],
                             :Herbivores => [:low, :high],
                             lagged(:Vegetation, 1) => [:sparse, :dense],
                             lagged(:Herbivores, 1) => [:low, :high];
                             mechanisms = [:Vegetation => (lagged(:Vegetation, 1),
                                                           lagged(:Herbivores, 1)),
                                           :Herbivores => :Vegetation],
                             closed = false);

julia> dbn = DynamicBayesNet(initial, transition);

julia> lags(dbn), current_variables(dbn), lagged_variables(dbn)
(1, [:Vegetation, :Herbivores], [Symbol("Vegetation[t-1]"), Symbol("Herbivores[t-1]")])

julia> variable_name.(Ref(unroll(dbn, 2)), parents(unroll(dbn, 2), :Vegetation_2))
2-element Vector{Symbol}:
 :Vegetation_1
 :Herbivores_1
```
"""
struct DynamicBayesNet
    initial::BayesNet
    transition::BayesNet
    lags::Int
end

function _max_lag(transition::AbstractBayesNet)
    return max(1, maximum((last(lag_of(x)) for x in variable_names(transition));
                          init=0))
end

function DynamicBayesNet(initial::BayesNet, transition::BayesNet;
                         lags::Integer=_max_lag(transition), validate::Bool=true)
    lags >= 1 || throw(ArgumentError("lags must be at least 1, got $lags"))
    dbn = DynamicBayesNet(initial, transition, Int(lags))
    validate && BayesianNetworks.validate(dbn)
    return dbn
end

"""
    initial_network(dbn::DynamicBayesNet) -> BayesNet
    initial_network(dm::DynamicBayesModel) -> BayesModel

The initial network (slices `0` to `lags - 1`) of a template, or the model bound to it.
"""
initial_network(dbn::DynamicBayesNet) = dbn.initial

"""
    transition_network(dbn::DynamicBayesNet) -> BayesNet
    transition_network(dm::DynamicBayesModel) -> BayesModel

The transition template (slices `t >= lags`) of a template, or the model bound to it.
"""
transition_network(dbn::DynamicBayesNet) = dbn.transition

"""
    lags(dbn) -> Int

The maximal lag of a [`DynamicBayesNet`](@ref) or [`DynamicBayesModel`](@ref).
"""
lags(dbn::DynamicBayesNet) = dbn.lags

"""
    current_variables(dbn) -> Vector{Symbol}

The current (unlagged) variables of the transition template, in part-id order: the
variables that every slice of the unrolled network carries.
"""
function current_variables(dbn::DynamicBayesNet)
    return filter(x -> !is_lagged(x), variable_names(dbn.transition))
end

"""
    lagged_variables(dbn) -> Vector{Symbol}

The lagged variables `X[t-k]` of the transition template, in part-id order.
"""
lagged_variables(dbn::DynamicBayesNet) = filter(is_lagged, variable_names(dbn.transition))

function slice_variables(dbn::DynamicBayesNet, t::Integer)
    return [variable_at(x, t) for x in current_variables(dbn)]
end

function Base.:(==)(a::DynamicBayesNet, b::DynamicBayesNet)
    return a.initial == b.initial && a.transition == b.transition && a.lags == b.lags
end
function Base.hash(d::DynamicBayesNet, h::UInt)
    return hash(d.lags, hash(d.transition, hash(d.initial, h)))
end

function Base.show(io::IO, dbn::DynamicBayesNet)
    return print(io, "DynamicBayesNet(", length(current_variables(dbn)),
                 " variables per slice, ", length(lagged_variables(dbn)),
                 " lagged inputs, lags = ", dbn.lags, ")")
end

# Validation
############

function _state_table_of(bn::AbstractVariableSpace, x::Symbol)
    return _state_table(bn, variable_id(bn, x))
end

"""
    validation_errors(dbn::DynamicBayesNet) -> Vector{Exception}

All problems of a dynamic template, in a deterministic order: the structural errors of
the initial network (checked closed with unique names) and of the transition template
(unique names; the derived graph, which is the within-slice graph plus the edges from
lagged inputs, must be acyclic), then [`DynamicTemplateError`](@ref)s for

- a current variable of the transition without a mechanism (`:missing_mechanism`);
- a lagged variable with a mechanism (`:lagged_mechanism`);
- a lagged variable `X[t-k]` whose base `X` is not a current variable
  (`:unknown_base`), or whose lag is not in `1:lags` (`:lag`);
- a lagged variable whose states, or `space_ref`, differ from those of its base
  (`:states`, `:space_ref`);
- an initial network whose variables are not exactly `X[t-k]` for every current `X`
  and `0 <= k < lags` (`:initial_variables`), or whose states or `space_ref` differ from
  the transition's (`:states`, `:space_ref`).
"""
function validation_errors(dbn::DynamicBayesNet)
    errs = Exception[]
    ini, tr, L = dbn.initial, dbn.transition, dbn.lags
    append!(errs, validation_errors(ini; closed=true, unique_names=true))
    append!(errs, validation_errors(tr; unique_names=true))
    isempty(errs) || return errs
    current = Set(current_variables(dbn))
    for x in variable_names(tr)
        base, k = lag_of(x)
        if k == 0
            has_mechanism(tr, x) ||
                push!(errs,
                      DynamicTemplateError(:missing_mechanism, x,
                                           "current variable of the transition has no mechanism"))
            continue
        end
        has_mechanism(tr, x) &&
            push!(errs,
                  DynamicTemplateError(:lagged_mechanism, x,
                                       "lagged variable must not have a mechanism"))
        if !(base in current)
            push!(errs,
                  DynamicTemplateError(:unknown_base, x,
                                       "its base :$base is not a current variable of the transition"))
            continue
        end
        k <= L ||
            push!(errs, DynamicTemplateError(:lag, x, "lag $k exceeds lags = $L"))
        _state_table_of(tr, x) == _state_table_of(tr, base) ||
            push!(errs,
                  DynamicTemplateError(:states, x,
                                       "states differ from those of :$base in the transition"))
        space_ref(tr, x) == space_ref(tr, base) ||
            push!(errs,
                  DynamicTemplateError(:space_ref, x,
                                       "space_ref differs from that of :$base in the transition"))
    end
    expected = sort!([lagged(x, k) for x in current for k in 0:(L - 1)])
    actual = sort(variable_names(ini))
    if expected != actual
        missing_ = setdiff(expected, actual)
        extra = setdiff(actual, expected)
        push!(errs,
              DynamicTemplateError(:initial_variables,
                                   isempty(missing_) ? first(extra) : first(missing_),
                                   "the initial network must have exactly the variables " *
                                   "X[t-k] for every current X and 0 <= k < $L; missing " *
                                   "$(missing_), unexpected $(extra)"))
        return errs
    end
    for x in actual
        base, _ = lag_of(x)
        _state_table_of(ini, x) == _state_table_of(tr, base) ||
            push!(errs,
                  DynamicTemplateError(:states, x,
                                       "states in the initial network differ from those of :$base in the transition"))
        space_ref(ini, x) == space_ref(tr, base) ||
            push!(errs,
                  DynamicTemplateError(:space_ref, x,
                                       "space_ref in the initial network differs from that of :$base in the transition"))
    end
    return errs
end

"""
    validate(dbn::DynamicBayesNet) -> Nothing

Throw the first entry of [`validation_errors(::DynamicBayesNet)`](@ref), if any.
"""
function validate(dbn::DynamicBayesNet)
    errs = validation_errors(dbn)
    isempty(errs) || throw(first(errs))
    return nothing
end

"""
    isvalid(dbn::DynamicBayesNet) -> Bool

Whether [`validation_errors(::DynamicBayesNet)`](@ref) is empty.
"""
Base.isvalid(dbn::DynamicBayesNet) = isempty(validation_errors(dbn))

# Unrolling
###########

# The slice a template variable of the initial network (`t0 = lags - 1`) or of the
# transition template at slice `t` refers to.
_slice_of(x::Symbol, t::Integer) = t - last(lag_of(x))

# Name of template variable `x` (current or lagged) seen from slice `t`.
_unrolled_name(x::Symbol, t::Integer) = variable_at(first(lag_of(x)), _slice_of(x, t))

# The mechanism name in the unrolled network: the default name `X_mechanism` of the
# template becomes the default name of the unrolled target, any other name gets the
# slice as a suffix.
function _unrolled_mechanism_name(mname::Symbol, x::Symbol, t::Integer)
    mname == Symbol(x, "_mechanism") && return Symbol(_unrolled_name(x, t), "_mechanism")
    return Symbol(mname, "_", _slice_of(x, t))
end

# The reference of the unrolled mechanism: named references follow the mechanism name
# (a reference equal to the template mechanism's name stays equal to the unrolled
# mechanism's name), point masses are kept, `NoRef` stays.
_unrolled_ref(::NoRef, ::Symbol, ::Symbol, ::Integer) = NoRef()
_unrolled_ref(r::PointMassRef, ::Symbol, ::Symbol, ::Integer) = r
function _unrolled_ref(r::NamedRef, mname::Symbol, x::Symbol, t::Integer)
    r.id == String(mname) &&
        return NamedRef(String(_unrolled_mechanism_name(mname, x, t)))
    return NamedRef(string(r.id, "_", _slice_of(x, t)))
end
function _unrolled_ref(r::PolicyRef, ::Symbol, x::Symbol, t::Integer)
    return PolicyRef(Symbol(r.decision, "_", _slice_of(x, t)))
end

# Copy the variables of `template` that are not yet in `out` (by unrolled name) and all
# its mechanisms, seen from slice `t`. Returns the map from template mechanism id to
# unrolled mechanism id.
function _add_slice!(out::BayesNet, template::BayesNet, t::Integer)
    for v in variables(template)
        x = _unrolled_name(variable_name(template, v), t)
        has_variable(out, x) && continue
        add_variable!(out, x; states=states(template, v),
                      space_ref=space_ref(template, v))
    end
    mmap = Dict{Int,Int}()
    for mech in mechanisms(template)
        x = variable_name(template, target(template, mech))
        mname = mechanism_name(template, mech)
        mmap[mech] = add_mechanism!(out, _unrolled_name(x, t);
                                    inputs=[_unrolled_name(variable_name(template, p), t)
                                            for p in inputs(template, mech)],
                                    name=_unrolled_mechanism_name(mname, x, t),
                                    kernel_ref=_unrolled_ref(_set_kernel_ref(template,
                                                                             mech),
                                                             mname, x, t))
    end
    return mmap
end

function _check_horizon(dbn::DynamicBayesNet, horizon::Integer)
    horizon >= dbn.lags - 1 || throw(HorizonError(Int(horizon), dbn.lags - 1, dbn.lags))
    return nothing
end

"""
    unroll(dbn::DynamicBayesNet, horizon::Integer) -> BayesNet
    unroll(dm::DynamicBayesModel, horizon::Integer) -> BayesModel

Compile the template into the closed network over slices `0, ..., horizon`: the
variables of slice `t` are named [`variable_at`](@ref)`(X, t)`, slices `0` to
`lags - 1` come from the initial network and every later slice from the transition
template, with a lagged input `X[t-k]` wired to `X_{t-k}` (see the boundary convention
in the module documentation; `horizon >= lags - 1` is required,
[`HorizonError`](@ref) otherwise). A template mechanism with the default name
`X_mechanism` becomes `X_t_mechanism`, any other name gets `_t` appended; a
[`NamedRef`](@ref) equal to the mechanism name follows it, other named references get
`_t` appended, [`PointMassRef`](@ref)s are kept.

On a [`DynamicBayesModel`](@ref) the kernels bound to the templates are copied into
every slice with their axes renamed accordingly, so the result evaluates with
[`marginal`](@ref), [`joint_distribution`](@ref), `BayesianNetworkInference.infer`
and the rest of the package. Evidence and history of the template models are not
carried over.
"""
function unroll(dbn::DynamicBayesNet, horizon::Integer)
    _check_horizon(dbn, horizon)
    out = BayesNet()
    _add_slice!(out, dbn.initial, dbn.lags - 1)
    for t in (dbn.lags):horizon
        _add_slice!(out, dbn.transition, t)
    end
    return out
end

"""
    initial_slice(dbn::DynamicBayesNet) -> BayesNet

The initial network with its variables renamed to slices `0, ..., lags - 1` (a closed
network; `unroll(dbn, lags - 1)`).
"""
initial_slice(dbn::DynamicBayesNet) = unroll(dbn, dbn.lags - 1)

"""
    transition_slice(dbn::DynamicBayesNet, t::Integer) -> BayesNet

The transition template seen from slice `t >= lags`: current variables renamed to `X_t`
and lagged variables to `X_{t-k}`, the latter exogenous. It is the piece that
[`unroll`](@ref) adds for slice `t`, and `Open(transition_slice(dbn, t); inputs =
lagged, outputs = current)` glued onto the unrolled network for `t - 1` along the lagged
variables gives `unroll(dbn, t)`.
"""
function transition_slice(dbn::DynamicBayesNet, t::Integer)
    t >= dbn.lags || throw(HorizonError(Int(t), dbn.lags, dbn.lags))
    out = BayesNet()
    _add_slice!(out, dbn.transition, t)
    return out
end

# Semantics
###########

"""
    DynamicBayesModel(dbn::DynamicBayesNet) -> DynamicBayesModel
    DynamicBayesModel(initial::BayesModel, transition::BayesModel, lags::Int)

A [`DynamicBayesNet`](@ref) with semantics: a [`BayesModel`](@ref) for the initial
network and one for the transition template. Bind kernels with
[`bind_kernel`](@ref)`(dm, :X => k; slice = :transition)` or `bind_cpt` (a transition
kernel's domain axes are named like the template's inputs, `X[t-1]` included), read them
back with `kernel(dm, :X; slice)`, and compile with [`unroll`](@ref), which copies the
kernels into every slice. `slice` is `:initial` or `:transition` (the default).

# Example

```jldoctest
julia> dm = vegetation_herbivore_model();

julia> has_semantics(dm), names(kernel(dm, :Vegetation).dom)
(true, [Symbol("Vegetation[t-1]"), Symbol("Herbivores[t-1]")])

julia> um = unroll(dm, 3);

julia> round.(marginal(um, :Vegetation_3).table; digits = 4)
2-element Vector{Float64}:
 0.4299
 0.5701
```
"""
struct DynamicBayesModel{M<:BayesModel}
    initial::M
    transition::M
    lags::Int
end

function DynamicBayesModel(dbn::DynamicBayesNet)
    return DynamicBayesModel(BayesModel(dbn.initial), BayesModel(dbn.transition), dbn.lags)
end

initial_network(dm::DynamicBayesModel) = dm.initial
transition_network(dm::DynamicBayesModel) = dm.transition
lags(dm::DynamicBayesModel) = dm.lags

"""
    template(dm::DynamicBayesModel) -> DynamicBayesNet

The structural template of a dynamic model (the syntax of its two models).
"""
function template(dm::DynamicBayesModel)
    return DynamicBayesNet(syntax(dm.initial), syntax(dm.transition), dm.lags)
end

current_variables(dm::DynamicBayesModel) = current_variables(template(dm))
lagged_variables(dm::DynamicBayesModel) = lagged_variables(template(dm))

function Base.:(==)(a::DynamicBayesModel, b::DynamicBayesModel)
    return a.initial == b.initial && a.transition == b.transition && a.lags == b.lags
end
function Base.hash(d::DynamicBayesModel, h::UInt)
    return hash(d.lags, hash(d.transition, hash(d.initial, h)))
end

function Base.show(io::IO, dm::DynamicBayesModel)
    nk = length(kernels(dm.initial)) + length(kernels(dm.transition))
    print(io, "DynamicBayesModel(", length(current_variables(dm)),
          " variables per slice, lags = ", dm.lags)
    nk == 0 || print(io, ", ", nk, " kernel", nk == 1 ? "" : "s")
    return print(io, ")")
end

function _slice_model(dm::DynamicBayesModel, slice::Symbol)
    slice == :initial && return dm.initial
    slice == :transition && return dm.transition
    return throw(ArgumentError("slice must be :initial or :transition, got :$slice"))
end

function _with_slice(dm::DynamicBayesModel, slice::Symbol, m::BayesModel)
    return slice == :initial ? DynamicBayesModel(m, dm.transition, dm.lags) :
           DynamicBayesModel(dm.initial, m, dm.lags)
end

"""
    bind_kernel(dm::DynamicBayesModel, :X => k; slice = :transition, kwargs...) -> DynamicBayesModel
    bind_cpt(dm::DynamicBayesModel, :X => table; slice = :transition, kwargs...) -> DynamicBayesModel

[`bind_kernel`](@ref) / [`bind_cpt`](@ref) on the initial or the transition model of
`dm`; vectors of pairs are accepted as for models.
"""
function bind_kernel(dm::DynamicBayesModel, b::Pair{Symbol,<:FiniteKernel};
                     slice::Symbol=:transition, kw...)
    return _with_slice(dm, slice, bind_kernel(_slice_model(dm, slice), b; kw...))
end

function bind_kernel(dm::DynamicBayesModel,
                     bs::AbstractVector{<:Pair{Symbol,<:FiniteKernel}};
                     kw...)
    return foldl((acc, b) -> bind_kernel(acc, b; kw...), bs; init=dm)
end

function bind_cpt(dm::DynamicBayesModel, b::Pair{Symbol,<:AbstractArray};
                  slice::Symbol=:transition, kw...)
    return _with_slice(dm, slice, bind_cpt(_slice_model(dm, slice), b; kw...))
end

function bind_cpt(dm::DynamicBayesModel, bs::AbstractVector{<:Pair{Symbol,<:AbstractArray}};
                  kw...)
    return foldl((acc, b) -> bind_cpt(acc, b; kw...), bs; init=dm)
end

"""
    kernel(dm::DynamicBayesModel, :X; slice = :transition) -> FiniteKernel

The kernel bound to the mechanism of `X` in the chosen template model (see
[`kernel`](@ref)).
"""
function kernel(dm::DynamicBayesModel, x::Symbol; slice::Symbol=:transition)
    return kernel(_slice_model(dm, slice), x)
end

"""
    missing_kernels(dm::DynamicBayesModel) -> Vector{Pair{Symbol,Symbol}}

The `slice => variable` pairs whose mechanism has no kernel, initial slice first.
"""
function missing_kernels(dm::DynamicBayesModel)
    return vcat([:initial => x for x in missing_kernels(dm.initial)],
                [:transition => x for x in missing_kernels(dm.transition)])
end

"""
    has_semantics(dm::DynamicBayesModel) -> Bool

Whether every mechanism of both templates resolves to a kernel.
"""
has_semantics(dm::DynamicBayesModel) = isempty(missing_kernels(dm))

"""
    validate(dm::DynamicBayesModel; semantics = false) -> Nothing

[`validate`](@ref) the template ([`validate(::DynamicBayesNet)`](@ref)) and both models
(the initial one closed, the transition one open; with `semantics = true` every
mechanism must resolve).
"""
function validate(dm::DynamicBayesModel; semantics::Bool=false)
    validate(template(dm))
    validate(dm.initial; closed=true, unique_names=true, semantics=semantics)
    validate(dm.transition; unique_names=true, semantics=semantics)
    return nothing
end

# Rename every axis of a kernel through `f`.
function _map_axes(k::FiniteKernel, f)
    function rename(X::FiniteSpace)
        return FiniteSpace(FiniteAxis[FiniteAxis(f(a.name), a.labels)
                                      for a in factors(X)])
    end
    return FiniteKernel(rename(k.dom), rename(k.codom), k.table; check=false)
end

# Copy the kernels of the template model `tm` for slice `t` into `ks`, keyed by the
# unrolled references (`mmap` maps template mechanism ids to unrolled ones in `out`).
function _copy_kernels!(ks::AbstractDict{KernelRef}, out::BayesNet, tm::BayesModel,
                        t::Integer, mmap::AbstractDict{Int,Int})
    bn = syntax(tm)
    for mech in mechanisms(bn)
        ref = kernel_ref(out, mmap[mech])
        (ref isa NamedRef || ref isa PolicyRef) || continue
        k = _lookup_kernel(bn, mech, _set_kernel_ref(bn, mech), kernels(tm))
        k === nothing && continue
        ks[ref] = k isa FiniteKernel ? _map_axes(k, x -> _unrolled_name(x, t)) : k
    end
    return ks
end

function unroll(dm::DynamicBayesModel, horizon::Integer)
    dbn = template(dm)
    _check_horizon(dbn, horizon)
    out = BayesNet()
    ks = Dict{KernelRef,valtype(kernels(dm.transition))}()
    mmap = _add_slice!(out, dbn.initial, dbn.lags - 1)
    _copy_kernels!(ks, out, dm.initial, dbn.lags - 1, mmap)
    for t in (dbn.lags):horizon
        mmap = _add_slice!(out, dbn.transition, t)
        _copy_kernels!(ks, out, dm.transition, t, mmap)
    end
    return BayesModel(out; kernels=ks, extras=_unrolled_extras(dbn, horizon))
end

# What `unroll` records about itself, so that `rollout` and `horizon(::BayesModel)` read
# the horizon instead of guessing it from the `X_t` names.
function _unrolled_extras(dbn::DynamicBayesNet, horizon::Integer)
    return Dict{Symbol,Any}(UNROLLED_EXTRA => Dict{Symbol,Any}(:horizon => Int(horizon),
                                                               :lags => dbn.lags,
                                                               :variables => current_variables(dbn)))
end

# Convenience queries on unrolled models
########################################

"""
    filter_marginal(m::BayesModel, :X, t; evidence = evidence(m), kwargs...) -> FiniteKernel

The posterior marginal of `X_t` in an unrolled model given the evidence (the model's
own by default): filtering when the evidence lies in slices up to `t`, smoothing when
it lies later. Brute force through [`marginal`](@ref); for long horizons use
`BayesianNetworkInference.infer` on the unrolled model, which eliminates variables
rather than enumerating them [LorenzinZanasi2025](@cite).
"""
function filter_marginal(m::BayesModel, x::Symbol, t::Integer; kw...)
    return marginal(m, variable_at(x, t); kw...)
end

"""
    rollout(m::BayesModel, :X; evidence = evidence(m), kwargs...) -> Vector{FiniteKernel}
    rollout(dm::DynamicBayesModel, :X, horizon; kwargs...) -> Vector{FiniteKernel}

The marginals of `X_t` for `t = 0, ..., horizon(m)` (entry `t + 1` is slice `t`), each
a state `I -> X_t`, by brute force ([`marginal`](@ref) with the given evidence). The
second form unrolls `dm` to `horizon` first. For long horizons use
`BayesianNetworkInference.infer` on the unrolled model instead.

`m` must be a model that [`unroll`](@ref) produced (or one derived from it, since every
operation carries `extras` over): the horizon and the template's variable names come
from what `unroll` recorded, not from the `X_t` names, so an ordinary model with a
variable called `A_1` is a [`NotUnrolledError`](@ref) rather than a lookup of the
non-existent `A_0`. `X` must be one of the template's variables
([`UnknownVariableError`](@ref)).
"""
function rollout(m::BayesModel, x::Symbol; kw...)
    r = _unrolling(m, :rollout, x)
    # `Symbol.` so that a model read back from JSON, whose extras carry strings, is
    # still recognised.
    x in Symbol.(r[:variables]) || throw(UnknownVariableError(x))
    return [filter_marginal(m, x, t; kw...) for t in 0:Int(r[:horizon])]
end

function rollout(dm::DynamicBayesModel, x::Symbol, horizon::Integer; kw...)
    return rollout(unroll(dm, horizon), x; kw...)
end
