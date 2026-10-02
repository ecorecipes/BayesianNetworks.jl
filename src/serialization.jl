"""
JSON serialisation. Networks are written with ACSets' `generate_json_acset` inside an
envelope that records the format name and schema version (SPEC §48).
"""

const JSON_FORMAT = "bayesnet-acset"
const JSON_SCHEMA_VERSION = "0.1"

# Decoding failures
###################

# A JSON document that cannot be decoded raises `FormatError`, selectively: only the
# conditions below are converted, where they arise, and everything else, `BayesNetError`s
# included, propagates unchanged. There is no catch-all, which would also turn a
# `MethodError` or an `InterruptException` into a `FormatError`.
#
# - JSON3's `ArgumentError` for text that is not JSON, at every `JSON3.read` of a document
#   (`_read_json`, which InfluenceDiagrams.jl's readers call too).
# - In the record decoders (the card, the kernel records and history of
#   `parse_json_model`, and the CatColab and presentation readers): the `KeyError` of a
#   missing key, and the `ArgumentError` of an unknown `KernelRef` type or of an
#   unparsable time (`_decode_ref`, `_decode_time`). `_kernel_ref_from` itself keeps the
#   `ArgumentError`, which the direct StructTypes path raises.
# - In a kernel record, also the FiniteKernels errors of an invalid space or table. A
#   `"size"` whose product, taken in `BigInt`, is not the table's length is checked first.
#
# - A value of the wrong JSON type, or a record that is not an object, is a
#   `_JSONShapeError` from the typed reads below (`_as_string`, `_as_int`, ...; `_field` and
#   `_ref_field` check their container), which the record decoders convert with `KeyError`
#   (`_SHAPE_ERRORS`). The reads check instead of converting blindly, so a `MethodError`
#   still means a bug (ADR 0015). A name (`_as_symbol`) is a string without a NUL
#   character, which a `Symbol` cannot hold; the model's `"extras"` is an object.
# - `_read_json` rejects a key repeated in any object of a document, and a document nested
#   more than `_JSON_MAX_DEPTH` levels deep (`_check_json_text`).
# - The `"acset"` body is checked against the schema first (`_check_acset_body`, below
#   `_parse_acset`): every table and column, and the JSON type and range of every value,
#   with the rules of the proved Lean decoder. A failure is a `FormatError` that names the
#   table, row and column. Only then does it go to ACSets' `parse_json_acset`, a
#   third-party parser of pure document data, so every exception it raises is about the
#   document: `_parse_acset` is the one scoped catch-all of the decoders, and lets an
#   `InterruptException` through (ADR 0015).

# Run `f()`, and report an exception of type `T` as a `FormatError` about `what`.
function _decoding(f, ::Type{T}, what::AbstractString) where {T}
    try
        return f()
    catch e
        e isa T || rethrow()
        throw(FormatError(string(what, ": ", _decoding_message(e))))
    end
end

_decoding_message(e::KeyError) = "missing key \"$(e.key)\""
_decoding_message(e::ArgumentError) = rstrip(e.msg)
_decoding_message(e) = first(split(sprint(showerror, e), '\n'))

# `_JSONShapeError` (errors.jl): a value of the wrong JSON type in a decoded document.
function _decoding_message(e::_JSONShapeError)
    return "\"$(e.key)\" must be $(e.expected), got $(_json_kind(e.value))"
end
const _SHAPE_ERRORS = Union{KeyError,_JSONShapeError}

function _json_kind(x)
    x === nothing && return "null"
    x isa AbstractString && return '\0' in x ? "a string with a NUL character" : "a string"
    x isa Bool && return "a boolean"
    x isa Number && return "the number $(x)"
    x isa AbstractDict && return "an object"
    x isa AbstractVector && return "an array"
    return string(typeof(x))
end

# Typed reads of a decoded JSON value; `key` names it in the error.
function _as_string(v, key)
    v isa AbstractString || throw(_JSONShapeError(string(key), "a string", v))
    return String(v)
end
# A name: a string that a `Symbol` can hold, so without a NUL character.
function _as_symbol(v, key)
    s = _as_string(v, key)
    '\0' in s && throw(_JSONShapeError(string(key), "a string without a NUL character", v))
    return Symbol(s)
end
function _as_float(v, key)
    v isa Real && !(v isa Bool) || throw(_JSONShapeError(string(key), "a number", v))
    return Float64(v)
end
function _as_int(v, key)
    ok = v isa Real && !(v isa Bool) && isfinite(v) && isinteger(v) &&
         typemin(Int) <= v <= typemax(Int)
    ok || throw(_JSONShapeError(string(key), "an integer", v))
    return Int(v)
end
function _as_array(v, key)
    v isa AbstractVector || throw(_JSONShapeError(string(key), "an array", v))
    return v
end
function _as_object(v, key)
    v isa AbstractDict || throw(_JSONShapeError(string(key), "an object", v))
    return v
end
_as_strings(v, key) = String[_as_string(x, key) for x in _as_array(v, key)]
_as_symbols(v, key) = Symbol[_as_symbol(x, key) for x in _as_array(v, key)]

# The text is parsed as text: `JSON3.read` of a `String` shorter than 255 bytes that names
# an existing file would read that file instead, so the reader parses the code units. The
# document is parsed once: `_check_json_text` and `_json_number_spellings` only scan it.
function _read_json(str::AbstractString)
    bytes = codeunits(String(str))
    _check_json_text(bytes)
    return _decoding(() -> JSON3.read(bytes), ArgumentError, "the text is not JSON")
end

# Two checks of a JSON text, made on the text before it is parsed:
#
# - Nesting. JSON3's parser recurses once per level and overflows the stack at a few thousand
#   levels, which a small file reaches. A document nested deeper than `_JSON_MAX_DEPTH`
#   levels is a `FormatError`, never a `StackOverflowError`; BayesianNetworkFormats sets the
#   same limit for its JSON.
# - Repeated keys. No object may repeat a key. JSON leaves the meaning of a repeated key to
#   the reader, and the readers disagree: JSON3 keeps every copy and looks up the last, which
#   the checks after it would see, while ACSets' `parse_json_acset` adds parts for every copy
#   of a table. `Lean.Json.parse`, which the Lean decoder trusts, keeps the last copy. Keys
#   are compared unescaped, as JSON3 reads them.
#
# A text that is not JSON is left to JSON3, which says so; the scan only must not fail on it.
const _JSON_MAX_DEPTH = 512

# A key of an open object: the FNV-1a hash of its unescaped bytes, and its raw text
# `bytes[first:last]`, or `text` when the raw text has an escape.
struct _JSONKey
    hash::UInt64
    first::Int
    last::Int
    text::Union{Nothing,String}
end

function _fnv1a(bytes)
    h = 0xcbf29ce484222325
    for b in bytes
        h = (h ⊻ b) * 0x00000100000001b3
    end
    return h
end

function _key_bytes(bytes, k::_JSONKey)
    return k.text === nothing ? view(bytes, (k.first):(k.last)) :
           codeunits(k.text)
end

# The class of a byte for `_check_json_text`: 1 a quote, 2 an opening bracket, 3 a closing
# one, 4 a comma, 0 anything else.
const _JSON_BYTE_CLASS = let t = zeros(UInt8, 256)
    t[Int('"') + 1] = 1
    t[Int('{') + 1] = t[Int('[') + 1] = 2
    t[Int('}') + 1] = t[Int(']') + 1] = 3
    t[Int(',') + 1] = 4
    t
end

function _check_json_text(bytes::AbstractVector{UInt8})
    n = length(bytes)
    object = Bool[]                       # per open container: whether it is an object
    opened = Int[]                        # per open container: the index of its bracket
    first_key = Int[]                     # per open container: its first entry in `keys`
    sets = Union{Nothing,Set{UInt64}}[]   # per open object of many keys: their hashes
    keys = _JSONKey[]                     # the keys of the open objects, outermost first
    in_object = false                     # the innermost open container is an object
    key_next = false                      # in an object, the next string is a key
    i = 1
    @inbounds while i <= n
        class = _JSON_BYTE_CLASS[bytes[i] + 1]
        if class == 1
            j = _json_string_end(bytes, i)
            if key_next
                _add_json_key!(keys, sets, object, opened, first_key, bytes, i, j)
                key_next = false
            end
            i = j
        elseif class == 2
            is_object = bytes[i] == UInt8('{')
            push!(object, is_object)
            push!(opened, i)
            push!(first_key, length(keys) + 1)
            push!(sets, nothing)
            length(object) > _JSON_MAX_DEPTH &&
                throw(FormatError("the document is nested more than $(_JSON_MAX_DEPTH) levels deep"))
            in_object = key_next = is_object
        elseif class == 3
            isempty(object) && return nothing
            pop!(object)
            pop!(opened)
            pop!(sets)
            resize!(keys, pop!(first_key) - 1)
            in_object = !isempty(object) && object[end]
            key_next = false
        elseif class == 4
            key_next = in_object
        end
        i += 1
    end
    return nothing
end

# Record the key `bytes[i:j]` (with its quotes) of the innermost open object, or throw if
# the object has it already. An object of more than 16 keys keeps their hashes in a set.
function _add_json_key!(keys, sets, object, opened, first_key, bytes, i::Int, j::Int)
    raw = view(bytes, (i + 1):(j - 1))
    text = UInt8('\\') in raw ?
           _decoding(() -> JSON3.read(bytes[i:j], String), ArgumentError,
                     "the text is not JSON") : nothing
    key = _JSONKey(_fnv1a(text === nothing ? raw : codeunits(text)), i + 1, j - 1, text)
    start = first_key[end]
    set = sets[end]
    if set === nothing || key.hash in set
        for k in start:length(keys)
            other = keys[k]
            other.hash == key.hash && _key_bytes(bytes, other) == _key_bytes(bytes, key) &&
                throw(FormatError(_repeated_key_message(bytes, key, object, opened,
                                                        first_key, keys)))
        end
    end
    push!(keys, key)
    if set !== nothing
        push!(set, key.hash)
    elseif length(keys) - start + 1 > 16
        sets[end] = Set{UInt64}(keys[k].hash for k in start:length(keys))
    end
    return nothing
end

_key_string(bytes, k::_JSONKey) = String(copy(_key_bytes(bytes, k)))

# The message for a key repeated in the innermost open object, naming the object by its
# path from the top level: a key of an enclosing object, or a one-based index of an
# enclosing array.
function _repeated_key_message(bytes, key::_JSONKey, object, opened, first_key, keys)
    name = _key_string(bytes, key)
    depth = length(object)
    depth == 1 && return "the key \"$name\" appears more than once in the top-level object"
    path = ""
    for f in 2:depth
        if object[f - 1]
            # The parent's last key, which this container is the value of (none in a text
            # that is not JSON).
            k = first_key[f] - 1
            step = k >= first_key[f - 1] ? _key_string(bytes, keys[k]) : "?"
            f == 2 && step == "acset" && depth == 2 &&
                return "the table \"$name\" appears more than once in the \"acset\" body"
            path = isempty(path) ? step : "$path.$step"
        else
            path = "$path[$(_json_array_index(bytes, opened[f - 1], opened[f]))]"
        end
    end
    return "the key \"$name\" appears more than once in the object at $path " *
           "(arrays are numbered from 1)"
end

# The one-based index, in the array whose bracket is at `from`, of the element that starts
# at `to`.
function _json_array_index(bytes, from::Int, to::Int)
    index, depth, i = 1, 0, from + 1
    while i < to
        b = bytes[i]
        if b == UInt8('"')
            i = _json_string_end(bytes, i)
        elseif b == UInt8('{') || b == UInt8('[')
            depth += 1
        elseif b == UInt8('}') || b == UInt8(']')
            depth -= 1
        elseif b == UInt8(',') && depth == 0
            index += 1
        end
        i += 1
    end
    return index
end

# The source spellings of the numbers in the top-level `"acset"` value of a JSON text that
# `_read_json` has read, in document order. JSON3 reads every integral number as an
# `Int64`, so `1`, `1.0`, `1e0`, `1E0`, `10e-1`, `1.`, `01` and `+1` are all the `Int64` 1 in
# `_read_json`'s tree; the ID, hom and position columns of an `"acset"` body need the
# spelling (`_check_acset_body`). `_json_number_spellings(str)[:acset]` is what
# `_parse_acset` takes; it pairs the spellings with the numbers of the body it reads.
struct _NumberSpellings
    numbers::Vector{String}
end

# The text is scanned, not parsed again. JSON3 accepted it, so it is JSON: a number runs to
# the next delimiter, and its text has no character that needs escaping. A token outside a
# string that is not `true`, `false`, `null` or punctuation is a number. The scan stops at
# the end of the `"acset"` value; a key is compared unescaped.
const _JSON_NUMBER_ENDS = (UInt8(','), UInt8(']'), UInt8('}'), UInt8(':'), UInt8('['),
                           UInt8('{'), UInt8('"'), UInt8(' '), UInt8('\t'), UInt8('\n'),
                           UInt8('\r'))
function _json_number_spellings(str::AbstractString)
    bytes = codeunits(String(str))
    numbers = String[]
    n = length(bytes)
    depth = 0             # containers open
    key_next = false      # in the top-level object, the next string is a key
    acset_next = false    # the last top-level key was "acset"
    collecting = false    # inside the "acset" value
    i = 1
    while i <= n
        b = bytes[i]
        if b == UInt8('"')
            j = _json_string_end(bytes, i)
            if depth == 1 && key_next
                acset_next = _json_key_equals(bytes, i, j, "acset")
                key_next = false
            end
            i = j + 1
        elseif b == UInt8('{') || b == UInt8('[')
            depth += 1
            if depth == 1
                key_next = b == UInt8('{')
            elseif depth == 2 && acset_next
                collecting = true
            end
            i += 1
        elseif b == UInt8('}') || b == UInt8(']')
            depth -= 1
            collecting && depth == 1 && break
            i += 1
        elseif b == UInt8(',')
            if depth == 1
                key_next = true
                acset_next = false
            end
            i += 1
        elseif b in _JSON_NUMBER_ENDS
            i += 1
        else
            j = i
            while j <= n && !(bytes[j] in _JSON_NUMBER_ENDS)
                j += 1
            end
            literal = b == UInt8('t') || b == UInt8('f') || b == UInt8('n')
            if !literal && (collecting || (depth == 1 && acset_next))
                push!(numbers, String(bytes[i:(j - 1)]))
            end
            i = j
        end
    end
    return (acset=_NumberSpellings(numbers),)
end

# The index of the quote that closes the string opening at `i`.
function _json_string_end(bytes, i::Int)
    j = i + 1
    while j <= length(bytes)
        b = bytes[j]
        b == UInt8('"') && return j
        j += b == UInt8('\\') ? 2 : 1
    end
    return length(bytes)
end

# Whether the string token `bytes[i:j]` is the key `key`, unescaped as JSON3 reads it.
function _json_key_equals(bytes, i::Int, j::Int, key::String)
    raw = view(bytes, (i + 1):(j - 1))
    UInt8('\\') in raw || return raw == codeunits(key)
    return JSON3.read(bytes[i:j], String) == key
end

# The `"acset"` body with each number replaced by its spelling: the numbers of `body` in
# document order (JSON3 iterates objects and arrays in document order) paired with
# `spellings`.
function _spelled_body(body, spellings::_NumberSpellings)
    next = Ref(0)
    tree = _spelled(body, spellings.numbers, next)
    next[] == length(spellings.numbers) ||
        error("internal: the \"acset\" body has $(next[]) numbers, its text $(length(spellings.numbers))")
    return tree
end

function _spelled(x, numbers::Vector{String}, next::Ref{Int})
    if x isa AbstractDict
        out = OrderedDict{Symbol,Any}()
        for (k, v) in x
            out[Symbol(k)] = _spelled(v, numbers, next)
        end
        return out
    elseif x isa AbstractVector
        return Any[_spelled(v, numbers, next) for v in x]
    elseif x isa Number && !(x isa Bool)
        next[] += 1
        next[] <= length(numbers) ||
            error("internal: the \"acset\" body has more numbers than its text")
        return numbers[next[]]
    end
    return x
end

# A JSON integer literal, `-?(0|[1-9][0-9]*)`: no fraction, no exponent, no `+` and no
# leading zero, the rule of the Lean decoder's documentation ("written without a fraction
# or exponent"). The decoder itself reads a parsed tree, where an integer is a `Json.num`
# with exponent `0`; `Lean.Json.parse`, which is trusted, also gives exponent `0` to `1e0`,
# `1E+0`, `1e-0` and `1.0e1`, so the Lean pipeline from text accepts those spellings, and
# this reader does not.
_is_integer_literal(s) = s isa AbstractString && occursin(r"^-?(0|[1-9][0-9]*)$", s)
function _decode_ref(x, what)
    return _decoding(() -> _kernel_ref_from(x), Union{ArgumentError,_SHAPE_ERRORS}, what)
end
function _decode_time(t, what)
    t isa AbstractString ||
        throw(FormatError("$what: time must be a string, got $(_json_kind(t))"))
    return _decoding(() -> DateTime(t), ArgumentError, "$what: time $(repr(t))")
end

# FiniteKernels' exception types, which a kernel record reaches through `FiniteAxis`,
# `FiniteSpace` and `FiniteKernel`.
const _FINITE_KERNELS_ERRORS = Union{FiniteKernels.InvalidAxisError,
                                     FiniteKernels.KernelShapeError,
                                     FiniteKernels.KernelEntryError,
                                     FiniteKernels.KernelNormalizationError,
                                     FiniteKernels.SpaceMismatchError}

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
ACSet `type`.

# Throws

[`FormatError`](@ref) (ADR 0015), whose message names the table, row and column at
fault:

- if `str` is not JSON, or the envelope is missing or names another format or schema
  version;
- if the `"acset"` body does not have exactly one table per object and attribute type of
  the schema of `type` (a missing `"Input"` or `"Label"` table is an error, not an empty
  one), or an attribute-type table is not empty;
- if a row does not have exactly the columns of its table (`"_id"`, the homs and the
  attributes; a missing `state_position` or `kernel_ref` is an error, not an unset
  attribute), or a value has the wrong JSON type or range: an `"_id"` other than the row
  number, a hom that is not the ID of a row of its codomain, a position that is not an
  integer `>= 1`, a label that is not a string, or a `Ref` that is not a
  [`KernelRef`](@ref) object with exactly its type's keys. An `"_id"`, hom or position
  must be written as a JSON integer literal: `1`, not `1.0`, `1e0` or `01`.

These are the rules of the proved Lean decoder
(`proofs/BayesianNetworksProofs/Finite/JsonRecords.lean`). A document that passes them can
still describe an invalid network, such as a cycle or repeated input positions:
[`validate`](@ref) reports those.
"""
function parse_json_bayesnet(str::AbstractString; type::Type{<:AbstractBayesNet}=BayesNet)
    return _parse_envelope(_read_json(str), str, type)
end

# `obj` is `_read_json(str)`; `str` gives the spellings of the numbers of its `"acset"`
# body.
function _parse_envelope(obj, str, type)
    _check_envelope(obj, (:format, :schema_version, :acset))
    return _parse_acset(type, obj[:acset], _json_number_spellings(str)[:acset])
end

function _check_envelope(obj, keys)
    obj isa AbstractDict || throw(FormatError("expected a JSON object envelope"))
    for key in keys
        haskey(obj, key) || throw(FormatError("envelope is missing the \"$key\" key"))
    end
    obj[:format] == JSON_FORMAT ||
        throw(FormatError("format is \"$(obj[:format])\", expected \"$JSON_FORMAT\""))
    obj[:schema_version] == JSON_SCHEMA_VERSION ||
        throw(FormatError("schema_version is \"$(obj[:schema_version])\", expected \"$JSON_SCHEMA_VERSION\""))
    return nothing
end

# The `"acset"` body: checked against the schema of `type` (`_check_acset_body`), then read
# by ACSets' `parse_json_acset`; `spellings` is `_json_number_spellings(str)[:acset]` of the
# document, or the body with each number replaced by its spelling. See "Decoding failures":
# the one scoped catch-all of the decoders, because the parser is third-party and reads only
# the document, so what it raises is about the document (ADR 0015).
function _parse_acset(type, body, spellings)
    body isa AbstractDict ||
        throw(FormatError("the \"acset\" body must be an object, got $(_json_kind(body))"))
    spelled = spellings isa _NumberSpellings ? _spelled_body(body, spellings) : spellings
    _check_acset_body(type, body, spelled)
    try
        return parse_json_acset(type, body)
    catch e
        e isa InterruptException && rethrow()
        throw(FormatError("the \"acset\" body is not a valid $(nameof(type)): " *
                          _decoding_message(e)))
    end
end

# The shape of an `"acset"` body, checked before ACSets' parser reads it, with the rules of
# the proved Lean decoders (`ColumnKind`, `Shape` and `decodeBody` in
# `proofs/BayesianNetworksProofs/Finite/JsonRecords.lean`; `idColumns` and
# `decodeDiagramBody` in InfluenceDiagrams.jl's `Finite/DVE/JsonRecords.lean`). The tables
# and columns come from the schema of `type`, so an influence diagram is checked against
# `SchInfluenceDiagram` by the same code:
#
# - the body has exactly one key per object and per attribute type of the schema;
# - an attribute-type table (`Label`, `Position`, `Ref`) is empty: `generate_json_acset`
#   writes one row per attribute variable, and the writers store none;
# - an object table is an array of objects, and its row `k` has exactly the columns
#   `"_id"`, the homs out of the object and the attributes on it;
# - `"_id"` is `k`; a hom is the ID of a row of its codomain table; a `Position` is an
#   integer `>= 1`; a `Label` is a string; a `Ref` is a `KernelRef` object with exactly
#   the keys of its type, each a string;
# - an `"_id"`, hom or `Position` is written as an integer literal (`_is_integer_literal`):
#   JSON3 reads `1.0` and `1e0` as the `Int64` 1, so the check reads the number's spelling
#   in `spellings`, the body with its numbers' spellings (`_spelled_body`);
# - no table appears twice and no row repeats a column: `_read_json` rejects a repeated key
#   in any object of the document.
#
# Unchecked, ACSets' parser read a missing table as zero rows, a missing attribute as unset
# and a number as a label (`Symbol("5")`), and accepted a `null` attribute.

# The kind of a column of each attribute type, as the Lean decoder's `ColumnKind`; `"_id"`
# is `:id` and a hom is `:hom`.
const _ATTRTYPE_COLUMN_KINDS = (Label=:label, Position=:position, Ref=:ref)

function _attrtype_column_kind(T::Symbol)
    haskey(_ATTRTYPE_COLUMN_KINDS, T) && return _ATTRTYPE_COLUMN_KINDS[T]
    throw(ArgumentError("the JSON reader has no column kind for the attribute type $T"))
end

# The columns of the rows of object `ob` of schema `S`, in schema order: name => (kind,
# codomain).
function _json_columns(S, ob::Symbol)
    cols = OrderedDict{Symbol,Tuple{Symbol,Symbol}}(:_id => (:id, ob))
    for (f, d, c) in homs(S)
        d == ob && (cols[f] = (:hom, c))
    end
    for (f, d, c) in attrs(S)
        d == ob && (cols[f] = (_attrtype_column_kind(c), c))
    end
    return cols
end

# Keys and values of a decoded JSON object, whose keys are Symbols (JSON3) or Strings.
_json_keys(d) = Symbol[Symbol(k) for k in keys(d)]
_json_get(d, k::Symbol) = haskey(d, k) ? d[k] : d[String(k)]
_json_integer(v) = v isa Integer && !(v isa Bool)

function _check_acset_body(type, body, spellings)
    S = acset_schema(type())
    function fail(msg)
        throw(FormatError("the \"acset\" body is not a valid $(nameof(type)): $msg"))
    end
    obs, ats = collect(objects(S)), collect(attrtypes(S))
    tables = vcat(obs, ats)
    present = _json_keys(body)
    for T in tables
        T in present || fail("missing the table \"$T\"")
    end
    for k in present
        k in tables || fail("unknown table \"$k\"")
    end
    for T in tables
        rows = _json_get(body, T)
        rows isa AbstractVector ||
            fail("the table \"$T\" must be an array, got $(_json_kind(rows))")
    end
    for T in ats
        n = length(_json_get(body, T))
        n == 0 || fail("the attribute table \"$T\" must be empty, got " *
                       (n == 1 ? "1 row" : "$n rows") * " (attribute variables are not read)")
    end
    nrows = Dict{Symbol,Int}(T => length(_json_get(body, T)) for T in obs)
    for T in obs
        cols = _json_columns(S, T)
        spelled_rows = _json_get(spellings, T)
        for (k, row) in enumerate(_json_get(body, T))
            row isa AbstractDict ||
                fail("$T row $k must be an object, got $(_json_kind(row))")
            keys_k = _json_keys(row)
            for c in keys(cols)
                c in keys_k || fail("$T row $k: missing the column \"$c\"")
            end
            for c in keys_k
                haskey(cols, c) || fail("$T row $k: unknown column \"$c\"")
            end
            spelled_row = spelled_rows[k]
            for (c, (kind, codom)) in cols
                v, spelling = _json_get(row, c), _json_get(spelled_row, c)
                problem = _column_problem(v, spelling, kind, codom, k, nrows)
                problem === nothing || fail("$T row $k: column \"$c\" $problem")
            end
        end
    end
    return nothing
end

# What is wrong with the value `v` of a column of kind `kind` in row `k`, or `nothing`;
# `spelling` is the value in `_json_number_spellings`, the source text of a number.
function _column_problem(v, spelling, kind::Symbol, codom::Symbol, k::Int, nrows)
    if kind in (:id, :hom, :position)
        int = _json_integer(v) && _is_integer_literal(spelling)
        got = v isa Number && !(v isa Bool) ? "the number $spelling" : _json_kind(v)
        if kind === :id
            int && v == k && return nothing
            return "must be the row number $k, an integer literal, got $got"
        elseif kind === :hom
            n = nrows[codom]
            int && 1 <= v <= n && return nothing
            return "must be the ID of a \"$codom\" row, an integer literal in 1:$n, got $got"
        else
            int && 1 <= v <= typemax(Int) && return nothing
            return "must be a one-based position, an integer literal in 1:$(typemax(Int)), " *
                   "got $got"
        end
    elseif kind === :label
        v isa AbstractString && return nothing
        return "must be a string, got $(_json_kind(v))"
    else
        return _kernel_ref_problem(v)
    end
end

# A `KernelRef` object as `StructTypes.lower` writes it: a string `"type"` naming one of
# `_KERNEL_REF_TYPES`, and one string per field of that type, with no other key (the Lean
# decoder's `decodeRef`).
function _kernel_ref_problem(v)
    v isa AbstractDict || return "must be a KernelRef object, got $(_json_kind(v))"
    ks = _json_keys(v)
    :type in ks || return "must be a KernelRef object with a \"type\" key"
    ty = _json_get(v, :type)
    ty isa AbstractString ||
        return "must be a KernelRef object whose \"type\" is a string, got $(_json_kind(ty))"
    T = get(_KERNEL_REF_TYPES, Symbol(ty), nothing)
    T === nothing && return "has the unknown KernelRef type \"$ty\""
    expected = (:type, fieldnames(T)...)
    Set(ks) == Set(expected) && length(ks) == length(expected) ||
        return "must be a $ty object with exactly the keys " *
               join(("\"$f\"" for f in expected), ", ") * ", got " *
               join(("\"$f\"" for f in ks), ", ")
    for f in fieldnames(T)
        x = _json_get(v, f)
        x isa AbstractString ||
            return "must be a $ty whose \"$f\" is a string, got $(_json_kind(x))"
    end
    return nothing
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

# Throws

[`FormatError`](@ref) for a document that [`parse_json_bayesnet`](@ref) rejects: text
that is not JSON, a wrong envelope, or an `"acset"` body with a missing or unknown table
or column or a value of the wrong JSON type or range; the message names the table, row
and column. A missing file is Base's `SystemError`.
"""
function read_json_bayesnet(path::AbstractString; type::Type{<:AbstractBayesNet}=BayesNet)
    str = read(path, String)
    return _parse_envelope(_read_json(str), str, type)
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

function _parse_provenance(p, what)
    str(k) = _as_string(_ref_field(p, k), k)
    source_type = _as_symbol(_ref_field(p, :source_type), :source_type)
    source_type in SOURCE_TYPES ||
        throw(FormatError("$what: source_type :$source_type is not one of $(SOURCE_TYPES)"))
    ts = _ref_field(p, :timestamp)
    return ParameterProvenance(; source_type, citation=str(:citation),
                               dataset=str(:dataset),
                               estimator=str(:estimator), expert=str(:expert),
                               timestamp=ts === nothing ? nothing : _decode_time(ts, what),
                               notes=str(:notes))
end

# The `"card"` section; the caller reports a missing key or a value of the wrong JSON type
# as a `FormatError`.
function _parse_card(c)
    str(k) = _as_string(_ref_field(c, k), k)
    sym(k) = _as_symbol(_ref_field(c, k), k)
    object(k) = _as_object(_ref_field(c, k), k)
    return ModelCard(; name=sym(:name), model_version=str(:model_version),
                     schema_version=str(:schema_version),
                     decision_context=str(:decision_context), endpoint=str(:endpoint),
                     spatial_extent=str(:spatial_extent),
                     temporal_extent=str(:temporal_extent),
                     graph_rationale=str(:graph_rationale),
                     alternative_structures=_as_strings(_ref_field(c,
                                                                   :alternative_structures),
                                                        :alternative_structures),
                     variables=_as_symbols(_ref_field(c, :variables), :variables),
                     states=Dict{Symbol,Vector{Symbol}}(Symbol(x) => _as_symbols(st,
                                                                                 "states.$x")
                                                        for (x, st) in object(:states)),
                     state_definitions=Dict{Symbol,String}(Symbol(x) => _as_string(t,
                                                                                   "state_definitions.$x")
                                                           for (x, t) in
                                                               object(:state_definitions)),
                     mechanisms=_as_symbols(_ref_field(c, :mechanisms), :mechanisms),
                     kernel_refs=Dict{Symbol,KernelRef}(Symbol(k) => _decode_ref(r,
                                                                                 "the card, kernel_refs entry $k")
                                                        for (k, r) in object(:kernel_refs)),
                     provenance=Dict{Symbol,ParameterProvenance}(Symbol(k) => _parse_provenance(p,
                                                                                                "the card, provenance of $k")
                                                                 for (k, p) in
                                                                     object(:provenance)),
                     elicitation_protocol=str(:elicitation_protocol),
                     validation_summary=str(:validation_summary),
                     validation_scores=Dict{Symbol,Float64}(Symbol(k) => _as_float(v,
                                                                                   "validation_scores.$k")
                                                            for (k, v) in
                                                                object(:validation_scores)),
                     intended_use=str(:intended_use), limitations=str(:limitations),
                     license=str(:license),
                     history=ModelEvent[_parse_event(e, "the card, history record $i")
                                        for (i, e) in
                                            enumerate(_as_array(_ref_field(c, :history),
                                                                :history))])
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
[`parse_json_bayesnet`](@ref), schema version included. Text that is not JSON, and a card
with a missing key, a JSON value of the wrong type, an unknown [`KernelRef`](@ref) type,
an unparsable time or a provenance `source_type` outside [`SOURCE_TYPES`](@ref), raise
[`FormatError`](@ref) (ADR 0015).
"""
function parse_json_card(str::AbstractString)
    obj = _read_json(str)
    _check_envelope(obj, (:format, :schema_version))
    haskey(obj, :card) || return nothing
    return _decoding(() -> _parse_card(obj[:card]), _SHAPE_ERRORS, "the card")
end

"""
    read_json_card(path) -> Union{ModelCard, Nothing}

The [`ModelCard`](@ref) stored in the file at `path`, or `nothing` when it has no
`"card"` section. Companion of [`read_json_model`](@ref), which reads the model from the
same file. Errors as for [`parse_json_card`](@ref).
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
    return FiniteAxis(_as_symbol(_ref_field(a, :name), :name),
                      _as_symbols(_ref_field(a, :labels), :labels))
end
_parse_space(v, key) = FiniteSpace(FiniteAxis[_parse_axis(a) for a in _as_array(v, key)])

function _parse_record(r, what)
    r === nothing && return nothing
    return MechanismRecord(_as_symbol(_ref_field(r, :name), :name),
                           _decode_ref(_ref_field(r, :kernel_ref), what),
                           _as_symbols(_ref_field(r, :inputs), :inputs))
end

# One history record, which `what` names in the `FormatError` of a record that cannot be
# decoded.
function _parse_event(e, what)
    return _decoding(_SHAPE_ERRORS, what) do
        return ModelEvent(_as_symbol(_ref_field(e, :kind), :kind),
                          _as_symbol(_ref_field(e, :target), :target),
                          _parse_record(_ref_field(e, :removed), what),
                          _parse_record(_ref_field(e, :added), what),
                          _as_string(_ref_field(e, :note), :note),
                          _decode_time(_ref_field(e, :time), what))
    end
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

A document that cannot be decoded raises [`FormatError`](@ref) too: text that is not
JSON; a kernel or history record with a missing key or an unknown [`KernelRef`](@ref)
type; a history record whose time does not parse; and a kernel record whose table does
not have the length its `"size"` gives, does not fit its spaces or has an entry that is
not a probability; a JSON value of the wrong type anywhere in the document; and an
`"acset"` body that [`parse_json_bayesnet`](@ref) rejects, such as one with a missing
table or column (ADR 0015). A
`BayesNetError` raised while the model is built, such as
[`UnknownStateError`](@ref) for evidence on a state the variable does not have, passes
through unchanged.
"""
function parse_json_model(str::AbstractString; type::Type{<:AbstractBayesNet}=BayesNet,
                          atol::Real=DEFAULT_ATOL)
    obj = _read_json(str)
    bn = _parse_envelope(obj, str, type)
    spaces = syntax_spaces(bn)
    kernels = Dict{KernelRef,FiniteKernel}()
    if haskey(obj, :semantics)
        sem = _decoding(() -> _as_object(obj[:semantics], :semantics), _JSONShapeError,
                        "the model document")
        _decoding(Union{_SHAPE_ERRORS,_FINITE_KERNELS_ERRORS}, "semantics.spaces") do
            for (x, labels) in _as_object(get(sem, :spaces, Dict()), :spaces)
                spaces[Symbol(x)] = FiniteSpace(Symbol(x), _as_symbols(labels, x))
            end
        end
        records = _decoding(() -> _as_array(get(sem, :kernels, []), :kernels),
                            _JSONShapeError, "the model document")
        for (i, k) in enumerate(records)
            ref = _decoding(() -> _decode_ref(_ref_field(k, :ref), "kernel record $i"),
                            _SHAPE_ERRORS, "kernel record $i")
            kernels[ref] = _decoding(Union{_SHAPE_ERRORS,_FINITE_KERNELS_ERRORS},
                                     "the kernel $(ref)") do
                dom, codom = _parse_space(k[:dom], :dom), _parse_space(k[:codom], :codom)
                values = Float64[_as_float(v, :table) for v in _as_array(k[:table], :table)]
                dims = Int[_as_int(d, :size) for d in _as_array(k[:size], :size)]
                all(>=(0), dims) ||
                    throw(_JSONShapeError("size", "an array of nonnegative integers",
                                          k[:size]))
                # The product is taken in BigInt: in Int it can wrap around to the length.
                prod(big, dims; init=big(1)) == length(values) ||
                    throw(_JSONShapeError("size",
                                          "an array of sizes whose product is the " *
                                          "length of \"table\" ($(length(values)))",
                                          k[:size]))
                table = reshape(values, Tuple(dims))
                try
                    return FiniteKernel(dom, codom, table; atol=atol)
                catch e
                    e isa FiniteKernels.KernelNormalizationError || rethrow()
                    throw(FormatError("the kernel $(ref) is not normalised within " *
                                      "atol=$(atol) (largest row-mass deviation " *
                                      "$(e.max_deviation)); pass the atol the model was " *
                                      "bound with"))
                end
            end
        end
    end
    evidence, events, extras = _decoding(_JSONShapeError, "the model document") do
        ev = Dict{Symbol,Symbol}(Symbol(k) => _as_symbol(v, "evidence.$k")
                                 for (k, v) in _as_object(get(obj, :evidence, Dict()),
                                                          :evidence))
        return ev, _as_array(get(obj, :history, []), :history),
               _from_json_extras(_as_object(get(obj, :extras, Dict()), :extras))
    end
    history = ModelEvent[_parse_event(e, "history record $i")
                         for (i, e) in enumerate(events)]
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
[`parse_json_model`](@ref) and must match the tolerance the model was bound with. Errors
as for [`parse_json_model`](@ref).
"""
function read_json_model(path::AbstractString; type::Type{<:AbstractBayesNet}=BayesNet,
                         atol::Real=DEFAULT_ATOL)
    return parse_json_model(read(path, String); type=type, atol=atol)
end
