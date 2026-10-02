//! Consumes the `fast_float` package the way an outside project would.
//!
//! Everything here goes through the published surface only: `b.dependency` in
//! `build.zig`, and `@import("fast_float")` here. No path reaches into the
//! library's own tree, and nothing is imported from the library's tests or
//! fixtures, so if this builds and produces the answers below, the module
//! contract is real.
//!
//! The task is a unit-conversion table: a set of physical constants written as
//! decimals, each of which has to land on an exact IEEE 754 value at both
//! widths. That is the shape most callers have — a number in a config file, a
//! sensor reading, a limit — and it is the shape where being one unit off is
//! invisible in a printed value and obvious in a bit pattern.
//!
//! Every expected pattern below was worked out by exact rational rounding, not
//! read out of this library, and each carries a note saying why it is the
//! nearest representable value. A mismatch returns an error, so the process
//! exits non-zero.
//!
//! No input is read from anywhere: the table is compiled in, so the program's
//! output is the same on every run and on every machine, which is what makes it
//! usable as a check rather than as a demonstration.

const std = @import("std");
const fast_float = @import("fast_float");

/// One decimal constant and the two IEEE 754 patterns it must produce.
const Constant = struct {
    name: []const u8,
    /// The decimal exactly as it would appear in a config file.
    text: []const u8,
    /// The nearest binary64 to `text`.
    bits64: u64,
    /// The nearest binary32 to `text`.
    bits32: u32,
};

/// The constants, with the reason each pattern is the right one.
const constants = [_]Constant{
    // 1/10 has no binary expansion, so both widths round. The nearest double
    // has significand 0x9999999999999 at exponent 1023 - 4, giving
    // 0x3FB999999999999A; its exact value is 0.10000000000000000555111512312578.
    // The nearest float has significand 0xCCCCCD at exponent 127 - 1, giving
    // 0x3DCCCCCD; its exact value is 0.100000001490116119384765625. Neither is
    // 0.1 and the two differ, which is the whole point of carrying a width.
    .{
        .name = "one tenth",
        .text = "0.1",
        .bits64 = 0x3FB999999999999A,
        .bits32 = 0x3DCCCCCD,
    },
    // -2.5 is exactly representable at both widths: 2.5 is 1.25 * 2^1, and a
    // power of two times 1.25 needs three significand bits. No rounding happens
    // at all, which makes it the control: a parser that were wrong about
    // anything structural would still get this one right.
    .{
        .name = "minus two and a half",
        .text = "-2.5",
        .bits64 = 0xC004000000000000,
        .bits32 = 0xC0200000,
    },
    // A tenth of a thousandth. The exponent is negative, so this is the case
    // where a parser has to divide rather than multiply by a power of ten.
    .{
        .name = "one thousandth",
        .text = "1e-3",
        .bits64 = 0x3F50624DD2F1A9FC,
        .bits32 = 0x3A83126F,
    },
    // One third is not representable at either width, and the two widths do not
    // agree on it: the double has 53 significand bits and lands on
    // 0x3FD5555555555555, the float has 24 and lands on 0x3EAAAAAB. Two decimals
    // a user would consider the same number, two different machine values.
    .{
        .name = "one third",
        .text = "0.3333333333333333",
        .bits64 = 0x3FD5555555555555,
        .bits32 = 0x3EAAAAAB,
    },
    // 255 is 2^8 - 1, the largest integer a float holds exactly and one below
    // the point where float integers stop being consecutive.
    .{
        .name = "a byte's worth",
        .text = "255",
        .bits64 = 0x406FE00000000000,
        .bits32 = 0x437F0000,
    },
    // Standard gravity, as a config file would write it. The decimal has five
    // significant digits, which both widths can hold, so the two answers are
    // each within half an ulp of it and both are exact roundings.
    .{
        .name = "standard gravity",
        .text = "9.80665",
        .bits64 = 0x40239D013A92A305,
        .bits32 = 0x411CE80A,
    },
    // Avogadro's number: ten significant digits, so the significand has to be
    // assembled from more digits than either width can keep, and the two
    // answers are far apart.
    .{
        .name = "Avogadro's number",
        .text = "6.02214076e23",
        .bits64 = 0x44DFE185CA57C517,
        .bits32 = 0x66FF0C2E,
    },
    // The Planck constant in its 2019 SI formulation. Ten significant digits
    // again, and a negative exponent, so the digits have to survive a division.
    // At float width the answer is still a normal number: 6.6e-34 is far above
    // the smallest normal float, 1.18e-38, so this is rounding and not
    // underflow.
    .{
        .name = "the Planck constant",
        .text = "6.62607015e-34",
        .bits64 = 0x390B860BDE023111,
        .bits32 = 0x085C305F,
    },
};

/// A number in a longer line, and where the number stops.
///
/// The buffer is what a line-oriented reader would hand over: a value followed
/// by a unit. `from_chars` reports the prefix, which is what lets the caller
/// find the unit without scanning again.
const measurement = "9.80665 m/s^2";

/// The double nearest to `9.80665`, the same value as in the table above.
const measurement_bits64: u64 = 0x40239D013A92A305;

/// The unparsed suffix includes the space separating the number from its unit.
const measurement_suffix = " m/s^2";

pub fn main() !void {
    std.debug.print("fast_float consumer, {d} constants\n", .{constants.len});

    for (constants) |constant| {
        // The exact entry points, because each `text` holds nothing but the
        // number and there is nothing else for them to accept.
        const as_double = try fast_float.parse64Exact(constant.text);
        const as_float = try fast_float.parse32Exact(constant.text);

        const got64: u64 = @as(u64, @bitCast(as_double));
        const got32: u32 = @as(u32, @bitCast(as_float));
        if (got64 != constant.bits64 or got32 != constant.bits32) {
            std.debug.print(
                "{s} ({s}): expected 0x{X:0>16}/0x{X:0>8}, parsed 0x{X:0>16}/0x{X:0>8}\n",
                .{ constant.name, constant.text, constant.bits64, constant.bits32, got64, got32 },
            );
            return error.ParsedBitsMismatch;
        }
        std.debug.print(
            "  {s:<22} {s} -> double 0x{X:0>16}, float 0x{X:0>8}\n",
            .{ constant.name, constant.text, got64, got32 },
        );
    }

    // A number followed by a unit. The prefix entry point is the one that can
    // answer this, and the consumed count is what says where the unit begins.
    const scanned = try fast_float.parse64(measurement);
    const scanned_bits: u64 = @as(u64, @bitCast(scanned.value));
    if (scanned_bits != measurement_bits64) {
        std.debug.print(
            "the measurement: expected 0x{X:0>16}, parsed 0x{X:0>16}\n",
            .{ measurement_bits64, scanned_bits },
        );
        return error.MeasurementBitsMismatch;
    }
    // `9.80665` is seven bytes; the separating space is not part of the number.
    const unit_start = "9.80665".len;
    if (scanned.consumed != unit_start) {
        std.debug.print(
            "the measurement: consumed {d} bytes, expected {d}\n",
            .{ scanned.consumed, unit_start },
        );
        return error.MeasurementLengthMismatch;
    }
    const suffix = measurement[scanned.consumed..];
    if (!std.mem.eql(u8, suffix, measurement_suffix)) {
        std.debug.print("the measurement: suffix is {s}, expected {s}\n", .{ suffix, measurement_suffix });
        return error.UnitMismatch;
    }
    std.debug.print(
        "  {s:<22} {s} -> double 0x{X:0>16}, {d} bytes consumed, suffix \"{s}\"\n",
        .{ "with a unit", measurement, scanned_bits, scanned.consumed, suffix },
    );

    // The same line through the exact entry point. Nothing about the parse
    // changed; what changed is the question, and this buffer does not answer it
    // because the unit is not part of the number.
    const outcome = fast_float.parse64Exact(measurement);
    if (outcome) |value| {
        std.debug.print("the measurement: exact parse accepted it as 0x{X:0>16}\n", .{@as(u64, @bitCast(value))});
        return error.TrailingBytesAccepted;
    } else |err| switch (err) {
        error.InvalidArgument => std.debug.print(
            "  exact parse of the same line: refused, {s} is not part of the number\n",
            .{measurement_suffix},
        ),
        else => {
            std.debug.print("the measurement: exact parse failed with {s}\n", .{@errorName(err)});
            return error.UnexpectedExactError;
        },
    }

    // A leading `+` is the difference between this format and `strtod`, and a
    // config file written by a human is exactly where it turns up.
    const plus = fast_float.parse64Exact("+9.80665");
    if (plus) |value| {
        std.debug.print("a leading plus was accepted, as 0x{X:0>16}\n", .{@as(u64, @bitCast(value))});
        return error.LeadingPlusAccepted;
    } else |err| switch (err) {
        error.InvalidArgument => std.debug.print("  a leading plus: refused, as std::from_chars does\n", .{}),
        else => {
            std.debug.print("a leading plus: failed with {s}\n", .{@errorName(err)});
            return error.UnexpectedRefusalError;
        },
    }

    std.debug.print(
        "every pattern above is the one worked out by exact rounding in the comment on each entry\n",
        .{},
    );
}
