//! Behavioural tests for the fast_float facade.
//!
//! Two kinds of expectation live here, and they are kept apart on purpose.
//!
//!   * The corpus tests read `testdata/supplemental/data`, which is an
//!     independent collection of decimal strings with their exact IEEE 754 bit
//!     patterns recorded beside them. Those patterns were produced by other
//!     projects — Google's double-conversion, Ryū, IBM's fpgen, Wuffs,
//!     FreeType, Lemire, RapidJSON — and not by this fork, so agreeing with them
//!     is this binding agreeing with implementations it shares no code with.
//!     `testdata/README.md` records which files are read, in what format, and
//!     what the cross-check of the columns found.
//!   * The hand-worked tests carry answers worked out by exact rational
//!     rounding, written down here with the reason they are the right answer.
//!     They are what pins the behaviours the corpus does not isolate: the
//!     halfway cases, the format boundaries, prefix versus whole-buffer, and
//!     the inputs no number can be made of.
//!
//! Nothing here was produced by running this fork. Every expected value is
//! either read out of the corpus or was worked out by hand.
//!
//! Every public method on `fast_float` — `parse32`, `parse64`, `parse32Exact`,
//! `parse64Exact` — is called from this file, which is what makes building the
//! test binary a real check of the facade rather than of an unreferenced C
//! archive. The raw `fast_float.c` surface is called too, and for a reason: the
//! typed surface deliberately withholds the value of an out-of-range parse, and
//! the corpus records the bit pattern such a parse has to end up with, so the
//! only place that value can be read is the raw call.
//!
//! ## The provider, in a runtime-loading build
//!
//! A `-Druntime` build links no bridge, so every test below reaches the library
//! through the loader and nothing works until a provider has been named. It is
//! named by `FASTFLOAT_PROVIDER`, an absolute path to a shared object or import
//! library exporting `ff_parse_f32` and `ff_parse_f64`. Nothing is loaded by
//! default and no other file is tried: a build that was not told which file to
//! load stops with the variable's name rather than reporting a failure that
//! says nothing about the reason. In a linked build the variable is never read.

const std = @import("std");
const fast_float = @import("fast_float");

/// Where the build put the fixture corpus. Relative to the build root, which is
/// the working directory a `Step.Run` with no explicit cwd inherits.
const paths = @import("fast_float_paths");

/// A shared object exporting `ff_parse_f32` and `ff_parse_f64`, named by the
/// environment in a runtime-loading build.
const provider_variable = "FASTFLOAT_PROVIDER";

/// Make the native library usable, once, before a test calls the facade.
///
/// Safe to call from every test: the loader's contract makes the same request
/// idempotent and keeps the handle to the end of the process. `loadedSource` is
/// what makes the second and later calls free of work, so the corpus below —
/// which asks for the library once per line, millions of times — pays for the
/// load once and for an acquire load per call after that, which is the same
/// check every routed call makes anyway.
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

/// The corpus files this fork reads, with the line count each one has.
///
/// The count is part of the expectation, not bookkeeping: a file that stopped
/// being read halfway would otherwise pass every remaining line it did read.
/// These are the counts observed in the vendored bytes, which are upstream's
/// and are not rewritten by this fork.
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

/// The 31 fixed bytes before the number on every corpus line: four hex digits of
/// binary16, a space, eight of binary32, a space, sixteen of binary64, a space.
/// This is upstream's own layout — `tests/basictest.cpp` reads the 32-bit column
/// from `str.data() + 5` and the 64-bit one from `str.data() + 14`, and takes
/// the number from `str.data() + 31` — not an inference from the data.
const column_bits32 = .{ .start = 5, .end = 13 };
const column_bits64 = .{ .start = 14, .end = 30 };
const column_number: usize = 31;

/// Reads `text` as hex into a `u32`, most significant digit first.
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

/// Reads `text` as hex into a `u64`, most significant digit first.
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

/// One corpus line, taken apart.
const Entry = struct {
    /// The exact binary32 pattern the decimal string is expected to produce.
    bits32: u32,
    /// The exact binary64 pattern, likewise.
    bits64: u64,
    /// The decimal string itself, which is the whole rest of the line.
    number: []const u8,
};

/// Takes one corpus line apart, or says why it cannot be.
///
/// The shape is checked rather than assumed: a line that is not 31 fixed bytes
/// followed by a nonempty number is a corpus this fork does not understand, and
/// silently skipping it would turn a changed fixture into a passing test.
fn entry(line: []const u8) !Entry {
    if (line.len <= column_number) return error.ShortLine;
    if (line[4] != ' ' or line[13] != ' ' or line[30] != ' ') return error.BadSeparator;
    return .{
        .bits32 = try hex32(line[column_bits32.start..column_bits32.end]),
        .bits64 = try hex64(line[column_bits64.start..column_bits64.end]),
        .number = line[column_number..],
    };
}

/// Says which file and line a bit-pattern disagreement was found on, then fails.
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

/// The same for a length, which is a count rather than a pattern.
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

/// Says which file and line a status disagreement was found on, then fails.
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

/// Reads one corpus file and checks every line against both widths.
///
/// A line whose number is in range goes through the typed surface, and its
/// consumed count has to be the whole number: the corpus records a number and
/// nothing after it, so a parse that stopped early would be a binding that
/// reports the wrong pointer even where it reports the right value.
///
/// A line whose number is out of range cannot be checked through the typed
/// surface, which reports that condition as an error and deliberately does not
/// hand back a value the caller did not write. Those lines go through the raw
/// `c` call instead, where the value upstream stored is visible, and both the
/// status and the bits are compared. That is the only place in this file where
/// the raw surface is used for the corpus, and it is used because the typed
/// surface cannot answer the question.
///
/// Both widths are parsed on every line before either one is judged, because a
/// number can be out of range at one width and in range at the other, and a
/// check that returned on the first outcome would leave the second unverified.
fn checkFile(dir: std.Io.Dir, file: []const u8, expected_lines: usize) !void {
    const io = std.testing.io;
    const handle = try dir.openFile(io, file, .{});
    defer handle.close(io);

    // The longest line in the corpus is 1055 bytes, and this buffer is an order
    // of magnitude larger, so no line can be split across a refill.
    var buffer: [64 * 1024]u8 = undefined;
    var reader = handle.readerStreaming(io, &buffer);
    const lines = &reader.interface;

    var seen: usize = 0;
    var in_range: usize = 0;
    var out_of_range: usize = 0;

    while (try lines.takeDelimiter('\n')) |raw| {
        // The delimiter is not part of the slice and end of stream is null, so
        // the trailing newline every corpus file ends with produces no empty
        // final line. A line longer than the buffer would be a `StreamTooLong`
        // error rather than a short line, which is the safe way round: it cannot
        // be mistaken for a shorter number. A stray `\r` would end up inside
        // `number`, where the parser stops before it and the consumed count
        // check below would fail on it.
        const line = try entry(raw);
        seen += 1;
        if (seen > expected_lines) {
            std.debug.print("{s}: more than the {d} lines this fork expects\n", .{ file, expected_lines });
            return error.CorpusGrew;
        }

        // Both parses are resolved before either is judged. A number can be out
        // of range at one width and in range at the other, which is ordinary
        // corpus content, so neither call may return early and leave the other
        // width — or the rest of this row — unchecked. `if` on an error union
        // binds the payload or the error; there is no `switch` on a union.
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

// ---------------------------------------------------------------------------
// Hand-worked known answers
// ---------------------------------------------------------------------------

test "one tenth is the same double and float whatever else is true of them" {
    nativeReady();
    // 1/10 has no binary expansion, so both widths round. The nearest double to
    // 1/10 has significand 0x9999999999999 and exponent 3 less than the bias,
    // giving 0x3FB999999999999A; the nearest float has significand 0xCCCCCD and
    // exponent 126, giving 0x3DCCCCCD. Neither is the decimal 0.1, which is the
    // whole reason this library exists.
    try std.testing.expectEqual(@as(u64, 0x3FB999999999999A), @as(u64, @bitCast(try fast_float.parse64Exact("0.1"))));
    try std.testing.expectEqual(@as(u32, 0x3DCCCCCD), @as(u32, @bitCast(try fast_float.parse32Exact("0.1"))));

    // The sign is the only difference, and it is in the pattern.
    try std.testing.expectEqual(@as(u64, 0xBFB999999999999A), @as(u64, @bitCast(try fast_float.parse64Exact("-0.1"))));
    try std.testing.expectEqual(@as(u32, 0xBDCCCCCD), @as(u32, @bitCast(try fast_float.parse32Exact("-0.1"))));
}

test "a halfway decimal rounds to even, and the next decimal up does not" {
    nativeReady();
    // The two doubles bracketing 1.0 are 1.0 and 1 + 2^-52. Their exact
    // midpoint is 1 + 2^-53, whose exact decimal expansion has 53 fractional
    // digits and terminates. At a tie, round-to-nearest-ties-to-even picks the
    // significand with an even last bit: 1.0 has significand 0, so the tie goes
    // down to 0x3FF0000000000000.
    const midpoint = "1.00000000000000011102230246251565404236316680908203125";
    try std.testing.expectEqual(@as(u64, 0x3FF0000000000000), @as(u64, @bitCast(try fast_float.parse64Exact(midpoint))));

    // One unit in the last place above that midpoint is not a tie, and rounds
    // up. The extra digit is at the 10^-54 place, far below the double's own
    // resolution, which is what makes the comparison about the tie rule and not
    // about how many digits were written.
    const above = "1.00000000000000011102230246251565404236316680908203126";
    try std.testing.expectEqual(@as(u64, 0x3FF0000000000001), @as(u64, @bitCast(try fast_float.parse64Exact(above))));

    // One unit below the midpoint: below the tie, so it rounds down to 1.0 as
    // well. Both directions of a tie land on the even significand, which is the
    // property being pinned.
    const below = "1.00000000000000011102230246251565404236316680908203124";
    try std.testing.expectEqual(@as(u64, 0x3FF0000000000000), @as(u64, @bitCast(try fast_float.parse64Exact(below))));

    // The same at float width, where the ulp above 1.0 is 2^-23 and the
    // midpoint is 1 + 2^-24, exact in 24 fractional digits.
    try std.testing.expectEqual(@as(u32, 0x3F800000), @as(u32, @bitCast(try fast_float.parse32Exact("1.000000059604644775390625"))));
    try std.testing.expectEqual(@as(u32, 0x3F800001), @as(u32, @bitCast(try fast_float.parse32Exact("1.000000059604644775390626"))));

    // The tie rule is upstream's own arithmetic rather than the host FPU's
    // rounding mode: `from_chars_float_advanced` reads the mode only to decide
    // whether its fast path is valid (`parse_number.h:78-80`, consulted once at
    // `:216`) and the digits above have to come out the same way whatever that
    // mode is.
}

test "more digits than the significand can hold change the answer only when they should" {
    nativeReady();
    // 2^53 is the last integer a double holds exactly; the gap above it is 2, so
    // 2^53 + 1 is not representable and rounds back down to 2^53.
    // 9007199254740995 is 2^53 + 3, which sits exactly halfway between the
    // representable 2^53 + 2 and 2^53 + 4, so it ties to even and becomes
    // 2^53 + 4 — its significand is even; 2^53 + 2 has an odd significand.
    try std.testing.expectEqual(@as(u64, 0x4340000000000000), @as(u64, @bitCast(try fast_float.parse64Exact("9007199254740992"))));
    try std.testing.expectEqual(@as(u64, 0x4340000000000000), @as(u64, @bitCast(try fast_float.parse64Exact("9007199254740993"))));
    try std.testing.expectEqual(@as(u64, 0x4340000000000001), @as(u64, @bitCast(try fast_float.parse64Exact("9007199254740994"))));
    try std.testing.expectEqual(@as(u64, 0x4340000000000002), @as(u64, @bitCast(try fast_float.parse64Exact("9007199254740995"))));
    try std.testing.expectEqual(@as(u64, 0x4340000000000002), @as(u64, @bitCast(try fast_float.parse64Exact("9007199254740996"))));

    // 2^24 is the last integer a float holds exactly, and 2^24 + 1 rounds back
    // to it while 2^24 + 2 is representable.
    try std.testing.expectEqual(@as(u32, 0x4B800000), @as(u32, @bitCast(try fast_float.parse32Exact("16777216"))));
    try std.testing.expectEqual(@as(u32, 0x4B800000), @as(u32, @bitCast(try fast_float.parse32Exact("16777217"))));
    try std.testing.expectEqual(@as(u32, 0x4B800001), @as(u32, @bitCast(try fast_float.parse32Exact("16777218"))));

    // 2^64 is exact in a double and needs the full significand, which is the
    // case a parser that truncated at 19 digits would get wrong.
    try std.testing.expectEqual(@as(u64, 0x43F0000000000000), @as(u64, @bitCast(try fast_float.parse64Exact("18446744073709551616"))));
    // ...and 2^64 + 1 is not, and rounds back down.
    try std.testing.expectEqual(@as(u64, 0x43F0000000000000), @as(u64, @bitCast(try fast_float.parse64Exact("18446744073709551617"))));
}

test "the largest finite value is in range and the next decimal out is not" {
    nativeReady();
    // The largest finite double is (2^53 - 1) * 2^971, and the shortest decimal
    // that still rounds to it is 1.7976931348623157e308. It is in range, so the
    // typed surface answers with a value.
    const largest = try fast_float.parse64Exact("1.7976931348623157e308");
    try std.testing.expectEqual(@as(u64, 0x7FEFFFFFFFFFFFFF), @as(u64, @bitCast(largest)));

    // The next decimal up, 1.7976931348623159e308, is past the midpoint between
    // the largest finite value and the overflow threshold, so it rounds to
    // infinity. That is out of range: the typed surface says so rather than
    // handing back an infinity the caller did not write.
    try std.testing.expectError(error.ResultOutOfRange, fast_float.parse64("1.7976931348623159e308"));
    // ...and "1.8e308" is further out and lands in the same place.
    try std.testing.expectError(error.ResultOutOfRange, fast_float.parse64("1.8e308"));

    // At float width the same boundary: 3.4028234663852886e38 is the largest
    // finite float and in range, while 3.5e38 is past the midpoint above it.
    const largest32 = try fast_float.parse32Exact("3.4028234663852886e38");
    try std.testing.expectEqual(@as(u32, 0x7F7FFFFF), @as(u32, @bitCast(largest32)));
    try std.testing.expectError(error.ResultOutOfRange, fast_float.parse32("3.5e38"));

    // Just below the float overflow threshold is still in range even though the
    // decimal is larger than the largest finite float: 3.4028235677973366e38
    // sits between that value and the midpoint above it, so it rounds back down
    // to the largest finite float and is a success. "Out of range" here means
    // "rounded to infinity", not "the decimal exceeds the largest finite value".
    const just_below = try fast_float.parse32Exact("3.4028235677973366e38");
    try std.testing.expectEqual(@as(u32, 0x7F7FFFFF), @as(u32, @bitCast(just_below)));
}

test "the smallest subnormal is in range and half of it is not" {
    nativeReady();
    // The smallest positive subnormal double is 2^-1074, and its shortest
    // decimal is 4.9406564584124654e-324. It is representable, so it is a
    // success with a nonzero value.
    const min_subnormal = try fast_float.parse64Exact("4.9406564584124654e-324");
    try std.testing.expectEqual(@as(u64, 0x0000000000000001), @as(u64, @bitCast(min_subnormal)));

    // Exactly half of it is 2^-1075, which is not representable and not greater
    // than half, so it ties to even and becomes zero. Zero is not the number
    // that was written, so this is out of range and the typed surface says so.
    try std.testing.expectError(error.ResultOutOfRange, fast_float.parse64("2.4703282292062327e-324"));

    // One decimal above that tie is greater than half, so it rounds up to the
    // smallest subnormal and is a success again. Two adjacent decimals, 17
    // digits each, differing in the answer.
    const above_tie = try fast_float.parse64Exact("2.4703282292062328e-324");
    try std.testing.expectEqual(@as(u64, 0x0000000000000001), @as(u64, @bitCast(above_tie)));

    // At float width the same boundary: 1.4012984643248171e-45 is the smallest
    // positive subnormal float and is in range.
    const min_subnormal32 = try fast_float.parse32Exact("1.4012984643248171e-45");
    try std.testing.expectEqual(@as(u32, 0x00000001), @as(u32, @bitCast(min_subnormal32)));

    // And the decimal just above half of it rounds up to that subnormal. This
    // string is line 35 of `lemire-fast-float.txt`, whose recorded pattern is
    // 0x00000001; it is in the corpus for both widths and restated here
    // because it is the float-width version of the tie above.
    const above_half32 = try fast_float.parse32Exact("7.0064923216240854e-46");
    try std.testing.expectEqual(@as(u32, 0x00000001), @as(u32, @bitCast(above_half32)));
}

test "the boundary between subnormal and normal is a step, not a slope" {
    nativeReady();
    // The largest subnormal double is (2^52 - 1) * 2^-1074 and the smallest
    // normal is 2^52 * 2^-1074, one unit apart at that exponent. Four
    // seventeen-digit decimals, the two either side of the boundary: the
    // subnormal side is still a subnormal and the normal side is the smallest
    // normal, with no third value between them for a caller to land in.
    try std.testing.expectEqual(@as(u64, 0x000FFFFFFFFFFFFF), @as(u64, @bitCast(try fast_float.parse64Exact("2.2250738585072009e-308"))));
    try std.testing.expectEqual(@as(u64, 0x000FFFFFFFFFFFFF), @as(u64, @bitCast(try fast_float.parse64Exact("2.2250738585072011e-308"))));
    try std.testing.expectEqual(@as(u64, 0x0010000000000000), @as(u64, @bitCast(try fast_float.parse64Exact("2.2250738585072012e-308"))));
    try std.testing.expectEqual(@as(u64, 0x0010000000000000), @as(u64, @bitCast(try fast_float.parse64Exact("2.2250738585072014e-308"))));

    // At float width: the largest subnormal float is (2^23 - 1) * 2^-149 and the
    // smallest normal float is 2^-126.
    try std.testing.expectEqual(@as(u32, 0x007FFFFF), @as(u32, @bitCast(try fast_float.parse32Exact("1.1754942106924411e-38"))));
    try std.testing.expectEqual(@as(u32, 0x00800000), @as(u32, @bitCast(try fast_float.parse32Exact("1.1754943508222875e-38"))));
}

test "an out-of-range parse still consumed the whole number and stored the rounded value" {
    nativeReady();
    // The typed surface reports the condition and withholds the value, so the
    // value is read through the raw call, where it is visible. `1e681` rounds to
    // infinity at double width, and the corpus records that decimal as
    // 0x7FF0000000000000 in the binary64 column.
    var value: f64 = undefined;
    var consumed: usize = undefined;
    const overflow_text = "1e681";
    const code = fast_float.c.ff_parse_f64(overflow_text.ptr, overflow_text.ptr + overflow_text.len, &value, &consumed);
    try std.testing.expectEqual(fast_float.c.FF_STATUS_RESULT_OUT_OF_RANGE, code);
    try std.testing.expectEqual(@as(u64, 0x7FF0000000000000), @as(u64, @bitCast(value)));
    // The number was recognised in full even though it is out of range: the
    // reported pointer is past the `e`, not at the start.
    try std.testing.expectEqual(@as(usize, overflow_text.len), consumed);

    // Underflow, at float width, where 1e-46 is below half the smallest
    // subnormal and rounds to zero.
    var small: f32 = undefined;
    var small_consumed: usize = undefined;
    const underflow_text = "1e-46";
    const small_code = fast_float.c.ff_parse_f32(underflow_text.ptr, underflow_text.ptr + underflow_text.len, &small, &small_consumed);
    try std.testing.expectEqual(fast_float.c.FF_STATUS_RESULT_OUT_OF_RANGE, small_code);
    try std.testing.expectEqual(@as(u32, 0x00000000), @as(u32, @bitCast(small)));
    try std.testing.expectEqual(@as(usize, underflow_text.len), small_consumed);

    // An underflow that is not out of range: 1e-38 is a normal float, small but
    // representable, so the typed surface answers with it.
    const normal_small = try fast_float.parse32Exact("1e-38");
    try std.testing.expectEqual(@as(u32, 0x006CE3EE), @as(u32, @bitCast(normal_small)));
}

test "a parse that matches nothing leaves the caller's out-parameters unwritten" {
    nativeReady();
    // The bridge promises that `*out_value` and `*out_consumed` are not touched
    // on `invalid_argument`, because upstream returns before storing anything.
    // The sentinel values below are the caller's own, and reading them back is
    // how this test can tell that nothing was written: a bridge that stored a
    // zero would show up here as a failure rather than as a passing parse.
    var value: f64 = @bitCast(@as(u64, 0xDEADBEEFCAFEF00D));
    var consumed: usize = 0x5EED5EED;
    const code = fast_float.c.ff_parse_f64("nonsense".ptr, "nonsense".ptr + 8, &value, &consumed);
    try std.testing.expectEqual(fast_float.c.FF_STATUS_INVALID_ARGUMENT, code);
    try std.testing.expectEqual(@as(u64, 0xDEADBEEFCAFEF00D), @as(u64, @bitCast(value)));
    try std.testing.expectEqual(@as(usize, 0x5EED5EED), consumed);

    // The same promise for the empty range, which is the one a binding is most
    // likely to break: `first` and `last` are the same address, so nothing
    // forms a pointer difference over a buffer that owns no bytes, and upstream
    // compares the two before reading either (`parse_number.h:332-336`). The
    // sentinels are fresh so that this is its own observation rather than a
    // repeat of the one above.
    var empty_value: f32 = @bitCast(@as(u32, 0xFEEDFACE));
    var empty_consumed: usize = 0x0BADF00D;
    const nothing: []const u8 = "";
    const empty_code = fast_float.c.ff_parse_f32(nothing.ptr, nothing.ptr, &empty_value, &empty_consumed);
    try std.testing.expectEqual(fast_float.c.FF_STATUS_INVALID_ARGUMENT, empty_code);
    try std.testing.expectEqual(@as(u32, 0xFEEDFACE), @as(u32, @bitCast(empty_value)));
    try std.testing.expectEqual(@as(usize, 0x0BADF00D), empty_consumed);
}

// ---------------------------------------------------------------------------
// What the format accepts and refuses
// ---------------------------------------------------------------------------

test "a prefix of the buffer is a parse, and the whole buffer is a stricter one" {
    nativeReady();
    // `from_chars` consumes what it recognised and stops, which is the contract
    // `parse32` and `parse64` report. The number here is "1.5" and the rest is
    // not part of it.
    const prefixed = try fast_float.parse64("1.5 seconds");
    try std.testing.expectEqual(@as(u64, 0x3FF8000000000000), @as(u64, @bitCast(prefixed.value)));
    try std.testing.expectEqual(@as(usize, 3), prefixed.consumed);

    // `parse64Exact` adds one condition, and only that one: the buffer held more
    // than the number. It is not a different parse, so the refusal is the
    // format's `invalid_argument` and not a separate error of this facade's.
    try std.testing.expectError(error.InvalidArgument, fast_float.parse64Exact("1.5 seconds"));
    // ...and on the same buffer without the tail it succeeds.
    try std.testing.expectEqual(@as(u64, 0x3FF8000000000000), @as(u64, @bitCast(try fast_float.parse64Exact("1.5"))));

    // At float width, where the value differs and so does the consumed count.
    const prefixed32 = try fast_float.parse32("1.5s");
    try std.testing.expectEqual(@as(u32, 0x3FC00000), @as(u32, @bitCast(prefixed32.value)));
    try std.testing.expectEqual(@as(usize, 3), prefixed32.consumed);
    try std.testing.expectError(error.InvalidArgument, fast_float.parse32Exact("1.5s"));

    // The exponent is part of the number, so the consumed count includes it and
    // the tail starts after it. `"1.5e3,"` is 1500 in five bytes.
    const with_exponent = try fast_float.parse64("1.5e3,");
    try std.testing.expectEqual(@as(u64, 0x4097700000000000), @as(u64, @bitCast(with_exponent.value)));
    try std.testing.expectEqual(@as(usize, 5), with_exponent.consumed);

    // A trailing `e` with no digits after it is not part of the number: the
    // parser stops before it and reports the number it did read.
    const dangling_exponent = try fast_float.parse64("1e");
    try std.testing.expectEqual(@as(u64, 0x3FF0000000000000), @as(u64, @bitCast(dangling_exponent.value)));
    try std.testing.expectEqual(@as(usize, 1), dangling_exponent.consumed);
}

test "the format refuses what the standard's from_chars refuses" {
    nativeReady();
    // C++17 20.19.3.(7.1) forbids a leading `+` and forbids skipping leading
    // whitespace, and this format opts into neither: `chars_format::general` is
    // `fixed | scientific` (`float_common.h:56`) and carries neither the
    // `allow_leading_plus` bit (`:57`, consulted at `ascii_number.h:354-358`)
    // nor the `skip_white_space` bit (`:58`, consulted at
    // `parse_number.h:327-331`). Each of these is `invalid_argument` at both
    // widths and through the exact entry points too.
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

    // An empty slice is the case where a binding is most likely to do pointer
    // arithmetic it should not: `first` and `last` are the same address, and
    // upstream compares them before reading either (`parse_number.h:332-336`).
    // This is the same expectation as the `""` row above, reached through an
    // explicitly empty slice rather than a string literal, which is how a caller
    // holding a buffer it has just drained arrives here.
    const empty: []const u8 = "";
    try std.testing.expectError(error.InvalidArgument, fast_float.parse64(empty));
    try std.testing.expectError(error.InvalidArgument, fast_float.parse32(empty));
}

test "infinity and not-a-number parse, and a negative zero keeps its sign" {
    nativeReady();
    // `chars_format::general` is fixed or scientific with no `no_infnan` bit, so
    // upstream's `parse_infnan` path (`parse_number.h:22-71`) accepts these. They
    // are successes, not errors, which is upstream's behaviour and the reason a
    // caller who cannot trust its input has to check before parsing.
    try std.testing.expectEqual(@as(u64, 0x7FF0000000000000), @as(u64, @bitCast(try fast_float.parse64Exact("inf"))));
    try std.testing.expectEqual(@as(u64, 0x7FF0000000000000), @as(u64, @bitCast(try fast_float.parse64Exact("INF"))));
    try std.testing.expectEqual(@as(u64, 0x7FF0000000000000), @as(u64, @bitCast(try fast_float.parse64Exact("infinity"))));
    try std.testing.expectEqual(@as(u64, 0xFFF0000000000000), @as(u64, @bitCast(try fast_float.parse64Exact("-infinity"))));
    try std.testing.expectEqual(@as(u32, 0x7F800000), @as(u32, @bitCast(try fast_float.parse32Exact("inf"))));

    // `inf` is a complete word upstream, so a longer buffer that merely starts
    // with it is a prefix parse and not a failure: `parse_infnan` advances the
    // reported pointer three bytes and stops (`parse_number.h:62`). Only when
    // the buffer is long enough does it look for the five bytes of `inity`
    // (`parse_number.h:59`), which is why `infinity` reports eight and `infin`
    // reports three.
    const truncated = try fast_float.parse64("infin");
    try std.testing.expectEqual(@as(u64, 0x7FF0000000000000), @as(u64, @bitCast(truncated.value)));
    try std.testing.expectEqual(@as(usize, 3), truncated.consumed);

    // A NaN has no single pattern, so what is pinned is that it is a NaN and
    // that the whole spelling was the number. The payload is upstream's
    // choice: `std::numeric_limits<T>::quiet_NaN()` at `parse_number.h:40-41`.
    // The exact entry points hand back the value alone, so the consumed count
    // is read from the prefix entry point, which is the one that reports it.
    const nan64 = try fast_float.parse64Exact("nan");
    try std.testing.expect(std.math.isNan(nan64));
    const nan_spelling = try fast_float.parse64("nan(ind)");
    try std.testing.expect(std.math.isNan(nan_spelling.value));
    try std.testing.expectEqual(@as(usize, 8), nan_spelling.consumed);
    const nan32 = try fast_float.parse32Exact("-nan");
    try std.testing.expect(std.math.isNan(nan32));

    // Negative zero is a distinct value from positive zero, and the sign is the
    // only thing that differs, so the two patterns are the clearest statement
    // that a parse did not normalise it away.
    try std.testing.expectEqual(@as(u64, 0x0000000000000000), @as(u64, @bitCast(try fast_float.parse64Exact("0"))));
    try std.testing.expectEqual(@as(u64, 0x8000000000000000), @as(u64, @bitCast(try fast_float.parse64Exact("-0"))));
    try std.testing.expectEqual(@as(u64, 0x8000000000000000), @as(u64, @bitCast(try fast_float.parse64Exact("-0.0"))));
    try std.testing.expectEqual(@as(u64, 0x8000000000000000), @as(u64, @bitCast(try fast_float.parse64Exact("-0e0"))));
    try std.testing.expectEqual(@as(u32, 0x80000000), @as(u32, @bitCast(try fast_float.parse32Exact("-0.0"))));

    // An underflow to zero keeps its sign too, so "-1e-400" is a negative zero
    // and not a positive one. It is out of range, so the raw call is where the
    // pattern is readable.
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
    // A leading dot is a number with an empty integer part, which this format
    // accepts; a trailing dot is a number with an empty fraction, which it also
    // accepts. Both spellings appear in the corpus, in `google-wuffs.txt` and
    // `google-double-conversion.txt` among others.
    try std.testing.expectEqual(@as(u64, 0x3FE0000000000000), @as(u64, @bitCast(try fast_float.parse64Exact(".5"))));
    try std.testing.expectEqual(@as(u64, 0x4014000000000000), @as(u64, @bitCast(try fast_float.parse64Exact("5."))));
    try std.testing.expectEqual(@as(u64, 0x40B3880000000000), @as(u64, @bitCast(try fast_float.parse64Exact("5.e3"))));

    // Upper and lower case exponents are both accepted, and so is a sign in the
    // exponent: C++17 20.19.3.(7.1) allows one there even though it forbids one
    // on the significand. `parse_number.h` consumes `e`/`E`, then an optional
    // `-` or `+`, then the digits.
    try std.testing.expectEqual(@as(u64, 0x3FF0000000000000), @as(u64, @bitCast(try fast_float.parse64Exact("1E0"))));
    try std.testing.expectEqual(@as(u64, 0x4097700000000000), @as(u64, @bitCast(try fast_float.parse64Exact("1.5e+3"))));
    try std.testing.expectEqual(@as(u64, 0x408F400000000000), @as(u64, @bitCast(try fast_float.parse64Exact("1e3"))));
    // 1e-2 is not 0.01 in binary: the nearest double to a tenth of a hundredth is
    // 0x3F847AE147AE147B, whose exact value is 0.0100000000000000002081668171...
    try std.testing.expectEqual(@as(u64, 0x3F847AE147AE147B), @as(u64, @bitCast(try fast_float.parse64Exact("1e-2"))));

    // Leading zeros are digits, not an error, in this format. The JSON and
    // JavaScript formats upstream also carries reject them; `general` does not,
    // and the corpus is full of them.
    try std.testing.expectEqual(@as(u64, 0x401C000000000000), @as(u64, @bitCast(try fast_float.parse64Exact("007"))));
    try std.testing.expectEqual(@as(u64, 0x3E7AD7F29ABCAF48), @as(u64, @bitCast(try fast_float.parse64Exact("0.0000001"))));

    // A long significand with no exponent is the case a parser that keeps only
    // the leading digits gets wrong: this decimal needs 39 digits and the double
    // that is nearest to it is 0x47D7383A69580580.
    const long = try fast_float.parse64Exact("123456789012345678901234567890123456789");
    try std.testing.expectEqual(@as(u64, 0x47D7383A69580580), @as(u64, @bitCast(long)));
}
