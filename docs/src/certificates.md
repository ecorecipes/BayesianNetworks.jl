# Finite-model proof certificates

[`proof_certificate`](@ref) exports the bound data of a closed finite
[`BayesModel`](@ref) without introducing a proof-assistant runtime dependency.
The separate `proofs/scripts/check_certificate.py` consumer transcribes the
JSON into literal Lean records and checks structural validity, reference
resolution, nonnegative weights, and evidence bounds and uniqueness with
`decide +kernel`. Exactly normalized data also obtain a proof that the compiled
joint has mass one.

```julia
using BayesianNetworks, JSON3

m = BayesModel(bayesnet(:Rain => [:no, :yes], :Wet => [:no, :yes];
                        mechanisms = [:Wet => :Rain]))
m = bind_cpt(m, :Rain => [0.75, 0.25])
m = bind_cpt(m, :Wet => [1.0 0.0; 0.25 0.75])
open("rain.json", "w") do io
    JSON3.write(io, proof_certificate(m))
end
```

From a checkout with the pinned Lean project built:

```sh
python3 proofs/scripts/check_certificate.py rain.json \
  --output rain.lean --require-normalized
```

The consumer refuses to overwrite an existing output unless `--force` is given.
Its successful result concerns the **emitted literal Lean data**. The Julia
exporter, JSON serializer, Python transcription, compiler and floating-point
inference runtime are not thereby proved correct.

## Data and ordering

The version is `finite-bn-certificate-1`. This is neither the ordinary
`json_model` format, the categorical package's `OpenNet.RawCertificate/v1`,
nor the influence-diagram package's `ecorecipes.dve-certificate`.

| Field | Content |
|---|---|
| `variables` | Original variable rows: `name`, `space_ref` |
| `states` | Original state rows: `variable`, `position`, `name` |
| `mechanisms` | Original mechanism rows: `name`, `target`, `kernel_ref` |
| `inputs` | Original input rows: `mechanism`, `variable`, `position` |
| `bindings` | Used named/policy references, ordered input/output labels and complete CPT columns |
| `topological_order` | A complete permutation of variable IDs, parents before children |
| `evidence` | Observations as `variable`, `state_position` |

IDs and positions are **one-based JSON integers**. The four structural arrays
stay in part-ID order; state and input rows are not sorted by their position
attributes. Non-dense part IDs are rejected, not silently renumbered.
The consumer derives semantic ordering from the copied positions.

References retain their identities: `NamedRef` is `{"kind":"named","key":...}`,
`PolicyRef` is `{"kind":"policy","key":...}`, `PointMassRef` is
`{"kind":"point_mass","state":...}`, and `NoRef` is `{"kind":"none"}`.
Space references are retained metadata, not verified external space lookups.
Generating `NoRef`s and unresolved named/policy references are errors.
Point masses are constructed by the Lean resolver and need no numeric binding.
Unused kernel dictionary entries are omitted.

Each binding has `kind`, `key`, `input_states`, `output_states` and `columns`.
A column has one-based `parents` coordinates and an output-ordered `weights`
list. A root has one column with empty `parents`. Coordinates are enumerated
lexicographically, with the last parent varying fastest. All repeated parent
slots and their **off-diagonal columns** are preserved from `cpt(k)`; the Lean
compiler, not the exporter, establishes diagonal evaluation.

Each used named/policy identity is emitted once, but every mechanism must pass
the full ordinary binding-signature check. In particular, current `FiniteAxis`
equality includes variable names: two differently named target variables
cannot share one bound kernel merely because their state counts agree.
The exporter never invents fresh reference keys to bypass this restriction.

## Exact numbers are not rounded decimal intentions

Every weight is `{"num":"integer","den":"positive integer"}` in reduced form.
Integers and rationals retain their values; `Float16`, `Float32`, `Float64`
and `BigFloat` values are converted to their **exact binary rational values**.
Negative zero becomes rational zero. This captures the bound entries before
any inference backend converts them to Float64.

For example, stored Float64 `[0.1, 0.9]` has exact rational sum
`36028797018963969 / 36028797018963968`, not one. It passes ordinary runtime
validation at `DEFAULT_ATOL`, and the consumer accepts its well-formed
nonnegative data while proving `normalization_checked = false`.
With `--require-normalized`, the consumer instead exits with status 2.
No certificate step clips, approximately rationalizes or renormalizes a row.
If exact thirds are intended, bind `[1//3, 2//3]` rather than rounded decimals.

Pass the original validation tolerance explicitly for rounded file data:
`proof_certificate(m; atol=1e-6)`. Nonfinite or negative entries, including
tiny negatives tolerated by ordinary validation, are rejected. Unsupported
scalar types and control characters in names raise [`ProofCertificateError`](@ref).

## Evidence and scope

By default, stored observations are exported. An explicit dictionary replaces
them completely: `proof_certificate(m; evidence=Dict(:Rain => :yes))` does not
merge it with `m.evidence`, and `evidence=Dict()` exports no observations.
Impossible but well-formed observations are allowed; evidence is recorded, not
applied to the kernels, and exporting does not compute a posterior.

Capture leaves the source unchanged and the returned arrays do not alias it.
Do not mutate the model while it is being captured. History, extras and
additional records of an extended schema are not certified. An influence
diagram instantiated with fixed policies may be exported as a BayesModel;
this certifies neither the original decision problem nor policy optimality.
