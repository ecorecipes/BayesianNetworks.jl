# Exact dyadic arithmetic and correct rounding (ADR 0016).
#
# Every finite Float64 is exactly an integer times a power of two, so sums and products of
# bound probabilities are exact in integer arithmetic once they share a power of two. The
# fallbacks of the posterior entry points (ADR 0014, amended by ADR 0016) compute there and
# round once, with `_nearest_binary64`, to the Float64 nearest the exact posterior of the
# model as bound. InfluenceDiagrams' exact decision elimination and BayesianNetworkInference's
# dyadic arithmetic use the same two functions; this is their one definition.

# `(n, p)` with `x == n * 2^p` exactly, `n` an integer. Zero gives `n == 0`.
function _dyadic(x::Float64)
    isfinite(x) || throw(ArgumentError("a non-finite value ($x) has no exact dyadic value"))
    num, pow, den = Base.decompose(x)
    return BigInt(num) * sign(den), Int(pow)
end

function _rational_exponent(n::BigInt, d::BigInt)
    exponent = ndigits(n; base=2) - ndigits(d; base=2)
    below = exponent >= 0 ? n < (d << exponent) : (n << -exponent) < d
    return below ? exponent - 1 : exponent
end

# The Float64 nearest `value`, ties to even: correct rounding. Integer rounding and word
# construction avoid ambient BigFloat precision, floating-point scaling and double rounding
# at representation boundaries.
function _nearest_binary64(value::Rational{BigInt})
    iszero(value) && return 0.0
    sign_bits = value < 0 ? 0x8000000000000000 : UInt64(0)
    n, d = abs(numerator(value)), denominator(value)
    exponent = _rational_exponent(n, d)
    exponent > 1023 && return reinterpret(Float64, sign_bits | 0x7ff0000000000000)
    exponent < -1075 && return reinterpret(Float64, sign_bits)
    shift = max(exponent - 52, -1074)
    numerator_ = shift < 0 ? n << -shift : n
    denominator_ = shift > 0 ? d << shift : d
    mantissa, remainder = divrem(numerator_, denominator_)
    twice = 2remainder
    if twice > denominator_ || (twice == denominator_ && isodd(mantissa))
        mantissa += 1
    end
    hidden_bit = big(1) << 52
    if mantissa < hidden_bit
        word = UInt64(mantissa)
    else
        field = max(exponent, -1022) + 1023
        if mantissa == 2hidden_bit
            mantissa = hidden_bit
            field += 1
        end
        word = (UInt64(field) << 52) | UInt64(mantissa - hidden_bit)
    end
    return reinterpret(Float64, sign_bits | word)
end

# The Float64 nearest `n / d` for integers with `d > 0`.
_nearest_binary64(n::BigInt, d::BigInt) = _nearest_binary64(Rational{BigInt}(n, d))
