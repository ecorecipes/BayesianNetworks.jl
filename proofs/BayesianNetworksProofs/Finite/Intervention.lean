import BayesianNetworksProofs.Finite.Evaluation

/-!
# BayesianNetworksProofs.Finite.Intervention

**Proposition 4 (hard intervention)** for the concrete finite model (SPEC §21.2, §22).

`do(X = a)` replaces the mechanism `m₀` generating `X` by the point mass `δ_a`, ignoring its
former parents. Syntactically this is `cut bn m₀` (the `Input` rows of `m₀` are deleted, i.e.
`parents m₀ := ∅`); semantically it is `intervene κ m₀ a`, which overwrites the kernel of `m₀`
with the indicator of `a`.

* `joint_intervene` — the truncated factorisation: the intervened joint is the indicator
  `[x X = a]` times the product of the *other* mechanisms' kernels, which are untouched.
* `normalised_intervene`, `local_cut` — the intervened family is again normalised and local for
  the rewritten network, so Proposition 1 applies to it (`sum_joint_intervene_eq_one`).
-/

namespace BayesianNetworksProofs

namespace FinBayesNet

variable {bn : FinBayesNet} {R : Type}

/-- The syntactic rewrite `do`: the mechanism `m₀` keeps its target but loses its inputs. -/
def cut (bn : FinBayesNet) (m₀ : bn.M) : FinBayesNet :=
  { bn with parents := Function.update bn.parents m₀ ∅ }

@[simp] theorem cut_parents (m₀ m : bn.M) :
    (bn.cut m₀).parents m = Function.update bn.parents m₀ ∅ m := rfl

/-- A topological order of `bn` is one of `bn.cut m₀` (parents only shrink). -/
def TopoOrder.cut (ord : bn.TopoOrder) (m₀ : bn.M) : (bn.cut m₀).TopoOrder where
  order := ord.order
  nodup := ord.nodup
  complete := ord.complete
  parents_before := ord.parents_before.imp fun {a b} h (m : bn.M) hm => by
    show b ∉ Function.update bn.parents m₀ ∅ m
    by_cases hmm : m = m₀
    · subst hmm
      simp
    · rw [Function.update_of_ne hmm]
      exact h m hm
  no_self := fun (m : bn.M) => by
    show bn.target m ∉ Function.update bn.parents m₀ ∅ m
    by_cases hmm : m = m₀
    · subst hmm
      simp
    · rw [Function.update_of_ne hmm]
      exact ord.no_self m

theorem closed_cut (hclosed : bn.Closed) (m₀ : bn.M) : (bn.cut m₀).Closed := hclosed

variable [CommSemiring R]

/-- The semantic rewrite: replace the kernel of `m₀` by the point mass at `a`. -/
def intervene (κ : bn.Kernel R) (m₀ : bn.M) (a : bn.states (bn.target m₀)) : bn.Kernel R :=
  Function.update κ m₀ (fun _ y => if y = a then 1 else 0)

@[simp] theorem intervene_self (κ : bn.Kernel R) (m₀ : bn.M) (a : bn.states (bn.target m₀))
    (x : bn.Assignment) (y : bn.states (bn.target m₀)) :
    intervene κ m₀ a m₀ x y = if y = a then 1 else 0 := by
  simp [intervene]

theorem intervene_of_ne (κ : bn.Kernel R) {m₀ m : bn.M} (h : m ≠ m₀)
    (a : bn.states (bn.target m₀)) : intervene κ m₀ a m = κ m := by
  simp [intervene, Function.update_of_ne h]

/-- **Proposition 4** (truncated factorisation). -/
theorem joint_intervene (κ : bn.Kernel R) (m₀ : bn.M) (a : bn.states (bn.target m₀))
    (x : bn.Assignment) :
    joint (intervene κ m₀ a) x =
      (if x (bn.target m₀) = a then 1 else 0) *
        ∏ m ∈ Finset.univ.erase m₀, κ m x (x (bn.target m)) := by
  unfold joint
  rw [← Finset.mul_prod_erase Finset.univ _ (Finset.mem_univ m₀)]
  congr 1
  · simp
  · exact Finset.prod_congr rfl fun m hm => by
      rw [intervene_of_ne κ (Finset.ne_of_mem_erase hm)]

/-- The point-mass kernel is normalised. -/
theorem normalised_intervene_self (κ : bn.Kernel R) (m₀ : bn.M) (a : bn.states (bn.target m₀)) :
    Normalised (intervene κ m₀ a) m₀ := by
  intro x
  simp

/-- Intervening preserves normalisation of every mechanism. -/
theorem normalised_intervene (κ : bn.Kernel R) (hnorm : ∀ m, Normalised κ m) (m₀ : bn.M)
    (a : bn.states (bn.target m₀)) : ∀ m, Normalised (intervene κ m₀ a) m := by
  intro m
  by_cases h : m = m₀
  · subst h
    exact normalised_intervene_self κ m a
  · intro x
    rw [intervene_of_ne κ h]
    exact hnorm m x

/-- The point-mass kernel reads no parents at all. -/
theorem localOn_empty_intervene (κ : bn.Kernel R) (m₀ : bn.M) (a : bn.states (bn.target m₀)) :
    LocalOn ∅ (intervene κ m₀ a m₀) := by
  intro x x' _
  funext y
  simp

/-- The intervened family is local for the rewritten network `bn.cut m₀`. -/
theorem local_cut (κ : bn.Kernel R) (hloc : ∀ m, Local κ m) (m₀ : bn.M)
    (a : bn.states (bn.target m₀)) :
    ∀ m, Local (bn := bn.cut m₀) (intervene κ m₀ a) m := by
  refine fun (m : bn.M) (x x' : bn.Assignment) hx => ?_
  by_cases h : m = m₀
  · subst h
    exact localOn_empty_intervene κ m a x x' (fun p hp => absurd hp (Finset.notMem_empty p))
  · show intervene κ m₀ a m x = intervene κ m₀ a m x'
    rw [intervene_of_ne κ h]
    refine hloc m x x' fun p hp => hx p ?_
    show p ∈ Function.update bn.parents m₀ ∅ m
    rw [Function.update_of_ne h]
    exact hp

/-- The intervened joint is again a probability distribution (Proposition 1 applied to the
rewritten network). -/
theorem sum_joint_intervene_eq_one (κ : bn.Kernel R) (hclosed : bn.Closed) (ord : bn.TopoOrder)
    (hloc : ∀ m, Local κ m) (hnorm : ∀ m, Normalised κ m) (m₀ : bn.M)
    (a : bn.states (bn.target m₀)) :
    ∑ x, joint (intervene κ m₀ a) x = 1 :=
  sum_joint_eq_one (bn := bn.cut m₀) (intervene κ m₀ a) (closed_cut hclosed m₀) (ord.cut m₀)
    (local_cut κ hloc m₀ a) (normalised_intervene κ hnorm m₀ a)

end FinBayesNet

end BayesianNetworksProofs
