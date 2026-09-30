"""
Finite-stochastic semantics of a `BayesModel` (SPEC §9, §10, §11 items 8 to 10): spaces
derived from the syntax, kernels bound to mechanisms through their `kernel_ref`, and
the checks that tie the two together. The ACSet never stores a table; a
`BayesModel{S, FiniteSpace, FiniteKernel}` stores kernels in a dictionary keyed by
[`KernelRef`](@ref) and the syntax only carries the references.

Axis convention (ADR 0002): the kernel bound to the mechanism of `X` with parents
`P1, ..., Pk` (in `input_position` order) is a `FiniteKernel` with domain
`P1 ⊗ ... ⊗ Pk` and codomain `X`, where every axis is `FiniteAxis(name, states)` with
the states in `state_position` order. Its table is outputs-first,
`size == (n(X), n(P1), ..., n(Pk))`; the user-facing parents-first layout
`(n(P1), ..., n(Pk), n(X))` is converted by `cpt` and never by hand.
"""

# Spaces from the syntax
########################

"""
    axis(bn, v) -> FiniteAxis

The axis of variable `v` (id or name): its name and its states in `state_position`
order.
"""
function axis(bn::AbstractVariableSpace, v)
    return FiniteAxis(variable_name(bn, _variable_id(bn, v)),
                      states(bn, v))
end

"""
    syntax_space(bn, v) -> FiniteSpace

The one-axis space of variable `v` (id or name), read from the syntax.
"""
syntax_space(bn::AbstractVariableSpace, v) = FiniteSpace(axis(bn, v))

"""
    syntax_spaces(bn) -> Dict{Symbol, FiniteSpace}

The spaces of all variables of `bn` keyed by name, as built by `BayesModel(bn)`.
Variables whose name is not unique or that have no states are skipped (they cannot be
addressed by name, or have no axis).
"""
function syntax_spaces(bn::AbstractVariableSpace)
    sp = Dict{Symbol,FiniteSpace}()
    counts = Dict{Symbol,Int}()
    for v in variables(bn)
        counts[variable_name(bn, v)] = get(counts, variable_name(bn, v), 0) + 1
    end
    for v in variables(bn)
        x = variable_name(bn, v)
        (counts[x] == 1 && nstates(bn, v) > 0) || continue
        sp[x] = syntax_space(bn, v)
    end
    return sp
end

# The stored spaces extended with entries for variables that lack one (after
# `substitute` added hidden variables, for example).
function _complete_spaces(sp::Dict{Symbol,Sp}, bn::AbstractVariableSpace) where {Sp}
    out = copy(sp)
    FiniteSpace <: Sp || return out
    for (x, s) in syntax_spaces(bn)
        haskey(out, x) || (out[x] = s)
    end
    return out
end

"""
    space(m::BayesModel, :X) -> FiniteSpace

The space bound to variable `X`: the entry of `spaces(m)`, or the space read from the
syntax when there is none.
"""
function space(m::BayesModel, x::Symbol)
    haskey(m.spaces, x) && return m.spaces[x]
    return syntax_space(m.syntax, variable_id(m.syntax, x))
end

# The tensor of the parents' axes of mechanism `mech` and the target's space, both read
# from the syntax.
function _mechanism_spaces(bn::AbstractBayesNet, mech::Integer)
    dom = FiniteSpace(FiniteAxis[axis(bn, p) for p in inputs(bn, mech)])
    codom = syntax_space(bn, target(bn, mech))
    return dom, codom
end

"""
    parent_space(m::BayesModel, :X) -> FiniteSpace

The tensor of the spaces of the parents of `X`, in `input_position` order (the domain
that a kernel bound to `X` must have); the unit space for a root.
"""
function parent_space(m::BayesModel, x::Symbol)
    bn = m.syntax
    mech = mechanism_of(bn, x)
    mech === nothing && return FiniteSpace()
    return first(_mechanism_spaces(bn, mech))
end

# Kernel checks
###############

# Check that `k` fits mechanism `mech` of `bn`: codomain, domain and normalisation.
function _check_kernel(bn::AbstractBayesNet, mech::Integer, k::FiniteKernel;
                       atol::Real=DEFAULT_ATOL)
    x = variable_name(bn, target(bn, mech))
    dom, codom = _mechanism_spaces(bn, mech)
    k.codom == codom || throw(KernelBindingError(x, :codom, codom, k.codom))
    k.dom == dom || throw(KernelBindingError(x, :dom, dom, k.dom))
    try
        assert_normalized(k; atol=atol)
    catch e
        if e isa FiniteKernels.KernelNormalizationError
            throw(UnnormalizedKernelError(x, e.max_deviation, atol))
        elseif e isa FiniteKernels.KernelEntryError
            throw(InvalidKernelEntryError(x, _entry_assignment(bn, mech, k, e.index),
                                          Float64(e.value), atol))
        end
        rethrow()
    end
    return k
end

# The entry at `index` of a kernel in FiniteKernels' internal `(codom axes..., dom axes...)`
# layout, as parent-state pairs in `input_position` order followed by the variable's own
# state, so that an error reads the same whichever layout the table was written in.
function _entry_assignment(bn::AbstractBayesNet, mech::Integer, k::FiniteKernel,
                           index::CartesianIndex)
    I = Tuple(index)
    nc = length(k.codom.axes)
    child = [a.name => a.labels[I[i]] for (i, a) in enumerate(k.codom.axes)]
    parents = [a.name => a.labels[I[nc + i]] for (i, a) in enumerate(k.dom.axes)]
    return Pair{Symbol,Symbol}[parents; child]
end

# `bind_cpt(renormalize=true)` rescales each row, so it first applies the entry and row
# checks that rescaling would otherwise hide: an entry that is not finite or is below
# `-atol`, and a row whose sum is not positive (which has no normalisation).
function _check_rows_for_renormalize(bn, mech, k::FiniteKernel, atol::Real)
    x = variable_name(bn, target(bn, mech))
    for ci in CartesianIndices(k.table)
        v = k.table[ci]
        (isfinite(v) && v >= -atol) ||
            throw(InvalidKernelEntryError(x, _entry_assignment(bn, mech, k, ci), Float64(v),
                                          atol))
    end
    nc = length(k.codom.axes)
    s = nc == 0 ? k.table : sum(k.table; dims=Tuple(1:nc))
    for t in s
        t > 0 || throw(UnnormalizedKernelError(x, abs(t - 1), atol))
    end
    return nothing
end

# Mechanism addressed by a variable name (its generating mechanism) or, failing that,
# by a mechanism name.
function _mechanism_for(bn::AbstractBayesNet, name::Symbol)
    if has_variable(bn, name)
        v = variable_id(bn, name)
        mech = mechanism_of(bn, v)
        mech === nothing && throw(MissingMechanismError(name, v))
        return mech
    end
    return mechanism_id(bn, name)
end

# Binding
#########

"""
    bind_kernel(m::BayesModel, :X => k::FiniteKernel; atol = DEFAULT_ATOL) -> BayesModel
    bind_kernel(m::BayesModel, :mechanism_name => k) -> BayesModel
    bind_kernel(m::BayesModel, [:X => k1, :Y => k2])

Bind the kernel `k` to the mechanism generating variable `X` (or to the mechanism
called `mechanism_name` when no variable has that name). The kernel must have the
variable's space as codomain and the tensor of its parents' spaces, in
`input_position` order, as domain (axis names and labels must match the syntax;
[`KernelBindingError`](@ref) otherwise) and must be normalised within `atol`
([`UnnormalizedKernelError`](@ref); the default `DEFAULT_ATOL` is FiniteKernels'
`1e-8`).

The kernel is stored under the mechanism's `kernel_ref`. A mechanism with
[`NoRef`](@ref) receives the fresh reference `NamedRef(string(mechanism_name))`, so
the returned model carries an updated syntax; the history is untouched. Mechanisms with
a [`PointMassRef`](@ref) are materialised on demand and cannot be bound
([`KernelBindingError`](@ref) with `what = :intervention`; use
[`soft_intervention`](@ref) to replace them).

# Example

```jldoctest
julia> m = BayesModel(bayesnet(:Rain => [:no, :yes], :Grass => [:dry, :wet];
                               mechanisms = [:Grass => :Rain]));

julia> m = bind_kernel(m, :Rain => state(space(m, :Rain), [0.8, 0.2]));

julia> m = bind_cpt(m, :Grass => [0.9 0.1; 0.2 0.8]);   # rows = Rain, columns = Grass

julia> has_semantics(m), kernel_ref(syntax(m), :Grass_mechanism)
(true, NamedRef("Grass_mechanism"))
```
"""
function bind_kernel(m::BayesModel, b::Pair{Symbol,<:FiniteKernel};
                     atol::Real=DEFAULT_ATOL)
    name, k = b
    bn = m.syntax
    mech = _mechanism_for(bn, name)
    ref = kernel_ref(bn, mech)
    ref isa PointMassRef &&
        throw(KernelBindingError(variable_name(bn, target(bn, mech)), :intervention,
                                 "a mechanism that is not a hard intervention (use soft_intervention to replace it)",
                                 ref))
    _check_kernel(bn, mech, k; atol=atol)
    syn = bn
    if ref isa NoRef
        ref = NamedRef(string(mechanism_name(bn, mech)))
        syn = deepcopy(bn)
        set_subpart!(syn, mech, :kernel_ref, ref)
    end
    ks = copy(m.kernels)
    ks[ref] = k
    return _with(m; syntax=syn, kernels=ks)
end

# `FiniteKernel{T,N}` carries the array rank, so a comprehension collecting kernels of
# different arity widens to the abstract `Pair{Symbol}`. Accept any vector of pairs
# keyed by `Symbol` and let the single-binding method type-check each value, rather
# than making callers annotate the element type.
function bind_kernel(m::BayesModel, bs::AbstractVector{<:Pair{Symbol,<:Any}}; kw...)
    for (v, k) in bs
        k isa FiniteKernel ||
            throw(ArgumentError("bind_kernel: the value bound to :$v is a $(typeof(k)), " *
                                "not a FiniteKernel"))
    end
    return foldl((acc, b) -> bind_kernel(acc, b; kw...), bs; init=m)
end

"""
    bind_cpt(m::BayesModel, :X => table; atol = DEFAULT_ATOL, renormalize = false) -> BayesModel
    bind_cpt(m::BayesModel, [:X => t1, :Y => t2])

[`bind_kernel`](@ref) with the kernel built by `cpt` from a conditional probability
table in the user-facing layout: `size(table) == (n(P1), ..., n(Pk), n(X))` for parents
`P1, ..., Pk` in `input_position` order, normalised over the last axis; a vector for a
root. A wrong size is a [`KernelBindingError`](@ref) with `what == :table`. With
`renormalize = true` every row is rescaled to sum to one before binding; the entries are
checked first (finite and at least `-atol`, else [`InvalidKernelEntryError`](@ref)), and a
row whose sum is not positive raises [`UnnormalizedKernelError`](@ref), since it has no
normalisation. Without it, an unnormalised row raises `UnnormalizedKernelError` and an
invalid entry `InvalidKernelEntryError`, both through [`bind_kernel`](@ref).
"""
function bind_cpt(m::BayesModel, b::Pair{Symbol,<:AbstractArray};
                  atol::Real=DEFAULT_ATOL, renormalize::Bool=false)
    name, table = b
    bn = m.syntax
    mech = _mechanism_for(bn, name)
    x = variable_name(bn, target(bn, mech))
    ps = FiniteAxis[axis(bn, p) for p in inputs(bn, mech)]
    child = axis(bn, target(bn, mech))
    expected = (map(length, ps)..., length(child))
    size(table) == expected ||
        throw(KernelBindingError(x, :table, expected, size(table)))
    k = cpt(ps, child, table; check=false)
    if renormalize
        _check_rows_for_renormalize(bn, mech, k, atol)
        k = normalize(k)
    end
    return bind_kernel(m, x => k; atol=atol)
end

function bind_cpt(m::BayesModel, bs::AbstractVector{<:Pair{Symbol,<:AbstractArray}}; kw...)
    return foldl((acc, b) -> bind_cpt(acc, b; kw...), bs; init=m)
end

# Resolution
############

# The kernel of mechanism `mech`, resolved through `lookup`: a dictionary keyed by
# `KernelRef` (the model's `kernels`; a `NoRef` never resolves) or by target variable
# name (a `NoRef` resolves like any other reference). Point-mass references are
# materialised as `Pa(X) -> I -> X` (SPEC section 21.2); `nothing` when the reference
# does not resolve.
function _resolve_kernel(bn::AbstractBayesNet, mech::Integer, lookup)
    ref = kernel_ref(bn, mech)
    if ref isa PointMassRef
        dom, codom = _mechanism_spaces(bn, mech)
        pm = point_mass(codom, ref.state)
        return isempty(dom) ? pm : compose_kernel(discard_kernel(dom), pm)
    end
    return _lookup_kernel(bn, mech, ref, lookup)
end

function _lookup_kernel(::AbstractBayesNet, ::Integer, ref::KernelRef,
                        ks::AbstractDict{<:KernelRef})
    return ref isa NoRef ? nothing : get(ks, ref, nothing)
end

function _lookup_kernel(bn::AbstractBayesNet, mech::Integer, ::KernelRef,
                        ks::AbstractDict{Symbol})
    return get(ks, variable_name(bn, target(bn, mech)), nothing)
end

"""
    kernel(m::BayesModel, :X) -> FiniteKernel

The kernel of the mechanism generating `X`: the entry of `kernels(m)` under the
mechanism's [`NamedRef`](@ref) or [`PolicyRef`](@ref), or, for a
[`PointMassRef`](@ref)`(s)`, the point mass on `s` (composed with the discard of the
parents when the mechanism has inputs), materialised on demand. Throws
[`MissingMechanismError`](@ref) for an exogenous variable and
[`MissingKernelError`](@ref) when the reference does not resolve.
"""
function kernel(m::BayesModel, x::Symbol)
    bn = m.syntax
    v = variable_id(bn, x)
    mech = mechanism_of(bn, v)
    mech === nothing && throw(MissingMechanismError(x, v))
    k = _resolve_kernel(bn, mech, m.kernels)
    k === nothing && throw(MissingKernelError(x, kernel_ref(bn, mech)))
    return k
end

"""
    missing_kernels(m::BayesModel) -> Vector{Symbol}

Names of the variables whose mechanism has a reference that does not resolve to a
kernel, in mechanism part-id order.
"""
function missing_kernels(m::BayesModel)
    bn = m.syntax
    return Symbol[variable_name(bn, target(bn, mech))
                  for mech in mechanisms(bn)
                  if _resolve_kernel(bn, mech, m.kernels) === nothing]
end

"""
    has_semantics(m::BayesModel) -> Bool

Whether every mechanism's reference resolves to a kernel (see
[`missing_kernels`](@ref)). Does not check that the network is closed.
"""
has_semantics(m::BayesModel) = isempty(missing_kernels(m))

# Semantic validation
#####################

"""
    semantic_errors(m::BayesModel; semantics = false, atol = DEFAULT_ATOL) -> Vector{Exception}

The semantic problems of `m` (SPEC section 11, items 8 to 10), in a deterministic
order: stored spaces that name no variable ([`UnknownVariableError`](@ref)) or differ
from the variable's states ([`KernelBindingError`](@ref) with `what == :space`), and for
every mechanism whose reference resolves, a kernel whose domain or codomain does not fit
([`KernelBindingError`](@ref)), that is not normalised within `atol`
([`UnnormalizedKernelError`](@ref)), or that has an entry that is not finite or is below
`-atol` ([`InvalidKernelEntryError`](@ref)); every one is collected rather than thrown, in
mechanism order, so [`validate`](@ref) throws the first. With `semantics = true` a reference that does not
resolve is a [`MissingKernelError`](@ref). Kernels that are not `FiniteKernel`s
(alternative semantics) are not checked.
"""
function semantic_errors(m::BayesModel; semantics::Bool=false, atol::Real=DEFAULT_ATOL)
    errs = Exception[]
    bn = m.syntax
    for x in sort!(collect(keys(m.spaces)))
        sp = m.spaces[x]
        sp isa FiniteSpace || continue
        if !has_variable(bn, x)
            push!(errs, UnknownVariableError(x))
            continue
        end
        expected = syntax_space(bn, variable_id(bn, x))
        sp == expected || push!(errs, KernelBindingError(x, :space, expected, sp))
    end
    for mech in mechanisms(bn)
        x = variable_name(bn, target(bn, mech))
        k = _resolve_kernel(bn, mech, m.kernels)
        if k === nothing
            semantics && push!(errs, MissingKernelError(x, kernel_ref(bn, mech)))
            continue
        end
        k isa FiniteKernel || continue
        try
            _check_kernel(bn, mech, k; atol=atol)
        catch e
            e isa BayesNetError || rethrow()
            push!(errs, e)
        end
    end
    return errs
end

# Approximate equality
######################

"""
    isapprox(a::BayesModel, b::BayesModel; kwargs...) -> Bool

Whether two models have the same semantics: the same syntax up to
[`canonicalize`](@ref), the same evidence, and for every variable either kernels that
are `isapprox` (keyword arguments are passed on) or no kernel on either side. History
and extras are ignored.
"""
function Base.isapprox(a::BayesModel, b::BayesModel; kwargs...)
    canonicalize(a.syntax) == canonicalize(b.syntax) || return false
    a.evidence == b.evidence || return false
    for x in variable_names(a.syntax)
        has_mechanism(a.syntax, x) || continue
        ka = _resolve_kernel(a.syntax, mechanism_of(a.syntax, x), a.kernels)
        kb = _resolve_kernel(b.syntax, mechanism_of(b.syntax, x), b.kernels)
        (ka === nothing) == (kb === nothing) || return false
        ka === nothing && continue
        isapprox(ka, kb; kwargs...) || return false
    end
    return true
end

# Semantics through renaming and substitution
#############################################

function _rename_axis(a::FiniteAxis, old::Symbol, new::Symbol)
    return a.name == old ?
           FiniteAxis(new, a.labels) : a
end
function _rename_axis(X::FiniteSpace, old::Symbol, new::Symbol)
    return FiniteSpace(FiniteAxis[_rename_axis(a, old, new) for a in factors(X)])
end
function _rename_axis(k::FiniteKernel, old::Symbol, new::Symbol)
    return FiniteKernel(_rename_axis(k.dom, old, new), _rename_axis(k.codom, old, new),
                        k.table; check=false)
end
_rename_axis(x, ::Symbol, ::Symbol) = x

# Spaces and kernels of a model after variable `old` was renamed `new`.
function _rename_semantics(m::BayesModel, old::Symbol, new::Symbol)
    sp = Dict{Symbol,valtype(m.spaces)}()
    for (x, s) in m.spaces
        sp[x == old ? new : x] = _rename_axis(s, old, new)
    end
    ks = Dict{KernelRef,valtype(m.kernels)}(r => _rename_axis(k, old, new)
                                            for (r, k) in m.kernels)
    return sp, ks
end

# Renaming
##########

"""
    rename_variable(bn::AbstractBayesNet, old::Symbol => new::Symbol) -> typeof(bn)
    rename_variable(m::BayesModel, old => new) -> BayesModel

A copy in which variable `old` is called `new`. On a model the evidence, the spaces and
the axis names inside every kernel follow the variable.

Names play no role in gluing (only legs do), so renaming is the explicit way to line up
interfaces that differ only by name; `CategoricalBayesianNetworks.jl` adds the method
for an open network, which renames the feet along with the apex.
"""
function rename_variable(bn::AbstractBayesNet, r::Pair{Symbol,Symbol})
    old, new = r
    v = variable_id(bn, old)
    out = deepcopy(bn)
    set_subpart!(out, v, :variable_name, new)
    return out
end

function rename_variable(m::BayesModel, r::Pair{Symbol,Symbol})
    old, new = r
    ev = copy(evidence(m))
    haskey(ev, old) && (ev[new] = pop!(ev, old))
    sp, ks = _rename_semantics(m, old, new)
    return _with(m; syntax=rename_variable(syntax(m), r), evidence=ev, spaces=sp,
                 kernels=ks)
end

# Soft interventions with a kernel
##################################

"""
    soft_intervention(m::BayesModel, :X => k::FiniteKernel; parents = names(k.dom), name = Symbol("soft[X]"), note = "", atol = DEFAULT_ATOL) -> BayesModel

Replace the mechanism of `X` by one with the given `parents` (by default the axis names
of the kernel's domain, in order) and the kernel `k`, stored under the fresh reference
`NamedRef(string(name))`. The kernel must fit the new mechanism
([`KernelBindingError`](@ref), [`UnnormalizedKernelError`](@ref) beyond `atol`); the
rewrite is recorded as a `:soft` [`ModelEvent`](@ref) like the reference-based method.
"""
function soft_intervention(m::BayesModel, iv::Pair{Symbol,<:FiniteKernel};
                           parents::Union{Nothing,AbstractVector{Symbol}}=nothing,
                           name::Symbol=Symbol("soft[", first(iv), "]"),
                           note::AbstractString="", atol::Real=DEFAULT_ATOL)
    x, k = iv
    ps = parents === nothing ? Symbol[a.name for a in factors(k.dom)] :
         collect(Symbol, parents)
    ref = NamedRef(string(name))
    return soft_intervention(m, x => ref; parents=ps, name=name, kernel=k, note=note,
                             atol=atol)
end

function soft_intervention(m::BayesModel,
                           ivs::AbstractVector{<:Pair{Symbol,<:FiniteKernel}};
                           kw...)
    return foldl((acc, iv) -> soft_intervention(acc, iv; kw...), ivs; init=m)
end
