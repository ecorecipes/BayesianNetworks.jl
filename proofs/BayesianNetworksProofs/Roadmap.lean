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
The remaining boundary is implementation translation: Julia/JSON decoding and reference
binding, concrete CliqueTrees/Bayes-ball code, ordered-array layout and IEEE arithmetic
adapters are not established merely by those finite-model theorems. Of the IEEE arithmetic,
one piece is covered: `Numeric/Binary64.lean` proves that the transcription of
`_nearest_binary64`, the single rounding the exact fallbacks of ADR 0016 apply, returns the
binary64 round-to-nearest-ties-to-even of every rational, overflow and signed zero included.
That is a theorem about the transcribed algorithm on mathematical integers; the floating-point
operations of the ordinary (non-fallback) paths, and Julia's execution of the rounding, remain
outside.

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
