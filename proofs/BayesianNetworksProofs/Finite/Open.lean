import BayesianNetworksProofs.Finite.Tensor

/-!
# BayesianNetworksProofs.Finite.Open

**Open networks and the closure theorem** (SPEC §13 and its revision note, §55.5, §61
Propositions 2 and 3), for the concrete finite model — no category theory, no quotient types.

An `OpenFinBayesNet` is a `FinBayesNet` with two distinguished sets of variables, `inputs` and
`outputs`, satisfying the *typed-interface rule* of `BayesianNetworks.jl`'s `Open`
(`src/open.jl`, `validation_errors(::OpenBayesNet)`):

| Julia rule | Lean field |
|---|---|
| at most one mechanism per variable (`validate(bn; closed = false)`) | `target_inj` |
| rule 1: input-foot variables have no mechanism | `input_exogenous` |
| rule 3: every mechanism-free apex variable is an input | `exogenous_input` |
| rule 4: the derived graph is acyclic | `topo` (a `TopoOrder`) |

Rule 2 (the input leg is injective) and rule 5 (legs natural, i.e. name-, reference- and
state-preserving) are absorbed into the representation: the feet here are *subsets* of the apex
variables rather than separate objects with a leg, so the leg is the inclusion, which is
injective and natural by construction. The interface match of `compose` is the injection `ι`
below, which plays the part of Catlab's `interface_matches` and of the pushout's gluing map;
`states_equiv` is the "same states, same positions" half of `interface_matches`.

## Composition without quotients

`Composable A B` is an injection `ι` from `B`'s inputs into `A`'s outputs together with the
matching of their state spaces. The pushout of the two structured cospans identifies each input
of `B` with its partner output of `A`; rather than quotient `A.V ⊕ B.V`, the composite takes

* `V := A.V ⊕ Priv B` where `Priv B = {v : B.V // v ∉ B.inputs}` — one representative per class,
  the glued variables being represented on the `A` side;
* `M := A.M ⊕ B.M` — mechanisms are never identified;
* `tr : B.V → A.V ⊕ Priv B`, injective, sending an input of `B` to `Sum.inl (ι …)` and any other
  variable to `Sum.inr` — the right-hand pushout leg.

`composeNet` is the resulting shape and `compose` bundles it back into an `OpenFinBayesNet`,
which is the closure theorem: producing the four fields *is* the proof that the composite is
again valid. The individual statements are

* `composeNet_target_injective` — **at most one mechanism per variable is preserved.** The key
  step is that a mechanism of `B` never targets a glued variable, because `B`'s inputs are
  exogenous (`target_notMem_inputs`); so the two mechanism families cannot collide;
* `compose_input_exogenous`, `compose_exogenous_input` — the composite's inputs are exactly
  `A.inputs`, and every variable contributed by `B` keeps its mechanism;
* `composeTopo` — **acyclicity is preserved**: `A`'s order followed by `B`'s order restricted to
  `Priv B` is a topological order of the composite. It is *derived*, not assumed.

Outputs are `(A.outputs \ glued) ∪ tr (B.outputs)`, exactly as in Julia's `glue`.

## Semantics (Proposition 3)

`composeKernel` puts two kernel families side by side; `restrictA` and `restrictB` read an
assignment of the composite as an assignment of `A` and of `B` (a glued variable is read on the
`A` side and transported by `states_equiv`).

* `joint_compose` — `⟦B ∘ A⟧ = ⟦A⟧ · ⟦B⟧` pointwise: the joint of the composite factors as the
  product of the two joints. This is the sequential analogue of `Finite/Tensor.lean`'s
  `joint_tensor`, and the algebraic heart of Proposition 3;
* `local_compose`, `normalised_compose`, `closed_compose`, `sum_joint_compose_eq_one` — the
  composite of local / normalised kernels is local / normalised, and if `A` has no inputs the
  composite is closed, so its joint is a probability distribution;
* `marg_joint_compose` — summing the composite joint over all values of `B`'s private variables
  returns `A`'s joint: `⟦B ∘ A⟧` marginalised back onto `A` is `⟦A⟧`. Only `B`'s kernels need to
  be normalised;
* `marg_joint_compose_split` — **Proposition 3.** Integrating out `S ∪ T`, with `S` on the `A`
  side and `T` on the `B` side, is `∑_S ⟦A⟧ · (∑_T ⟦B⟧)`: the composite semantics is the sum
  over the interface of the product of the two open semantics. Taking `S` to be `A`'s hidden
  variables together with the glued interface and `T` to be `B`'s hidden variables gives
  `⟦B ∘ A⟧ = ⟦B⟧ ∘ ⟦A⟧`. What is *not* proved here is the last book-keeping step that rewrites
  those two marginals as the open semantics of `A` and of `B` on their own variable types; see
  `Roadmap.lean`.
-/

namespace BayesianNetworksProofs

structure OpenFinBayesNet extends FinBayesNet where
  inputs : Finset V
  outputs : Finset V
  target_inj : Function.Injective target
  input_exogenous : ∀ v ∈ inputs, ∀ m, target m ≠ v
  exogenous_input : ∀ v, (∀ m, target m ≠ v) → v ∈ inputs
  topo : FinBayesNet.TopoOrder toFinBayesNet

namespace OpenFinBayesNet

open FinBayesNet

variable {A B : OpenFinBayesNet}

/-- Rule 1 restated: a mechanism never targets an input. -/
theorem target_notMem_inputs (O : OpenFinBayesNet) (m : O.M) : O.target m ∉ O.inputs :=
  fun h => O.input_exogenous _ h m rfl

/-- Rule 3 restated: a non-input variable is generated by some mechanism. -/
theorem exists_mechanism (O : OpenFinBayesNet) {v : O.V} (h : v ∉ O.inputs) :
    ∃ m, O.target m = v := by
  by_contra hc
  exact h (O.exogenous_input v (fun m hm => hc ⟨m, hm⟩))

/-- The hidden (non-interface) variables of an open network. -/
def hidden (O : OpenFinBayesNet) : Finset O.V := (O.inputs ∪ O.outputs)ᶜ

/-- The **open semantics** `⟦O⟧` of an open network: the joint with the hidden variables summed
out, a function of the interface (input and output) variables alone. -/
def osem {R : Type} [CommSemiring R] (O : OpenFinBayesNet) (κ : O.Kernel R)
    (x : O.Assignment) : R := marg O.hidden (joint κ) x

/-- The variables of `B` that are not inputs — one representative per pushout class on the
`B` side. -/
abbrev Priv (B : OpenFinBayesNet) := {v : B.V // v ∉ B.inputs}

/-- `some` on the non-input variables of `B`, `none` on the inputs. -/
def privOf (v : B.V) : Option (Priv B) := if h : v ∈ B.inputs then none else some ⟨v, h⟩

/-- `privOf` picks out exactly the non-input variables. -/
theorem privOf_eq_some {v : B.V} {w : Priv B} : privOf v = some w ↔ v = w.val := by
  unfold privOf
  by_cases h : v ∈ B.inputs
  · simp only [dif_pos h, reduceCtorEq, false_iff]
    rintro rfl
    exact w.property h
  · simp [dif_neg h, Subtype.ext_iff]

/-- An interface match: an injection of `B`'s inputs into `A`'s outputs (Catlab's gluing map,
validated by `interface_matches` in Julia) together with the identification of the state spaces
it pairs up. -/
structure Composable (A B : OpenFinBayesNet) where
  ι : {v : B.V // v ∈ B.inputs} → {v : A.V // v ∈ A.outputs}
  ι_inj : Function.Injective ι
  states_equiv : ∀ w : {v : B.V // v ∈ B.inputs}, A.states (ι w).val ≃ B.states w.val

namespace Composable

/-- The right-hand pushout leg: `B`'s variables inside the composite. -/
def tr (c : Composable A B) (v : B.V) : A.V ⊕ Priv B :=
  if h : v ∈ B.inputs then Sum.inl (c.ι ⟨v, h⟩).val else Sum.inr ⟨v, h⟩

variable {c : Composable A B}

theorem tr_of_mem {v : B.V} (h : v ∈ B.inputs) : c.tr v = Sum.inl (c.ι ⟨v, h⟩).val := dif_pos h

theorem tr_of_notMem {v : B.V} (h : v ∉ B.inputs) : c.tr v = Sum.inr ⟨v, h⟩ := dif_neg h

/-- The right leg is injective: two `B` variables are identified in the composite only if they
were equal. -/
theorem tr_injective : Function.Injective c.tr := by
  intro v w h
  by_cases hv : v ∈ B.inputs <;> by_cases hw : w ∈ B.inputs
  · rw [tr_of_mem hv, tr_of_mem hw, Sum.inl.injEq] at h
    exact congrArg Subtype.val (c.ι_inj (Subtype.ext h))
  · rw [tr_of_mem hv, tr_of_notMem hw] at h
    exact absurd h (by simp)
  · rw [tr_of_notMem hv, tr_of_mem hw] at h
    exact absurd h (by simp)
  · rw [tr_of_notMem hv, tr_of_notMem hw, Sum.inr.injEq] at h
    exact congrArg Subtype.val h

variable (c) in
/-- `tr` as an embedding, for `Finset.map`. -/
def trEmb : B.V ↪ A.V ⊕ Priv B := ⟨c.tr, tr_injective⟩

@[simp] theorem trEmb_apply (v : B.V) : c.trEmb v = c.tr v := rfl

@[simp] theorem inr_mem_map_trEmb {s : Finset B.V} {w : Priv B} :
    Sum.inr w ∈ s.map c.trEmb ↔ w.val ∈ s := by
  simp only [Finset.mem_map, trEmb_apply]
  constructor
  · rintro ⟨p, hp, h⟩
    by_cases hpi : p ∈ B.inputs
    · rw [tr_of_mem hpi] at h
      exact absurd h (by simp)
    · rw [tr_of_notMem hpi, Sum.inr.injEq] at h
      rw [← h]
      exact hp
  · exact fun h => ⟨w.val, h, tr_of_notMem w.property⟩

variable (c) in
/-- The `A`-outputs that are glued to inputs of `B`. -/
def glued : Finset A.V := Finset.univ.image (fun w : {v : B.V // v ∈ B.inputs} => (c.ι w).val)

variable (c) in
/-- The underlying shape of the composite. -/
@[reducible] def composeNet : FinBayesNet where
  V := A.V ⊕ Priv B
  M := A.M ⊕ B.M
  states := Sum.elim A.states (fun w => B.states w.val)
  fintypeS := fun
    | .inl v => A.fintypeS v
    | .inr w => B.fintypeS w.val
  decS := fun
    | .inl v => A.decS v
    | .inr w => B.decS w.val
  nonemptyS := fun
    | .inl v => A.nonemptyS v
    | .inr w => B.nonemptyS w.val
  target := Sum.elim (fun m => Sum.inl (A.target m))
    (fun m => Sum.inr ⟨B.target m, B.target_notMem_inputs m⟩)
  parents := Sum.elim (fun m => (A.parents m).map Function.Embedding.inl)
    (fun m => (B.parents m).map c.trEmb)

-- `composeNet` is reducible, so instance search sees through `(composeNet c).states v` to the
-- `Sum.elim` and no longer matches `FinBayesNet.fintypeS`; re-expose the instances by hand.
instance instFintypeComposeStates (v : (composeNet c).V) : Fintype ((composeNet c).states v) :=
  (composeNet c).fintypeS v

instance instDecidableEqComposeStates (v : (composeNet c).V) :
    DecidableEq ((composeNet c).states v) := (composeNet c).decS v

@[simp] theorem composeNet_target_inl (m : A.M) :
    (composeNet c).target (.inl m) = .inl (A.target m) := rfl

@[simp] theorem composeNet_target_inr (m : B.M) :
    (composeNet c).target (.inr m) = .inr ⟨B.target m, B.target_notMem_inputs m⟩ := rfl

@[simp] theorem composeNet_parents_inl (m : A.M) :
    (composeNet c).parents (.inl m) = (A.parents m).map Function.Embedding.inl := rfl

@[simp] theorem composeNet_parents_inr (m : B.M) :
    (composeNet c).parents (.inr m) = (B.parents m).map c.trEmb := rfl

variable (c) in
/-- Appending `B`'s topological order (on its non-input variables) after `A`'s. -/
def composeTopo : (composeNet c).TopoOrder where
  order := A.topo.order.map Sum.inl ++ (B.topo.order.filterMap privOf).map Sum.inr
  nodup := by
    refine List.Nodup.append (A.topo.nodup.map Sum.inl_injective)
      (List.Nodup.map Sum.inr_injective ?_) ?_
    · refine List.Nodup.filterMap ?_ B.topo.nodup
      intro a a' b hb hb'
      rw [Option.mem_def, privOf_eq_some] at hb hb'
      exact hb.trans hb'.symm
    · rintro x hx hx'
      obtain ⟨a, _, rfl⟩ := List.mem_map.1 hx
      obtain ⟨w, _, h⟩ := List.mem_map.1 hx'
      exact Sum.inr_ne_inl h
  complete := fun
    | .inl a => List.mem_append_left _ (List.mem_map_of_mem (A.topo.complete a))
    | .inr w => List.mem_append_right _
        (List.mem_map_of_mem (List.mem_filterMap.2 ⟨w.val, B.topo.complete w.val,
          privOf_eq_some.2 rfl⟩))
  parents_before := by
    refine List.pairwise_append.2 ⟨?_, ?_, ?_⟩
    · refine List.pairwise_map.2 (A.topo.parents_before.imp ?_)
      rintro a b hab (m | m) hm
      · rw [composeNet_target_inl, Sum.inl.injEq] at hm
        simpa using hab m hm
      · exact absurd hm (by simp)
    · have hB : ((B.topo.order.filterMap privOf).Pairwise
          fun w w' : Priv B => ∀ m, B.target m = w.val → w'.val ∉ B.parents m) := by
        refine List.Pairwise.filterMap privOf ?_ B.topo.parents_before
        intro a a' hR b hb b' hb'
        rw [privOf_eq_some] at hb hb'
        subst hb; subst hb'
        exact hR
      refine List.pairwise_map.2 (hB.imp ?_)
      · rintro w w' hww' (m | m) hm
        · exact absurd hm (by simp)
        · rw [composeNet_target_inr, Sum.inr.injEq] at hm
          rw [composeNet_parents_inr, inr_mem_map_trEmb]
          exact hww' m (congrArg Subtype.val hm)
    · rintro x hx y hy (m | m) hm
      · obtain ⟨w, _, rfl⟩ := List.mem_map.1 hy
        simp
      · obtain ⟨a, _, rfl⟩ := List.mem_map.1 hx
        exact absurd hm (by simp)
  no_self := fun
    | .inl m => by simpa using A.topo.no_self m
    | .inr m => by
        rw [composeNet_target_inr, composeNet_parents_inr, inr_mem_map_trEmb]
        exact B.topo.no_self m

variable (c) in
/-- **The closure theorem, rule 1 ("at most one mechanism per variable").** The target map of
the composite is injective whenever those of `A` and `B` are. -/
theorem composeNet_target_injective : Function.Injective (composeNet c).target := by
  rintro (m | m) (m' | m') h
  · exact congrArg Sum.inl (A.target_inj (Sum.inl.inj h))
  · exact absurd h (by simp)
  · exact absurd h (by simp)
  · exact congrArg Sum.inr (B.target_inj (congrArg Subtype.val (Sum.inr.inj h)))

variable (c) in
/-- **The closure theorem, rule 1' (inputs are exogenous).** No composite mechanism targets a
variable of `A.inputs`. -/
theorem compose_input_exogenous :
    ∀ v ∈ A.inputs.map Function.Embedding.inl, ∀ m, (composeNet c).target m ≠ v := by
  intro v hv m
  obtain ⟨a, ha, rfl⟩ := Finset.mem_map.1 hv
  cases m with
  | inl m => exact fun h => A.input_exogenous a ha m (Sum.inl.inj h)
  | inr m => exact fun h => by simp at h

variable (c) in
/-- **The closure theorem, rule 3 (every mechanism-free variable is an input).** A composite
variable with no generating mechanism comes from `A` and is an input of `A`; the variables
contributed by `B` all keep their mechanism. -/
theorem compose_exogenous_input :
    ∀ v, (∀ m, (composeNet c).target m ≠ v) → v ∈ A.inputs.map Function.Embedding.inl := by
  rintro (a | w) h
  · exact Finset.mem_map_of_mem _
      (A.exogenous_input a fun m hm => h (.inl m) (congrArg Sum.inl hm))
  · exact absurd (B.exogenous_input w.val fun m hm =>
      h (.inr m) (congrArg Sum.inr (Subtype.ext hm))) w.property

variable (c) in
/-- **The open-network closure theorem (SPEC §13, revision note).** The pushout composite of two
valid open networks along an injective interface match is again a valid open network: its inputs
are `A`'s inputs, its outputs are `A`'s unglued outputs together with `B`'s outputs, and the four
typed-interface rules hold. -/
@[reducible] def compose : OpenFinBayesNet where
  toFinBayesNet := composeNet c
  inputs := A.inputs.map Function.Embedding.inl
  outputs := (A.outputs \ c.glued).map Function.Embedding.inl ∪ B.outputs.map c.trEmb
  target_inj := composeNet_target_injective c
  input_exogenous := compose_input_exogenous c
  exogenous_input := compose_exogenous_input c
  topo := composeTopo c

/-! ## Semantics -/

variable (c) in
/-- The `A`-part of a composite assignment. -/
def restrictA (x : (composeNet c).Assignment) : A.Assignment := fun a => x (Sum.inl a)

variable (c) in
/-- The `B`-part of a composite assignment: glued variables are read off the `A` side
through the interface equivalence. -/
def restrictB (x : (composeNet c).Assignment) : B.Assignment := fun v =>
  if h : v ∈ B.inputs then c.states_equiv ⟨v, h⟩ (x (Sum.inl (c.ι ⟨v, h⟩).val))
  else x (Sum.inr ⟨v, h⟩)

variable (c) in
/-- On a variable that is not an input of `B`, `restrictB` just reads the `Sum.inr` component. -/
theorem restrictB_of_notMem (x : (composeNet c).Assignment) {v : B.V} (h : v ∉ B.inputs) :
    restrictB c x v = x (Sum.inr ⟨v, h⟩) := dif_neg h

variable (c) in
/-- Two kernel families side by side on the composite. -/
def composeKernel {R : Type} (κA : A.Kernel R) (κB : B.Kernel R) : (composeNet c).Kernel R
  | .inl m => fun x y => κA m (restrictA c x) y
  | .inr m => fun x y => κB m (restrictB c x) y

section Semantics

variable {R : Type}

/-- **Proposition 2 for sequential composition.** The joint of the composite is the product of
the two joints, each read off the corresponding part of the composite assignment. -/
theorem joint_compose [CommMonoid R] (κA : A.Kernel R) (κB : B.Kernel R)
    (x : (composeNet c).Assignment) :
    joint (composeKernel c κA κB) x = joint κA (restrictA c x) * joint κB (restrictB c x) := by
  have h2 : ∀ m : B.M, composeKernel c κA κB (.inr m) x (x ((composeNet c).target (.inr m)))
      = κB m (restrictB c x) (restrictB c x (B.target m)) := fun m =>
    congrArg _ (restrictB_of_notMem c x (B.target_notMem_inputs m)).symm
  unfold joint
  rw [Fintype.prod_sum_type, Finset.prod_congr rfl fun m _ => h2 m]
  rfl

theorem normalised_compose [AddCommMonoid R] [One R] (κA : A.Kernel R) (κB : B.Kernel R)
    (hA : ∀ m, Normalised κA m) (hB : ∀ m, Normalised κB m) :
    ∀ m, Normalised (composeKernel c κA κB) m
  | .inl m => fun x => hA m (restrictA c x)
  | .inr m => fun x => hB m (restrictB c x)

theorem local_compose (κA : A.Kernel R) (κB : B.Kernel R)
    (hA : ∀ m, Local κA m) (hB : ∀ m, Local κB m) :
    ∀ m, Local (composeKernel c κA κB) m
  | .inl m => fun x x' hx => hA m (restrictA c x) (restrictA c x') fun p hp =>
      hx (Sum.inl p) (Finset.mem_map_of_mem _ hp)
  | .inr m => fun x x' hx => hB m (restrictB c x) (restrictB c x') fun p hp => by
      have hxx := hx (c.tr p) (Finset.mem_map_of_mem c.trEmb hp)
      by_cases h : p ∈ B.inputs
      · rw [tr_of_mem h] at hxx
        simp only [restrictB, dif_pos h]
        exact congrArg _ hxx
      · rw [tr_of_notMem h] at hxx
        rw [restrictB_of_notMem c x h, restrictB_of_notMem c x' h]
        exact hxx

variable (c) in
/-- The composite variables contributed by `A` (its own variables and the glued ones). -/
def varsA : Finset (composeNet c).V := Finset.univ.map Function.Embedding.inl

variable (c) in
/-- The composite variables contributed by `B` alone: its non-input ("private") variables. -/
def varsB : Finset (composeNet c).V := Finset.univ.map Function.Embedding.inr

@[simp] theorem inl_mem_varsA (a : A.V) : (Sum.inl a : (composeNet c).V) ∈ varsA c :=
  Finset.mem_map_of_mem _ (Finset.mem_univ a)

@[simp] theorem inr_notMem_varsA (w : Priv B) : (Sum.inr w : (composeNet c).V) ∉ varsA c := by
  simp [varsA]

@[simp] theorem inr_mem_varsB (w : Priv B) : (Sum.inr w : (composeNet c).V) ∈ varsB c :=
  Finset.mem_map_of_mem _ (Finset.mem_univ w)

@[simp] theorem inl_notMem_varsB (a : A.V) : (Sum.inl a : (composeNet c).V) ∉ varsB c := by
  simp [varsB]

/-- The two halves are disjoint. -/
theorem disjoint_varsA_varsB : Disjoint (varsA c) (varsB c) := by
  rw [Finset.disjoint_left]
  rintro (a | w) hA hB
  · exact inl_notMem_varsB a hB
  · exact inr_notMem_varsA w hA

/-- The two halves of the composite's variables partition it. -/
theorem compl_varsA : (varsA c)ᶜ = varsB c := by
  ext v; cases v <;> simp [varsA, varsB]

/-- The composite mechanisms targeting the `A` side are exactly `A`'s. -/
theorem filter_target_mem_varsA :
    (Finset.univ.filter fun m => (composeNet c).target m ∈ varsA c)
      = Finset.univ.map Function.Embedding.inl := by
  ext m; cases m <;> simp [varsA]

/-- **Proposition 3, downstream half, for open networks.** Summing the joint of the composite
over all values of `B`'s private variables leaves the joint of `A` — the semantics of `B ∘ A`
marginalised back onto `A`'s variables is the semantics of `A`. Only `B`'s kernels have to be
normalised. -/
theorem marg_joint_compose [CommSemiring R] (κA : A.Kernel R) (κB : B.Kernel R)
    (hlocA : ∀ m, Local κA m) (hlocB : ∀ m, Local κB m) (hnormB : ∀ m, Normalised κB m)
    (x₀ : (composeNet c).Assignment) :
    marg (varsB c) (joint (composeKernel c κA κB)) x₀ = joint κA (restrictA c x₀) := by
  have h := marg_joint_downstream (bn := composeNet c) (composeKernel c κA κB)
    (composeNet_target_injective c) (composeTopo c) (local_compose κA κB hlocA hlocB) (varsA c)
    (by
      rintro (m | m) hm
      · exact absurd (inl_mem_varsA (A.target m)) hm
      · exact fun x => hnormB m (restrictB c x))
    (by
      rintro (m | m) hm p hp
      · rw [composeNet_parents_inl, Finset.mem_map] at hp
        obtain ⟨a, _, rfl⟩ := hp
        exact inl_mem_varsA a
      · exact absurd hm (by simp [varsA]))
    (by
      rintro (a | w) hv
      · exact absurd (inl_mem_varsA a) hv
      · obtain ⟨m, hm⟩ := B.exists_mechanism w.property
        exact ⟨.inr m, congrArg Sum.inr (Subtype.ext hm)⟩)
    x₀
  rw [compl_varsA] at h
  rw [h, filter_target_mem_varsA, Finset.prod_map]
  rfl

/-- **Proposition 3 (sequential compositionality, SPEC §13.2, §61).** For any set `S` of
composite variables coming from `A` and any disjoint set `T` coming from `B`'s private part,
integrating `S ∪ T` out of the joint of the composite is the same as integrating `T` out of
`B`'s joint first, multiplying by `A`'s joint, and then integrating `S` out. Taking `S` to be
`A`'s hidden variables together with the glued interface and `T` to be `B`'s hidden variables,
this reads `⟦B ∘ A⟧ = ⟦B⟧ ∘ ⟦A⟧`: the composite semantics is the sum over the interface of the
product of the two open semantics. -/
theorem marg_joint_compose_split [CommSemiring R] (κA : A.Kernel R) (κB : B.Kernel R)
    {S T : Finset (composeNet c).V} (hS : S ⊆ varsA c) (hT : T ⊆ varsB c)
    (x : (composeNet c).Assignment) :
    marg (S ∪ T) (joint (composeKernel c κA κB)) x
      = marg S (fun y => joint κA (restrictA c y)
          * marg T (fun z => joint κB (restrictB c z)) y) x := by
  have hjc : joint (composeKernel c κA κB)
      = fun z => joint κA (restrictA c z) * joint κB (restrictB c z) :=
    funext fun z => joint_compose κA κB z
  rw [marg_union_disjoint ((disjoint_varsA_varsB (c := c)).mono hS hT), hjc]
  unfold marg
  refine Finset.sum_congr rfl fun y _ => ?_
  refine marg_mul_left fun z hz => ?_
  have : restrictA c z = restrictA c y := by
    funext a
    exact mem_fibre.1 hz (Sum.inl a) fun hmem => inl_notMem_varsB a (hT hmem)
  rw [this]

variable (c) in
/-- Composing a *closed* network `A` (no inputs) with an open `B` gives a closed network: every
composite variable still has exactly one mechanism. -/
theorem closed_compose (h : A.inputs = ∅) : (composeNet c).Closed := by
  refine ⟨composeNet_target_injective c, ?_⟩
  rintro (a | w)
  · obtain ⟨m, hm⟩ := A.exists_mechanism (show a ∉ A.inputs by simp [h])
    exact ⟨.inl m, congrArg Sum.inl hm⟩
  · obtain ⟨m, hm⟩ := B.exists_mechanism w.property
    exact ⟨.inr m, congrArg Sum.inr (Subtype.ext hm)⟩

/-- Proposition 1a for a composite with a closed left factor: `⟦B ∘ A⟧` is a probability
distribution on the composite variables. -/
theorem sum_joint_compose_eq_one [CommSemiring R] (h : A.inputs = ∅) (κA : A.Kernel R)
    (κB : B.Kernel R) (hlocA : ∀ m, Local κA m) (hlocB : ∀ m, Local κB m)
    (hnormA : ∀ m, Normalised κA m) (hnormB : ∀ m, Normalised κB m) :
    ∑ x, joint (composeKernel c κA κB) x = 1 :=
  sum_joint_eq_one _ (closed_compose c h) (composeTopo c) (local_compose κA κB hlocA hlocB)
    (normalised_compose κA κB hnormA hnormB)

end Semantics

end Composable

end OpenFinBayesNet

end BayesianNetworksProofs

