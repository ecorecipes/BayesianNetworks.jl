# BayesianNetworksProofs

Lean 4 / Mathlib formalisation accompanying `BayesianNetworks.jl` (toolchain
`leanprover/lean4:v4.30.0`, Mathlib tag `v4.30.0`; ADR 0005).

```sh
cd proofs
lake exe cache get          # prebuilt Mathlib oleans (shared checkout, see below)
lake build                  # verifies every proof in the default target
lake env lean Audit.lean    # `make audit`: #print axioms for every main theorem
lake exe emit_schema        # `make emit-schema`: regenerate schemas/*.schema.json
lake exe emit_schema --check  # `make check-schema`: exit 1 if the JSON is stale
lake build BayesianNetworksProofs.Roadmap  # `make roadmap`: type-check the unproved statements
```

The dependency checkout is shared with the other ecosystem `proofs/` projects through
`packagesDir = "../../.lake-packages"` (gitignored); CI rewrites it to a local `.lake/packages`.

## Documents

The proofs are also rendered as a readable document (`BayesianNetworksProofs.md`, `.html`, `.pdf`, committed
here). It is generated from the Lean sources by [mdgen](https://github.com/Seasawher/mdgen)
(Lake dependency, tag `v4.30.0`): the `/-! ... -/` module docstrings become prose and everything
else becomes a `lean` code block, so the document is the verbatim, machine-checked source.

```sh
make mdgen   # BayesianNetworksProofs.md   — lake exe mdgen, modules concatenated in import order
make html    # BayesianNetworksProofs.html — pandoc --standalone --toc --mathjax, style.css
make pdf     # BayesianNetworksProofs.pdf  — pandoc → lualatex with header.tex (STIX Two Text/Math, JuliaMono)
make docs    # all three
```

Requirements: pandoc (≥ 3.8; `lean.xml` is a minimal Lean syntax definition, pandoc has none
built in) and a TeX distribution with `lualatex` (TinyTeX or MacTeX). Fonts: STIX Two Text and
STIX Two Math (macOS system fonts, or TeX Live `stix2-otf`) for prose and mathematics, and
[JuliaMono](https://juliamono.netlify.app) (SIL OFL) for code, which covers all of Lean's
Unicode; it is read from `../../fonts/JuliaMono/` by path (`header.tex`), not installed
system-wide. `make pdf` prints the number of `Missing character` warnings in the LaTeX log
(expected 0). The documents are built locally and committed; CI does not rebuild them.

Module order (`MD_FILES` in the `Makefile`, the import order of `BayesianNetworksProofs.lean`):

1. `Basic.lean` — introduction, structure and SPEC §61 correspondence tables
2. `Schema/Desc.lean`
3. `Schema/BayesNet.lean`
4. `Finite/BayesNet.lean`
5. `Finite/Evaluation.lean`
6. `Finite/Intervention.lean`
7. `Finite/Tensor.lean`
8. `Finite/Open.lean`
9. `Markov/Basic.lean`
10. `Finite/Probability.lean`
11. `Roadmap.lean` — rendered last as "Roadmap (contains `sorry`)"; not in the default target

## What is formalised

| Module | Content |
|---|---|
| `Schema/Desc.lean` | `SchemaDesc` (obs, homs, attrtypes, attrs) with decidable `WF`, `Sub`, `NoOutgoing`, `extend`, and `toACSetsJson` reproducing ACSets.jl's `generate_json_acset_schema` format. Mathlib-free. |
| `Schema/BayesNet.lean` | `schVariableSpace`, `schBayesNet`, `schInfluenceDiagram` (SPEC §8, §24) and, by `decide`: all three `WF`; `Sub schVariableSpace schBayesNet`; `Sub schBayesNet schInfluenceDiagram`; `NoOutgoing schVariableSpace schBayesNet` and `... schInfluenceDiagram` (the precondition of Catlab's `OpenACSetTypes(BayesNet, VariableSpace)`). |
| `Finite/BayesNet.lean` | The concrete finite model `FinBayesNet` (finite `V`, `M`, finite non-empty `states v`, `target`, `parents`), kernels `Kernel R` over any commutative semiring, `Local`, `Normalised`, `Closed` (`target` bijective), `TopoOrder`, and the joint `joint κ x = ∏ m, κ m x (x (target m))`. |
| `Finite/Evaluation.lean` | **Prop 1a** `sum_joint_eq_one`: closed + topological order + local + normalised ⇒ `∑ x, joint κ x = 1`. Proved by integrating variables out along the order using `fibre`/`marg` (sums over assignments agreeing with a base point outside a set; no dependent tuples). **Prop 1b** `evalSeq_eq_joint`: the sequential evaluator along any complete duplicate-free order equals `joint`. Also the marginalisation toolkit: `marg_union_disjoint` (finite Fubini for fibres), `marg_mul_left`, `marg_joint_downstream` and **Prop 3 closed-world shadow** `marg_joint_upstream` (integrating the downstream variables out of the full joint leaves the joint of the upstream mechanisms) — formerly a `sorry` in `Roadmap.lean`, now proved. |
| `Finite/Intervention.lean` | **Prop 4** `joint_intervene`: `joint (intervene κ m₀ a) x = [x (target m₀) = a] * ∏ m ≠ m₀, κ m x (x (target m))`; the intervened kernel is normalised (`normalised_intervene`) and local with empty parents for the rewritten network `bn.cut m₀` (`local_cut`, `TopoOrder.cut`); corollary `sum_joint_intervene_eq_one`. |
| `Finite/Tensor.lean` | **Prop 2** `joint_tensor`: on `V₁ ⊕ V₂`, `M₁ ⊕ M₂` the joint of `tensorKernel κ₁ κ₂` is the product of the joints; `closed_tensor`, `normalised_tensor`, `local_tensor`, `TopoOrder.tensor`. |
| `Finite/Open.lean` | **The open-network closure theorem** and **Prop 3**. `OpenFinBayesNet` = `FinBayesNet` + `inputs`/`outputs` + the typed-interface rule (`target_inj`, `input_exogenous`, `exogenous_input`, `topo`); `Composable A B` = an injection `ι` of `B`'s inputs into `A`'s outputs plus the matching of their state spaces; `compose` = the quotient-free pushout on `A.V ⊕ {v : B.V // v ∉ B.inputs}`. See below. |
| `Finite/Probability.lean` | The above instantiated at `ℝ≥0`. |
| `Markov/Basic.lean` | Against Mathlib's abstract `MarkovCategory` / `CopyDiscardCategory`: `discard_natural` (`f ≫ ε = ε`), `state_discard`, `deterministic_comp` (Mathlib's `IsComonHom` composition instance), `deterministic_copy`, and the comonoid laws as `example`s. These are the statements the Julia tests check for the finite-stochastic instance. No finite `MarkovCategory` instance is attempted. |
| `Roadmap.lean` | Unproved statements (`sorry`), **not** in the default target or the audit — see below. |

`Audit.lean` prints the axioms of every main theorem; all report a subset of
`propext`, `Classical.choice`, `Quot.sound`.

### Open networks: the closure theorem and Proposition 3 (`Finite/Open.lean`)

`OpenFinBayesNet` is the Lean counterpart of Julia's `Open(bn; inputs, outputs)` (`src/open.jl`).
The feet are *subsets* of the apex variables rather than separate objects with a leg, so rule 2
(the input leg is injective) and rule 5 (legs natural, name/reference/state preserving) hold by
construction; the remaining rules are structure fields:

| Julia (`validation_errors(::OpenBayesNet)`) | Lean field |
|---|---|
| at most one mechanism per variable (`validate(bn; closed = false)`) | `target_inj` |
| rule 1 — input-foot variables have no mechanism | `input_exogenous` |
| rule 3 — every mechanism-free apex variable is an input | `exogenous_input` |
| rule 4 — the derived graph is acyclic | `topo : TopoOrder` |

`Composable A B` (an injection `ι : B.inputs ↪ A.outputs` plus `states_equiv`, the "same states,
same positions" half of Julia's `interface_matches`) gives the composite **without quotient
types**: `V := A.V ⊕ {v : B.V // v ∉ B.inputs}` keeps one representative per pushout class, the
glued variables being represented on the `A` side, and `tr : B.V → V` is the right-hand pushout
leg. Proven, sorry-free:

* `composeNet_target_injective` — **at most one mechanism per variable is preserved.** This is
  the theorem the SPEC §13 revision note and `compose`'s docstring assert ("Under the
  typed-interface rule the pushout never produces two mechanisms for one variable"). The key
  step: a mechanism of `B` never targets a glued variable, because `B`'s inputs are exogenous;
  so the two mechanism families cannot collide.
* `compose_input_exogenous`, `compose_exogenous_input` — the composite's inputs are exactly
  `A.inputs`, and every variable contributed by `B` keeps its mechanism (rules 1 and 3).
* `composeTopo` — **acyclicity is preserved** (rule 4): `A`'s order followed by `B`'s order
  restricted to the non-input variables is a topological order of the composite. This is
  *derived*, not assumed as a hypothesis.
* `compose` — the four above bundled back into an `OpenFinBayesNet`, with outputs
  `(A.outputs \ glued) ∪ tr (B.outputs)` exactly as in Julia's `glue`. Producing this term
  *is* the closure theorem.
* `closed_compose`, `sum_joint_compose_eq_one` — if `A` has no inputs the composite is closed,
  so `⟦B ∘ A⟧` is a probability distribution.

Semantics (**Proposition 3**, SPEC §13.2, §55.5, §61):

* `joint_compose` — `joint (composeKernel c κA κB) x = joint κA (restrictA c x) * joint κB
  (restrictB c x)`: the joint of the composite factors as the product of the two joints. The
  sequential analogue of `joint_tensor`, and the algebraic heart of Proposition 3.
* `local_compose`, `normalised_compose` — locality and normalisation are preserved.
* `marg_joint_compose` — summing the composite joint over all values of `B`'s private variables
  returns `A`'s joint: `⟦B ∘ A⟧` marginalised back onto `A` is `⟦A⟧`. Only `B`'s kernels have to
  be normalised (`marg_partialJoint_eq_one`'s normalisation hypothesis was weakened to the
  mechanisms targeting the variables being integrated out).
* `marg_joint_compose_split` — **Proposition 3**: for `S` on the `A` side and `T` on the `B`
  side, `marg (S ∪ T) ⟦B ∘ A⟧ = marg S (⟦A⟧ · marg T ⟦B⟧)`. Taking `S` to be `A`'s hidden
  variables together with the glued interface and `T` to be `B`'s hidden variables, this is
  `⟦B ∘ A⟧ = ⟦B⟧ ∘ ⟦A⟧`: the composite semantics is the sum over the interface of the product of
  the two open semantics.

What is **not** covered: `marg_joint_compose_split` states both marginals *inside the
composite*, over composite assignments. Rewriting them as `osem A κA` and `osem B κB` — the open
semantics on `A`'s and `B`'s own variable types — needs (i) a transfer lemma across the two
pushout legs (a `Finset.sum_nbij'` argument) and (ii) the identification of the composite's
hidden variables with `(A.hidden ∪ glued) ⊕ B.hidden`, which holds under side conditions (no
pass-through variables, total interface match). That last step is `Roadmap.osem_compose`.

### Roadmap (contains `sorry`)

* `OpenFinBayesNet.Composable.osem_compose` — Proposition 3 in interface form, i.e.
  `marg_joint_compose_split` with the marginals expressed as `osem` on each side's own
  variables. The two missing book-keeping steps are spelled out in the module docstring. The
  mathematical content of Proposition 3 is already proved (see above).
* Not yet stated: Prop 5 (policy instantiation) and Prop 6 (expected utility) belong to
  `InfluenceDiagrams.jl/proofs`; Prop 7 (DVE) is deferred to v0.2 (Julia property tests).

## How the schema JSON reaches Julia

The Lean terms in `Schema/BayesNet.lean` and the `@present` schemas in `BayesianNetworks.jl/src/schemas.jl`
are two independent hand-written definitions. Neither is generated from the other; they are *checked to agree*
by `lake exe emit_schema --check` here and by a test in the Julia package.
`lake exe emit_schema` (target `emit_schema`, root `Main.lean`; links only Lean core because the
`Schema/` modules do not import Mathlib) writes

```
schemas/variable_space.schema.json
schemas/bayesnet.schema.json
schemas/influence_diagram.schema.json
```

in exactly the shape of ACSets.jl's `generate_json_acset_schema`:
`{"version": {"ACSetSchema": "0.0.1", "ACSets": "0.2.29"}, "Ob": [{"name"}], "Hom": [{"name","dom","codom"}],
"AttrType": [{"name"}], "Attr": [{"name","dom","codom"}], "equations": []}`. Generator order is
the declaration order of the Lean terms (base schema first, then the extension). JSON object keys
are printed in Lean's fixed `Json.obj` order, so compare *structurally*: the Julia test does
`generate_json_acset_schema(SchBayesNet) == JSON3.read("proofs/schemas/bayesnet.schema.json")`
modulo the `version` object. `lake exe emit_schema --check` (run in CI after the build) exits 1
if a committed file differs from what the Lean terms would emit, so the two sides cannot drift.
