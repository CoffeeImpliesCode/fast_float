//! Public Zig surface of the fast_float fork.
//!
//! Scope: `fast_float::from_chars` for `float` and `double`, at the widths
//! upstream instantiates for them, in `chars_format::general`. Nothing below
//! parses, rounds, classifies or range-checks a number: every value comes out
//! of the C bridge in `bridge.cpp`, which calls the upstream template once and
//! reports what upstream returned. Each declaration names the header and line
//! it was read out of, so a reader can check the binding against upstream
//! rather than against this file.
//!
//! Three ways in:
//!   * `pub const c` is the complete translated `bridge.h`, not a filtered
//!     view: `ff_parse_f32`, `ff_parse_f64`, the three `FF_STATUS_*` values as
//!     top-level `c_int` constants, and the `_Static_assert`s as compile-time
//!     checks are all there. Reach for it when a caller needs an entry point
//!     this facade does not wrap.
//!   * `parse32` and `parse64` give the value and how much of the buffer was
//!     consumed, which is the `from_chars` contract: a prefix of the input is
//!     a successful parse.
//!   * `parse32Exact` and `parse64Exact` require the whole buffer to have been
//!     the number.
//!
//! The upstream C++ headers are installed too, under `include/fast_float/`,
//! unmodified and complete, so a C++ caller can use fast_float directly without
//! going through this binding at all. They are not reachable through Zig,
//! because `from_chars` is a template (`fast_float.h:33-37`) and has no symbol
//! to call; that is the whole reason `bridge.cpp` exists.
//!
//! Ownership and lifetime:
//!   * The input slice is borrowed. It is never copied and never retained: the
//!     bridge reads it and returns, and the caller's buffer is untouched.
//!   * Nothing allocates. Upstream states that it "does not throw and does not
//!     allocate memory" (`fast_float.h:22-23`), and these four functions add no
//!     allocation of their own; the returned structs are returned in registers
//!     or on the caller's stack.
//!   * No out-parameter is left holding a value on a failed parse. See
//!     `bridge.h`: on `InvalidArgument` upstream returns before `to_float`, so
//!     nothing was ever written and there is nothing to un-write.
//!   * A parse that fails leaves the caller's own variables exactly as they
//!     were, because the value only exists inside the returned struct.

/// The complete translated `bridge.h`.
///
/// This is the raw C surface of this fork, not a filtered one. Upstream's own
/// C++ API is deliberately absent from it: `from_chars` is a template and
/// `zig translate-c` cannot see one. What is here is what `bridge.cpp` compiles
/// from the same headers, so the two cannot disagree.
pub const c = @import("c");

/// Everything these functions can refuse to do.
///
/// The taxonomy stops where the checks stop. Each name is a claim about what
/// this file compared or what the bridge reported, not a guess at a cause.
/// The status behind each one is one of the three `FF_STATUS_*` values
/// `bridge.h` declares, which translate-c hands Zig as top-level `c_int`
/// constants rather than as a tag type: there is deliberately no second
/// spelling of those three values here, so a caller comparing statuses
/// compares the translated C ones.
pub const Error = error{
    /// `c.FF_STATUS_INVALID_ARGUMENT`: the buffer does not begin with
    /// a number this format accepts. That is the empty buffer, a leading space
    /// or tab, a leading `+`, and a lone `.` or `-`.
    InvalidArgument,
    /// `c.FF_STATUS_RESULT_OUT_OF_RANGE`: the number parsed and
    /// rounded, but to an infinity or to a zero that is not the number written.
    /// The value the bridge rounded to is still readable through the raw `c`
    /// surface; this facade reports the condition rather than handing back a
    /// number the caller did not write.
    ResultOutOfRange,
    /// The bridge returned a value that is not one of the three `bridge.h`
    /// enumerators. `classify` in `bridge.cpp` has exactly three returns and the
    /// header pins their values with `_Static_assert`, so no input reaches this;
    /// it is here so that a future change to that function would be a returned
    /// error rather than a branch the compiler has to assume cannot fail.
    StatusNotRecognised,
};

/// A `float` parse and the length of the prefix it consumed.
///
/// `consumed` is upstream's `from_chars_result::ptr` (`float_common.h:80`)
/// measured from the start of the buffer, which is how `std::from_chars`
/// reports it too: the number is a prefix, and `buffer[consumed..]` is
/// whatever followed it.
pub const Parsed32 = struct {
    /// The value upstream rounded to. On `ResultOutOfRange` this is the
    /// infinity or zero it produced, which is why the out-of-range case is an
    /// error rather than a second successful result.
    value: f32,
    /// Bytes of the input that were part of the number. Always at least one
    /// when the call succeeded, because upstream accepts no number with no
    /// digits.
    consumed: usize,
};

/// A `double` parse and the length of the prefix it consumed. See `Parsed32`.
pub const Parsed64 = struct {
    value: f64,
    consumed: usize,
};

/// The first byte of the range handed to the bridge.
///
/// `bytes.ptr` is the caller's own address; a slice is never null, so this is a
/// conversion and not an invention.
inline fn firstOf(bytes: []const u8) [*c]const u8 {
    return bytes.ptr;
}

/// The end of the range handed to the bridge.
///
/// For a buffer that owns bytes this is `bytes.ptr + bytes.len`. For one that
/// owns none it is `firstOf(bytes)` unchanged, so no arithmetic is performed on
/// an address that has nothing behind it — which is what an empty slice leaves
/// behind, and what a caller who has just drained its buffer has. Upstream
/// compares the two before dereferencing either (`parse_number.h:332-336`), so
/// the empty case arrives as an ordinary `invalid_argument` decided upstream
/// rather than by this file.
inline fn lastOf(bytes: []const u8) [*c]const u8 {
    if (bytes.len == 0) return firstOf(bytes);
    return bytes.ptr + bytes.len;
}

/// Parses the longest number at the start of `bytes` as a `float`.
///
/// Format is `chars_format::general` (`fast_float.h:37`): fixed or scientific
/// notation, and nothing else. What that means, all of it upstream's behaviour
/// and not this file's:
///
///   * No leading whitespace and no leading `+`. `from_chars` differs from
///     `strtod` here on purpose (`fast_float.h:11-15`, and `parse_number.h:31`
///     quotes C++17 20.19.3.(7.1) forbidding a `+` here), so `" 1"`, `"\t1"`
///     and `"+1"` are all `InvalidArgument`.
///   * A leading `-` is accepted and gives a negative value, including
///     negative zero: `"-0"` is `0x80000000`, not `0x00000000`.
///   * `"inf"`, `"infinity"` and `"nan"` are accepted case insensitively, with
///     an optional `-`, and with the C++17 `nan(n-char-seq-opt)` payload
///     (`parse_number.h:37-56`). These parse successfully, which is
///     upstream's `chars_format::general` and is what makes this binding
///     unsuitable for untrusted input without a pre-check.
///   * Rounding is exact and is round-to-nearest, ties to even
///     (`fast_float.h:12-15`), independent of the FPU rounding mode: upstream
///     reads the mode only to decide whether its fast path is valid
///     (`parse_number.h:78-80`, consulted once at `:216`) and does the
///     arithmetic itself.
///   * Subnormals are produced, not flushed. A value below the smallest
///     normal but above zero rounds into the subnormal range; a value that
///     rounds all the way to zero is `ResultOutOfRange` (`parse_number.h:290`).
///   * Overflow to infinity and underflow to zero are `ResultOutOfRange`
///     (`parse_number.h:290-292`), with the rounded value still reported by
///     the raw `c` surface.
///
/// An empty `bytes` is `InvalidArgument` and nothing else happens: `first` and
/// `last` are both the start of the buffer, `lastOf` performs no arithmetic when
/// there is nothing to point past, and upstream compares the two before
/// dereferencing either (`parse_number.h:332-336`). The answer is upstream's
/// and not this file's, and no pointer difference is formed over a buffer that
/// owns no bytes.
pub fn parse32(bytes: []const u8) Error!Parsed32 {
    var value: f32 = undefined;
    var consumed: usize = undefined;
    const code = c.ff_parse_f32(firstOf(bytes), lastOf(bytes), &value, &consumed);
    // The prongs are the translated `bridge.h` values themselves: translate-c
    // drops the `ff_status` tag type and emits the three enumerators as
    // top-level `c_int` constants, which is the same `int` the bridge returns,
    // so each case compares as it is and no integer is re-spelled here.
    switch (code) {
        c.FF_STATUS_OK => return .{ .value = value, .consumed = consumed },
        c.FF_STATUS_INVALID_ARGUMENT => return error.InvalidArgument,
        c.FF_STATUS_RESULT_OUT_OF_RANGE => return error.ResultOutOfRange,
        // Not one of the three `bridge.h` enumerators. The bridge's `classify`
        // has exactly those three returns and the header pins their values, so
        // this is a statement about the bridge rather than about the input; it
        // is an error and not a safety panic so that a mismatch is reported
        // instead of aborting.
        else => return error.StatusNotRecognised,
    }
}

/// Parses the longest number at the start of `bytes` as a `double`.
///
/// Identical to `parse32` in every respect but the width, and the reasoning is
/// the same one the bridge makes: `from_chars` is a template
/// (`fast_float.h:33-37`), so each width is a separate instantiation at a
/// separate call rather than a runtime choice between them.
pub fn parse64(bytes: []const u8) Error!Parsed64 {
    var value: f64 = undefined;
    var consumed: usize = undefined;
    const code = c.ff_parse_f64(firstOf(bytes), lastOf(bytes), &value, &consumed);
    switch (code) {
        c.FF_STATUS_OK => return .{ .value = value, .consumed = consumed },
        c.FF_STATUS_INVALID_ARGUMENT => return error.InvalidArgument,
        c.FF_STATUS_RESULT_OUT_OF_RANGE => return error.ResultOutOfRange,
        else => return error.StatusNotRecognised,
    }
}

/// `parse32` plus the requirement that the number filled the whole buffer.
///
/// A prefix is a successful `from_chars` and stays one here; what this adds is
/// the extra condition that `consumed == bytes.len`, so `"1.5x"` is
/// `InvalidArgument` rather than `1.5`. The value is returned on its own
/// because there is nothing else to say about it: no offset, because the offset
/// is the length.
pub fn parse32Exact(bytes: []const u8) Error!f32 {
    const parsed = try parse32(bytes);
    if (parsed.consumed != bytes.len) return error.InvalidArgument;
    return parsed.value;
}

/// `parse64` plus the requirement that the number filled the whole buffer. See
/// `parse32Exact`.
pub fn parse64Exact(bytes: []const u8) Error!f64 {
    const parsed = try parse64(bytes);
    if (parsed.consumed != bytes.len) return error.InvalidArgument;
    return parsed.value;
}
