//! Tests the typed and raw facade against external corpus bits and hand-worked edge cases.
//! Runtime-loading builds require `FASTFLOAT_PROVIDER`; linked builds use the compiled bridge.

const std = @import("std");
const fast_float = @import("fast_float");

/// Fixture directory supplied by the build.
const paths = @import("fast_float_paths");

const provider_variable = "FASTFLOAT_PROVIDER";

/// Loads the runtime provider once before facade tests.
fn nativeReady() void {
    if (comptime !fast_float.runtime_loaded) return;
    if (fast_float.loadedSource() != null) return;

    var buffer: [4096]u8 = undefined;
    const value = std.testing.environ.getAlloc(std.testing.allocator, provider_variable) catch
        missingProvider();
    defer std.testing.allocator.free(value);
    if (value.len == 0 or value.len > buffer.len) missingProvider();
    @memcpy(buffer[0..value.len], value);
    fast_float.load(.{ .path = buffer[0..value.len] }) catch |err| {
        std.debug.print(
            "tests.zig: loading " ++ provider_variable ++ " = \"{s}\" failed: {t}\n",
            .{ buffer[0..value.len], err },
        );
        @panic("tests.zig: the provider named by " ++ provider_variable ++
            " did not load; nothing below this line ran");
    };
}

fn missingProvider() noreturn {
    @panic(
        "tests.zig: this is a runtime-loading build and " ++ provider_variable ++
            " is not set. Point it at a shared object exporting ff_parse_f32 and " ++
            "ff_parse_f64, for example the one `zig build -Dlinkage=dynamic " ++
            "-Doptimize=Debug` installs, and export it for the whole `zig build` " ++
            "invocation: the build cannot inject a path into a run step's " ++
            "environment.",
    );
}

/// Corpus files and expected line counts.
const corpus = [_]struct { name: []const u8, lines: usize }{
    .{ .name = "google-double-conversion.txt", .lines = 564_745 },
    .{ .name = "ulfjack-ryu.txt", .lines = 599_458 },
    .{ .name = "ibm-fpgen.txt", .lines = 102_792 },
    .{ .name = "lemire-fast-double-parser.txt", .lines = 94_313 },
    .{ .name = "google-wuffs.txt", .lines = 10_744 },
    .{ .name = "freetype-2-7.txt", .lines = 3_566 },
    .{ .name = "lemire-fast-float.txt", .lines = 3_299 },
    .{ .name = "tencent-rapidjson.txt", .lines = 3_563 },
    .{ .name = "more-test-cases.txt", .lines = 3 },
};

/// Fixture offsets match upstream's reader: binary32 at 5, binary64 at 14, number at 31.
const column_bits32 = .{ .start = 5, .end = 13 };
const column_bits64 = .{ .start = 14, .end = 30 };
const column_number: usize = 31;

fn hex32(text: []const u8) !u32 {
    if (text.len != 8) return error.NotAHexColumn;
    var value: u32 = 0;
    for (text) |byte| {
        const digit: u32 = switch (byte) {
            '0'...'9' => byte - '0',
            'a'...'f' => byte - 'a' + 10,
            'A'...'F' => byte - 'A' + 10,
            else => return error.NotAHexColumn,
        };
        value = (value << 4) | digit;
    }
    return value;
}

fn hex64(text: []const u8) !u64 {
    if (text.len != 16) return error.NotAHexColumn;
    var value: u64 = 0;
    for (text) |byte| {
        const digit: u64 = switch (byte) {
            '0'...'9' => byte - '0',
            'a'...'f' => byte - 'a' + 10,
            'A'...'F' => byte - 'A' + 10,
            else => return error.NotAHexColumn,
        };
        value = (value << 4) | digit;
    }
    return value;
}

const Entry = struct {
    bits32: u32,
    bits64: u64,
    number: []const u8,
};

/// Validates the corpus line shape and returns its expected patterns and decimal input.
fn entry(line: []const u8) !Entry {
    if (line.len <= column_number) return error.ShortLine;
    if (line[4] != ' ' or line[13] != ' ' or line[30] != ' ') return error.BadSeparator;
    return .{
        .bits32 = try hex32(line[column_bits32.start..column_bits32.end]),
        .bits64 = try hex64(line[column_bits64.start..column_bits64.end]),
        .number = line[column_number..],
    };
}

fn bitsMismatch(
    comptime what: []const u8,
    file: []const u8,
    number: usize,
    got: anytype,
    want: anytype,
) error{CorpusMismatch} {
    std.debug.print("{s}: line {d} ({s}): parsed 0x{x}, the recorded pattern is 0x{x}\n", .{
        file,
        number,
        what,
        got,
        want,
    });
    return error.CorpusMismatch;
}

fn lengthMismatch(
    file: []const u8,
    number: usize,
    got: usize,
    want: usize,
) error{CorpusMismatch} {
    std.debug.print("{s}: line {d}: consumed {d} bytes, the number written is {d} bytes long\n", .{
        file,
        number,
        got,
        want,
    });
    return error.CorpusMismatch;
}

fn statusMismatch(comptime what: []const u8, file: []const u8, number: usize, got: c_int, want: []const u8) error{CorpusMismatch} {
    std.debug.print("{s}: line {d} ({s}): status {d}, the recorded pattern belongs to {s}\n", .{
        file,
        number,
        what,
        got,
        want,
    });
    return error.CorpusMismatch;
}

/// Parses each fixture at both widths and compares bits, consumed lengths, and row counts.
/// Out-of-range cases use raw calls because the typed API discards the rounded result.
/// Both widths are checked for every row because either may be out of range.
fn checkFile(dir: std.Io.Dir, file: []const u8, expected_lines: usize) !void {
    const io = std.testing.io;
    const handle = try dir.openFile(io, file, .{});
    defer handle.close(io);

    // The 64 KiB buffer exceeds the corpus's longest line (1055 bytes).
    var buffer: [64 * 1024]u8 = undefined;
    var reader = handle.readerStreaming(io, &buffer);
    const lines = &reader.interface;

    var seen: usize = 0;
    var in_range: usize = 0;
    var out_of_range: usize = 0;

    while (try lines.takeDelimiter('\n')) |raw| {
        // A trailing newline adds no record; a stray carriage return fails the consumed-length check.
        const line = try entry(raw);
        seen += 1;
        if (seen > expected_lines) {
            std.debug.print("{s}: more than the {d} lines this fork expects\n", .{ file, expected_lines });
            return error.CorpusGrew;
        }

        // Check both widths for each row; one may be in range while the other is not.
        const parsed32 = fast_float.parse32(line.number);
        const parsed64 = fast_float.parse64(line.number);

        if (parsed32) |parsed| {
            in_range += 1;
            const bits: u32 = @bitCast(parsed.value);
            if (bits != line.bits32) return bitsMismatch("binary32", file, seen, bits, line.bits32);
            if (parsed.consumed != line.number.len)
                return lengthMismatch(file, seen, parsed.consumed, line.number.len);
        } else |err| switch (err) {
            error.ResultOutOfRange => {
                out_of_range += 1;
                var raw_value: f32 = undefined;
                var raw_consumed: usize = undefined;
                const code = fast_float.c.ff_parse_f32(
                    line.number.ptr,
                    line.number.ptr + line.number.len,
                    &raw_value,
                    &raw_consumed,
                );
                if (code != fast_float.c.FF_STATUS_RESULT_OUT_OF_RANGE)
                    return statusMismatch("binary32 status", file, seen, code, "result_out_of_range");
                const bits: u32 = @bitCast(raw_value);
                if (bits != line.bits32) return bitsMismatch("binary32", file, seen, bits, line.bits32);
                if (raw_consumed != line.number.len)
                    return lengthMismatch(file, seen, raw_consumed, line.number.len);
            },
            else => {
                std.debug.print("{s}: line {d} ({s}) did not parse at binary32: {s}\n", .{
                    file,
                    seen,
                    line.number,
                    @errorName(err),
                });
                return error.CorpusMismatch;
            },
        }

        if (parsed64) |parsed| {
            in_range += 1;
            const bits: u64 = @bitCast(parsed.value);
            if (bits != line.bits64) return bitsMismatch("binary64", file, seen, bits, line.bits64);
            if (parsed.consumed != line.number.len)
                return lengthMismatch(file, seen, parsed.consumed, line.number.len);
        } else |err| switch (err) {
            error.ResultOutOfRange => {
                out_of_range += 1;
                var raw_value: f64 = undefined;
                var raw_consumed: usize = undefined;
                const code = fast_float.c.ff_parse_f64(
                    line.number.ptr,
                    line.number.ptr + line.number.len,
                    &raw_value,
                    &raw_consumed,
                );
                if (code != fast_float.c.FF_STATUS_RESULT_OUT_OF_RANGE)
                    return statusMismatch("binary64 status", file, seen, code, "result_out_of_range");
                const bits: u64 = @bitCast(raw_value);
                if (bits != line.bits64) return bitsMismatch("binary64", file, seen, bits, line.bits64);
                if (raw_consumed != line.number.len)
                    return lengthMismatch(file, seen, raw_consumed, line.number.len);
            },
            else => {
                std.debug.print("{s}: line {d} ({s}) did not parse at binary64: {s}\n", .{
                    file,
                    seen,
                    line.number,
                    @errorName(err),
                });
                return error.CorpusMismatch;
            },
        }
    }

    if (seen != expected_lines) {
        std.debug.print("{s}: read {d} lines, this fork expects {d}\n", .{ file, seen, expected_lines });
        return error.CorpusShrank;
    }
    if (seen == 0) {
        std.debug.print("{s}: no lines were read at all\n", .{file});
        return error.CorpusEmpty;
    }
    std.debug.print("{s}: {d} lines, {d} parses in range, {d} out of range\n", .{
        file,
        seen,
        in_range,
        out_of_range,
    });
}

test "every selected corpus file matches its recorded bit patterns at both widths" {
    nativeReady();
    const io = std.testing.io;
    var dir = try std.Io.Dir.cwd().openDir(io, paths.data_dir, .{});
    defer dir.close(io);

    for (corpus) |file| {
        try checkFile(dir, file.name, file.lines);
    }
}

// Hand-worked edge cases.

test "one tenth is the same double and float whatever else is true of them" {
    nativeReady();
    // Exact 1/10 rounds differently at each width; negative inputs retain their sign.
    try std.testing.expectEqual(@as(u64, 0x3FB999999999999A), @as(u64, @bitCast(try fast_float.parse64Exact("0.1"))));
    try std.testing.expectEqual(@as(u32, 0x3DCCCCCD), @as(u32, @bitCast(try fast_float.parse32Exact("0.1"))));

    try std.testing.expectEqual(@as(u64, 0xBFB999999999999A), @as(u64, @bitCast(try fast_float.parse64Exact("-0.1"))));
    try std.testing.expectEqual(@as(u32, 0xBDCCCCCD), @as(u32, @bitCast(try fast_float.parse32Exact("-0.1"))));
}

test "a halfway decimal rounds to even, and the next decimal up does not" {
    nativeReady();
    // The exact midpoint between adjacent doubles rounds to the even significand.
    const midpoint = "1.00000000000000011102230246251565404236316680908203125";
    try std.testing.expectEqual(@as(u64, 0x3FF0000000000000), @as(u64, @bitCast(try fast_float.parse64Exact(midpoint))));

    const above = "1.00000000000000011102230246251565404236316680908203126";
    try std.testing.expectEqual(@as(u64, 0x3FF0000000000001), @as(u64, @bitCast(try fast_float.parse64Exact(above))));

    const below = "1.00000000000000011102230246251565404236316680908203124";
    try std.testing.expectEqual(@as(u64, 0x3FF0000000000000), @as(u64, @bitCast(try fast_float.parse64Exact(below))));

    try std.testing.expectEqual(@as(u32, 0x3F800000), @as(u32, @bitCast(try fast_float.parse32Exact("1.000000059604644775390625"))));
    try std.testing.expectEqual(@as(u32, 0x3F800001), @as(u32, @bitCast(try fast_float.parse32Exact("1.000000059604644775390626"))));

    // The tie result is independent of the host FPU rounding mode.
}

test "more digits than the significand can hold change the answer only when they should" {
    nativeReady();
    // Around 2^53, the cases cover exact, inexact, and halfway decimal inputs.
    try std.testing.expectEqual(@as(u64, 0x4340000000000000), @as(u64, @bitCast(try fast_float.parse64Exact("9007199254740992"))));
    try std.testing.expectEqual(@as(u64, 0x4340000000000000), @as(u64, @bitCast(try fast_float.parse64Exact("9007199254740993"))));
    try std.testing.expectEqual(@as(u64, 0x4340000000000001), @as(u64, @bitCast(try fast_float.parse64Exact("9007199254740994"))));
    try std.testing.expectEqual(@as(u64, 0x4340000000000002), @as(u64, @bitCast(try fast_float.parse64Exact("9007199254740995"))));
    try std.testing.expectEqual(@as(u64, 0x4340000000000002), @as(u64, @bitCast(try fast_float.parse64Exact("9007199254740996"))));

    try std.testing.expectEqual(@as(u32, 0x4B800000), @as(u32, @bitCast(try fast_float.parse32Exact("16777216"))));
    try std.testing.expectEqual(@as(u32, 0x4B800000), @as(u32, @bitCast(try fast_float.parse32Exact("16777217"))));
    try std.testing.expectEqual(@as(u32, 0x4B800001), @as(u32, @bitCast(try fast_float.parse32Exact("16777218"))));

    // 2^64 exercises all 53 bits of the double significand.
    try std.testing.expectEqual(@as(u64, 0x43F0000000000000), @as(u64, @bitCast(try fast_float.parse64Exact("18446744073709551616"))));
    try std.testing.expectEqual(@as(u64, 0x43F0000000000000), @as(u64, @bitCast(try fast_float.parse64Exact("18446744073709551617"))));
}

test "the largest finite value is in range and the next decimal out is not" {
    nativeReady();
    // The largest finite value succeeds; values that round to infinity are out of range.
    const largest = try fast_float.parse64Exact("1.7976931348623157e308");
    try std.testing.expectEqual(@as(u64, 0x7FEFFFFFFFFFFFFF), @as(u64, @bitCast(largest)));

    try std.testing.expectError(error.ResultOutOfRange, fast_float.parse64("1.7976931348623159e308"));
    try std.testing.expectError(error.ResultOutOfRange, fast_float.parse64("1.8e308"));

    const largest32 = try fast_float.parse32Exact("3.4028234663852886e38");
    try std.testing.expectEqual(@as(u32, 0x7F7FFFFF), @as(u32, @bitCast(largest32)));
    try std.testing.expectError(error.ResultOutOfRange, fast_float.parse32("3.5e38"));

    // A value above max finite can still round back to max finite.
    const just_below = try fast_float.parse32Exact("3.4028235677973366e38");
    try std.testing.expectEqual(@as(u32, 0x7F7FFFFF), @as(u32, @bitCast(just_below)));
}

test "the smallest subnormal is in range and half of it is not" {
    nativeReady();
    // Check the smallest positive subnormal and the half-way underflow boundary.
    const min_subnormal = try fast_float.parse64Exact("4.9406564584124654e-324");
    try std.testing.expectEqual(@as(u64, 0x0000000000000001), @as(u64, @bitCast(min_subnormal)));

    try std.testing.expectError(error.ResultOutOfRange, fast_float.parse64("2.4703282292062327e-324"));

    // A value just above half rounds up to the smallest subnormal.
    const above_tie = try fast_float.parse64Exact("2.4703282292062328e-324");
    try std.testing.expectEqual(@as(u64, 0x0000000000000001), @as(u64, @bitCast(above_tie)));

    const min_subnormal32 = try fast_float.parse32Exact("1.4012984643248171e-45");
    try std.testing.expectEqual(@as(u32, 0x00000001), @as(u32, @bitCast(min_subnormal32)));

    const above_half32 = try fast_float.parse32Exact("7.0064923216240854e-46");
    try std.testing.expectEqual(@as(u32, 0x00000001), @as(u32, @bitCast(above_half32)));
}

test "the boundary between subnormal and normal is a step, not a slope" {
    nativeReady();
    // Adjacent patterns straddle the normal/subnormal boundary with no gap.
    try std.testing.expectEqual(@as(u64, 0x000FFFFFFFFFFFFF), @as(u64, @bitCast(try fast_float.parse64Exact("2.2250738585072009e-308"))));
    try std.testing.expectEqual(@as(u64, 0x000FFFFFFFFFFFFF), @as(u64, @bitCast(try fast_float.parse64Exact("2.2250738585072011e-308"))));
    try std.testing.expectEqual(@as(u64, 0x0010000000000000), @as(u64, @bitCast(try fast_float.parse64Exact("2.2250738585072012e-308"))));
    try std.testing.expectEqual(@as(u64, 0x0010000000000000), @as(u64, @bitCast(try fast_float.parse64Exact("2.2250738585072014e-308"))));

    try std.testing.expectEqual(@as(u32, 0x007FFFFF), @as(u32, @bitCast(try fast_float.parse32Exact("1.1754942106924411e-38"))));
    try std.testing.expectEqual(@as(u32, 0x00800000), @as(u32, @bitCast(try fast_float.parse32Exact("1.1754943508222875e-38"))));
}

test "an out-of-range parse still consumed the whole number and stored the rounded value" {
    nativeReady();
    // Raw calls expose rounded values that typed errors discard.
    var value: f64 = undefined;
    var consumed: usize = undefined;
    const overflow_text = "1e681";
    const code = fast_float.c.ff_parse_f64(overflow_text.ptr, overflow_text.ptr + overflow_text.len, &value, &consumed);
    try std.testing.expectEqual(fast_float.c.FF_STATUS_RESULT_OUT_OF_RANGE, code);
    try std.testing.expectEqual(@as(u64, 0x7FF0000000000000), @as(u64, @bitCast(value)));
    try std.testing.expectEqual(@as(usize, overflow_text.len), consumed);

    var small: f32 = undefined;
    var small_consumed: usize = undefined;
    const underflow_text = "1e-46";
    const small_code = fast_float.c.ff_parse_f32(underflow_text.ptr, underflow_text.ptr + underflow_text.len, &small, &small_consumed);
    try std.testing.expectEqual(fast_float.c.FF_STATUS_RESULT_OUT_OF_RANGE, small_code);
    try std.testing.expectEqual(@as(u32, 0x00000000), @as(u32, @bitCast(small)));
    try std.testing.expectEqual(@as(usize, underflow_text.len), small_consumed);

    const normal_small = try fast_float.parse32Exact("1e-38");
    try std.testing.expectEqual(@as(u32, 0x006CE3EE), @as(u32, @bitCast(normal_small)));
}

test "a parse that matches nothing leaves the caller's out-parameters unwritten" {
    nativeReady();
    // Invalid arguments must leave both out-parameters unchanged.
    var value: f64 = @bitCast(@as(u64, 0xDEADBEEFCAFEF00D));
    var consumed: usize = 0x5EED5EED;
    const code = fast_float.c.ff_parse_f64("nonsense".ptr, "nonsense".ptr + 8, &value, &consumed);
    try std.testing.expectEqual(fast_float.c.FF_STATUS_INVALID_ARGUMENT, code);
    try std.testing.expectEqual(@as(u64, 0xDEADBEEFCAFEF00D), @as(u64, @bitCast(value)));
    try std.testing.expectEqual(@as(usize, 0x5EED5EED), consumed);

    // Empty ranges have the same no-write behavior.
    var empty_value: f32 = @bitCast(@as(u32, 0xFEEDFACE));
    var empty_consumed: usize = 0x0BADF00D;
    const nothing: []const u8 = "";
    const empty_code = fast_float.c.ff_parse_f32(nothing.ptr, nothing.ptr, &empty_value, &empty_consumed);
    try std.testing.expectEqual(fast_float.c.FF_STATUS_INVALID_ARGUMENT, empty_code);
    try std.testing.expectEqual(@as(u32, 0xFEEDFACE), @as(u32, @bitCast(empty_value)));
    try std.testing.expectEqual(@as(usize, 0x0BADF00D), empty_consumed);
}

// Accepted and rejected input forms.

test "a prefix of the buffer is a parse, and the whole buffer is a stricter one" {
    nativeReady();
    // Prefix parsing stops before the tail; exact parsing rejects it.
    const prefixed = try fast_float.parse64("1.5 seconds");
    try std.testing.expectEqual(@as(u64, 0x3FF8000000000000), @as(u64, @bitCast(prefixed.value)));
    try std.testing.expectEqual(@as(usize, 3), prefixed.consumed);

    try std.testing.expectError(error.InvalidArgument, fast_float.parse64Exact("1.5 seconds"));
    try std.testing.expectEqual(@as(u64, 0x3FF8000000000000), @as(u64, @bitCast(try fast_float.parse64Exact("1.5"))));

    const prefixed32 = try fast_float.parse32("1.5s");
    try std.testing.expectEqual(@as(u32, 0x3FC00000), @as(u32, @bitCast(prefixed32.value)));
    try std.testing.expectEqual(@as(usize, 3), prefixed32.consumed);
    try std.testing.expectError(error.InvalidArgument, fast_float.parse32Exact("1.5s"));

    // A complete exponent belongs to the parsed prefix.
    const with_exponent = try fast_float.parse64("1.5e3,");
    try std.testing.expectEqual(@as(u64, 0x4097700000000000), @as(u64, @bitCast(with_exponent.value)));
    try std.testing.expectEqual(@as(usize, 5), with_exponent.consumed);

    // An exponent marker without digits remains in the tail.
    const dangling_exponent = try fast_float.parse64("1e");
    try std.testing.expectEqual(@as(u64, 0x3FF0000000000000), @as(u64, @bitCast(dangling_exponent.value)));
    try std.testing.expectEqual(@as(usize, 1), dangling_exponent.consumed);
}

test "the format refuses what the standard's from_chars refuses" {
    nativeReady();
    // General format rejects leading whitespace and a leading plus sign.
    const refused = [_][]const u8{
        "", // nothing at all
        " ", // whitespace only
        "+1", // leading plus
        " 1", // leading space
        "\t1", // leading tab
        "\n1", // leading newline
        "abc", // no number anywhere
        ".", // a dot with no digits on either side
        "-", // a sign with nothing after it
        "-+1", // a sign followed by a sign
        "--1", // two signs
        "e5", // an exponent marker with no significand
        "E5", // the same in upper case
        "e", // a lone exponent marker
    };
    for (refused) |input| {
        try std.testing.expectError(error.InvalidArgument, fast_float.parse64(input));
        try std.testing.expectError(error.InvalidArgument, fast_float.parse32(input));
        try std.testing.expectError(error.InvalidArgument, fast_float.parse64Exact(input));
        try std.testing.expectError(error.InvalidArgument, fast_float.parse32Exact(input));
    }

    // Exercise an empty slice without performing pointer arithmetic.
    const empty: []const u8 = "";
    try std.testing.expectError(error.InvalidArgument, fast_float.parse64(empty));
    try std.testing.expectError(error.InvalidArgument, fast_float.parse32(empty));
}

test "infinity and not-a-number parse, and a negative zero keeps its sign" {
    nativeReady();
    // General format accepts infinity and NaN; validate untrusted input separately.
    try std.testing.expectEqual(@as(u64, 0x7FF0000000000000), @as(u64, @bitCast(try fast_float.parse64Exact("inf"))));
    try std.testing.expectEqual(@as(u64, 0x7FF0000000000000), @as(u64, @bitCast(try fast_float.parse64Exact("INF"))));
    try std.testing.expectEqual(@as(u64, 0x7FF0000000000000), @as(u64, @bitCast(try fast_float.parse64Exact("infinity"))));
    try std.testing.expectEqual(@as(u64, 0xFFF0000000000000), @as(u64, @bitCast(try fast_float.parse64Exact("-infinity"))));
    try std.testing.expectEqual(@as(u32, 0x7F800000), @as(u32, @bitCast(try fast_float.parse32Exact("inf"))));

    // The prefix parser recognizes `inf` even when the longer spelling is incomplete.
    const truncated = try fast_float.parse64("infin");
    try std.testing.expectEqual(@as(u64, 0x7FF0000000000000), @as(u64, @bitCast(truncated.value)));
    try std.testing.expectEqual(@as(usize, 3), truncated.consumed);

    // NaN payload bits are unspecified; check classification and consumed length.
    const nan64 = try fast_float.parse64Exact("nan");
    try std.testing.expect(std.math.isNan(nan64));
    const nan_spelling = try fast_float.parse64("nan(ind)");
    try std.testing.expect(std.math.isNan(nan_spelling.value));
    try std.testing.expectEqual(@as(usize, 8), nan_spelling.consumed);
    const nan32 = try fast_float.parse32Exact("-nan");
    try std.testing.expect(std.math.isNan(nan32));

    // Negative zero has a distinct sign bit.
    try std.testing.expectEqual(@as(u64, 0x0000000000000000), @as(u64, @bitCast(try fast_float.parse64Exact("0"))));
    try std.testing.expectEqual(@as(u64, 0x8000000000000000), @as(u64, @bitCast(try fast_float.parse64Exact("-0"))));
    try std.testing.expectEqual(@as(u64, 0x8000000000000000), @as(u64, @bitCast(try fast_float.parse64Exact("-0.0"))));
    try std.testing.expectEqual(@as(u64, 0x8000000000000000), @as(u64, @bitCast(try fast_float.parse64Exact("-0e0"))));
    try std.testing.expectEqual(@as(u32, 0x80000000), @as(u32, @bitCast(try fast_float.parse32Exact("-0.0"))));

    // Raw output preserves the sign of an underflowed zero.
    var underflowed: f64 = 0;
    var consumed: usize = 0;
    const underflow_text = "-1e-400";
    const code = fast_float.c.ff_parse_f64(underflow_text.ptr, underflow_text.ptr + underflow_text.len, &underflowed, &consumed);
    try std.testing.expectEqual(fast_float.c.FF_STATUS_RESULT_OUT_OF_RANGE, code);
    try std.testing.expectEqual(@as(u64, 0x8000000000000000), @as(u64, @bitCast(underflowed)));
    try std.testing.expectEqual(@as(usize, underflow_text.len), consumed);
}

test "the decimal point and the exponent are the ones the corpus was written with" {
    nativeReady();
    // A decimal point may have digits on only one side.
    try std.testing.expectEqual(@as(u64, 0x3FE0000000000000), @as(u64, @bitCast(try fast_float.parse64Exact(".5"))));
    try std.testing.expectEqual(@as(u64, 0x4014000000000000), @as(u64, @bitCast(try fast_float.parse64Exact("5."))));
    try std.testing.expectEqual(@as(u64, 0x40B3880000000000), @as(u64, @bitCast(try fast_float.parse64Exact("5.e3"))));

    // Exponents accept either case and an optional sign.
    try std.testing.expectEqual(@as(u64, 0x3FF0000000000000), @as(u64, @bitCast(try fast_float.parse64Exact("1E0"))));
    try std.testing.expectEqual(@as(u64, 0x4097700000000000), @as(u64, @bitCast(try fast_float.parse64Exact("1.5e+3"))));
    try std.testing.expectEqual(@as(u64, 0x408F400000000000), @as(u64, @bitCast(try fast_float.parse64Exact("1e3"))));
    try std.testing.expectEqual(@as(u64, 0x3F847AE147AE147B), @as(u64, @bitCast(try fast_float.parse64Exact("1e-2"))));

    // General format accepts leading zeros.
    try std.testing.expectEqual(@as(u64, 0x401C000000000000), @as(u64, @bitCast(try fast_float.parse64Exact("007"))));
    try std.testing.expectEqual(@as(u64, 0x3E7AD7F29ABCAF48), @as(u64, @bitCast(try fast_float.parse64Exact("0.0000001"))));

    // Long significands are not truncated before rounding.
    const long = try fast_float.parse64Exact("123456789012345678901234567890123456789");
    try std.testing.expectEqual(@as(u64, 0x47D7383A69580580), @as(u64, @bitCast(long)));
}
