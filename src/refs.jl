"""
    KernelRef

Abstract supertype of the small sum type stored in the `Ref` attribute slots of a
[`BayesNet`](@ref) (`space_ref` on variables and `kernel_ref` on mechanisms).

A reference names the semantic object (a finite space or a stochastic kernel) that a
structural part will be bound to. The structural layer never stores numerical tables;
it stores references that a `BayesModel` resolves. Concrete subtypes:

- [`NamedRef`](@ref): a stable string identifier resolved against a kernel table;
- [`PointMassRef`](@ref): a point-mass kernel produced by a hard intervention;
- [`PolicyRef`](@ref): a kernel supplied by a decision policy;
- [`NoRef`](@ref): no reference attached (structure only).

All subtypes serialise to JSON as objects with a `"type"` discriminator, so an ACSet
containing them round-trips through `generate_json_acset` / `parse_json_acset`.
"""
abstract type KernelRef end

"""
    NamedRef(id::String)

Reference to a kernel or space by a stable identifier.
"""
struct NamedRef <: KernelRef
    id::String
end

"""
    PointMassRef(state::Symbol)

Reference to the point-mass kernel that puts all mass on `state`; the result of a hard
intervention `do(X = state)`.
"""
struct PointMassRef <: KernelRef
    state::Symbol
end

"""
    PolicyRef(decision::Symbol)

Reference to the kernel implementing the policy of decision variable `decision`.
"""
struct PolicyRef <: KernelRef
    decision::Symbol
end

"""
    NoRef()

The absence of a reference. Structural networks without attached semantics use it for
every `space_ref` and `kernel_ref`.
"""
struct NoRef <: KernelRef end

const _KERNEL_REF_TYPES = (NamedRef=NamedRef, PointMassRef=PointMassRef,
                           PolicyRef=PolicyRef, NoRef=NoRef)

# StructTypes integration
#########################

# Reading through the abstract type dispatches on the "type" key; each concrete type
# is a CustomStruct so that the discriminator is written alongside its fields.
StructTypes.StructType(::Type{KernelRef}) = StructTypes.AbstractType()
StructTypes.subtypekey(::Type{KernelRef}) = :type
StructTypes.subtypes(::Type{KernelRef}) = _KERNEL_REF_TYPES

StructTypes.StructType(::Type{<:KernelRef}) = StructTypes.CustomStruct()
StructTypes.lower(r::NamedRef) = (type="NamedRef", id=r.id)
StructTypes.lower(r::PointMassRef) = (type="PointMassRef", state=String(r.state))
StructTypes.lower(r::PolicyRef) = (type="PolicyRef", decision=String(r.decision))
StructTypes.lower(::NoRef) = (type="NoRef",)

# A field of a decoded record, by Symbol or String key. A record that is not an object is
# a `_JSONShapeError` (serialization.jl), which the decoders report as a `FormatError`.
function _ref_field(x, key::Symbol)
    x isa Union{AbstractDict,NamedTuple} ||
        throw(_JSONShapeError(string(key, " (its record)"), "an object", x))
    return haskey(x, key) ? x[key] : x[String(key)]
end

# A string field of a reference; another JSON type is the `ArgumentError` of the direct
# StructTypes path, which the decoders also convert.
function _ref_string(x, key::Symbol)
    v = _ref_field(x, key)
    v isa AbstractString ||
        throw(ArgumentError("the KernelRef field \"$key\" must be a string, got $(repr(v))"))
    return String(v)
end

function _kernel_ref_from(x)
    ty = _ref_string(x, :type)
    if ty == "NamedRef"
        return NamedRef(_ref_string(x, :id))
    elseif ty == "PointMassRef"
        return PointMassRef(Symbol(_ref_string(x, :state)))
    elseif ty == "PolicyRef"
        return PolicyRef(Symbol(_ref_string(x, :decision)))
    elseif ty == "NoRef"
        return NoRef()
    else
        throw(ArgumentError("unknown KernelRef type \"$ty\""))
    end
end

function StructTypes.construct(::Type{T},
                               x::Union{AbstractDict,NamedTuple}) where {T<:KernelRef}
    r = _kernel_ref_from(x)
    r isa T || throw(ArgumentError("expected a $(T), got $(typeof(r))"))
    return r
end
