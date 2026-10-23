// SPDX-License-Identifier: Apache-2.0 OR MIT OR BSL-1.0
//
//! fast_float-specific synchronization and provider validation for runtime loading.
const rt = @import("rt");

/// Namespaced synchronization functions required by the loader.
pub const Sync = struct {
    extern fn fast_float_rt_lock() void;
    extern fn fast_float_rt_unlock() void;
    extern fn fast_float_rt_wait() void;
    extern fn fast_float_rt_broadcast() void;
    // The C ABI's `unsigned long long` is represented as `u64`.
    extern fn fast_float_rt_thread_self() u64;

    pub fn lock() void {
        fast_float_rt_lock();
    }
    pub fn unlock() void {
        fast_float_rt_unlock();
    }
    pub fn wait() void {
        fast_float_rt_wait();
    }
    pub fn broadcast() void {
        fast_float_rt_broadcast();
    }
    pub fn threadSelf() u64 {
        return fast_float_rt_thread_self();
    }
};

/// Decimal used to validate the binary64 parser.
const probe_text = "1.5";

/// Exact bit patterns for 1.5 in binary64 and binary32.
const probe_bits64: u64 = 0x3FF8000000000000;
const probe_bits32: u32 = 0x3FC00000;

/// Decimal used to validate exponent parsing and consumed length.
const power_text = "1e3";
const power_bits64: u64 = 0x408F400000000000;

/// Configuration for the generated dispatch's runtime loader.
pub fn Config(comptime dispatch: type) type {
    return struct {
        /// Name used in pre-load errors.
        pub const library_name = "fast_float";

        /// Dispatch table and provider symbol lists.
        pub const table = dispatch.Table;
        pub const symbols = dispatch.symbols;
        pub const optional_symbols = dispatch.optional_symbols;

        /// Synchronization binding used by this SDK.
        pub const sync = Sync;
        pub fn tablePtr() *table {
            return dispatch.tablePtr();
        }

        pub fn ready() *rt.Ready {
            return &dispatch.ready;
        }

        pub fn assign(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assign(index, dst, address);
        }

        pub inline fn assignOptional(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assignOptional(index, dst, address);
        }

        pub inline fn assignMissing(comptime index: usize, dst: *table) void {
            dispatch.assignMissing(index, dst);
        }

        /// Validates the resolved provider; returns a message on mismatch.
        pub fn validate(dst: *const table) ?[]const u8 {
            {
                var value: f64 = undefined;
                var consumed: usize = undefined;
                const code = dst.ff_parse_f64(probe_text.ptr, probe_text.ptr + probe_text.len, &value, &consumed);
                if (code != 0) {
                    return "ff_parse_f64 answered " ++
                        "a status that is not FF_STATUS_OK (0) for \"1.5\", so this " ++
                        "provider is not built from this fork's bridge header: its " ++
                        "status values or its out-parameter convention do not match";
                }
                if (@as(u64, @bitCast(value)) != probe_bits64) {
                    return "ff_parse_f64 stored a value for \"1.5\" that is not the " ++
                        "nearest binary64 to 3/2, so the resolved entry point is not " ++
                        "the double-width one this header declares";
                }
                if (consumed != probe_text.len) {
                    return "ff_parse_f64 reported the wrong number of consumed bytes " ++
                        "for \"1.5\", so the size_t out-parameter does not round-trip " ++
                        "across this ABI";
                }
            }

            {
                var value: f32 = undefined;
                var consumed: usize = undefined;
                const code = dst.ff_parse_f32(probe_text.ptr, probe_text.ptr + probe_text.len, &value, &consumed);
                if (code != 0) {
                    return "ff_parse_f32 answered a status that is not FF_STATUS_OK " ++
                        "(0) for \"1.5\", so this provider is not built from this " ++
                        "fork's bridge header";
                }
                if (@as(u32, @bitCast(value)) != probe_bits32) {
                    return "ff_parse_f32 stored a value for \"1.5\" that is not the " ++
                        "nearest binary32 to 3/2, so the resolved entry point is not " ++
                        "the float-width one this header declares";
                }
                if (consumed != probe_text.len) {
                    return "ff_parse_f32 reported the wrong number of consumed bytes " ++
                        "for \"1.5\", so the size_t out-parameter does not round-trip " ++
                        "across this ABI";
                }
            }

            {
                var value: f64 = undefined;
                var consumed: usize = undefined;
                const code = dst.ff_parse_f64(power_text.ptr, power_text.ptr + power_text.len, &value, &consumed);
                if (code != 0 or @as(u64, @bitCast(value)) != power_bits64 or consumed != power_text.len) {
                    return "ff_parse_f64 did not parse \"1e3\" as 1000.0 in three " ++
                        "bytes, so the reported end-of-number is not a pointer " ++
                        "difference into the buffer this call was handed";
                }
            }

            return null;
        }
    };
}
