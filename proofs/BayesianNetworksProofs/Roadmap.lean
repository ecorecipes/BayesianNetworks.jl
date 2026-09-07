import BayesianNetworksProofs.Finite.Open

/-!
# Roadmap (contains `sorry`)

Module `BayesianNetworksProofs.Roadmap`.
Statements that are **not yet proved**. This module is deliberately *not* imported by the
default target (`BayesianNetworksProofs.lean`) and is excluded from `Audit.lean`; build it with
`lake build BayesianNetworksProofs.Roadmap` (or `make roadmap`). Every `sorry` here is listed in
`README.md`.

## Proposition 3 — the interface form

Proposition 3 itself, `⟦B ∘ A⟧ = ⟦B⟧ ∘ ⟦A⟧`, is proved in `Finite/Open.lean`
(`marg_joint_compose_split`) in the form

```text
marg (S ∪ T) ⟦B ∘ A⟧ = marg S (⟦A⟧ · marg T ⟦B⟧)
```

for any set `S` of composite variables coming from `A` and any disjoint set `T` coming from
`B`'s private part, both marginals being taken *inside the composite*, over composite
assignments. What remains is purely book-keeping, in two steps.

1. **Transfer.** `marg (S.map Sum.inl) (fun z => F (restrictA c z)) x = marg S F (restrictA c x)`
   and its `B` analogue. Both are `Finset.sum_nbij'` arguments: restricting a composite
   assignment is a bijection from the fibre of `S.map Sum.inl` onto the fibre of `S`, with
   inverse "keep the other component of `x`". Nothing deep, but a page of dependent-function
   extensionality.
2. **Interface sets.** Identifying the composite's hidden variables with
   `(A.hidden ∪ glued) ⊕ B.hidden`. This needs side conditions — no pass-through variables
   (`inputs ∩ outputs = ∅` on both sides) and a total interface match (`ι` surjective, Julia's
   strict `compose` rather than the partial `glue`) — under which
   `(compose c).hidden = (A.inputsᶜ).map Sum.inl ∪ ((B.outputsᶜ) ∩ Priv).map Sum.inr`.

Together they turn `marg_joint_compose_split` into the statement below, which is the exact
finite-model reading of SPEC §13.2 and §55.5: the semantics of the composite is the sum over the
glued interface of the product of the two open semantics.
-/

namespace BayesianNetworksProofs

namespace OpenFinBayesNet

namespace Composable

open FinBayesNet

variable {A B : OpenFinBayesNet} {R : Type} [CommSemiring R]

/-- **Proposition 3, interface form (unproved).** For a total interface match between two open
networks without pass-through variables, `⟦B ∘ A⟧ = ⟦B⟧ ∘ ⟦A⟧`: the open semantics of the
composite is the sum, over all values of the glued interface variables, of the product of the
two open semantics. -/
theorem osem_compose (c : Composable A B) (κA : A.Kernel R) (κB : B.Kernel R)
    (hlocA : ∀ m, Local κA m) (hlocB : ∀ m, Local κB m) (hnormB : ∀ m, Normalised κB m)
    (hA : A.inputs ∩ A.outputs = ∅) (hB : B.inputs ∩ B.outputs = ∅)
    (hι : Function.Surjective c.ι) (x : (compose c).Assignment) :
    osem (compose c) (composeKernel c κA κB) x =
      marg (c.glued.map Function.Embedding.inl)
        (fun y => osem A κA (restrictA c y) * osem B κB (restrictB c y)) x := by
  sorry

end Composable

end OpenFinBayesNet

end BayesianNetworksProofs
