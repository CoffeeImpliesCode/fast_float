/* Real C ABI over fast_float's own `fast_float::from_chars`.
 *
 * fast_float is a header-only C++11 library whose public entry points are
 * templates (`include/fast_float/fast_float.h:33-37`), so there is no symbol to
 * link against and no `extern "C"` declaration upstream: the only thing this
 * header can do is name the calling convention the translation unit that wraps
 * it will produce. The definitions live in `bridge.cpp`, which is compiled as
 * C++ and reaches the upstream headers by include path.
 *
 * Everything here is plain C: no C++ types, no `enum class`, no references, no
 * default arguments. That is what lets `addTranslateC` read this header
 * directly, with no C++ front end and no libstdc++ on the Zig side.
 *
 * Ownership and lifetime:
 *   * `first` and `last` are the caller's own buffer. Neither is copied, and
 *     nothing here allocates: fast_float documents that it "does not throw and
 *     does not allocate memory" (`fast_float.h:22-23`) and neither does this
 *     file. The pair is a half-open range, exactly as upstream takes it
 *     (`fast_float.h:9`).
 *   * `out_value` and `out_consumed` are the caller's. Both are written only
 *     when the return is `FF_STATUS_OK`, and both are written on
 *     `FF_STATUS_RESULT_OUT_OF_RANGE` as well, because upstream has already
 *     stored the value it rounded to by then (`parse_number.h:288` calls
 *     `to_float` before the range test at `:290-292`). On
 *     `FF_STATUS_INVALID_ARGUMENT` upstream returns before `to_float`
 *     (`parse_number.h:332-336` and `:347-350` are the two early exits) and
 *     this file writes neither.
 *   * `first` and `last` may be equal, and both may be the address of a
 *     zero-length object. Upstream compares them before dereferencing
 *     (`parse_number.h:332-336`), so an empty range is an ordinary
 *     `FF_STATUS_INVALID_ARGUMENT` and no pointer arithmetic happens on an
 *     address that owns no bytes.
 */

#ifndef FAST_FLOAT_BRIDGE_H
#define FAST_FLOAT_BRIDGE_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* What one parse did.
 *
 * The values are upstream's `std::errc` classification as it reaches it:
 * `parse_number.h` sets `answer.ec = std::errc()` on the optimistic path
 * (`:28`, `:268`, `:373`), `std::errc::invalid_argument` when no number
 * matches or the range is empty (`:69`, `:333`, `:348`, `:513`), and
 * `std::errc::result_out_of_range` when a nonzero mantissa rounded to zero or
 * the exponent reached infinity (`:292`, `:396`). No other value is reachable
 * from the float entry point, so the taxonomy stops here rather than carrying
 * a catch-all this library can never return.
 *
 * The spelling is this fork's: upstream declares no status enum, because it
 * has no C ABI. The three names are the three outcomes above.
 */
enum ff_status {
  /* `std::errc()`. The whole leading token parsed and the value is in range. */
  FF_STATUS_OK = 0,
  /* `std::errc::invalid_argument`. No number matched, so neither out-parameter
   * was written and no input was consumed. */
  FF_STATUS_INVALID_ARGUMENT = 1,
  /* `std::errc::result_out_of_range`. A number did match, but it rounded past
   * the largest finite magnitude or below the smallest, so upstream stored
   * infinity or a zero and reported the range failure separately. */
  FF_STATUS_RESULT_OUT_OF_RANGE = 2
};

/* The numbers the two functions below return are `enum ff_status` values.
 *
 * The return type is spelled `int` rather than `enum ff_status` so that the
 * translated Zig sees one C integer type at the boundary and cannot drift onto
 * a different spelling of the same three values. The assertions below are what
 * makes that safe, and they are checked by the C++ compiler every time
 * `bridge.cpp` is built, on every target, rather than being a claim in a
 * comment. A C caller may compare the result against the enumerator names
 * directly; a caller that has not seen this header compares against 0.
 */
_Static_assert(FF_STATUS_OK == 0, "ff_status::FF_STATUS_OK must be 0");
_Static_assert(FF_STATUS_INVALID_ARGUMENT == 1,
               "ff_status::FF_STATUS_INVALID_ARGUMENT must be 1");
_Static_assert(FF_STATUS_RESULT_OUT_OF_RANGE == 2,
               "ff_status::FF_STATUS_RESULT_OUT_OF_RANGE must be 2");

/* Parses the half-open byte range `[first, last)` as a `float`.
 *
 * Calls `fast_float::from_chars<float>` with the default
 * `chars_format::general` (`fast_float.h:37`), which is fixed or scientific,
 * accepts neither leading whitespace nor a leading `+`, and accepts `inf`,
 * `infinity` and `nan` case insensitively (`parse_number.h:37-67`).
 *
 * `*out_value` receives the parsed value on `FF_STATUS_OK` and on
 * `FF_STATUS_RESULT_OUT_OF_RANGE`. `*out_consumed` receives the number of bytes
 * of `[first, last)` that were part of the number, which is upstream's
 * `from_chars_result::ptr` (`float_common.h:80`) moved back to `first`. A
 * caller that wants a prefix parse compares that count against its buffer
 * length; the range is never re-scanned here to find it.
 *
 * Returns one of the three `FF_STATUS_OK`, `FF_STATUS_INVALID_ARGUMENT`,
 * `FF_STATUS_RESULT_OUT_OF_RANGE` values.
 */
int ff_parse_f32(const char *first, const char *last, float *out_value,
                 size_t *out_consumed);

/* The same, for `double`.
 *
 * A separate function rather than a size or a tag parameter, so the C++ side
 * instantiates `from_chars<double>` at its own call and the caller names the
 * type it wants; there is no runtime width selection to get wrong.
 */
int ff_parse_f64(const char *first, const char *last, double *out_value,
                 size_t *out_consumed);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* FAST_FLOAT_BRIDGE_H */