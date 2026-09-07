import BayesianNetworksProofs.Finite.Evaluation
import Mathlib.Data.Fintype.Sum
import Mathlib.Data.Fintype.BigOperators
import Mathlib.Data.Finset.Sum

/-!
# BayesianNetworksProofs.Finite.Tensor

**Proposition 2 (tensor compositionality)** for the concrete finite model (SPEC §13.1).

The tensor `bn₁.tensor bn₂` of two networks has variables `V₁ ⊕ V₂` and mechanisms `M₁ ⊕ M₂`
(the disjoint union of the two ACSets, `⊗` of `OpenBayesNet`s with no shared feet). Its kernels
are the two families side by side, and `joint_tensor` shows that the joint of the tensor is the
product of the two joints — `⟦A ⊗ B⟧ = ⟦A⟧ ⊗ ⟦B⟧` in the finite stochastic semantics. The
tensor of closed / local / normalised / topologically ordered networks is again so.
-/

namespace BayesianNetworksProofs

namespace FinBayesNet

/-- Disjoint union of two networks. Reducible so that `simp`/`rw` see `V = V₁ ⊕ V₂` etc. -/
@[reducible] def tensor (bn₁ bn₂ : FinBayesNet) : FinBayesNet where
  V := bn₁.V ⊕ bn₂.V
  M := bn₁.M ⊕ bn₂.M
  states := Sum.elim bn₁.states bn₂.states
  fintypeS := fun
    | .inl v => bn₁.fintypeS v
    | .inr v => bn₂.fintypeS v
  decS := fun
    | .inl v => bn₁.decS v
    | .inr v => bn₂.decS v
  nonemptyS := fun
    | .inl v => bn₁.nonemptyS v
    | .inr v => bn₂.nonemptyS v
  target := Sum.map bn₁.target bn₂.target
  parents := fun
    | .inl m => (bn₁.parents m).map Function.Embedding.inl
    | .inr m => (bn₂.parents m).map Function.Embedding.inr

variable {bn₁ bn₂ : FinBayesNet} {R : Type}

@[simp] theorem tensor_target_inl (m : bn₁.M) :
    (bn₁.tensor bn₂).target (.inl m) = .inl (bn₁.target m) := rfl

@[simp] theorem tensor_target_inr (m : bn₂.M) :
    (bn₁.tensor bn₂).target (.inr m) = .inr (bn₂.target m) := rfl

@[simp] theorem tensor_parents_inl (m : bn₁.M) :
    (bn₁.tensor bn₂).parents (.inl m) = (bn₁.parents m).map Function.Embedding.inl := rfl

@[simp] theorem tensor_parents_inr (m : bn₂.M) :
    (bn₁.tensor bn₂).parents (.inr m) = (bn₂.parents m).map Function.Embedding.inr := rfl

@[simp] theorem inl_mem_map_inl {α β : Type} {s : Finset α} {a : α} :
    Sum.inl a ∈ s.map (Function.Embedding.inl (β := β)) ↔ a ∈ s := by
  simp [Finset.mem_map]

@[simp] theorem inr_mem_map_inr {α β : Type} {s : Finset β} {b : β} :
    Sum.inr b ∈ s.map (Function.Embedding.inr (α := α)) ↔ b ∈ s := by
  simp [Finset.mem_map]

@[simp] theorem inr_notMem_map_inl {α β : Type} {s : Finset α} {b : β} :
    Sum.inr b ∉ s.map (Function.Embedding.inl (β := β)) := by
  simp [Finset.mem_map]

@[simp] theorem inl_notMem_map_inr {α β : Type} {s : Finset β} {a : α} :
    Sum.inl a ∉ s.map (Function.Embedding.inr (α := α)) := by
  simp [Finset.mem_map]

/-- Restrict an assignment of the tensor to the left factor. -/
def Assignment.left (x : (bn₁.tensor bn₂).Assignment) : bn₁.Assignment := fun v => x (.inl v)

/-- Restrict an assignment of the tensor to the right factor. -/
def Assignment.right (x : (bn₁.tensor bn₂).Assignment) : bn₂.Assignment := fun v => x (.inr v)

/-- Two kernel families side by side. -/
def tensorKernel (κ₁ : bn₁.Kernel R) (κ₂ : bn₂.Kernel R) : (bn₁.tensor bn₂).Kernel R := fun
  | .inl m => fun x y => κ₁ m (Assignment.left x) y
  | .inr m => fun x y => κ₂ m (Assignment.right x) y

/-- **Proposition 2.** The joint of the tensor is the product of the joints. -/
theorem joint_tensor [CommMonoid R] (κ₁ : bn₁.Kernel R) (κ₂ : bn₂.Kernel R)
    (x : (bn₁.tensor bn₂).Assignment) :
    joint (tensorKernel κ₁ κ₂) x = joint κ₁ (Assignment.left x) * joint κ₂ (Assignment.right x) := by
  unfold joint
  exact Fintype.prod_sum_type _

theorem closed_tensor (h₁ : bn₁.Closed) (h₂ : bn₂.Closed) : (bn₁.tensor bn₂).Closed :=
  h₁.sumMap h₂

theorem normalised_tensor [AddCommMonoid R] [One R] (κ₁ : bn₁.Kernel R) (κ₂ : bn₂.Kernel R)
    (h₁ : ∀ m, Normalised κ₁ m) (h₂ : ∀ m, Normalised κ₂ m) :
    ∀ m, Normalised (tensorKernel κ₁ κ₂) m
  | .inl m => fun x => h₁ m (Assignment.left x)
  | .inr m => fun x => h₂ m (Assignment.right x)

theorem local_tensor (κ₁ : bn₁.Kernel R) (κ₂ : bn₂.Kernel R)
    (h₁ : ∀ m, Local κ₁ m) (h₂ : ∀ m, Local κ₂ m) :
    ∀ m, Local (tensorKernel κ₁ κ₂) m
  | .inl m => fun x x' hx =>
      h₁ m (Assignment.left x) (Assignment.left x') fun p hp =>
        hx (.inl p) (Finset.mem_map_of_mem _ hp)
  | .inr m => fun x x' hx =>
      h₂ m (Assignment.right x) (Assignment.right x') fun p hp =>
        hx (.inr p) (Finset.mem_map_of_mem _ hp)

/-- Concatenating topological orders gives a topological order of the tensor. -/
def TopoOrder.tensor (o₁ : bn₁.TopoOrder) (o₂ : bn₂.TopoOrder) : (bn₁.tensor bn₂).TopoOrder where
  order := o₁.order.map Sum.inl ++ o₂.order.map Sum.inr
  nodup := by
    refine List.Nodup.append (o₁.nodup.map Sum.inl_injective) (o₂.nodup.map Sum.inr_injective) ?_
    intro a h₁ h₂
    obtain ⟨v, _, rfl⟩ := List.mem_map.1 h₁
    obtain ⟨w, _, h⟩ := List.mem_map.1 h₂
    exact Sum.inr_ne_inl h
  complete := fun
    | .inl v => List.mem_append_left _ (List.mem_map_of_mem (o₁.complete v))
    | .inr v => List.mem_append_right _ (List.mem_map_of_mem (o₂.complete v))
  parents_before := by
    refine List.pairwise_append.2 ⟨List.pairwise_map.2 (o₁.parents_before.imp ?_),
      List.pairwise_map.2 (o₂.parents_before.imp ?_), ?_⟩
    · rintro a b h (m | m) hm
      · simpa using h m (Sum.inl_injective hm)
      · simp at hm
    · rintro a b h (m | m) hm
      · simp at hm
      · simpa using h m (Sum.inr_injective hm)
    · rintro a ha b hb (m | m) hm
      · obtain ⟨w, _, rfl⟩ := List.mem_map.1 hb
        simp
      · obtain ⟨v, _, rfl⟩ := List.mem_map.1 ha
        simp at hm
  no_self := fun
    | .inl m => by simpa using o₁.no_self m
    | .inr m => by simpa using o₂.no_self m

end FinBayesNet

end BayesianNetworksProofs
