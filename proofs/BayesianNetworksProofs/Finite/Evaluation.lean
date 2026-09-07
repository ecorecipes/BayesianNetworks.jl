import BayesianNetworksProofs.Finite.BayesNet
import Mathlib.Algebra.BigOperators.Ring.Finset

/-!
# BayesianNetworksProofs.Finite.Evaluation

**Proposition 1 (BN evaluation)** for the concrete finite model.

* `sum_joint_eq_one` (Prop 1a): for a closed network with local, normalised kernels the joint
  `∏ m, κ m x (x (target m))` sums to one over all assignments, i.e. it is a probability
  distribution — the state `p_G : I → ⨂ X_v` of SPEC §5.
* `evalSeq_eq_joint` (Prop 1b): the sequential evaluator that walks a topological order and
  multiplies in the kernels of the mechanisms generating each variable computes the same
  product.

The proof of 1a integrates the variables out one at a time along the topological order. To
stay free of dependent tuples, "integrating out `S`" is expressed with `fibre S x₀`, the finite
set of assignments agreeing with a base assignment `x₀` outside `S`; `marg S F x₀` sums `F`
over that fibre. Adding a variable to `S` splits the fibre by the value of that variable
(`marg_insert`), and locality lets the kernel of the newest variable be pulled out of the sum.
-/

namespace BayesianNetworksProofs

namespace FinBayesNet

variable {bn : FinBayesNet} {R : Type}

/-! ## Fibres and marginalisation -/

/-- Assignments agreeing with `x₀` outside `S`. -/
def fibre (S : Finset bn.V) (x₀ : bn.Assignment) : Finset bn.Assignment :=
  Finset.univ.filter (fun y => ∀ v, v ∉ S → y v = x₀ v)

theorem mem_fibre {S : Finset bn.V} {x₀ y : bn.Assignment} :
    y ∈ fibre S x₀ ↔ ∀ v, v ∉ S → y v = x₀ v := by
  simp [fibre]

theorem fibre_empty (x₀ : bn.Assignment) : fibre (∅ : Finset bn.V) x₀ = {x₀} := by
  ext y
  simp [mem_fibre, funext_iff]

theorem fibre_univ (x₀ : bn.Assignment) : fibre (Finset.univ : Finset bn.V) x₀ = Finset.univ := by
  ext y
  simp [mem_fibre]

/-- Splitting the fibre of `insert v₀ S` by the value at `v₀`. -/
theorem fibre_insert_filter {S : Finset bn.V} {v₀ : bn.V} (hv : v₀ ∉ S) (x₀ : bn.Assignment)
    (z : bn.states v₀) :
    (fibre (insert v₀ S) x₀).filter (fun y => y v₀ = z) = fibre S (Function.update x₀ v₀ z) := by
  ext y
  simp only [Finset.mem_filter, mem_fibre, Finset.mem_insert, not_or]
  constructor
  · rintro ⟨h, hz⟩ v hvS
    by_cases hvv : v = v₀
    · subst hvv
      simp [hz]
    · rw [Function.update_of_ne hvv]
      exact h v ⟨hvv, hvS⟩
  · intro h
    refine ⟨fun v ⟨hvv, hvS⟩ => ?_, ?_⟩
    · have := h v hvS
      rwa [Function.update_of_ne hvv] at this
    · have := h v₀ hv
      simpa using this

variable [CommSemiring R]

/-- Sum of `F` over the assignments agreeing with `x₀` outside `S`. -/
def marg (S : Finset bn.V) (F : bn.Assignment → R) (x₀ : bn.Assignment) : R :=
  ∑ y ∈ fibre S x₀, F y

theorem marg_empty (F : bn.Assignment → R) (x₀ : bn.Assignment) : marg ∅ F x₀ = F x₀ := by
  simp [marg, fibre_empty]

theorem marg_univ (F : bn.Assignment → R) (x₀ : bn.Assignment) :
    marg Finset.univ F x₀ = ∑ y, F y := by
  simp [marg, fibre_univ]

theorem marg_insert {S : Finset bn.V} {v₀ : bn.V} (hv : v₀ ∉ S) (F : bn.Assignment → R)
    (x₀ : bn.Assignment) :
    marg (insert v₀ S) F x₀ = ∑ z, marg S F (Function.update x₀ v₀ z) := by
  unfold marg
  rw [← Finset.sum_fiberwise (fibre (insert v₀ S) x₀) (fun y => y v₀) F]
  refine Finset.sum_congr rfl fun z _ => ?_
  rw [fibre_insert_filter hv]

/-- Integrating out `S ∪ T` (disjoint) is integrating out `S` and then, inside, `T`: the finite
Fubini theorem for fibres. -/
theorem marg_union_disjoint {S T : Finset bn.V} (hd : Disjoint S T) (F : bn.Assignment → R)
    (x₀ : bn.Assignment) : marg (S ∪ T) F x₀ = marg S (fun y => marg T F y) x₀ := by
  induction S using Finset.induction_on generalizing x₀ with
  | empty => simp [marg_empty]
  | insert v₀ S hv ih =>
    have hvT : v₀ ∉ T := fun h => (Finset.disjoint_left.1 hd (Finset.mem_insert_self v₀ S)) h
    have hd' : Disjoint S T := hd.mono_left (Finset.subset_insert _ _)
    rw [Finset.insert_union, marg_insert (by simp [hv, hvT]), marg_insert hv]
    exact Finset.sum_congr rfl fun z _ => ih hd' _

/-- A factor that is constant on the fibre comes out of the sum. -/
theorem marg_mul_left {T : Finset bn.V} {F G : bn.Assignment → R} {x₀ : bn.Assignment}
    (hF : ∀ y ∈ fibre T x₀, F y = F x₀) :
    marg T (fun y => F y * G y) x₀ = F x₀ * marg T G x₀ := by
  unfold marg
  rw [Finset.mul_sum]
  exact Finset.sum_congr rfl fun y hy => by show F y * G y = F x₀ * G y; rw [hF y hy]

/-! ## Partial joints along a list of variables -/

/-- The product of the kernels of the mechanisms whose target lies in `l`. -/
def partialJoint (κ : bn.Kernel R) (l : List bn.V) (x : bn.Assignment) : R :=
  ∏ m ∈ Finset.univ.filter (fun m => bn.target m ∈ l), κ m x (x (bn.target m))

theorem filter_target_cons (hinj : Function.Injective bn.target) {l : List bn.V} (m₀ : bn.M) :
    Finset.univ.filter (fun m => bn.target m ∈ bn.target m₀ :: l) =
      insert m₀ (Finset.univ.filter (fun m => bn.target m ∈ l)) := by
  ext m
  simp only [Finset.mem_filter, Finset.mem_univ, true_and, List.mem_cons, Finset.mem_insert]
  constructor
  · rintro (h | h)
    · exact Or.inl (hinj h)
    · exact Or.inr h
  · rintro (rfl | h)
    · exact Or.inl rfl
    · exact Or.inr h

/-- The core induction: integrating out the variables of a suffix `l` of a topological order
(every variable in `l` has a mechanism, every parent of a mechanism targeting `l` that lies in
`l` comes earlier) gives total weight one, whatever the values of the other variables. -/
theorem marg_partialJoint_eq_one (κ : bn.Kernel R) (hinj : Function.Injective bn.target)
    (hloc : ∀ m, Local κ m)
    (hself : ∀ m, bn.target m ∉ bn.parents m) (l : List bn.V) (hnd : l.Nodup)
    (hnorm : ∀ m, bn.target m ∈ l → Normalised κ m)
    (hpw : l.Pairwise (fun a b => ∀ m, bn.target m = a → b ∉ bn.parents m))
    (hsurj : ∀ v ∈ l, ∃ m, bn.target m = v) (x₀ : bn.Assignment) :
    marg l.toFinset (partialJoint κ l) x₀ = 1 := by
  induction l generalizing x₀ with
  | nil => simp [marg_empty, partialJoint]
  | cons v₀ l ih =>
    obtain ⟨m₀, hm₀⟩ := hsurj v₀ (List.mem_cons_self ..)
    subst hm₀
    rw [List.nodup_cons] at hnd
    rw [List.pairwise_cons] at hpw
    have hnotl : bn.target m₀ ∉ l.toFinset := by simpa using hnd.1
    rw [List.toFinset_cons, marg_insert hnotl]
    have key : ∀ z, marg l.toFinset (partialJoint κ (bn.target m₀ :: l))
        (Function.update x₀ (bn.target m₀) z) = κ m₀ x₀ z := by
      intro z
      have hfac : ∀ y ∈ fibre l.toFinset (Function.update x₀ (bn.target m₀) z),
          partialJoint κ (bn.target m₀ :: l) y = κ m₀ x₀ z * partialJoint κ l y := by
        intro y hy
        rw [mem_fibre] at hy
        unfold partialJoint
        rw [filter_target_cons hinj, Finset.prod_insert (by simpa using hnd.1)]
        congr 1
        have hy0 : y (bn.target m₀) = z := by
          rw [hy _ hnotl, Function.update_self]
        have hκ : κ m₀ y = κ m₀ x₀ := by
          refine hloc m₀ y x₀ fun p hp => ?_
          have hpl : p ∉ l := fun hpl => hpw.1 p hpl m₀ rfl hp
          have hne : p ≠ bn.target m₀ := fun h => hself m₀ (h ▸ hp)
          rw [hy p (by simpa using hpl), Function.update_of_ne hne]
        rw [hκ, hy0]
      unfold marg
      rw [Finset.sum_congr rfl hfac, ← Finset.mul_sum]
      have := ih hnd.2 (fun m hm => hnorm m (List.mem_cons_of_mem _ hm)) hpw.2
        (fun v hv => hsurj v (List.mem_cons_of_mem _ hv))
        (Function.update x₀ (bn.target m₀) z)
      unfold marg at this
      rw [this, mul_one]
    rw [Finset.sum_congr rfl fun z _ => key z]
    exact hnorm m₀ (List.mem_cons_self ..) x₀

/-! ## Proposition 1 -/

/-- **Proposition 1a.** In a closed network with a topological order, local and normalised
kernels make the joint a probability distribution. -/
theorem sum_joint_eq_one (κ : bn.Kernel R) (hclosed : bn.Closed) (ord : bn.TopoOrder)
    (hloc : ∀ m, Local κ m) (hnorm : ∀ m, Normalised κ m) :
    ∑ x, joint κ x = 1 := by
  obtain ⟨x₀⟩ : Nonempty bn.Assignment := inferInstance
  have h := marg_partialJoint_eq_one κ hclosed.1 hloc ord.no_self ord.order ord.nodup
    (fun m _ => hnorm m) ord.parents_before (fun v _ => hclosed.2 v) x₀
  have hu : ord.order.toFinset = Finset.univ :=
    Finset.eq_univ_of_forall fun v => by simpa using ord.complete v
  rw [hu, marg_univ] at h
  rw [← h]
  refine Finset.sum_congr rfl fun x _ => ?_
  unfold joint partialJoint
  rw [Finset.filter_true_of_mem fun m _ => ord.complete _]

/-- The sequential evaluator: walk the variables in the given order and multiply in the kernels
of the mechanisms generating each of them. This is the loop `for v in order` of
`joint_distribution` in Julia. -/
def evalSeq (κ : bn.Kernel R) (l : List bn.V) (x : bn.Assignment) : R :=
  (l.map fun v => ∏ m ∈ Finset.univ.filter (fun m => bn.target m = v), κ m x (x (bn.target m))).prod

/-- **Proposition 1b.** The sequential evaluator along any complete duplicate-free order of the
variables computes the joint product (no acyclicity or closedness is needed for this identity). -/
theorem evalSeq_eq_joint (κ : bn.Kernel R) (l : List bn.V) (hnd : l.Nodup) (hcomp : ∀ v, v ∈ l)
    (x : bn.Assignment) : evalSeq κ l x = joint κ x := by
  unfold evalSeq joint
  have hu : l.toFinset = Finset.univ := Finset.eq_univ_of_forall fun v => by simpa using hcomp v
  rw [← List.prod_toFinset _ hnd, hu]
  exact Finset.prod_fiberwise Finset.univ bn.target _

/-- Proposition 1b specialised to a topological order. -/
theorem evalSeq_topo_eq_joint (κ : bn.Kernel R) (ord : bn.TopoOrder) (x : bn.Assignment) :
    evalSeq κ ord.order x = joint κ x :=
  evalSeq_eq_joint κ ord.order ord.nodup ord.complete x


/-! ## Marginalising the downstream variables out (Proposition 3, closed-world shadow) -/

/-- A set of "upstream" variables `U` is *closed under parents*: every mechanism generating a
variable of `U` reads only variables of `U`. -/
def UpstreamClosed (U : Finset bn.V) : Prop :=
  ∀ m, bn.target m ∈ U → bn.parents m ⊆ U

/-- **Integrating the downstream variables out.** If `U` is closed under parents, every variable
outside `U` is generated by some mechanism, and the kernels of those mechanisms are normalised,
then summing the joint over all assignments that agree with `x₀` on `U` leaves exactly the
product of the kernels of the mechanisms targeting `U`. Only the *downstream* kernels have to be
normalised; the upstream ones merely have to be local.

This is the closed-world shadow of **Proposition 3** (SPEC §61): the downstream half of a
sequential composite integrates out to one, so the marginal of `⟦B ∘ A⟧` on `A`'s variables is
`⟦A⟧`. See `BayesianNetworksProofs.Finite.Open` for the open-network form
(`OpenFinBayesNet.Composable.marg_joint_compose`). -/
theorem marg_joint_downstream (κ : bn.Kernel R) (hinj : Function.Injective bn.target)
    (ord : bn.TopoOrder) (hloc : ∀ m, Local κ m) (U : Finset bn.V)
    (hnorm : ∀ m, bn.target m ∉ U → Normalised κ m)
    (hU : UpstreamClosed U) (hmech : ∀ v ∉ U, ∃ m, bn.target m = v) (x₀ : bn.Assignment) :
    marg Uᶜ (joint κ) x₀ =
      ∏ m ∈ Finset.univ.filter (fun m => bn.target m ∈ U), κ m x₀ (x₀ (bn.target m)) := by
  set l := ord.order.filter (fun v => decide (v ∉ U)) with hl
  have hmemL : ∀ v, v ∈ l ↔ v ∉ U := by
    intro v
    rw [hl, List.mem_filter]
    simp [ord.complete v]
  have hlt : l.toFinset = Uᶜ := by
    ext v
    simp [hmemL v]
  have key := marg_partialJoint_eq_one κ hinj hloc ord.no_self l (ord.nodup.filter _)
    (fun m hm => hnorm m ((hmemL _).1 hm)) (ord.parents_before.filter _)
    (fun v hv => hmech v ((hmemL v).1 hv)) x₀
  rw [← hlt]
  unfold marg at key ⊢
  have hfac : ∀ y ∈ fibre l.toFinset x₀, joint κ y =
      (∏ m ∈ Finset.univ.filter (fun m => bn.target m ∈ U), κ m x₀ (x₀ (bn.target m)))
        * partialJoint κ l y := by
    intro y hy
    rw [mem_fibre] at hy
    have hagree : ∀ v ∈ U, y v = x₀ v := fun v hv =>
      hy v (by simp [List.mem_toFinset, hmemL v, hv])
    unfold joint partialJoint
    rw [← Finset.prod_filter_mul_prod_filter_not Finset.univ (fun m => bn.target m ∈ U)]
    congr 1
    · refine Finset.prod_congr rfl fun m hm => ?_
      have hmU : bn.target m ∈ U := (Finset.mem_filter.1 hm).2
      rw [hloc m y x₀ fun p hp => hagree p (hU m hmU hp), hagree _ hmU]
    · exact Finset.prod_congr (by ext m; simp [hmemL]) fun m _ => rfl
  rw [Finset.sum_congr rfl hfac, ← Finset.mul_sum, key, mul_one]

/-- **Proposition 3 (closed-world shadow).** In a closed network with a topological order and
local, normalised kernels, integrating the downstream variables out of the full joint leaves the
joint of the upstream mechanisms. -/
theorem marg_joint_upstream (κ : bn.Kernel R) (hclosed : bn.Closed) (ord : bn.TopoOrder)
    (hloc : ∀ m, Local κ m) (hnorm : ∀ m, Normalised κ m) (U : Finset bn.V)
    (hU : UpstreamClosed U) (x₀ : bn.Assignment) :
    marg Uᶜ (joint κ) x₀ =
      ∏ m ∈ Finset.univ.filter (fun m => bn.target m ∈ U), κ m x₀ (x₀ (bn.target m)) :=
  marg_joint_downstream κ hclosed.1 ord hloc U (fun m _ => hnorm m) hU
    (fun v _ => hclosed.2 v) x₀

end FinBayesNet

end BayesianNetworksProofs
