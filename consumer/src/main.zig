//! Example consumer for the published fast_float package.

const std = @import("std");
const fast_float = @import("fast_float");

/// Error returned when a runtime provider was not named.
const ConfigurationError = error{NoProviderConfigured};

/// Decimal input and its expected binary32 and binary64 patterns.
const Constant = struct {
    name: []const u8,
    text: []const u8,
    bits64: u64,
    bits32: u32,
};

/// Constants and their expected IEEE-754 bit patterns.
const constants = [_]Constant{
    // 0.1 rounds differently at binary32 and binary64 widths.
    .{
        .name = "one tenth",
        .text = "0.1",
        .bits64 = 0x3FB999999999999A,
        .bits32 = 0x3DCCCCCD,
    },
    // Exact at both widths; a control case.
    .{
        .name = "minus two and a half",
        .text = "-2.5",
        .bits64 = 0xC004000000000000,
        .bits32 = 0xC0200000,
    },
    // Exercises exponent scaling.
    .{
        .name = "one thousandth",
        .text = "1e-3",
        .bits64 = 0x3F50624DD2F1A9FC,
        .bits32 = 0x3A83126F,
    },
    // 1/3 rounds to different values at the two widths.
    .{
        .name = "one third",
        .text = "0.3333333333333333",
        .bits64 = 0x3FD5555555555555,
        .bits32 = 0x3EAAAAAB,
    },
    .{
        .name = "a byte's worth",
        .text = "255",
        .bits64 = 0x406FE00000000000,
        .bits32 = 0x437F0000,
    },
    // Common decimal constant with fixed rounded patterns.
    .{
        .name = "standard gravity",
        .text = "9.80665",
        .bits64 = 0x40239D013A92A305,
        .bits32 = 0x411CE80A,
    },
    // Exercises rounding a large decimal at both widths.
    .{
        .name = "Avogadro's number",
        .text = "6.02214076e23",
        .bits64 = 0x44DFE185CA57C517,
        .bits32 = 0x66FF0C2E,
    },
    // Exercises a tiny normal value at both widths.
    .{
        .name = "the Planck constant",
        .text = "6.62607015e-34",
        .bits64 = 0x390B860BDE023111,
        .bits32 = 0x085C305F,
    },
};

/// Number with a unit suffix, for prefix-parsing checks.
const measurement = "9.80665 m/s^2";

const measurement_bits64: u64 = 0x40239D013A92A305;

const measurement_suffix = " m/s^2";

pub fn main(init: std.process.Init) !void {
    if (comptime fast_float.runtime_loaded) {
        try fast_float.load(.{ .path = try providerRequest(init) });
    }

    std.debug.print("fast_float consumer ({s} build), {d} constants\n", .{
        if (fast_float.runtime_loaded) "runtime-loaded" else "linked",
        constants.len,
    });

    for (constants) |constant| {
        // Exact parsing accepts only inputs containing a number.
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

    // Prefix parsing must stop before the unit suffix.
    const scanned = try fast_float.parse64(measurement);
    const scanned_bits: u64 = @as(u64, @bitCast(scanned.value));
    if (scanned_bits != measurement_bits64) {
        std.debug.print(
            "the measurement: expected 0x{X:0>16}, parsed 0x{X:0>16}\n",
            .{ measurement_bits64, scanned_bits },
        );
        return error.MeasurementBitsMismatch;
    }
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

    // Exact parsing must reject the trailing unit.
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

    // `from_chars` rejects a leading plus.
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

fn noProvider() ConfigurationError {
    std.debug.print(
        "consumer: this is a runtime-loading build. Pass --provider <path>, or " ++
            "export FASTFLOAT_PROVIDER with a shared object exporting ff_parse_f32 " ++
            "and ff_parse_f64. Nothing is loaded by default and no other file is " ++
            "tried.\n",
        .{},
    );
    return error.NoProviderConfigured;
}
