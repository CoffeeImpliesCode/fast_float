//! A runnable, deterministic demonstration of the facade. `zig build smoke`
//! runs this.
//!
//! It parses one literal, `"0.1"`, at both widths and prints the IEEE 754 bit
//! pattern of each result. Every expected pattern below was worked out by exact
//! rational rounding, not read out of this library, so a change in the output is
//! a change in fast_float or in the binding rather than a restatement of
//! either:
//!
//! ```text
//! 1/10 has no binary expansion. At double width the nearest value is
//! 0x3FB999999999999A, whose exact decimal value is
//! 0.1000000000000000055511151231257827021181583404541015625. At float width
//! the nearest value is 0x3DCCCCCD, whose exact value is
//! 0.100000001490116119384765625.
//! ```
//!
//! Then it shows the three things a caller has to handle and cannot see from a
//! value alone: that a number can be a prefix of a longer buffer, that a tail
//! makes the same buffer unacceptable to the exact entry point, and that a
//! leading `+` is refused where `strtod` would accept it.
//!
//! Each expected value is compared with an ordinary comparison and a mismatch
//! returns an error, so the process exits non-zero. A debug assertion would be
//! compiled out of a release build, which is not a check.

const std = @import("std");
const fast_float = @import("fast_float");

/// The one literal every known answer below is about.
const tenth = "0.1";

/// The nearest double to 1/10, and the nearest float to it.
///
/// Written as the bit patterns, not as decimal, because a decimal here would
/// itself be a value this library produces and could not be checked against.
const tenth_bits64: u64 = 0x3FB999999999999A;
const tenth_bits32: u32 = 0x3DCCCCCD;

pub fn main() !void {
    var threaded: std.Io.Threaded = .init(std.heap.page_allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout.interface;

    try w.print("fast_float smoke\n", .{});
    try w.print("parsing the literal {s} at both widths\n", .{tenth});

    // The exact entry points, because the buffer holds nothing but the number
    // and there is nothing else for them to accept.
    const as_double = try fast_float.parse64Exact(tenth);
    if (@as(u64, @bitCast(as_double)) != tenth_bits64) {
        try w.print("  double: expected 0x{X:0>16}, parsed 0x{X:0>16}\n", .{
            tenth_bits64,
            @as(u64, @bitCast(as_double)),
        });
        try w.flush();
        return error.DoubleBitsMismatch;
    }
    try w.print("  double: 0.1 -> 0x{X:0>16}\n", .{tenth_bits64});

    const as_float = try fast_float.parse32Exact(tenth);
    if (@as(u32, @bitCast(as_float)) != tenth_bits32) {
        try w.print("  float:  expected 0x{X:0>8}, parsed 0x{X:0>8}\n", .{
            tenth_bits32,
            @as(u32, @bitCast(as_float)),
        });
        try w.flush();
        return error.FloatBitsMismatch;
    }
    try w.print("  float:  0.1 -> 0x{X:0>8}\n", .{tenth_bits32});

    // The prefix contract. `from_chars` consumes the number and stops at the
    // first byte that cannot continue it, and reports where it stopped, so the
    // caller decides what a number followed by something else means.
    const buffered = "0.1 seconds";
    const prefix = try fast_float.parse64(buffered);
    if (@as(u64, @bitCast(prefix.value)) != tenth_bits64 or prefix.consumed != 3) {
        try w.print("  prefix {s}: parsed 0x{X:0>16} after {d} bytes, expected 0x{X:0>16} after 3\n", .{
            buffered,
            @as(u64, @bitCast(prefix.value)),
            prefix.consumed,
            tenth_bits64,
        });
        try w.flush();
        return error.PrefixMismatch;
    }
    try w.print("  prefix {s}: 0x{X:0>16} in the first {d} bytes, the rest is not a number\n", .{
        buffered,
        tenth_bits64,
        prefix.consumed,
    });

    // The same prefix contract at float width, which is the other half of the
    // typed surface and lands on a different value: 0.1 is not representable at
    // either width and the two roundings differ.
    const buffered32 = "0.1 seconds";
    const prefix32 = try fast_float.parse32(buffered32);
    const prefix32_bits: u32 = @as(u32, @bitCast(prefix32.value));
    if (prefix32_bits != tenth_bits32 or prefix32.consumed != 3) {
        try w.print("  prefix {s}: parsed 0x{X:0>8} after {d} bytes, expected 0x{X:0>8} after 3\n", .{
            buffered32,
            prefix32_bits,
            prefix32.consumed,
            tenth_bits32,
        });
        try w.flush();
        return error.PrefixFloatMismatch;
    }
    try w.print("  prefix {s}: 0x{X:0>8} in the first {d} bytes at float width\n", .{
        buffered32,
        prefix32_bits,
        prefix32.consumed,
    });

    // The same buffer through the exact entry point. This is the one difference
    // between the two pairs of functions, and it is a difference in what the
    // caller asked for, not in what was parsed: the number is still 0.1, and the
    // buffer is simply not entirely a number.
    const refusal = fast_float.parse64Exact(buffered);
    if (refusal) |value| {
        try w.print("  exact {s}: unexpectedly accepted, as 0x{X:0>16}\n", .{ buffered, @as(u64, @bitCast(value)) });
        try w.flush();
        return error.TrailingBytesAccepted;
    } else |err| switch (err) {
        error.InvalidArgument => try w.print("  exact {s}: refused, the buffer holds more than the number\n", .{buffered}),
        else => {
            try w.print("  exact {s}: failed with {s}, expected a refusal of the trailing bytes\n", .{ buffered, @errorName(err) });
            try w.flush();
            return error.UnexpectedExactError;
        },
    }

    // The format is the one C++17 gives `from_chars` and not the one `strtod`
    // gives: no leading `+`, and no skipping of leading whitespace. Both of
    // these are the same number to `strtod`, and both are refused here.
    for ([_][]const u8{ "+0.1", " 0.1", "\t0.1" }) |refused| {
        const outcome = fast_float.parse64Exact(refused);
        if (outcome) |value| {
            try w.print("  {s}: unexpectedly accepted, as 0x{X:0>16}\n", .{ refused, @as(u64, @bitCast(value)) });
            try w.flush();
            return error.ForbiddenPrefixAccepted;
        } else |err| switch (err) {
            error.InvalidArgument => try w.print("  {s}: refused\n", .{std.mem.trim(u8, refused, " \t")}),
            else => {
                try w.print("  {s}: failed with {s}\n", .{ refused, @errorName(err) });
                try w.flush();
                return error.UnexpectedRefusalError;
            },
        }
    }

    // A negative zero keeps its sign, which is a property of the value that a
    // decimal print would hide.
    const negative_zero = try fast_float.parse64Exact("-0.0");
    const zero_bits: u64 = @as(u64, @bitCast(negative_zero));
    if (zero_bits != 0x8000000000000000) {
        try w.print("  -0.0: expected 0x{X:0>16}, parsed 0x{X:0>16}\n", .{ @as(u64, 0x8000000000000000), zero_bits });
        try w.flush();
        return error.NegativeZeroMismatch;
    }
    try w.print("  -0.0 -> 0x{X:0>16}, a negative zero and not a positive one\n", .{zero_bits});

    try w.print("every printed pattern is the one worked out in the comment above this file\n", .{});
    try w.flush();
}
