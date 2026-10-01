import Mathlib.Data.Int.Log
import Mathlib.Data.Rat.Floor
import Mathlib.Data.Nat.Log
import Mathlib.Algebra.Order.Field.Power
import Mathlib.Tactic.Linarith
import Mathlib.Tactic.NormNum
import Mathlib.Tactic.Positivity
import Mathlib.Tactic.FieldSimp
import Mathlib.Tactic.Ring

/-!
# Correct rounding to binary64: `_nearest_binary64`, `_rational_exponent` and `_dyadic`

ADR 0016 makes the exact evidence-mass fallback of `BayesianNetworks` and
`BayesianNetworkInference`, and the exact decision elimination of `InfluenceDiagrams`, round
an exact rational once with `_nearest_binary64` from `BayesianNetworks/src/exact_rounding.jl`.
This module states IEEE 754 binary64 round-to-nearest-ties-to-even of a rational, transcribes
the three Julia functions over `ℕ`, `ℤ` and `ℚ`, and proves the transcriptions correct.

**The format.** A word is a natural number below `2 ^ 64` read as a UInt64: sign bit 63, an
11-bit biased exponent `field` (bits 52 to 62) and a 52-bit `fraction`. A field of `0` is a
zero or subnormal, `2 ^ -1022 * (fraction / 2 ^ 52)`; a field of `1` to `2046` is normal,
`2 ^ (field - 1023) * (1 + fraction / 2 ^ 52)`; a field of `2047` is an infinity (fraction `0`)
or a NaN. `decode` maps a word to that extended value, keeping the sign of a zero.

**The specification** (`RoundsTo q w`, IEEE 754-2019 §4.3.1 and §7.4). A rational of magnitude at
least `2 ^ 1024 - 2 ^ 970` (`b ^ emax * (b - b ^ (1 - p) / 2)`, the midpoint above the largest
finite value) rounds to the infinity of its sign. Any other rational rounds to a finite word
whose value is no farther from it than the value of any finite word; when a finite word of a
different value is equally near, the result's significand is even; and the result has the sign
of the rational, so a result of zero is `-0.0` for a negative rational and `+0.0` otherwise.

**The transcription.** `nearestBinary64` follows `_nearest_binary64` line by line with the
same branches and constants (`1023`, `-1075`, `52`, `-1074`, `-1022`, `0x8000000000000000`,
`0x7ff0000000000000`). Julia's `Rational{BigInt}` is normalized with a positive denominator, as
`ℚ` is, so `numerator` and `denominator` are `Rat.num` and `Rat.den`. `BigInt` shifts are `<<<`
on `ℕ` (multiplication by a power of two), `divrem` of nonnegative integers is `/` and `%`,
`isodd` is `% 2 = 1`, `ndigits(n; base = 2)` is `Nat.log 2 n + 1` (`1` at `0`, as in Julia), and
the `UInt64` conversions, `<<` and `|` act on values the proofs show to be in range, so the
word is a natural number below `2 ^ 64`. `reinterpret(Float64, word)` is `decode`.
`decompose` follows `Base.decompose(::Float64)` (Julia 1.12, `base/float.jl`) on the word, and
`dyadic` is `_dyadic`, with `none` for the `ArgumentError` it throws on a non-finite value.

**What is proved.**

* `rationalExponent_eq_log`: for `n, d > 0`, `rationalExponent n d = ⌊log₂ (n / d)⌋`
  (`Int.log 2`), with the two-sided bound in `rationalExponent_spec`.
* `nearestBinary64_roundsTo`: for every rational `q`, `RoundsTo q (nearestBinary64 q)`. This
  is the full range: zero (to `+0.0`), negative rationals, underflow to a signed zero,
  subnormals, the rounding of a subnormal up to the least normal, the carry into the exponent
  when the mantissa rounds up to `2 ^ 53`, and overflow exactly at `2 ^ 1024 - 2 ^ 970`.
* `dyadic_value`: on a finite word, `dyadic` returns the integer `±significand` and exponent
  `max field 1 - 1075`, whose value `n * 2 ^ p` is the word's value; `dyadic_none_iff`: it
  fails exactly on the infinities and NaNs. A negative zero gives `n = 0`.
* `nearestBinary64_value`: rounding a finite word's value returns that word, except that both
  zeros return `+0.0`, which the fallback's bit-exact tests rely on.

**What is not proved.** These are theorems about the transcribed algorithm on mathematical
integers and rationals. They do not cover Julia's execution of the source, GMP's `BigInt`
arithmetic, `reinterpret`, or that the transcription matches the Julia text; that last step is
a reading, recorded in `docs/LEAN-JULIA-DISCREPANCIES-2026-09-30.md`. The specification does
not include uniqueness or monotonicity of rounding.
-/

set_option autoImplicit false

namespace BayesianNetworksProofs.Binary64

/-! ## Binary64 words -/

/-- The sign bit (bit 63) of a word. -/
def signBit (w : ℕ) : Bool := decide (w / 2 ^ 63 % 2 = 1)

/-- The 11-bit biased exponent field (bits 52 to 62). -/
def field (w : ℕ) : ℕ := w / 2 ^ 52 % 2 ^ 11

/-- The 52-bit fraction (trailing significand) field. -/
def fraction (w : ℕ) : ℕ := w % 2 ^ 52

/-- A 64-bit word encoding a finite number: neither an infinity nor a NaN. -/
def IsFinite (w : ℕ) : Prop := w < 2 ^ 64 ∧ field w ≠ 2047

/-- The magnitude of a finite word: subnormal (and zero) for a field of `0`, normal otherwise. -/
def magnitude (w : ℕ) : ℚ :=
  if field w = 0 then (2 : ℚ) ^ (-1022 : ℤ) * (fraction w / 2 ^ 52)
  else (2 : ℚ) ^ ((field w : ℤ) - 1023) * (1 + fraction w / 2 ^ 52)

/-- The signed value of a finite word; both zeros have value `0`. -/
def value (w : ℕ) : ℚ := if signBit w then -magnitude w else magnitude w

/-- The integral significand: the fraction, with the hidden bit `2 ^ 52` for a normal word.
Its parity is the parity of the significand's last digit, which ties to even compares. -/
def significand (w : ℕ) : ℕ := if field w = 0 then fraction w else 2 ^ 52 + fraction w

/-- A binary64 datum: a finite number with its sign (so `-0.0` is `finite true 0`), an
infinity, or a NaN. -/
inductive Extended where
  | finite (negative : Bool) (x : ℚ)
  | infinity (negative : Bool)
  | nan
  deriving DecidableEq

/-- `reinterpret(Float64, w)`, as the datum it encodes. -/
def decode (w : ℕ) : Extended :=
  if field w = 2047 then (if fraction w = 0 then .infinity (signBit w) else .nan)
  else .finite (signBit w) (value w)

/-! ## The specification -/

/-- `2 ^ 1024 - 2 ^ 970`: the midpoint between the largest finite binary64 value
`(2 ^ 53 - 1) * 2 ^ 971` and `2 ^ 1024`. A rational of at least this magnitude overflows. -/
def overflowThreshold : ℚ := 2 ^ 1024 - 2 ^ 970

/-- `w` is the binary64 word that IEEE 754 round-to-nearest, ties-to-even, delivers for the
rational `q`: overflow to the infinity of `q`'s sign at or beyond `overflowThreshold`;
otherwise a finite word with `q`'s sign, at least as near `q` as every finite word, and with an
even significand when a finite word of a different value is equally near. -/
structure RoundsTo (q : ℚ) (w : ℕ) : Prop where
  word : w < 2 ^ 64
  overflow : overflowThreshold ≤ |q| → decode w = .infinity (decide (q < 0))
  finite : |q| < overflowThreshold → field w ≠ 2047
  sign : |q| < overflowThreshold → signBit w = decide (q < 0)
  nearest : |q| < overflowThreshold → ∀ w', IsFinite w' → |value w - q| ≤ |value w' - q|
  tiesToEven : |q| < overflowThreshold → ∀ w', IsFinite w' →
    |value w' - q| = |value w - q| → value w' ≠ value w → Even (significand w)

/-! ## The transcription of `src/exact_rounding.jl` -/

/-- Julia's `ndigits(n; base = 2)`: the number of binary digits of `n`, and `1` for `0`. -/
def ndigits2 (n : ℕ) : ℕ := Nat.log 2 n + 1

/-- `_rational_exponent(n, d)`. -/
def rationalExponent (n d : ℕ) : ℤ :=
  let exponent : ℤ := (ndigits2 n : ℤ) - ndigits2 d
  let below : Bool :=
    if exponent ≥ 0 then decide (n < d <<< exponent.toNat)
    else decide (n <<< (-exponent).toNat < d)
  if below then exponent - 1 else exponent

/-- `_nearest_binary64(value::Rational{BigInt})`, returning the word that Julia reinterprets
as a `Float64`. -/
def nearestBinary64 (value : ℚ) : ℕ :=
  if value = 0 then 0 else
  let sign_bits : ℕ := if value < 0 then 0x8000000000000000 else 0
  let n := value.num.natAbs
  let d := value.den
  let exponent := rationalExponent n d
  if exponent > 1023 then sign_bits ||| 0x7ff0000000000000 else
  if exponent < -1075 then sign_bits else
  let shift : ℤ := max (exponent - 52) (-1074)
  let numerator_ := if shift < 0 then n <<< (-shift).toNat else n
  let denominator_ := if shift > 0 then d <<< shift.toNat else d
  let mantissa := numerator_ / denominator_
  let remainder := numerator_ % denominator_
  let twice := 2 * remainder
  let mantissa :=
    if twice > denominator_ ∨ (twice = denominator_ ∧ mantissa % 2 = 1) then mantissa + 1
    else mantissa
  let hidden_bit := 1 <<< 52
  let word :=
    if mantissa < hidden_bit then mantissa
    else
      let field := max exponent (-1022) + 1023
      let (mantissa, field) :=
        if mantissa = 2 * hidden_bit then (hidden_bit, field + 1) else (mantissa, field)
      (field.toNat <<< 52) ||| (mantissa - hidden_bit)
  sign_bits ||| word

/-- `Base.decompose(x::Float64)` on the word of `x`: `(num, pow, den)` with `x = num * 2 ^ pow
/ den`, `(0, 0, 0)` for a NaN and `(±1, 0, 0)` for an infinity. -/
def decompose (w : ℕ) : ℤ × ℤ × ℤ :=
  if field w = 2047 ∧ fraction w ≠ 0 then (0, 0, 0) else
  if field w = 2047 then ((if signBit w then -1 else 1), 0, 0) else
  let s := w &&& 0x000fffffffffffff
  let e := (w &&& 0x7ff0000000000000) >>> 52
  let s := s ||| ((if e ≠ 0 then 1 else 0) <<< 52)
  let d : ℤ := if signBit w then -1 else 1
  ((s : ℤ), (e : ℤ) - 1075 + (if e = 0 then 1 else 0), d)

/-- `_dyadic(x)`: `(BigInt(num) * sign(den), Int(pow))`, and `none` where Julia throws the
`ArgumentError` for a non-finite `x`. -/
def dyadic (w : ℕ) : Option (ℤ × ℤ) :=
  if field w = 2047 then none
  else
    let (num, pow, den) := decompose w
    some (num * Int.sign den, pow)

/-! ## `_rational_exponent` is the binary logarithm -/

theorem rationalExponent_spec (n d : ℕ) (hn : 0 < n) (hd : 0 < d) :
    (2 : ℚ) ^ rationalExponent n d ≤ (n : ℚ) / d ∧
      (n : ℚ) / d < (2 : ℚ) ^ (rationalExponent n d + 1) := by
  have hn1 := Nat.pow_log_le_self 2 hn.ne'
  have hn2 := Nat.lt_pow_succ_log_self (by norm_num : 1 < 2) n
  have hd1 := Nat.pow_log_le_self 2 hd.ne'
  have hd2 := Nat.lt_pow_succ_log_self (by norm_num : 1 < 2) d
  set a := Nat.log 2 n
  set b := Nat.log 2 d
  have hdq : (0 : ℚ) < d := by exact_mod_cast hd
  have hnq1 : (2 : ℚ) ^ a ≤ n := by exact_mod_cast hn1
  have hnq2 : (n : ℚ) < 2 ^ (a + 1) := by exact_mod_cast hn2
  have hdq1 : (2 : ℚ) ^ b ≤ d := by exact_mod_cast hd1
  have hdq2 : (d : ℚ) < 2 ^ (b + 1) := by exact_mod_cast hd2
  -- `below` is the comparison `n / d < 2 ^ exponent`.
  have hbelow : ∀ E : ℤ, ((if E ≥ 0 then decide (n < d <<< E.toNat)
      else decide (n <<< (-E).toNat < d)) = true) ↔ (n : ℚ) / d < (2 : ℚ) ^ E := by
    intro E
    rw [div_lt_iff₀ hdq]
    split_ifs with h
    · have hk : (2 : ℚ) ^ E.toNat = 2 ^ E := by
        rw [← zpow_natCast, Int.toNat_of_nonneg h]
      rw [decide_eq_true_iff, Nat.shiftLeft_eq, ← Nat.cast_lt (α := ℚ)]
      push_cast
      rw [hk, mul_comm]
    · have hk : (2 : ℚ) ^ (-E).toNat = 2 ^ (-E) := by
        rw [← zpow_natCast, Int.toNat_of_nonneg (by omega)]
      rw [decide_eq_true_iff, Nat.shiftLeft_eq, ← Nat.cast_lt (α := ℚ)]
      push_cast
      rw [hk]
      have h2 : (0 : ℚ) < 2 ^ (-E) := by positivity
      have h3 : (2 : ℚ) ^ E * 2 ^ (-E) = 1 := by
        rw [← zpow_add₀ two_ne_zero]; simp
      constructor
      · intro hlt
        have := mul_lt_mul_of_pos_right hlt (show (0 : ℚ) < 2 ^ E by positivity)
        calc (n : ℚ) = n * 2 ^ (-E) * 2 ^ E := by
                rw [mul_assoc, mul_comm (2 ^ (-E) : ℚ), h3, mul_one]
          _ < d * 2 ^ E := this
          _ = _ := by ring
      · intro hlt
        have := mul_lt_mul_of_pos_right hlt h2
        calc (n : ℚ) * 2 ^ (-E) < 2 ^ E * d * 2 ^ (-E) := this
          _ = d := by rw [mul_comm _ (d : ℚ), mul_assoc, h3, mul_one]
  have hlo : (2 : ℚ) ^ ((a : ℤ) - b - 1) ≤ (n : ℚ) / d := by
    rw [le_div_iff₀ hdq]
    calc (2 : ℚ) ^ ((a : ℤ) - b - 1) * d ≤ 2 ^ ((a : ℤ) - b - 1) * 2 ^ ((b : ℤ) + 1) := by
            gcongr; exact_mod_cast hdq2.le
      _ = 2 ^ a := by rw [← zpow_add₀ two_ne_zero, ← zpow_natCast]; congr 1; ring
      _ ≤ n := hnq1
  have hhi : (n : ℚ) / d < (2 : ℚ) ^ ((a : ℤ) - b + 1) := by
    rw [div_lt_iff₀ hdq]
    calc (n : ℚ) < 2 ^ (a + 1) := hnq2
      _ = 2 ^ ((a : ℤ) - b + 1) * 2 ^ (b : ℤ) := by
            rw [← zpow_add₀ two_ne_zero, ← zpow_natCast]; congr 1; push_cast; ring
      _ ≤ 2 ^ ((a : ℤ) - b + 1) * d := by
            gcongr; rw [zpow_natCast]; exact hdq1
  unfold rationalExponent ndigits2
  simp only []
  have hE : ((a + 1 : ℕ) : ℤ) - ((b + 1 : ℕ) : ℤ) = (a : ℤ) - b := by push_cast; ring
  rw [hE]
  by_cases hb : (n : ℚ) / d < (2 : ℚ) ^ ((a : ℤ) - b)
  · rw [if_pos ((hbelow _).mpr hb)]
    exact ⟨hlo, by simpa using hb⟩
  · rw [if_neg (fun h => hb ((hbelow _).mp h))]
    exact ⟨not_lt.mp hb, hhi⟩

/-- `_rational_exponent(n, d)` is `⌊log₂ (n / d)⌋` for positive `n` and `d`. -/
theorem rationalExponent_eq_log (n d : ℕ) (hn : 0 < n) (hd : 0 < d) :
    rationalExponent n d = Int.log 2 ((n : ℚ) / d) := by
  obtain ⟨h1, h2⟩ := rationalExponent_spec n d hn hd
  have hpos : (0 : ℚ) < n / d := by positivity
  have l1 := Int.zpow_log_le_self (b := 2) (by norm_num) hpos
  have l2 := Int.lt_zpow_succ_log_self (b := 2) (by norm_num) ((n : ℚ) / d)
  push_cast at l1 l2
  have u1 := (zpow_lt_zpow_iff_right₀ (by norm_num : (1 : ℚ) < 2)).mp (lt_of_le_of_lt h1 l2)
  have u2 := (zpow_lt_zpow_iff_right₀ (by norm_num : (1 : ℚ) < 2)).mp (lt_of_le_of_lt l1 h2)
  omega

/-! ## Rounding the scaled quotient to an integer -/

/-- The integer rounding step of `_nearest_binary64`: the quotient, plus one when twice the
remainder exceeds the divisor, or equals it and the quotient is odd. -/
def roundHalfEven (N D : ℕ) : ℕ :=
  let mantissa := N / D
  let remainder := N % D
  let twice := 2 * remainder
  if twice > D ∨ (twice = D ∧ mantissa % 2 = 1) then mantissa + 1 else mantissa

private theorem scaled_abs (N D : ℕ) (hD : 0 < D) (x : ℚ) :
    |x - (N : ℚ) / D| = |x * D - N| / D := by
  have hDq : (0 : ℚ) < D := by exact_mod_cast hD
  rw [show x - (N : ℚ) / D = (x * D - N) / D by field_simp, abs_div, abs_of_pos hDq]

/-- Lower bounds on the scaled distance from an integer `k` to `N / D`, by the position of `k`
relative to the quotient `m`. -/
private theorem grid_bounds (D m r k : ℚ) (hD : 0 < D) (hr : 0 ≤ r) :
    (k ≤ m - 1 → D + r ≤ |k * D - (D * m + r)|) ∧
    (k ≤ m → r ≤ |k * D - (D * m + r)|) ∧
    (k = m → |k * D - (D * m + r)| = r) ∧
    (k = m + 1 → |k * D - (D * m + r)| = |D - r|) ∧
    (m + 1 ≤ k → D - r ≤ |k * D - (D * m + r)|) ∧
    (m + 2 ≤ k → 2 * D - r ≤ |k * D - (D * m + r)|) := by
  refine ⟨fun h => ?_, fun h => ?_, fun h => ?_, fun h => ?_, fun h => ?_, fun h => ?_⟩
  · have := mul_le_mul_of_nonneg_right h hD.le
    exact le_abs.mpr (Or.inr (by nlinarith))
  · have := mul_le_mul_of_nonneg_right h hD.le
    exact le_abs.mpr (Or.inr (by nlinarith))
  · rw [h, show m * D - (D * m + r) = -r by ring, abs_neg, abs_of_nonneg hr]
  · rw [h]; congr 1; ring
  · have := mul_le_mul_of_nonneg_right h hD.le
    exact le_abs.mpr (Or.inl (by nlinarith))
  · have := mul_le_mul_of_nonneg_right h hD.le
    exact le_abs.mpr (Or.inl (by nlinarith))

/-- `roundHalfEven N D` is an integer nearest `N / D`, its tie goes to the even integer, and it
is the quotient or the quotient plus one. -/
theorem roundHalfEven_spec (N D : ℕ) (hD : 0 < D) :
    (∀ k : ℤ, |(roundHalfEven N D : ℚ) - N / D| ≤ |(k : ℚ) - N / D|) ∧
    (∀ k : ℤ, |(k : ℚ) - N / D| = |(roundHalfEven N D : ℚ) - N / D| →
      k ≠ (roundHalfEven N D : ℤ) → Even (roundHalfEven N D)) ∧
    (N / D ≤ roundHalfEven N D ∧ roundHalfEven N D ≤ N / D + 1) := by
  have hDq : (0 : ℚ) < D := by exact_mod_cast hD
  have hN : (N : ℚ) = D * (N / D : ℕ) + (N % D : ℕ) := by
    exact_mod_cast (Nat.div_add_mod N D).symm
  have hr0 : (0 : ℚ) ≤ (N % D : ℕ) := by positivity
  have hrD : ((N % D : ℕ) : ℚ) < D := by exact_mod_cast Nat.mod_lt N hD
  set m := N / D with hm
  set r := N % D with hr
  have key : ∀ k : ℤ, |(k : ℚ) - N / D| = |(k : ℚ) * D - (D * m + r)| / D := by
    intro k; rw [scaled_abs N D hD, hN]
  unfold roundHalfEven
  simp only []
  rw [← hm, ← hr]
  split_ifs with hup
  · -- rounded up: `2 r ≥ D`
    have h2r : (D : ℚ) ≤ 2 * r := by
      rcases hup with h | ⟨h, _⟩
      · exact_mod_cast h.le
      · exact_mod_cast h.symm.le
    have hM : |(((m + 1 : ℕ) : ℤ) : ℚ) * D - (D * m + r)| = D - r := by
      obtain ⟨-, -, -, h4, -, -⟩ := grid_bounds D m r ((m : ℚ) + 1) hDq hr0
      push_cast; rw [h4 rfl, abs_of_nonneg (by linarith)]
    refine ⟨fun k => ?_, fun k hk hne => ?_, by omega⟩
    · have hM' := hM; push_cast at hM'
      rw [show ((m + 1 : ℕ) : ℚ) = (((m + 1 : ℕ) : ℤ) : ℚ) by push_cast; rfl, key, key]
      apply div_le_div_of_nonneg_right _ hDq.le
      rw [hM]
      obtain ⟨-, h2, -, -, h5, -⟩ := grid_bounds D m r k hDq hr0
      rcases le_or_gt k (m : ℤ) with h | h
      · have := h2 (by exact_mod_cast h); linarith
      · exact h5 (by exact_mod_cast h)
    · rw [show ((m + 1 : ℕ) : ℚ) = (((m + 1 : ℕ) : ℤ) : ℚ) by push_cast; rfl, key, key,
        hM] at hk
      have hk' : |(k : ℚ) * D - (D * m + r)| = D - r := by
        field_simp at hk; linarith [hk]
      obtain ⟨h1, -, h3, -, -, h6⟩ := grid_bounds D m r k hDq hr0
      have hpos : (0 : ℚ) < r := by linarith
      rcases (show k ≤ (m : ℤ) - 1 ∨ k = m ∨ k = m + 1 ∨ (m : ℤ) + 2 ≤ k by omega) with
        h | h | h | h
      · have := h1 (by exact_mod_cast h); linarith
      · have := h3 (by exact_mod_cast h)
        have h2r' : 2 * r = D := by
          have : (2 * r : ℚ) = D := by linarith
          exact_mod_cast this
        rcases hup with h' | ⟨-, hodd⟩
        · omega
        · exact (Nat.even_add_one.mpr (Nat.not_even_iff_odd.mpr (Nat.odd_iff.mpr hodd)))
      · exact absurd (by push_cast [h]; ring) hne
      · have := h6 (by exact_mod_cast h); linarith
  · -- kept: `2 r ≤ D`
    have h2r : 2 * (r : ℚ) ≤ D := by
      have : 2 * r ≤ D := by omega
      exact_mod_cast this
    have hM : |(((m : ℕ) : ℤ) : ℚ) * D - (D * m + r)| = r := by
      obtain ⟨-, -, h3, -, -, -⟩ := grid_bounds D m r (m : ℚ) hDq hr0
      push_cast; exact h3 rfl
    refine ⟨fun k => ?_, fun k hk hne => ?_, by omega⟩
    · rw [show ((m : ℕ) : ℚ) = (((m : ℕ) : ℤ) : ℚ) by push_cast; rfl, key, key]
      apply div_le_div_of_nonneg_right _ hDq.le
      rw [hM]
      obtain ⟨-, h2, -, -, h5, -⟩ := grid_bounds D m r k hDq hr0
      rcases le_or_gt k (m : ℤ) with h | h
      · exact h2 (by exact_mod_cast h)
      · have := h5 (by exact_mod_cast h); linarith
    · rw [show ((m : ℕ) : ℚ) = (((m : ℕ) : ℤ) : ℚ) by push_cast; rfl, key, key, hM] at hk
      have hk' : |(k : ℚ) * D - (D * m + r)| = r := by
        field_simp at hk; linarith [hk]
      obtain ⟨h1, -, -, h4, -, h6⟩ := grid_bounds D m r k hDq hr0
      rcases (show k ≤ (m : ℤ) - 1 ∨ k = m ∨ k = m + 1 ∨ (m : ℤ) + 2 ≤ k by omega) with
        h | h | h | h
      · have := h1 (by exact_mod_cast h); linarith
      · exact absurd (by rw [h]) hne
      · have := h4 (by exact_mod_cast h)
        rw [hk', abs_of_nonneg (by linarith)] at this
        have h2r' : 2 * r = D := by
          have : (2 * r : ℚ) = D := by linarith
          exact_mod_cast this
        have : ¬ m % 2 = 1 := fun hodd => hup (Or.inr ⟨h2r', hodd⟩)
        exact Nat.even_iff.mpr (by omega)
      · have := h6 (by exact_mod_cast h); linarith

/-! ## `_nearest_binary64` in pieces

`nearestBinary64` is the single transcription; `roundHalfEven`, `packWord` and `magnitudeWord`
name its integer rounding step, its word construction and its result before the sign bits,
and `nearestBinary64_eq` checks that they recompose it. -/

/-- The word construction of `_nearest_binary64` from a rounded mantissa. -/
def packWord (mantissa : ℕ) (exponent : ℤ) : ℕ :=
  let hidden_bit := 1 <<< 52
  if mantissa < hidden_bit then mantissa
  else
    let field := max exponent (-1022) + 1023
    let (mantissa, field) :=
      if mantissa = 2 * hidden_bit then (hidden_bit, field + 1) else (mantissa, field)
    (field.toNat <<< 52) ||| (mantissa - hidden_bit)

/-- `_nearest_binary64` after its sign, on the magnitude `n / d`. -/
def magnitudeWord (n d : ℕ) : ℕ :=
  let exponent := rationalExponent n d
  if exponent > 1023 then 0x7ff0000000000000 else
  if exponent < -1075 then 0 else
  let shift : ℤ := max (exponent - 52) (-1074)
  let numerator_ := if shift < 0 then n <<< (-shift).toNat else n
  let denominator_ := if shift > 0 then d <<< shift.toNat else d
  packWord (roundHalfEven numerator_ denominator_) exponent

theorem nearestBinary64_zero : nearestBinary64 0 = 0 := by simp [nearestBinary64]

theorem nearestBinary64_eq (q : ℚ) (hq : q ≠ 0) :
    nearestBinary64 q = (if q < 0 then 0x8000000000000000 else 0) |||
      magnitudeWord q.num.natAbs q.den := by
  unfold nearestBinary64 magnitudeWord
  rw [if_neg hq]
  simp only []
  by_cases h1 : rationalExponent q.num.natAbs q.den > 1023
  · simp only [if_pos h1]
  · simp only [if_neg h1]
    by_cases h2 : rationalExponent q.num.natAbs q.den < -1075
    · simp only [if_pos h2, Nat.or_zero]
    · simp only [if_neg h2]
      rfl

/-! ## Fields of assembled words -/

theorem or_shift52 (f t : ℕ) (ht : t < 2 ^ 52) : (f <<< 52) ||| t = f * 2 ^ 52 + t := by
  rw [← Nat.shiftLeft_add_eq_or_of_lt ht, Nat.shiftLeft_eq]

theorem sign_or (w : ℕ) (hw : w < 2 ^ 63) : (0x8000000000000000 : ℕ) ||| w = 2 ^ 63 + w := by
  rw [show (0x8000000000000000 : ℕ) = 1 <<< 63 from rfl, ← Nat.shiftLeft_add_eq_or_of_lt hw,
    Nat.shiftLeft_eq, one_mul]

theorem field_pack (f t : ℕ) (hf : f < 2048) (ht : t < 2 ^ 52) : field (f * 2 ^ 52 + t) = f := by
  unfold field; norm_num at ht ⊢; omega

theorem fraction_pack (f t : ℕ) (ht : t < 2 ^ 52) : fraction (f * 2 ^ 52 + t) = t := by
  unfold fraction; norm_num at ht ⊢; omega

theorem signBit_low (w : ℕ) (hw : w < 2 ^ 63) : signBit w = false := by
  unfold signBit; norm_num at hw ⊢; omega

theorem signBit_high (w : ℕ) (hw : w < 2 ^ 63) : signBit (2 ^ 63 + w) = true := by
  unfold signBit; norm_num at hw ⊢; omega

theorem field_high (w : ℕ) : field (2 ^ 63 + w) = field w := by
  unfold field; norm_num; omega

theorem fraction_high (w : ℕ) : fraction (2 ^ 63 + w) = fraction w := by
  unfold fraction; norm_num; omega

theorem field_lt (w : ℕ) : field w < 2048 := by
  unfold field; exact Nat.mod_lt _ (by norm_num)

theorem fraction_lt (w : ℕ) : fraction w < 2 ^ 52 := by
  unfold fraction; exact Nat.mod_lt _ (by norm_num)

/-! ## Values -/

theorem magnitude_eq (w : ℕ) :
    magnitude w = (significand w : ℚ) * 2 ^ (max (field w : ℤ) 1 - 1075) := by
  unfold magnitude significand
  split_ifs with h
  · rw [h, show max ((0 : ℕ) : ℤ) 1 - 1075 = -1022 + (-52) by norm_num,
      zpow_add₀ two_ne_zero, show (2 : ℚ) ^ (-52 : ℤ) = 1 / 2 ^ 52 by norm_num]
    ring
  · have h1 : max (field w : ℤ) 1 - 1075 = ((field w : ℤ) - 1023) + (-52) := by omega
    rw [h1, zpow_add₀ two_ne_zero, zpow_neg,
      show ((2 : ℚ) ^ (52 : ℤ)) = 2 ^ (52 : ℕ) from zpow_natCast _ _]
    push_cast
    field_simp
    norm_num

theorem magnitude_nonneg (w : ℕ) : 0 ≤ magnitude w := by
  rw [magnitude_eq]; positivity

theorem abs_value (w : ℕ) : |value w| = magnitude w := by
  unfold value; split_ifs <;> simp [abs_of_nonneg (magnitude_nonneg w)]

/-- The finite nonnegative binary64 values: `m * 2 ^ k` with a 53-bit integer `m` and `k` at
least the subnormal exponent `-1074`. The largest exponent is not needed by the proofs. -/
def Representable (y : ℚ) : Prop :=
  ∃ m : ℕ, ∃ k : ℤ, m < 2 ^ 53 ∧ -1074 ≤ k ∧ y = m * 2 ^ k

theorem magnitude_representable (w : ℕ) : Representable (magnitude w) := by
  refine ⟨significand w, max (field w : ℤ) 1 - 1075, ?_, by omega, magnitude_eq w⟩
  have := fraction_lt w
  unfold significand; split_ifs <;> norm_num at this ⊢ <;> omega

/-! ## The word construction -/

/-- The word construction: below `2 ^ 52` a subnormal word, otherwise a normal word with the
hidden bit removed, and at `2 ^ 53` the carry into the exponent field, which at `exponent =
1023` is the infinity. Every finite result has value `mantissa * 2 ^ shift`. -/
theorem packWord_spec (M : ℕ) (E : ℤ) (hE : E ≤ 1023) (hM : M ≤ 2 ^ 53)
    (hsub : M < 2 ^ 52 → max (E - 52) (-1074) = -1074) :
    packWord M E < 2 ^ 63 ∧
    (M = 2 ^ 53 ∧ E = 1023 → packWord M E = 2047 * 2 ^ 52) ∧
    (¬(M = 2 ^ 53 ∧ E = 1023) → field (packWord M E) ≠ 2047 ∧
       magnitude (packWord M E) = M * 2 ^ (max (E - 52) (-1074)) ∧
       (Even M → Even (significand (packWord M E)))) := by
  unfold packWord
  simp only [show (1 <<< 52 : ℕ) = 2 ^ 52 from rfl]
  by_cases hlt : M < 2 ^ 52
  · rw [if_pos hlt]
    have hf : field M = 0 := by
      have := field_pack 0 M (by norm_num) hlt; simpa using this
    have hfr : fraction M = M := by
      have := fraction_pack 0 M hlt; simpa using this
    have hsig : significand M = M := by simp [significand, hf, hfr]
    refine ⟨by omega, fun h => by omega, fun _ => ⟨by omega, ?_, by rw [hsig]; exact id⟩⟩
    rw [magnitude_eq, hsig, hf, hsub hlt]; norm_num
  · rw [if_neg hlt]
    by_cases hc : M = 2 * 2 ^ 52
    · rw [if_pos hc]
      simp only []
      have hF : (0 : ℤ) ≤ max E (-1022) + 1023 + 1 := by omega
      set F := (max E (-1022) + 1023 + 1).toNat with hFdef
      have hFz : (F : ℤ) = max E (-1022) + 1024 := by rw [hFdef, Int.toNat_of_nonneg hF]; ring
      have hword : (F <<< 52) ||| (2 ^ 52 - 2 ^ 52) = F * 2 ^ 52 + 0 := by
        rw [Nat.sub_self]; exact or_shift52 F 0 (by norm_num)
      rw [hword]
      have hF2 : F < 2048 := by omega
      refine ⟨by norm_num; omega, fun h => by omega, fun h => ?_⟩
      have hfield := field_pack F 0 hF2 (by norm_num)
      have hfrac := fraction_pack F 0 (by norm_num)
      have hF3 : F ≠ 2047 := by omega
      have hsig : significand (F * 2 ^ 52 + 0) = 2 ^ 52 := by
        simp only [significand, hfield, hfrac]; split_ifs <;> omega
      refine ⟨by rw [hfield]; exact hF3, ?_, fun _ => by rw [hsig]; exact ⟨2 ^ 51, by norm_num⟩⟩
      rw [magnitude_eq, hsig, hfield, hc]
      rw [show max (F : ℤ) 1 - 1075 = max (E - 52) (-1074) + 1 by omega, zpow_add_one₀ two_ne_zero]
      push_cast; ring
    · rw [if_neg hc]
      simp only []
      have hF : (0 : ℤ) ≤ max E (-1022) + 1023 := by omega
      set F := (max E (-1022) + 1023).toNat with hFdef
      have hFz : (F : ℤ) = max E (-1022) + 1023 := by rw [hFdef, Int.toNat_of_nonneg hF]
      have hM' : M < 2 * 2 ^ 52 := by omega
      have ht : M - 2 ^ 52 < 2 ^ 52 := by omega
      rw [or_shift52 F _ ht]
      have hF2 : F < 2047 := by omega
      have hfield := field_pack F _ (by omega) ht
      have hfrac := fraction_pack F _ ht
      have hsig : significand (F * 2 ^ 52 + (M - 2 ^ 52)) = M := by
        simp only [significand, hfield, hfrac]; split_ifs <;> omega
      refine ⟨by norm_num at ht hM' ⊢; omega, fun h => by omega, fun _ => ⟨by omega, ?_, ?_⟩⟩
      · rw [magnitude_eq, hsig, hfield, show max (F : ℤ) 1 - 1075 = max (E - 52) (-1074) by omega]
      · rw [hsig]; exact id

/-! ## Nearest on the grid `2 ^ s ℤ`, and below it -/

theorem scale_abs (x a : ℚ) (s : ℤ) : |x * 2 ^ s - a| = 2 ^ s * |x - a / 2 ^ s| := by
  have hp : (0 : ℚ) < 2 ^ s := by positivity
  rw [show x * 2 ^ s - a = 2 ^ s * (x - a / 2 ^ s) by field_simp, abs_mul, abs_of_pos hp]

/-- If `M` is an integer nearest `a / 2 ^ s`, ties to even, and every binary64 value not on the
grid `2 ^ s ℤ` lies below `2 ^ (s + 52) ≤ a`, then `M * 2 ^ s` is a binary64 value nearest `a`,
and a different binary64 value equally near forces `M` even. -/
theorem grid_nearest (a : ℚ) (s : ℤ) (M : ℕ)
    (hnear : ∀ k : ℤ, |(M : ℚ) - a / 2 ^ s| ≤ |(k : ℚ) - a / 2 ^ s|)
    (htie : ∀ k : ℤ, |(k : ℚ) - a / 2 ^ s| = |(M : ℚ) - a / 2 ^ s| → k ≠ M → Even M)
    (hoff : -1074 < s → (2 : ℚ) ^ (s + 52) ≤ a) (y : ℚ) (hy : Representable y) :
    |(M : ℚ) * 2 ^ s - a| ≤ |y - a| ∧
      (|y - a| = |(M : ℚ) * 2 ^ s - a| → y ≠ (M : ℚ) * 2 ^ s → Even M) := by
  obtain ⟨m, k, hm, hk, rfl⟩ := hy
  have hp : (0 : ℚ) < 2 ^ s := by positivity
  by_cases hks : s ≤ k
  · set K : ℤ := ((m * 2 ^ (k - s).toNat : ℕ) : ℤ) with hK
    have hyK : (m : ℚ) * 2 ^ k = (K : ℚ) * 2 ^ s := by
      rw [hK]; push_cast
      rw [← zpow_natCast, Int.toNat_of_nonneg (by omega), mul_assoc, ← zpow_add₀ two_ne_zero]
      congr 2; ring
    rw [hyK, scale_abs, scale_abs]
    refine ⟨mul_le_mul_of_nonneg_left (hnear K) hp.le, fun h hne => ?_⟩
    have h' := mul_left_cancel₀ hp.ne' h
    refine htie K h' fun hKM => hne ?_
    rw [hKM]; push_cast; rfl
  · have hs : -1074 < s := by omega
    have ha := hoff hs
    have hy1 : (m : ℚ) * 2 ^ k < 2 ^ (s + 52) := by
      have hm' : (m : ℚ) < 2 ^ (53 : ℤ) := by
        rw [show (2 : ℚ) ^ (53 : ℤ) = 2 ^ (53 : ℕ) from zpow_natCast 2 53]; exact_mod_cast hm
      calc (m : ℚ) * 2 ^ k < 2 ^ (53 : ℤ) * 2 ^ k := by
              exact mul_lt_mul_of_pos_right hm' (by positivity)
        _ = 2 ^ (k + 53) := by rw [← zpow_add₀ two_ne_zero]; ring_nf
        _ ≤ 2 ^ (s + 52) := zpow_le_zpow_right₀ (by norm_num) (by omega)
    have hy0 : (0 : ℚ) ≤ (m : ℚ) * 2 ^ k := by positivity
    have hgrid := hnear (2 ^ 52 : ℕ)
    rw [← mul_le_mul_iff_of_pos_left hp, ← scale_abs, ← scale_abs] at hgrid
    have h52 : (((2 ^ 52 : ℕ) : ℤ) : ℚ) * 2 ^ s = 2 ^ (s + 52) := by
      rw [zpow_add₀ two_ne_zero]; norm_num; ring
    rw [h52, abs_of_nonpos (show (2 : ℚ) ^ (s + 52) - a ≤ 0 by linarith)] at hgrid
    have hstrict : |(M : ℚ) * 2 ^ s - a| < |(m : ℚ) * 2 ^ k - a| := by
      rw [abs_of_nonpos (by linarith : (m : ℚ) * 2 ^ k - a ≤ 0)]; linarith
    exact ⟨hstrict.le, fun h _ => absurd h hstrict.ne'⟩

/-! ## The magnitude word -/

set_option exponentiation.threshold 1100 in
/-- The result before the sign bits, on the magnitude `n / d`: the infinity exactly from
`overflowThreshold` on, and otherwise a finite word nearest `n / d` among the binary64
magnitudes, ties to even. -/
theorem magnitudeWord_spec (n d : ℕ) (hn : 0 < n) (hd : 0 < d) :
    magnitudeWord n d < 2 ^ 63 ∧
    (overflowThreshold ≤ (n : ℚ) / d → magnitudeWord n d = 2047 * 2 ^ 52) ∧
    ((n : ℚ) / d < overflowThreshold → field (magnitudeWord n d) ≠ 2047 ∧
      (∀ y, Representable y →
        |magnitude (magnitudeWord n d) - (n : ℚ) / d| ≤ |y - (n : ℚ) / d|) ∧
      (∀ y, Representable y →
        |y - (n : ℚ) / d| = |magnitude (magnitudeWord n d) - (n : ℚ) / d| →
        y ≠ magnitude (magnitudeWord n d) → Even (significand (magnitudeWord n d)))) := by
  obtain ⟨hE1, hE2⟩ := rationalExponent_spec n d hn hd
  have hapos : (0 : ℚ) < (n : ℚ) / d := by positivity
  set a : ℚ := (n : ℚ) / d with ha
  have hthr : overflowThreshold = (2 ^ 53 - 1 / 2) * 2 ^ (971 : ℤ) := by
    norm_num [overflowThreshold]
  have hthr2 : (2 : ℚ) ^ (1023 : ℤ) < overflowThreshold := by rw [hthr]; norm_num
  unfold magnitudeWord
  simp only []
  set E := rationalExponent n d with hEdef
  by_cases h1 : E > 1023
  · rw [if_pos h1]
    have h1024 : (2 : ℚ) ^ (1024 : ℤ) ≤ a :=
      le_trans (zpow_le_zpow_right₀ (by norm_num) (by omega)) hE1
    have hlt : ¬ a < overflowThreshold := by
      rw [hthr]; norm_num at h1024 ⊢; linarith
    exact ⟨by norm_num, fun _ => by norm_num, fun h => absurd h hlt⟩
  rw [if_neg h1]
  by_cases h2 : E < -1075
  · rw [if_pos h2]
    have hsmall : a < 2 ^ (-1075 : ℤ) :=
      lt_of_lt_of_le hE2 (zpow_le_zpow_right₀ (by norm_num) (by omega))
    have hm0 : magnitude 0 = 0 := by rw [magnitude_eq]; simp [significand, fraction, field]
    have hlt : a < overflowThreshold := by
      have : (2 : ℚ) ^ (-1075 : ℤ) < 2 ^ (1023 : ℤ) :=
        zpow_lt_zpow_right₀ (by norm_num) (by norm_num)
      exact lt_trans hsmall (lt_trans this hthr2)
    refine ⟨by norm_num, fun h => absurd h (not_le.mpr hlt), fun _ => ⟨by simp [field], ?_,
      fun _ _ _ _ => by simp [significand, field, fraction]⟩⟩
    intro y ⟨m, k, hm, hk, hy⟩
    rw [hm0, zero_sub, abs_neg, abs_of_pos hapos]
    rcases Nat.eq_zero_or_pos m with h0 | hpos
    · rw [hy, h0]; simp [abs_of_pos hapos]
    · have hk' : (2 : ℚ) ^ (-1074 : ℤ) ≤ 2 ^ k := zpow_le_zpow_right₀ (by norm_num) hk
      have hm1 : (1 : ℚ) ≤ m := by exact_mod_cast hpos
      have hy1 : (2 : ℚ) ^ (-1074 : ℤ) ≤ y := by
        rw [hy]; nlinarith [show (0 : ℚ) < 2 ^ k by positivity]
      have h2' : (2 : ℚ) ^ (-1074 : ℤ) = 2 * 2 ^ (-1075 : ℤ) := by
        rw [show (-1074 : ℤ) = 1 + (-1075) by norm_num, zpow_add₀ two_ne_zero, zpow_one]
      rw [abs_of_nonneg (by linarith)]; linarith
  rw [if_neg h2]
  set s : ℤ := max (E - 52) (-1074) with hs
  set N := (if s < 0 then n <<< (-s).toNat else n) with hN
  set D := (if s > 0 then d <<< s.toNat else d) with hD
  have hDpos : 0 < D := by
    rw [hD]; split_ifs
    · rw [Nat.shiftLeft_eq]; positivity
    · exact hd
  have hp : (0 : ℚ) < 2 ^ s := by positivity
  have hdq : (0 : ℚ) < d := by exact_mod_cast hd
  have ht : (N : ℚ) / D = a / 2 ^ s := by
    rw [hN, hD, ha]
    rcases lt_trichotomy s 0 with h | h | h
    · rw [if_pos h, if_neg (by omega), Nat.shiftLeft_eq]; push_cast
      rw [← zpow_natCast, Int.toNat_of_nonneg (by omega), zpow_neg]; field_simp
    · rw [h]; simp
    · rw [if_neg (by omega), if_pos h, Nat.shiftLeft_eq]; push_cast
      rw [← zpow_natCast, Int.toNat_of_nonneg (by omega)]; field_simp
  have hDq : (0 : ℚ) < D := by exact_mod_cast hDpos
  obtain ⟨hnear, htie, hlo, hhi⟩ := roundHalfEven_spec N D hDpos
  set M := roundHalfEven N D with hMdef
  rw [ht] at hnear htie
  set t := a / 2 ^ s with htdef
  have hta : a = t * 2 ^ s := by rw [htdef]; field_simp
  -- `t < 2 ^ 53`, so `M ≤ 2 ^ 53`.
  have htlt : t < 2 ^ 53 := by
    rw [htdef, div_lt_iff₀ hp]
    calc a < 2 ^ (E + 1) := hE2
      _ = 2 ^ (53 : ℤ) * 2 ^ (E - 52) := by rw [← zpow_add₀ two_ne_zero]; ring_nf
      _ ≤ 2 ^ (53 : ℤ) * 2 ^ s := by
          gcongr
          · norm_num
          · omega
      _ = 2 ^ 53 * 2 ^ s := by norm_num
  have hM53 : M ≤ 2 ^ 53 := by
    have hND : N < 2 ^ 53 * D := by
      have : (N : ℚ) < 2 ^ 53 * D := by
        rw [← div_lt_iff₀ hDq, ht]; exact htlt
      exact_mod_cast this
    have := (Nat.div_lt_iff_lt_mul hDpos).mpr hND
    omega
  have hsub : M < 2 ^ 52 → max (E - 52) (-1074) = -1074 := by
    intro hM
    by_contra hne
    have hsE : s = E - 52 := by omega
    have ht52 : (2 : ℚ) ^ 52 ≤ t := by
      rw [htdef, le_div_iff₀ hp, hsE]
      calc (2 : ℚ) ^ 52 * 2 ^ (E - 52) = 2 ^ E := by
            rw [show (2 : ℚ) ^ 52 = 2 ^ (52 : ℤ) by norm_num, ← zpow_add₀ two_ne_zero]; ring_nf
        _ ≤ a := hE1
    have hND : 2 ^ 52 * D ≤ N := by
      have : (2 : ℚ) ^ 52 * D ≤ N := by
        rw [← le_div_iff₀ hDq, ht]; exact ht52
      exact_mod_cast this
    have := Nat.div_le_div_right (c := D) hND
    rw [Nat.mul_div_cancel _ hDpos] at this
    omega
  obtain ⟨hlt63, hover, hfin⟩ := packWord_spec M E (by omega) hM53 hsub
  have hiff : overflowThreshold ≤ a ↔ (M = 2 ^ 53 ∧ E = 1023) := by
    constructor
    · intro h
      have hE : E = 1023 := by
        by_contra hne
        have : (2 : ℚ) ^ (E + 1) ≤ 2 ^ (1023 : ℤ) := zpow_le_zpow_right₀ (by norm_num) (by omega)
        linarith
      have hs971 : s = 971 := by omega
      have ht1 : 2 ^ 53 - 1 / 2 ≤ t := by
        rw [htdef, le_div_iff₀ hp, hs971]; rw [hthr] at h; exact h
      refine ⟨?_, hE⟩
      by_contra hM
      have hM' : (M : ℚ) + 1 ≤ 2 ^ 53 := by
        have : M + 1 ≤ 2 ^ 53 := by omega
        exact_mod_cast this
      have hk := hnear ((2 : ℤ) ^ 53)
      simp only [Int.cast_pow, Int.cast_ofNat] at hk
      rw [abs_of_pos (show (0 : ℚ) < 2 ^ 53 - t by linarith)] at hk
      have hge : t - M ≤ |(M : ℚ) - t| := by rw [abs_sub_comm]; exact le_abs_self _
      have hMeq : M + 1 = 2 ^ 53 := by
        have : (M : ℚ) + 1 = 2 ^ 53 := le_antisymm hM' (by linarith)
        exact_mod_cast this
      have heq : |(((2 : ℤ) ^ 53 : ℤ) : ℚ) - t| = |(M : ℚ) - t| := by
        simp only [Int.cast_pow, Int.cast_ofNat]
        rw [abs_of_pos (show (0 : ℚ) < 2 ^ 53 - t by linarith)]
        apply le_antisymm _ hk
        linarith
      have hne : (2 : ℤ) ^ 53 ≠ (M : ℤ) := by
        intro h'; have : ((M : ℕ) : ℤ) + 1 = 2 ^ 53 := by exact_mod_cast hMeq
        omega
      have hev := htie _ heq hne
      have : M = 2 ^ 53 - 1 := by omega
      rw [this] at hev
      exact absurd hev (by decide)
    · rintro ⟨hM, hE⟩
      have hs971 : s = 971 := by omega
      have hk := hnear ((2 : ℤ) ^ 53 - 1)
      rw [hM] at hk
      simp only [Int.cast_sub, Int.cast_pow, Int.cast_ofNat, Int.cast_one, Nat.cast_pow,
        Nat.cast_ofNat] at hk
      rw [abs_of_pos (show (0 : ℚ) < 2 ^ 53 - t by linarith)] at hk
      have ht1 : 2 ^ 53 - 1 / 2 ≤ t := by
        rcases le_abs.mp hk with h | h
        · linarith
        · linarith
      rw [hthr, hta, hs971]
      exact mul_le_mul_of_nonneg_right ht1 (by positivity)
  refine ⟨hlt63, fun h => hover (hiff.mp h), fun h => ?_⟩
  have hno : ¬(M = 2 ^ 53 ∧ E = 1023) := fun h' => absurd (hiff.mpr h') (not_le.mpr h)
  obtain ⟨hf, hmag, heven⟩ := hfin hno
  have hoff : -1074 < s → (2 : ℚ) ^ (s + 52) ≤ a := fun h' => by
    rw [show s + 52 = E by omega]; exact hE1
  refine ⟨hf, fun y hy => ?_, fun y hy htie' hne => ?_⟩
  · rw [hmag]; exact (grid_nearest a s M hnear htie hoff y hy).1
  · rw [hmag] at htie' hne
    exact heven ((grid_nearest a s M hnear htie hoff y hy).2 htie' hne)

/-! ## The sign -/

theorem signed_word (P : Prop) [Decidable P] (w : ℕ) (hw : w < 2 ^ 63) :
    ((if P then 0x8000000000000000 else 0) ||| w) < 2 ^ 64 ∧
    signBit ((if P then 0x8000000000000000 else 0) ||| w) = decide P ∧
    field ((if P then 0x8000000000000000 else 0) ||| w) = field w ∧
    fraction ((if P then 0x8000000000000000 else 0) ||| w) = fraction w ∧
    significand ((if P then 0x8000000000000000 else 0) ||| w) = significand w ∧
    value ((if P then 0x8000000000000000 else 0) ||| w) =
      if P then -magnitude w else magnitude w := by
  by_cases hP : P
  · rw [if_pos hP, sign_or w hw]
    have h1 := field_high w
    have h2 := fraction_high w
    refine ⟨by omega, by rw [signBit_high w hw]; simp [hP], h1, h2,
      by simp only [significand, h1, h2], ?_⟩
    simp only [value, signBit_high w hw, magnitude, h1, h2, if_pos hP, ↓reduceIte]
  · rw [if_neg hP, Nat.zero_or]
    refine ⟨by omega, by simp [signBit_low w hw, hP], rfl, rfl, rfl, ?_⟩
    simp [value, signBit_low w hw, hP]

theorem abs_num_div_den (q : ℚ) : ((q.num.natAbs : ℕ) : ℚ) / (q.den : ℚ) = |q| := by
  have h := Rat.num_div_den q
  conv_rhs => rw [← h]
  rw [abs_div, Nat.abs_cast, Nat.cast_natAbs, Int.cast_abs]

/-! ## Correct rounding -/

/-- **Correct rounding.** For every rational `q`, the word `_nearest_binary64(q)` computes is the
IEEE 754 binary64 round-to-nearest-ties-to-even of `q`, overflow and signed zero included. -/
theorem nearestBinary64_roundsTo (q : ℚ) : RoundsTo q (nearestBinary64 q) := by
  have hthr : (0 : ℚ) < overflowThreshold :=
    sub_pos.mpr (pow_lt_pow_right₀ (by norm_num) (by norm_num))
  by_cases hq : q = 0
  · subst hq
    rw [nearestBinary64_zero]
    have hf : field 0 = 0 := by simp [field]
    have hm0 : magnitude 0 = 0 := by
      rw [magnitude_eq]
      simp only [significand, fraction, field, Nat.zero_div, Nat.zero_mod, ↓reduceIte,
        Nat.cast_zero, zero_mul]
    have hv : value 0 = 0 := by unfold value; rw [hm0]; simp
    refine ⟨by norm_num, fun h => by simp at h; linarith, fun _ => by rw [hf]; norm_num,
      fun _ => by simp [signBit], fun _ w' _ => by rw [hv]; simp, fun _ _ _ _ _ => ?_⟩
    simp [significand, hf, fraction]
  set n := q.num.natAbs with hn
  set d := q.den with hd
  have hn0 : 0 < n := Int.natAbs_pos.mpr (Rat.num_ne_zero.mpr hq)
  have hd0 : 0 < d := q.den_pos
  have ha : (n : ℚ) / d = |q| := abs_num_div_den q
  have hqa : 0 < |q| := abs_pos.mpr hq
  obtain ⟨hlt63, hover, hfin⟩ := magnitudeWord_spec n d hn0 hd0
  rw [ha] at hover hfin
  set mw := magnitudeWord n d with hmw
  rw [nearestBinary64_eq q hq]
  obtain ⟨hW64, hWsign, hWfield, hWfrac, hWsig, hWval⟩ := signed_word (q < 0) mw hlt63
  set W := (if q < 0 then 0x8000000000000000 else 0) ||| mw with hW
  have hr := magnitude_nonneg mw
  -- the distance of the result, and of a value of the result's magnitude and the other sign
  have hdist : |value W - q| = abs (magnitude mw - |q|) := by
    rw [hWval]
    by_cases hneg : q < 0
    · rw [if_pos hneg, abs_of_neg hneg, show -magnitude mw - q = -(magnitude mw - -q) by ring,
        abs_neg]
    · rw [if_neg hneg, abs_of_nonneg (not_lt.mp hneg)]
  have hopp : ∀ v : ℚ, |v| = magnitude mw → v ≠ value W → |v - q| = magnitude mw + |q| := by
    intro v hv hne
    rw [hWval] at hne
    rcases (abs_eq hr).mp hv with h | h
    · by_cases hneg : q < 0
      · rw [h, abs_of_neg hneg, abs_of_nonneg (by linarith)]; ring
      · rw [if_neg hneg] at hne; exact absurd h hne
    · by_cases hneg : q < 0
      · rw [if_pos hneg] at hne; exact absurd h hne
      · have hq' : 0 < q := lt_of_le_of_ne (not_lt.mp hneg) (Ne.symm hq)
        rw [h, abs_of_pos hq', abs_of_neg (by linarith)]; ring
  have hfar : ∀ w', abs (magnitude w' - |q|) ≤ |value w' - q| := by
    intro w'
    rw [← abs_value w']
    exact abs_abs_sub_abs_le_abs_sub _ _
  refine ⟨hW64, fun h => ?_, fun h => ?_, fun _ => hWsign, fun h w' hw' => ?_,
    fun h w' hw' htie hne => ?_⟩
  · have h1 := hover h
    have hf : field W = 2047 := by rw [hWfield, h1]; exact field_pack 2047 0 (by norm_num) (by norm_num)
    have hfr : fraction W = 0 := by rw [hWfrac, h1]; exact fraction_pack 2047 0 (by norm_num)
    simp [decode, hf, hfr, hWsign]
  · rw [hWfield]; exact (hfin h).1
  · rw [hdist]
    exact le_trans ((hfin h).2.1 _ (magnitude_representable w')) (hfar w')
  · rw [hWsig]
    obtain ⟨-, hnear, hties⟩ := hfin h
    have heq : abs (magnitude w' - |q|) = abs (magnitude mw - |q|) := by
      apply le_antisymm _ (hnear _ (magnitude_representable w'))
      rw [← hdist, ← htie]; exact hfar w'
    by_cases hm : magnitude w' = magnitude mw
    · have := hopp (value w') (by rw [abs_value, hm]) hne
      rw [this, hdist] at htie
      exfalso
      rcases abs_cases (magnitude mw - |q|) with ⟨h1, -⟩ | ⟨h1, -⟩
      · rw [h1] at htie; linarith
      · rw [h1] at htie
        have hr0 : magnitude mw = 0 := by linarith
        have hv0 : value w' = 0 := by
          rw [← abs_eq_zero, abs_value, hm, hr0]
        have hW0 : value W = 0 := by
          rw [hWval, hr0]; simp
        exact hne (hv0.trans hW0.symm)
    · exact hties _ (magnitude_representable w') heq hm

/-! ## `Base.decompose` and `_dyadic` -/

theorem fraction_mask (w : ℕ) : w &&& 0x000fffffffffffff = fraction w := by
  rw [show (0x000fffffffffffff : ℕ) = 2 ^ 52 - 1 from rfl, Nat.and_two_pow_sub_one_eq_mod]; rfl

theorem field_mask (w : ℕ) : (w &&& 0x7ff0000000000000) >>> 52 = field w := by
  rw [Nat.shiftRight_and_distrib, show (0x7ff0000000000000 : ℕ) >>> 52 = 2 ^ 11 - 1 from rfl,
    Nat.and_two_pow_sub_one_eq_mod, Nat.shiftRight_eq_div_pow]; rfl

/-- `_dyadic` throws exactly on the infinities and NaNs. -/
theorem dyadic_none_iff (w : ℕ) : dyadic w = none ↔ field w = 2047 := by
  unfold dyadic; split_ifs with h <;> simp [h]

/-- On a finite word, `_dyadic` returns `(±significand, max field 1 - 1075)`, and `n * 2 ^ p` is
the word's value. -/
theorem dyadic_value (w : ℕ) (hw : field w ≠ 2047) :
    dyadic w = some ((significand w : ℤ) * (if signBit w then -1 else 1),
      max (field w : ℤ) 1 - 1075) ∧
    ∀ n p, dyadic w = some (n, p) → (n : ℚ) * 2 ^ p = value w := by
  have hdec : decompose w = ((significand w : ℤ), max (field w : ℤ) 1 - 1075,
      (if signBit w then -1 else 1)) := by
    unfold decompose
    rw [if_neg (fun h => hw h.1), if_neg hw]
    simp only [fraction_mask, field_mask]
    have hor : fraction w ||| ((if field w ≠ 0 then 1 else 0) <<< 52) = significand w := by
      rw [Nat.or_comm, ← Nat.shiftLeft_add_eq_or_of_lt (fraction_lt w), Nat.shiftLeft_eq]
      unfold significand
      split_ifs <;> simp_all
    rw [hor]
    congr 2
    split_ifs with h
    · simp [h]
    · simp; omega
  have hdy : dyadic w = some ((significand w : ℤ) * (if signBit w then -1 else 1),
      max (field w : ℤ) 1 - 1075) := by
    unfold dyadic
    rw [if_neg hw, hdec]
    split_ifs <;> simp
  refine ⟨hdy, fun n p h => ?_⟩
  rw [hdy] at h
  obtain ⟨rfl, rfl⟩ := Prod.mk.inj (Option.some.inj h)
  unfold value
  rw [magnitude_eq]
  split_ifs <;> push_cast <;> ring

/-! ## Round trip -/

theorem word_eq (w : ℕ) (hw : w < 2 ^ 64) :
    w = (if signBit w then 2 ^ 63 else 0) + field w * 2 ^ 52 + fraction w := by
  unfold signBit field fraction
  norm_num at hw ⊢
  split_ifs with h <;> omega

theorem significand_lt (w : ℕ) : significand w < 2 ^ 53 := by
  have := fraction_lt w
  unfold significand; split_ifs <;> omega

theorem significand_ge (w : ℕ) (h : field w ≠ 0) : 2 ^ 52 ≤ significand w := by
  unfold significand; rw [if_neg h]; omega

theorem significand_lt_of_zero (w : ℕ) (h : field w = 0) : significand w < 2 ^ 52 := by
  unfold significand; rw [if_pos h]; exact fraction_lt w

private theorem exponent_not_lt (w₁ w₂ : ℕ)
    (h : (significand w₁ : ℚ) * 2 ^ (max (field w₁ : ℤ) 1 - 1075) =
      (significand w₂ : ℚ) * 2 ^ (max (field w₂ : ℤ) 1 - 1075)) :
    ¬ max (field w₁ : ℤ) 1 - 1075 < max (field w₂ : ℤ) 1 - 1075 := by
  intro hlt
  set e₁ := max (field w₁ : ℤ) 1 - 1075
  set e₂ := max (field w₂ : ℤ) 1 - 1075
  have hf2 : field w₂ ≠ 0 := by omega
  have hm2 : (2 : ℚ) ^ 52 ≤ significand w₂ := by exact_mod_cast significand_ge w₂ hf2
  have hm1 : (significand w₁ : ℚ) < 2 ^ 53 := by exact_mod_cast significand_lt w₁
  have hp : (0 : ℚ) < 2 ^ e₁ := by positivity
  have h2 : (2 : ℚ) ≤ 2 ^ (e₂ - e₁) := by
    calc (2 : ℚ) = 2 ^ (1 : ℤ) := by norm_num
      _ ≤ 2 ^ (e₂ - e₁) := zpow_le_zpow_right₀ (by norm_num) (by omega)
  have hsplit : (2 : ℚ) ^ e₂ = 2 ^ (e₂ - e₁) * 2 ^ e₁ := by
    rw [← zpow_add₀ two_ne_zero]; ring_nf
  rw [hsplit, ← mul_assoc] at h
  have h' := mul_right_cancel₀ hp.ne' h
  have : (2 : ℚ) * 2 ^ 52 ≤ significand w₁ := by
    rw [h']; nlinarith
  linarith

theorem magnitude_injective (w₁ w₂ : ℕ) (h : magnitude w₁ = magnitude w₂) :
    field w₁ = field w₂ ∧ fraction w₁ = fraction w₂ := by
  rw [magnitude_eq, magnitude_eq] at h
  have he : max (field w₁ : ℤ) 1 - 1075 = max (field w₂ : ℤ) 1 - 1075 :=
    le_antisymm (not_lt.mp (exponent_not_lt w₂ w₁ h.symm)) (not_lt.mp (exponent_not_lt w₁ w₂ h))
  rw [he] at h
  have hs : significand w₁ = significand w₂ := by
    exact_mod_cast mul_right_cancel₀ (zpow_ne_zero _ two_ne_zero) h
  have h1 := fraction_lt w₁
  have h2 := fraction_lt w₂
  unfold significand at hs
  split_ifs at hs with hf1 hf2 hf2 <;> omega

set_option exponentiation.threshold 1100 in
theorem magnitude_lt_threshold (w : ℕ) (hw : field w ≠ 2047) :
    magnitude w < overflowThreshold := by
  have hthr : overflowThreshold = (2 ^ 53 - 1 / 2) * 2 ^ (971 : ℤ) := by
    norm_num [overflowThreshold]
  have hf := field_lt w
  have hs : (significand w : ℚ) + 1 ≤ 2 ^ 53 := by
    have := significand_lt w
    exact_mod_cast this
  have he : (2 : ℚ) ^ (max (field w : ℤ) 1 - 1075) ≤ 2 ^ (971 : ℤ) :=
    zpow_le_zpow_right₀ (by norm_num) (by omega)
  have hp : (0 : ℚ) < 2 ^ (971 : ℤ) := by positivity
  rw [magnitude_eq, hthr]
  calc (significand w : ℚ) * 2 ^ (max (field w : ℤ) 1 - 1075)
      ≤ (2 ^ 53 - 1) * 2 ^ (971 : ℤ) := by
        apply mul_le_mul (by linarith) he (by positivity) (by norm_num)
    _ < (2 ^ 53 - 1 / 2) * 2 ^ (971 : ℤ) := by
        apply mul_lt_mul_of_pos_right (by norm_num) hp

/-- Round trip: a finite word's value rounds back to the same word, except that `-0.0` rounds
to `+0.0` (the rational `0` has no sign). -/
theorem nearestBinary64_value (w : ℕ) (hw : IsFinite w) :
    nearestBinary64 (value w) = if value w = 0 then 0 else w := by
  split_ifs with h0
  · rw [h0, nearestBinary64_zero]
  have R := nearestBinary64_roundsTo (value w)
  set r := nearestBinary64 (value w) with hr
  have hlt : |value w| < overflowThreshold := by
    rw [abs_value]; exact magnitude_lt_threshold w hw.2
  have hv : value r = value w := by
    have := R.nearest hlt w hw
    rw [sub_self, abs_zero] at this
    exact sub_eq_zero.mp (abs_nonpos_iff.mp this)
  have hm : 0 < magnitude w := by
    refine lt_of_le_of_ne (magnitude_nonneg w) (fun h => h0 ?_)
    unfold value; split_ifs <;> simp [← h]
  have hsign : signBit r = signBit w := by
    rw [R.sign hlt]
    unfold value
    cases hb : signBit w
    · simp only [Bool.false_eq_true, ↓reduceIte, decide_eq_false_iff_not, not_lt]
      exact hm.le
    · simp only [↓reduceIte, decide_eq_true_eq, Left.neg_neg_iff]
      exact hm
  have hmag : magnitude r = magnitude w := by rw [← abs_value, hv, abs_value]
  obtain ⟨hf, hfr⟩ := magnitude_injective r w hmag
  rw [word_eq r R.word, word_eq w hw.1, hsign, hf, hfr]

end BayesianNetworksProofs.Binary64
