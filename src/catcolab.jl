"""
Export to CatColab (SPEC §48; plan "CatColab path"). CatColab does not yet have a
Bayesian-network theory, so these functions are export-only: they write the ACSet
schema as a model of CatColab's `simple-schema` theory (objects typed `Entity` or
`AttrType`, morphisms typed `Hom(Entity)` or `Attr`), a network as a diagram in that
model (one object generator per part, one morphism generator per hom value, attribute
values as labels), and a model's presentation as the generator list of a free Markov
category (`markov-presentation/0.1`). Identifiers are UUID v5 names derived from a fixed
namespace, so the same input always produces the same document.

Document shapes follow CatColab's `notebook-types` v1: a document is
`{"type", "name", "theory" | "diagramIn", "version": "1", "notebook": {"cellContents",
"cellOrder"}}` and a formal cell is `{"tag": "formal", "id", "content": judgment}` with
the judgments of `model_judgment.rs` / `diagram_judgment.rs`. The catlog-side
`Model{obGenerators, morGenerators}` shape read by CatColab's Julia interop
(`CatlabExt.model_to_schema`) is available as [`catcolab_model`](@ref).
"""

"""
    CATCOLAB_NAMESPACE

The UUID v5 namespace of every identifier written by the CatColab exporters
(`uuid5(namespace_url, "https://github.com/ecorecipes/BayesianNetworks.jl")`).
"""
const CATCOLAB_NAMESPACE = UUID("18bfd1b6-dbbf-57db-b67c-f7bffe246837")

"""
    catcolab_uuid(parts...) -> String

The deterministic identifier of a generator or cell: UUID v5 of `join(parts, "/")` in
[`CATCOLAB_NAMESPACE`](@ref).
"""
catcolab_uuid(parts...) = string(uuid5(CATCOLAB_NAMESPACE, join(string.(parts), "/")))

_basic(content) = OrderedDict{String,Any}("tag" => "Basic", "content" => content)
_hom_type(ob) = OrderedDict{String,Any}("tag" => "Hom", "content" => _basic(ob))

# The generators of the schema of ACSet type `T` (or of a presentation) as
# `(name, kind, dom, cod)` tuples, kind in `:ob`, `:attrtype`, `:hom`, `:attr`.
function _schema_generators(S::BasicSchema)
    gens = Tuple{Symbol,Symbol,Union{Nothing,Symbol},Union{Nothing,Symbol}}[]
    for o in objects(S)
        push!(gens, (o, :ob, nothing, nothing))
    end
    for a in attrtypes(S)
        push!(gens, (a, :attrtype, nothing, nothing))
    end
    for (f, d, c) in homs(S)
        push!(gens, (f, :hom, d, c))
    end
    for (f, d, c) in attrs(S)
        push!(gens, (f, :attr, d, c))
    end
    return gens
end
function _schema_generators(::Type{T}) where {T<:AbstractVariableSpace}
    return _schema_generators(acset_schema(T()))
end

# A presentation goes through ACSets' JSON description, which is what `schema_json`
# already produces for it.
function _schema_generators(pres::Presentation)
    sj = schema_json(pres)
    gens = Tuple{Symbol,Symbol,Union{Nothing,Symbol},Union{Nothing,Symbol}}[]
    for o in sj["Ob"]
        push!(gens, (Symbol(o["name"]), :ob, nothing, nothing))
    end
    for a in sj["AttrType"]
        push!(gens, (Symbol(a["name"]), :attrtype, nothing, nothing))
    end
    for f in sj["Hom"]
        push!(gens, (Symbol(f["name"]), :hom, Symbol(f["dom"]), Symbol(f["codom"])))
    end
    for f in sj["Attr"]
        push!(gens, (Symbol(f["name"]), :attr, Symbol(f["dom"]), Symbol(f["codom"])))
    end
    return gens
end

_ob_type(kind::Symbol) = _basic(kind == :ob ? "Entity" : "AttrType")

function _mor_type(kind::Symbol, obkinds::AbstractDict{Symbol,Symbol}, dom::Symbol)
    kind == :attr && return _basic("Attr")
    return _hom_type(obkinds[dom] == :ob ? "Entity" : "AttrType")
end

"""
    catcolab_model(T::Type{<:AbstractVariableSpace}; name = "SchBayesNet") -> OrderedDict
    catcolab_model(pres::Presentation; name)

The schema of ACSet type `T` (or the schema presentation `pres`) in the shape that
CatColab's Julia interop parses as a `Model`: `"obGenerators"`, a list of
`{"id", "label": [name], "obType"}` with `obType` `Entity` for objects and `AttrType`
for attribute types, and `"morGenerators"`, a list of
`{"id", "label", "morType", "dom", "cod"}` with `morType` `Hom(Entity)` for homs and
`Attr` for attributes and `dom` / `cod` referring to object ids. Identifiers come from
[`catcolab_uuid`](@ref)`(name, kind, generator)`. Export-only; CatColab does not yet
have a Bayesian-network theory.
"""
function catcolab_model(schema; name::AbstractString="SchBayesNet")
    gens = _schema_generators(schema)
    obkinds = Dict{Symbol,Symbol}(g[1] => g[2] for g in gens if g[2] in (:ob, :attrtype))
    ids = Dict{Symbol,String}(g[1] => catcolab_uuid(name,
                                                    g[2] in (:ob, :attrtype) ? "ob" : "mor",
                                                    g[1]) for g in gens)
    obs = Any[]
    mors = Any[]
    for (g, kind, d, c) in gens
        if kind in (:ob, :attrtype)
            push!(obs,
                  OrderedDict{String,Any}("id" => ids[g], "label" => [string(g)],
                                          "obType" => _ob_type(kind)))
        else
            push!(mors,
                  OrderedDict{String,Any}("id" => ids[g], "label" => [string(g)],
                                          "morType" => _mor_type(kind, obkinds, d),
                                          "dom" => _basic(ids[d]), "cod" => _basic(ids[c])))
        end
    end
    return OrderedDict{String,Any}("obGenerators" => obs, "morGenerators" => mors)
end

function _formal_cell(name::AbstractString, kind::AbstractString, gen::AbstractString,
                      content)
    id = catcolab_uuid(name, "cell", kind, gen)
    return id => OrderedDict{String,Any}("tag" => "formal", "id" => id,
                                         "content" => content)
end

function _document(type::AbstractString, name::AbstractString, cells; extra...)
    contents = OrderedDict{String,Any}()
    order = String[]
    for (id, cell) in cells
        contents[id] = cell
        push!(order, id)
    end
    doc = OrderedDict{String,Any}("type" => type, "name" => String(name))
    for (k, v) in extra
        doc[string(k)] = v
    end
    doc["version"] = "1"
    doc["notebook"] = OrderedDict{String,Any}("cellContents" => contents,
                                              "cellOrder" => order)
    return doc
end

"""
    catcolab_schema_document(T::Type{<:AbstractVariableSpace}; name = "SchBayesNet") -> OrderedDict
    catcolab_schema_document(pres::Presentation; name)

The schema of ACSet type `T` as a CatColab model document of the `simple-schema`
theory: `{"type": "model", "name", "theory": "simple-schema", "version": "1",
"notebook": {"cellContents", "cellOrder"}}` with one formal cell per generator, in the
order objects, attribute types, homs, attributes. An object cell's content is
`{"tag": "object", "name", "id", "obType": {"tag": "Basic", "content": "Entity" |
"AttrType"}}` and a morphism cell's content
`{"tag": "morphism", "name", "id", "morType", "dom", "cod"}` with `morType`
`{"tag": "Hom", "content": {"tag": "Basic", "content": "Entity"}}` for homs and
`{"tag": "Basic", "content": "Attr"}` for attributes, and `dom` / `cod`
`{"tag": "Basic", "content": id}`. Identifiers are deterministic
([`catcolab_uuid`](@ref)). Serialise with `JSON3.write`; read back with
[`parse_catcolab_schema`](@ref). Export-only; CatColab does not yet have a
Bayesian-network theory.

# Example

```jldoctest
julia> doc = catcolab_schema_document(BayesNet);

julia> doc["theory"], length(doc["notebook"]["cellOrder"])
("simple-schema", 18)

julia> parse_catcolab_schema(doc) == BayesianNetworks.acset_schema(BayesNet())
true
```
"""
function catcolab_schema_document(schema; name::AbstractString="SchBayesNet")
    model = catcolab_model(schema; name=name)
    cells = Pair{String,Any}[]
    for ob in model["obGenerators"]
        content = OrderedDict{String,Any}("tag" => "object", "name" => only(ob["label"]),
                                          "id" => ob["id"], "obType" => ob["obType"])
        push!(cells, _formal_cell(name, "object", only(ob["label"]), content))
    end
    for mor in model["morGenerators"]
        content = OrderedDict{String,Any}("tag" => "morphism",
                                          "name" => only(mor["label"]), "id" => mor["id"],
                                          "morType" => mor["morType"], "dom" => mor["dom"],
                                          "cod" => mor["cod"])
        push!(cells, _formal_cell(name, "morphism", only(mor["label"]), content))
    end
    return _document("model", name, cells; theory="simple-schema")
end

# Reading documents back
########################

_field(x, key::AbstractString) = haskey(x, key) ? x[key] : x[Symbol(key)]
_hasfield(x, key::AbstractString) = haskey(x, key) || haskey(x, Symbol(key))

_as_document(doc::AbstractString) = JSON3.read(doc)
_as_document(doc) = doc

# The formal judgments of a document, in cell order.
function _judgments(doc)
    nb = _field(doc, "notebook")
    contents, order = _field(nb, "cellContents"), _field(nb, "cellOrder")
    out = Any[]
    for id in order
        cell = _field(contents, string(id))
        String(_field(cell, "tag")) == "formal" || continue
        push!(out, _field(cell, "content"))
    end
    return out
end

# The generators of a schema document or `catcolab_model` shape as
# `(id, label, kind, dom_id, cod_id)`.
function _generators(doc)
    doc = _as_document(doc)
    if _hasfield(doc, "obGenerators")
        obs = [(String(_field(o, "id")), String(only(_field(o, "label"))),
                String(_field(_field(o, "obType"), "content")), nothing, nothing)
               for o in _field(doc, "obGenerators")]
        mors = [(String(_field(m, "id")), String(only(_field(m, "label"))),
                 _mor_kind(_field(m, "morType")),
                 String(_field(_field(m, "dom"), "content")),
                 String(_field(_field(m, "cod"), "content")))
                for m in _field(doc, "morGenerators")]
        return vcat(obs, mors)
    end
    _hasfield(doc, "notebook") ||
        throw(FormatError("expected a CatColab model document or a Model{obGenerators, morGenerators}"))
    String(_field(doc, "type")) == "model" ||
        throw(FormatError("expected a CatColab document of type \"model\", got \"$(_field(doc, "type"))\""))
    gens = Any[]
    for j in _judgments(doc)
        tag = String(_field(j, "tag"))
        if tag == "object"
            push!(gens,
                  (String(_field(j, "id")), String(_field(j, "name")),
                   String(_field(_field(j, "obType"), "content")), nothing, nothing))
        elseif tag == "morphism"
            push!(gens,
                  (String(_field(j, "id")), String(_field(j, "name")),
                   _mor_kind(_field(j, "morType")),
                   String(_field(_field(j, "dom"), "content")),
                   String(_field(_field(j, "cod"), "content"))))
        else
            throw(FormatError("unsupported model judgment \"$tag\""))
        end
    end
    return gens
end

function _mor_kind(mt)
    tag = String(_field(mt, "tag"))
    tag == "Basic" && return String(_field(mt, "content"))
    tag == "Hom" && return "Hom"
    return throw(FormatError("unsupported morphism type tag \"$tag\""))
end

"""
    parse_catcolab_schema(doc) -> BasicSchema{Symbol}

Read a `simple-schema` model document (or the `Model{obGenerators, morGenerators}`
shape, or their JSON text) back into an ACSets `BasicSchema`, mirroring
`CatlabExt.model_to_schema` in CatColab: `Entity` objects become objects, `AttrType`
objects attribute types, `Attr` morphisms attributes and every other morphism a hom.
Inverse of [`catcolab_schema_document`](@ref) and [`catcolab_model`](@ref); a document
of another shape is a [`FormatError`](@ref).
"""
function parse_catcolab_schema(doc)
    names = Dict{String,Symbol}()
    obs, attrtypes_, homs_, attrs_ = Symbol[], Symbol[], Tuple{Symbol,Symbol,Symbol}[],
                                     Tuple{Symbol,Symbol,Symbol}[]
    for (id, label, kind, d, c) in _generators(doc)
        names[id] = Symbol(label)
        if d === nothing
            if kind == "Entity"
                push!(obs, names[id])
            elseif kind == "AttrType"
                push!(attrtypes_, names[id])
            else
                throw(FormatError("unsupported object type \"$kind\""))
            end
        else
            (haskey(names, d) && haskey(names, c)) ||
                throw(FormatError("morphism $label refers to an unknown object"))
            entry = (names[id], names[d], names[c])
            kind == "Attr" ? push!(attrs_, entry) : push!(homs_, entry)
        end
    end
    return BasicSchema{Symbol}(obs, homs_, attrtypes_, attrs_, [])
end

# Instances
###########

# Identifiers of the objects and morphisms of a schema document, by name.
function _schema_ids(doc)
    ids = Dict{Symbol,String}()
    for (id, label, _, _, _) in _generators(doc)
        ids[Symbol(label)] = id
    end
    return ids
end

# A readable label for part `p` of object `ob`, unique within the network for valid
# networks with unique names.
function _part_label(bn::AbstractBayesNet, ob::Symbol, p::Int)
    ob == :Variable && return string(variable_name(bn, p))
    ob == :State &&
        return string(variable_name(bn, subpart(bn, p, :state_variable)), ".",
                      subpart(bn, p, :state_name))
    ob == :Mechanism && return string(mechanism_name(bn, p))
    ob == :Input &&
        return string(mechanism_name(bn, subpart(bn, p, :input_mechanism)), ".",
                      subpart(bn, p, :input_position))
    return string(ob, p)
end

"""
    catcolab_instance_document(bn, schema_doc; name = "BayesNet instance") -> OrderedDict

A network as a CatColab diagram document in the model `schema_doc` (the output of
[`catcolab_schema_document`](@ref) for the network's schema): `{"type": "diagram",
"name", "diagramIn": link, "version": "1", "notebook"}` with one object cell per part,
`{"tag": "object", "name": label, "id", "obType": Entity, "over": {"tag": "Basic",
"content": object id}}`, and one morphism cell per hom value, `{"tag": "morphism",
"name": "", "id", "morType": Hom(Entity), "over": hom id, "dom": part id, "cod": part
id}`. Labels are the variable, `Variable.state`, mechanism and `Mechanism.position`
names, which is how attribute values travel (CatColab diagrams carry no attribute
columns). `diagramIn` links the model by a deterministic `_id`; replace it with the id
CatColab assigned to the uploaded schema document. Export-only.
"""
function catcolab_instance_document(bn::AbstractBayesNet, schema_doc;
                                    name::AbstractString="BayesNet instance")
    validate(bn; unique_names=true)
    schema_doc = _as_document(schema_doc)
    ids = _schema_ids(schema_doc)
    S = acset_schema(bn)
    for o in objects(S)
        haskey(ids, o) || throw(FormatError("the schema document has no object $o"))
    end
    part_ids = Dict{Tuple{Symbol,Int},String}()
    cells = Pair{String,Any}[]
    for ob in objects(S), p in parts(bn, ob)
        label = _part_label(bn, ob, p)
        id = catcolab_uuid(name, "part", ob, p)
        part_ids[(ob, p)] = id
        content = OrderedDict{String,Any}("tag" => "object", "name" => label, "id" => id,
                                          "obType" => _basic("Entity"),
                                          "over" => _basic(ids[ob]))
        push!(cells, _formal_cell(name, "object", "$ob/$p", content))
    end
    for (f, d, c) in homs(S)
        haskey(ids, f) || throw(FormatError("the schema document has no morphism $f"))
        for p in parts(bn, d)
            q = subpart(bn, p, f)
            id = catcolab_uuid(name, "hom", f, p)
            content = OrderedDict{String,Any}("tag" => "morphism", "name" => "", "id" => id,
                                              "morType" => _hom_type("Entity"),
                                              "over" => _basic(ids[f]),
                                              "dom" => _basic(part_ids[(d, p)]),
                                              "cod" => _basic(part_ids[(c, q)]))
            push!(cells, _formal_cell(name, "morphism", "$f/$p", content))
        end
    end
    link = OrderedDict{String,Any}("_id" => catcolab_uuid(String(_field(schema_doc, "name")),
                                                          "document"),
                                   "_version" => nothing, "_server" => nothing,
                                   "type" => "diagram-in")
    return _document("diagram", name, cells; diagramIn=link)
end

# Markov presentations
######################

const PRESENTATION_FORMAT = "markov-presentation/0.1"

"""
    presentation_json(m::BayesModel) -> String
    presentation_json(bn::AbstractBayesNet) -> String

The generators of the free Markov-category presentation of a network as JSON:
`{"format": "markov-presentation/0.1", "objects": [{"name", "states"}], "generators":
[{"name", "dom": [object names], "cod": [target], "kernel_ref"}]}`, one object per
variable (in part order) and one generator per mechanism with its inputs in
`input_position` order and its [`KernelRef`](@ref) in the JSON form of
[`json_bayesnet`](@ref). This is the generator list behind
`CategoricalBayesianNetworks.to_free_expression` and the input for a future Bayesian-network theory in
CatColab. Inverse: [`parse_presentation_json`](@ref).
"""
function presentation_json(bn::AbstractBayesNet)
    objs = [(name=string(variable_name(bn, v)), states=string.(states(bn, v)))
            for v in variables(bn)]
    gens = [(name=string(mechanism_name(bn, mech)),
             dom=[string(variable_name(bn, p)) for p in inputs(bn, mech)],
             cod=[string(variable_name(bn, target(bn, mech)))],
             kernel_ref=StructTypes.lower(kernel_ref(bn, mech)))
            for mech in mechanisms(bn)]
    return JSON3.write((format=PRESENTATION_FORMAT, objects=objs, generators=gens))
end
presentation_json(m::BayesModel) = presentation_json(syntax(m))

"""
    parse_presentation_json(str) -> BayesNet

Read a network from the JSON written by [`presentation_json`](@ref): one variable per
object and one mechanism per generator (a generator must have exactly one codomain
object). A wrong `"format"` is a [`FormatError`](@ref).
"""
function parse_presentation_json(str::AbstractString)
    obj = JSON3.read(str)
    _hasfield(obj, "format") && String(_field(obj, "format")) == PRESENTATION_FORMAT ||
        throw(FormatError("expected format \"$PRESENTATION_FORMAT\""))
    bn = BayesNet()
    for o in _field(obj, "objects")
        add_variable!(bn, Symbol(_field(o, "name"));
                      states=Symbol[Symbol(s) for s in _field(o, "states")])
    end
    for g in _field(obj, "generators")
        cod = _field(g, "cod")
        length(cod) == 1 ||
            throw(FormatError("generator $(_field(g, "name")) must have exactly one codomain object"))
        add_mechanism!(bn, Symbol(only(cod));
                       inputs=Symbol[Symbol(x) for x in _field(g, "dom")],
                       name=Symbol(_field(g, "name")),
                       kernel_ref=_kernel_ref_from(_field(g, "kernel_ref")))
    end
    return bn
end
