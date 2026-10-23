//! Zig facade for upstream `fast_float::from_chars` on `float` and `double`.
//! The bridge parses general-format numbers; this module exposes prefix and exact APIs.
//! `c` exposes the raw bridge, while `-Druntime` selects explicit provider loading.

/// Complete translated bridge surface for raw calls.
/// Pass a valid input range and writable, non-null out-pointers.
pub const c = @import("c");

const std = @import("std");

/// Loader types used by linked builds.
const rt = @import("rt");

/// Whether this build uses runtime symbol loading.
/// Comptime constant: false for linked builds, true for dispatch builds.
pub const runtime_loaded: bool = if (@hasDecl(c, "rt_runtime_loaded")) c.rt_runtime_loaded else false;

/// Explicit provider source: `.path` names a file; `.system` names a loader entry.
pub const LoadSource = if (runtime_loaded) c.LoadSource else rt.LoadSource;

/// Failures reported by `load` in runtime-loading builds.
pub const LoadError = if (runtime_loaded) c.LoadError else rt.LoadError;

/// Loads the explicit provider used by runtime dispatch; its handle stays open until process exit.
/// Identical requests succeed; failures and conflicting requests return `LoadError`. Linked builds panic.
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

/// The retained provider request, or null before loading and in linked builds.
/// The returned value is owned by the loader and remains valid for the process.
pub fn loadedSource() ?LoadSource {
    if (comptime !runtime_loaded) return null;
    return c.loadedSource();
}

/// Parse failures from the bridge and the full-buffer check.
/// Typed errors carry no result; use raw `c` calls to inspect out-of-range residue.
pub const Error = error{
    /// Input is not a valid prefix, or an exact parse left trailing bytes.
    InvalidArgument,
    /// The number rounded to infinity or zero; typed calls discard that value.
    ResultOutOfRange,
    /// The bridge returned an unrecognized status.
    StatusNotRecognised,
};

/// Successful `f32` parse and consumed byte count.
/// The input is borrowed for the call; errors return no result.
pub const Parsed32 = struct {
    /// Parsed value, present only on success.
    value: f32,
    /// Number of input bytes in the parsed prefix.
    consumed: usize,
};

/// Successful `f64` parse and consumed byte count; owns no input.
pub const Parsed64 = struct {
    /// Parsed value.
    value: f64,
    /// Number of input bytes in the parsed prefix.
    consumed: usize,
};

inline fn firstOf(bytes: []const u8) [*c]const u8 {
    return bytes.ptr;
}

/// Preserve an empty slice's pointer without performing pointer arithmetic.
inline fn lastOf(bytes: []const u8) [*c]const u8 {
    if (bytes.len == 0) return firstOf(bytes);
    return bytes.ptr + bytes.len;
}

/// Parses the longest leading number as `f32`; borrows `bytes` and retains nothing.
/// A prefix may succeed; use `parse32Exact` to require the whole buffer.
pub fn parse32(bytes: []const u8) Error!Parsed32 {
    var value: f32 = undefined;
    var consumed: usize = undefined;
    const code = c.ff_parse_f32(firstOf(bytes), lastOf(bytes), &value, &consumed);
    switch (code) {
        c.FF_STATUS_OK => return .{ .value = value, .consumed = consumed },
        c.FF_STATUS_INVALID_ARGUMENT => return error.InvalidArgument,
        c.FF_STATUS_RESULT_OUT_OF_RANGE => return error.ResultOutOfRange,
        // Unknown bridge statuses are errors, not panics.
        else => return error.StatusNotRecognised,
    }
}

/// Parses the longest leading number as `f64`; borrows `bytes` and retains nothing.
/// Returns `Error` for invalid input or an out-of-range result.
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

/// Parses the leading number as `f32` only when it fills the whole buffer.
/// Borrows `bytes`, retains nothing, and returns no value on `Error`.
pub fn parse32Exact(bytes: []const u8) Error!f32 {
    const parsed = try parse32(bytes);
    if (parsed.consumed != bytes.len) return error.InvalidArgument;
    return parsed.value;
}

/// Parses a full `f64` buffer; ownership and errors match `parse32Exact`.
pub fn parse64Exact(bytes: []const u8) Error!f64 {
    const parsed = try parse64(bytes);
    if (parsed.consumed != bytes.len) return error.InvalidArgument;
    return parsed.value;
}
