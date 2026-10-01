import BayesianNetworksProofs.Finite.OpenSemantics
import BayesianNetworksProofs.Finite.RefinementExamples

/-!
# Roadmap

The former `osem_compose` hole is now proved in `Finite/OpenSemantics.lean`, in the default
target and axiom audit. Its original premises are retained by a compatibility theorem.
The stronger `osem_compose_glue` needs only disjoint input/output sets on both sides:
locality, normalisation and total interface matching are unnecessary for this finite-sum
identity.

Concrete finite records/references and repeated slots, genuine conditioned distributions,
the actual Shafer-Shenoy collect/distribute computation, moralized-ancestral d-separation
soundness, and conditional numerical error contracts now have checked developments.
The remaining boundary is implementation translation. Of the JSON decoding, one piece is
covered: `Finite/JsonRecords.lean` decodes a parsed `Lean.Json` tree in the ACSets layout of
`write_json_bayesnet` into the raw rows, and proves the decoder faithful (`decodeTables_eq_ok`:
it succeeds exactly when every table, row and column holds the decoded values, hom columns as
one-based IDs), a right inverse of its encoder (`decodeTables_encodeTables`), failing on a
missing table or column, a hom ID out of range or a value of the wrong JSON type, and, with the
computed causal rank and `Network.check`, succeeding exactly on valid documents
(`decodeChecked_isSome_iff`). Parsing the text (`Lean.Json.parse`) and Julia's JSON3/ACSets
writer are trusted, not proved. Reference binding (the `"semantics"` kernels of
`write_json_model` against the `KernelRef`s), concrete CliqueTrees/Bayes-ball code,
ordered-array layout and IEEE arithmetic adapters are not established merely by those
finite-model theorems. Of the IEEE arithmetic,
one piece is covered: `Numeric/Binary64.lean` proves that the transcription of
`_nearest_binary64`, the single rounding the exact fallbacks of ADR 0016 apply, returns the
binary64 round-to-nearest-ties-to-even of every rational, overflow and signed zero included.
That is a theorem about the transcribed algorithm on mathematical integers. For the ordinary
(non-fallback) paths, `Numeric/ErrorBounds.lean` proves forward error bounds under the standard
rounding model (each operation's result is its exact result times `1 + δ`, `|δ| ≤ u`): sums
and products of nonnegative numbers in any association, variable elimination entrywise within
relative `γ N` for an explicit `N`, the normalised posterior, and log-sum-exp. It also proves
that correct binary64 rounding satisfies that model with `u = 2 ^ -53` in the normal range.
Underflow and overflow are excluded from those bounds, and that Julia's Float64 operations are
correctly rounded is assumed (IEEE 754 and Julia's semantics), not proved; Julia's loop order
and execution, and its execution of the rounding, remain outside.

The general structural open-network category, including non-injective output legs,
pass-through and coherent copy/discard, is now constructed separately in
`CategoricalBayesianNetworks.jl/proofs/` (ADR 0010), together with its numerical semantics:
a strong braided monoidal functor into FinStoch preserving copy and discard
(`OpenNet.Interpretation.functor`), whose composition formula `Interpretation.kernel_comp`
covers copied and pass-through outputs. This project's own `OpenFinBayesNet` now has its
pass-through formula too: `osem_compose_passthrough` in `Finite/OpenSemantics.lean` sums only
the glued variables the composite hides and needs no hypotheses; `osem_compose_glue` is its
disjoint-interface special case. The category of stochastic kernels is a different result, provided by
`FiniteKernels.jl/proofs/FiniteKernelsProofs/Theory/FinStoch.lean`.
-/
