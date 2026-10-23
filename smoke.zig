//! Deterministic demonstration of prefix, exact, rejection, and sign-preserving parses.
//! Runtime-loading builds require `--provider <path>` or `FASTFLOAT_PROVIDER`.

const std = @import("std");
const fast_float = @import("fast_float");

const ConfigurationError = error{NoProviderConfigured};

const tenth = "0.1";

/// Expected nearest binary64 and binary32 encodings of 1/10.
const tenth_bits64: u64 = 0x3FB999999999999A;
const tenth_bits32: u32 = 0x3DCCCCCD;

pub fn main(init: std.process.Init) !void {
    if (comptime fast_float.runtime_loaded) {
        try fast_float.load(.{ .path = try providerRequest(init) });
    }

    const io = init.io;
    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout.interface;

    try w.print("fast_float smoke ({s} build)\n", .{
        if (fast_float.runtime_loaded) "runtime-loaded" else "linked",
    });

    // Report the provider used by a runtime-loading build.
    if (fast_float.runtime_loaded) {
        if (fast_float.loadedSource()) |source| switch (source) {
            .path => |p| try w.print("provider: {s}\n", .{p}),
            .system => |s| try w.print("provider: {s} (named to the platform loader)\n", .{s}),
        };
    }
    try w.print("parsing the literal {s} at both widths\n", .{tenth});

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

    // Prefix parsing reports where the numeric portion ends.
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

    // Exact parsing rejects the same buffer's trailing text.
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

    // General format rejects leading whitespace and a leading plus sign.
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

    // Inspect bits because decimal formatting hides negative zero.
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

/// Reads an explicit provider path from `--provider` or `FASTFLOAT_PROVIDER`.
fn providerRequest(init: std.process.Init) ConfigurationError![]const u8 {
    const args = init.minimal.args.toSlice(init.arena.allocator()) catch
        return noProvider();
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        if (std.mem.eql(u8, args[index], "--provider")) {
            if (index + 1 >= args.len) return noProvider();
            return args[index + 1];
        }
    }
    return init.environ_map.get("FASTFLOAT_PROVIDER") orelse
        return noProvider();
}

/// Prints the missing-provider diagnostic and returns the configuration error.
fn noProvider() ConfigurationError {
    std.debug.print(
        "smoke: this is a runtime-loading build. Pass --provider <path>, or " ++
            "export FASTFLOAT_PROVIDER with a shared object exporting ff_parse_f32 " ++
            "and ff_parse_f64. Nothing is loaded by default and no other file is " ++
            "tried.\n",
        .{},
    );
    return error.NoProviderConfigured;
}
