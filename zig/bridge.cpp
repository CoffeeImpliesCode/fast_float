/* The C ABI declared in `bridge.h`, over fast_float's own templates.
 *
 * This is the only translation unit in the fork that includes the upstream C++
 * headers. It exists because `fast_float::from_chars` is a template
 * (`include/fast_float/fast_float.h:33-37`): the algorithm is header-only, so
 * something has to be compiled in C++ for the symbols to exist at all, and a C
 * consumer cannot name a template. Everything this file does is call
 * `from_chars` once per width and report what came back. No parsing, rounding
 * or range logic is written here.
 */

#include <fast_float/fast_float.h>

#include "bridge.h" /* the fork's C ABI; installed as fast_float_bridge.h */

namespace {

/* Classifies one upstream `std::errc` as one `ff_status`.
 *
 * The three cases are the three values `from_chars` can hand back for a
 * floating-point type, and the reason each one is the value it is is spelled
 * out at the site upstream sets it: `parse_number.h:28` and `:268` (success),
 * `:69` (no pattern matched, reached through `parse_infnan`), `:333` (the range
 * was empty), `:348` (`no_infnan` was set and the token was not a number),
 * `:292` and `:396` (rounded out of range). `std::errc()` is tested first so
 * the common path is one compare.
 *
 * No fourth case is invented: every other `std::errc` value is unrepresentable
 * as a `std::errc` at this call, so the remainder is exactly the one remaining
 * answer rather than a bucket something could hide in.
 */
inline int classify(std::errc ec) noexcept {
  if (ec == std::errc()) {
    return FF_STATUS_OK;
  }
  if (ec == std::errc::result_out_of_range) {
    return FF_STATUS_RESULT_OUT_OF_RANGE;
  }
  return FF_STATUS_INVALID_ARGUMENT;
}

} /* namespace */

extern "C" int ff_parse_f32(const char *first, const char *last,
                            float *out_value, size_t *out_consumed) {
  /* `last == first` is upstream's own empty-range test, and it is checked
   * before anything is read (`parse_number.h:332-336`), so the empty case is
   * passed straight through rather than answered here: this file does not get
   * to decide that an empty range is invalid, upstream does.
   */
  float value{};
  fast_float::from_chars_result result =
      fast_float::from_chars(first, last, value);
  /* `result.ec != invalid_argument` covers the two answers that carry a value:
   * `FF_STATUS_OK`, and `FF_STATUS_RESULT_OUT_OF_RANGE`, where upstream has
   * already called `to_float` (`parse_number.h:288`) and so has already stored
   * the infinity or zero it rounded to. `result.ptr` is set on every path
   * (`parse_number.h:269` and `:374`, and the early exits at `:334` and `:349`,
   * with `parse_infnan` setting it at `:27`), so the distance from `first` is
   * defined in all three.
   */
  if (result.ec != std::errc::invalid_argument) {
    *out_value = value;
    *out_consumed = static_cast<size_t>(result.ptr - first);
  }
  return classify(result.ec);
}

extern "C" int ff_parse_f64(const char *first, const char *last,
                            double *out_value, size_t *out_consumed) {
  /* Same shape, at the width this function names. `from_chars<double>` is
   * instantiated here, once, rather than being selected at runtime.
   */
  double value{};
  fast_float::from_chars_result result =
      fast_float::from_chars(first, last, value);
  if (result.ec != std::errc::invalid_argument) {
    *out_value = value;
    *out_consumed = static_cast<size_t>(result.ptr - first);
  }
  return classify(result.ec);
}