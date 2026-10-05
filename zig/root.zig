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
//!   * `pub const c` is the complete `bridge.h` surface, not a filtered
//!     view: `ff_parse_f32`, `ff_parse_f64`, the three `FF_STATUS_*` values as
//!     top-level `c_int` constants, and the `_Static_assert`s as compile-time
//!     checks are all there. Reach for it when a caller needs an entry point
//!     this facade does not wrap, or the value behind an out-of-range refusal.
//!   * `parse32` and `parse64` give the value and how much of the buffer was
//!     consumed, which is the `from_chars` contract: a prefix of the input is
//!     a successful parse.
//!   * `parse32Exact` and `parse64Exact` require the whole buffer to have been
//!     the number.
//!
//! Shortest usage sequence:
//!
//! ```zig
//! const std = @import("std");
//! const fast_float = @import("fast_float");
//!
//! pub fn main() !void {
//!     const tenth = try fast_float.parse64Exact("0.1");
//!     const scanned = try fast_float.parse64("9.80665 m/s^2");
//!     std.debug.print("{d} {d} {d}\n", .{ tenth, scanned.value, scanned.consumed });
//! }
//! ```
//!
//! In a runtime-loading build one line comes before the first parse, and it is
//! the only difference in the program:
//!
//! ```zig
//!     try fast_float.load(.{ .path = "/usr/lib/libfast_float.so.0" });
//! ```
//!
//! Routes: a dependent imports this one module, `dep.module("fast_float")`
//! from `b.dependency("fast_float", ...)`, and the build binds `c` and, in a
//! linked build, links the compiled bridge into it; in a runtime-loading build
//! nothing is linked and `c` resolves the same names through the loader. `c` is
//! a supported route of its own and carries the obligations stated on its
//! declaration. There is no second module name, no per-target name and no
//! relative-import route.
//!
//! ## Two configurations: linked and runtime-loaded
//!
//! This module is built in one of two shapes, and `runtime_loaded` says which
//! at comptime.
//!
//! *Linked* is the default. The bridge is linked, `c` is the translated
//! header, and every call below — the typed four and the raw two — is a direct
//! call to the compiled C++ with no table, no readiness check and no cost.
//!
//! *Runtime-loaded* is opt-in (`-Druntime`). The bridge is not linked; `c` is a
//! dispatch generated from the same translation step's output, and the two
//! entry points `zig/bridge.h:103-113` declares are resolved through the
//! platform loader when the caller calls
//!
//! ```zig
//! try fast_float.load(.{ .path = "/usr/lib/libfast_float.so.0" });
//! ```
//!
//! before using anything else. A call into a module that has not loaded stops
//! the program with a message naming the function, in every optimization mode.
//! That is a programming error rather than a recoverable condition: the table
//! does not exist yet, and there is no partial state to fall back on. The load
//! itself reports a missing file, a provider that does not export both entry
//! points, a provider whose entry points do not behave as this header declares,
//! a request that cannot be honoured because a different provider already won,
//! or a reentrant call, as errors rather than as a different library being
//! loaded instead.
//!
//! The provider is reached, never guessed. `.path` names a file and `.system`
//! names a library for the platform loader; neither falls back to the other,
//! the module has no unload and no reset, and it keeps the handle and its own
//! copy of the request to the end of the process. What a provider has to be is
//! stated in `runtime/library.zig`, next to the ABI boundary and what is and is
//! not checked about it.
//!
//! Compiler and ABI: this module is written for Zig 0.16.0, which is what
//! `build.zig.zon` states as `minimum_zig_version`. Every value it returns
//! crosses the C ABI `zig/bridge.h` declares, so what a caller is bound to is
//! that header's scalar widths (`float`, `double`, `size_t`), its three status
//! values (pinned by `_Static_assert` at `bridge.h:80-84`) and its
//! out-parameter convention — not upstream's C++ API, which is a template and
//! has no symbol a C translation could name. The library behind that ABI is
//! compiled out of upstream's own headers at a pinned `-std=c++17`
//! (`build_support/graph.zig`), and a dependent that reaches this module
//! through `dep.module` in a linked build gets it with libc and the C++
//! runtime. In a runtime-loading build the same two entry points arrive from a
//! provider named at run time instead, and `runtime/library.zig` records what
//! such a provider has to match and what is checked about it.
//!
//! Allocation: there is none, on either side of that boundary. No function on
//! this surface takes an allocator or returns memory; upstream's entry points
//! are pure functions of the byte range they are handed
//! (`include/fast_float/fast_float.h:22-23`) and `zig/bridge.cpp` adds none of
//! its own. Nothing here links or needs a C++ runtime, a locale or a threading
//! library to satisfy it, which is part of what makes a provider usable at all.
//!
//! What this module deliberately does not do: it parses no integer, selects no
//! `chars_format` and no `parse_options`, formats nothing, and exposes no
//! rounding-mode setting. Upstream reaches all of those through
//! `from_chars_advanced` and the integer overloads in the
//! installed C++ header tree, which is where they stay, because they are
//! templates and have no symbol a C translation could name.
//!
//! Ownership and lifetime:
//!   * The input slice is borrowed for the duration of the call. It is never
//!     copied and never retained: the bridge reads it and returns, and the
//!     caller's buffer is untouched.
//!   * Nothing allocates and nothing has to be released afterwards. Upstream
//!     states that it "does not throw and does not allocate memory"
//!     (`fast_float.h:22-23`), the bridge adds no allocation of its own, and
//!     the four typed functions hand their result back by value.
//!   * The typed surface and the raw `c` surface disagree about what a failed
//!     parse leaves behind, and that difference is the whole reason both
//!     routes are published. A typed failure returns no result:
//!     `parse32`, `parse64`, `parse32Exact` and `parse64Exact` construct
//!     nothing on any error, so every caller variable still holds exactly what
//!     the caller put there. A raw call writes its out-parameters before it
//!     reports a range failure, so `FF_STATUS_RESULT_OUT_OF_RANGE` leaves the
//!     rounded infinity or zero in `*out_value` and the byte count it took in
//!     `*out_consumed`, while `FF_STATUS_INVALID_ARGUMENT` leaves both alone.
//!   * A caller that needs the value behind `error.ResultOutOfRange` makes the
//!     raw call itself. The typed channel discards that residue and the tag
//!     carries none of it back.
//!   * In a runtime-loading build the process handle and the loader's own copy
//!     of the request outlive every call here, and there is no call that gives
//!     them back. That is a property of the loader, not of these functions: it
//!     holds one table for the life of the process because other code may
//!     already have parsed through it.
//!
//! The upstream C++ headers are installed too, under `include/fast_float/`,
//! unmodified and complete, so a C++ caller can use fast_float directly without
//! going through this binding at all. They are not reachable through Zig,
//! because `from_chars` is a template (`fast_float.h:33-37`) and has no symbol
//! to call; that is the whole reason `bridge.cpp` exists.

/// The complete translated `bridge.h`, and this fork's supported raw route to
/// the bridge.
///
/// Upstream's own C++ API is deliberately absent from it: `from_chars` is a
/// template (`fast_float.h:33-37`) and `zig translate-c` cannot see one. What
/// is here is what `bridge.cpp` compiles from the same headers, so the two
/// cannot disagree. The two entry points are `ff_parse_f32` and `ff_parse_f64`
/// and the three `FF_STATUS_*` names arrive as top-level `c_int` constants
/// rather than as a tag type.
///
/// A typed call carries three obligations the caller does not have to satisfy.
/// On this route they are the caller's:
///
///   * `first` and `last` must both point into one allocation the caller
///     still owns, and `last` may equal `first`. Neither is copied and
///     nothing is retained past the return. For a buffer that owns no bytes
///     both are its own address, and upstream compares them before
///     dereferencing either (`parse_number.h:332-336`), so an empty range is
///     an ordinary `FF_STATUS_INVALID_ARGUMENT`.
///   * `out_value` and `out_consumed` must both be non-null and writable.
///     There is no null check on this path and no way to drop either
///     out-parameter.
///   * Both out-parameters are written on `FF_STATUS_OK` and on
///     `FF_STATUS_RESULT_OUT_OF_RANGE`, and neither is written on
///     `FF_STATUS_INVALID_ARGUMENT`. On the range failure `*out_value` holds
///     the infinity or the zero the number rounded to and `*out_consumed`
///     holds the bytes it took, because upstream stores through `to_float`
///     before it tests the range (`parse_number.h:288` before `:290-292`) and
///     returns before `to_float` on both early exits
///     (`parse_number.h:332-336`, `:347-350`). Reading that residue is the
///     only way this package exposes the result of an out-of-range parse; the
///     typed functions report the same condition and discard it.
///
/// In a runtime-loading build this module is a generated dispatch instead of
/// the translation step's own output. It publishes the same namespace: the
/// three `FF_STATUS_*` values are re-exported from the translated header
/// rather than restated, so there is one spelling of each of them either way.
/// What differs is how a name reaches the library. In the linked configuration
/// a call is direct; in the runtime-loaded one it goes through a table that
/// `load` fills, and a call before that fill stops the program with a message
/// naming the function. `runtime_loaded` says which configuration this is, at
/// comptime.
pub const c = @import("c");

const std = @import("std");

/// The loader core, which is where a linked build's two public types come from.
///
/// It is imported only by the linked configuration. In a runtime-loading build
/// the dispatch carries its own copy of the same declarations and this module is
/// never referenced, so it is never resolved and never compiled. Either way
/// there is exactly one `LoadSource` and one `LoadError` in a build, which is
/// what keeps them one type for a consumer that names them.
const rt = @import("rt");

/// Whether this module was configured to resolve its native symbols at run
/// time.
///
/// False for the ordinary build, where the bridge is linked and `c` is the
/// translated header itself. True when the build generated a dispatch that
/// resolves the same symbols through the platform loader, in which case `load`
/// is the call that makes the library usable.
///
/// It is a comptime constant, so a consumer can write two different code paths
/// and have only the one it chose analyzed.
pub const runtime_loaded: bool = if (@hasDecl(c, "rt_runtime_loaded")) c.rt_runtime_loaded else false;

/// Which native library `load` should open.
///
/// `.path` is an explicit file path and `.system` is an explicit name for the
/// platform loader. There is no path-to-system fallback and no implicit
/// fallback of any kind; a request that cannot be honoured is an error, not a
/// different library.
pub const LoadSource = if (runtime_loaded) c.LoadSource else rt.LoadSource;

/// Every way `load` can decline.
///
/// Declared here, in the module a consumer imports, rather than only inside the
/// loader: the caller names the failure it is handling.
pub const LoadError = if (runtime_loaded) c.LoadError else rt.LoadError;

/// Load the native library this module dispatches to.
///
/// In a runtime-loading build this is the whole contract: call it once, then
/// use this module as if it were linked. Calling it again with the same request
/// succeeds and changes nothing; calling it with a different request after a
/// success is `ProviderMismatch`, and the library already in use stays in use.
/// A failed attempt publishes nothing and can be retried explicitly, by
/// calling this again: there is no automatic retry, and no implicit second
/// source.
///
/// It keeps the process handle and its own copy of the request to the end of
/// the process. There is no unload and no reset, because the table is
/// process-global state that other code may already have called through.
///
/// Safe to call from any thread. A thread that arrives while an attempt for
/// the same request is in flight waits for that attempt and gets its result,
/// whatever it was. A call from the thread that is running the attempt is
/// `ReentrantLoad` rather than a deadlock.
///
/// In a linked build there is no provider, no table and nothing to resolve, so
/// this stops the program with a message saying so instead of quietly
/// succeeding. `runtime_loaded` is false there, so a consumer that supports
/// both configurations can tell the two apart at comptime instead of meeting
/// this at run time.
pub fn load(source: LoadSource) LoadError!void {
    if (comptime !runtime_loaded) {
        std.debug.panic(
            "fast_float: load was called on a linked build; this module is not " ++
                "runtime-loaded, so there is no library to load. Build with " ++
                "runtime loading configured, or do not call load.",
            .{},
        );
    }
    return c.load(source);
}

/// The request that succeeded, or null when nothing has loaded yet.
///
/// The answer is the loader's own retained copy and stays valid for the life of
/// the process. Null in a linked build, which has no request.
pub fn loadedSource() ?LoadSource {
    if (comptime !runtime_loaded) return null;
    return c.loadedSource();
}

/// Everything these functions can refuse to do.
///
/// The taxonomy stops where the checks stop. Each name is a claim about what
/// this file compared or what the bridge reported, not a guess at a cause.
/// The bridge's three `FF_STATUS_*` values are not this declaration: they
/// reach Zig as top-level `c_int` constants rather than as a tag type, and
/// there is deliberately no second spelling of them here, so a caller
/// comparing what the bridge reported compares the translated C ones. A tag,
/// though, is not a status. `parse32` and `parse64` translate one into the
/// other and nothing else, while `parse32Exact` and `parse64Exact` add one
/// comparison of their own after a successful parse, so a tag can arrive with
/// no `FF_STATUS_*` behind it at all: the bridge reported `c.FF_STATUS_OK`.
/// Which half produced a tag is settled by which entry point the caller
/// called, and nothing here converts a tag into a status.
pub const Error = error{
    /// Two entry points produce this tag, and they do not mean the same thing.
    ///
    /// From `parse32` and `parse64` it is `c.FF_STATUS_INVALID_ARGUMENT`: the
    /// buffer does not begin with a number this format accepts — the empty
    /// buffer, a leading space or tab, a leading `+`, a lone `.` or `-`. The
    /// bridge wrote neither out-parameter (`bridge.h:20-27`), and neither typed
    /// entry point constructs a result.
    ///
    /// From `parse32Exact` and `parse64Exact` it is this file's own
    /// `consumed != bytes.len` comparison, reached only after a parse that
    /// succeeded: the bridge reported `c.FF_STATUS_OK` and wrote the value and
    /// the byte count it took into its out-parameters (`bridge.cpp:62-66`), and
    /// both are dropped here. No count comes back either, so a caller who wants
    /// to know how far the number ran calls `parse32` or `parse64`.
    InvalidArgument,
    /// `c.FF_STATUS_RESULT_OUT_OF_RANGE`: the number parsed and
    /// rounded, but to an infinity or to a zero that is not the number written.
    /// The bridge wrote that value and the byte count it consumed into its own
    /// out-parameters before it returned this status, and this facade drops
    /// both: no `Parsed32` or `Parsed64` is ever constructed on this path, so
    /// `error.ResultOutOfRange` carries none of that residue. A caller who
    /// wants it makes the raw `c` call itself.
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
/// Only a successful parse constructs one: every `Error` returns without a
/// result, so a caller that got an error holds no value and no count. The
/// struct owns nothing, copies independently, and borrows nothing — both
/// fields are computed from `bytes` before the call returned, so the slice
/// may be released as soon as it does.
pub const Parsed32 = struct {
    /// The value upstream rounded to, valid because the call succeeded. On a
    /// range failure upstream rounded to an infinity or a zero too, but that
    /// path is an error and constructs nothing, so this field never carries a
    /// value the caller did not write.
    value: f32,
    /// Bytes of the input that were part of the number, counted from
    /// `bytes[0]`, which is upstream's `from_chars_result::ptr`
    /// (`float_common.h:80`) moved back to the start of the buffer. Always at
    /// least one when the call succeeded, because upstream accepts no number
    /// with no digits, and never more than `bytes.len`.
    consumed: usize,
};

/// A `double` parse and the length of the prefix it consumed. Only a
/// successful parse constructs one, and it owns and borrows nothing. See
/// `Parsed32` for the contract; the width is the only difference.
pub const Parsed64 = struct {
    /// See `Parsed32.value`.
    value: f64,
    /// See `Parsed32.consumed`.
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
/// `bytes` is borrowed for the call, never copied and never retained, nothing
/// allocates, and the caller has nothing to release afterwards. Every `Error`
/// returns no `Parsed32`, so the caller's own variables are left exactly as
/// they were; that is the typed contract, and it is narrower than the raw `c`
/// call's, which writes its out-parameters before it reports a range failure.
/// `error.ResultOutOfRange` in particular discards the infinity or zero
/// upstream rounded to, along with how many bytes the number took.
///
/// Format is `chars_format::general` (`fast_float.h:37`), which is
/// `fixed | scientific` and nothing else (`float_common.h:56`). What that
/// means, all of it upstream's behaviour and not this file's:
///
///   * No leading whitespace and no leading `+`, because neither
///     `chars_format::skip_white_space` (`float_common.h:58`, consulted at
///     `parse_number.h:327-331`) nor `chars_format::allow_leading_plus`
///     (`float_common.h:57`, consulted at `ascii_number.h:354-358` for a
///     number and at `parse_number.h:32-36` for `inf` and `nan`) is a bit of
///     `general`. So `" 1"`, `"\t1"` and `"+1"` are all `InvalidArgument`.
///     Unlike this parser, `strtod` accepts leading whitespace and `+`.
///   * A leading `-` is accepted and gives a negative value, including
///     negative zero: `"-0"` is `0x80000000`, not `0x00000000`.
///   * `"inf"`, `"infinity"` and `"nan"` are accepted case insensitively, with
///     an optional `-`, and with the C++17 `nan(n-char-seq-opt)` payload
///     (`parse_number.h:37-67`). These parse successfully, which is upstream's
///     `chars_format::general` — `no_infnan` is not one of its bits
///     (`float_common.h:50`, `:56`) — and is what makes this binding
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
///     (`parse_number.h:290-292`), and the raw `c` surface reports the value
///     and the byte count for both.
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
    // so each case compares as it is and no integer is re-spelled here. In a
    // runtime-loading build `c.FF_STATUS_OK` is the dispatch's re-export of the
    // translation's own constant rather than a second value spelled the same.
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
/// The contract is `parse32`'s with the width changed: the same borrow of
/// `bytes`, the same absence of any allocation and of anything to release,
/// the same rule that no `Parsed64` exists on any `Error`, and the same
/// `error.ResultOutOfRange` residue being discarded rather than returned.
/// It is a separate function rather than a runtime choice between widths
/// because `from_chars` is a template (`fast_float.h:33-37`) and the bridge
/// instantiates it once per width at its own call.
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
/// `InvalidArgument` rather than `1.5`. It is the same tag the format's own
/// refusals use, because a trailing tail is the only thing being rejected.
/// The value is returned on its own because there is nothing else to say about
/// it: no offset, because the offset is the length.
///
/// `bytes` is borrowed and never retained, nothing allocates, and nothing has
/// to be released afterwards. Each `Error` returns no value:
/// `error.ResultOutOfRange` arrives unchanged from the prefix parse and
/// discards the rounded residue with it, and the trailing-bytes
/// `error.InvalidArgument` discards a parse that did succeed and reports no
/// count, so a caller who needs to know how far the number ran calls
/// `parse32`.
pub fn parse32Exact(bytes: []const u8) Error!f32 {
    const parsed = try parse32(bytes);
    if (parsed.consumed != bytes.len) return error.InvalidArgument;
    return parsed.value;
}

/// `parse64` plus the requirement that the number filled the whole buffer, with
/// the same borrow, allocation, residue and release contract as `parse32Exact`.
pub fn parse64Exact(bytes: []const u8) Error!f64 {
    const parsed = try parse64(bytes);
    if (parsed.consumed != bytes.len) return error.InvalidArgument;
    return parsed.value;
}
