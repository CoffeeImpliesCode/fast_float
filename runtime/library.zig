// SPDX-License-Identifier: Apache-2.0 OR MIT OR BSL-1.0
//
//! fast_float's side of the runtime loader: the names its synchronization binding
//! has, and what it requires of a provider beyond resolving its symbols.
//!
//! Everything else about the runtime route is generic. `runtime/loader.zig` is
//! the state machine and the platform layer; `runtime/generate.zig` builds the
//! dispatch from whatever the translation step actually produced;
//! `runtime/graph.zig` wires them together. This file is what makes them
//! fast_float's, and it is the file another SDK replaces.
//!
//! ## What a provider must be
//!
//! A shared object or import library exporting both entry points this fork's C
//! ABI declares, and nothing else is required:
//!
//!   * `ff_parse_f32(const char *first, const char *last, float *out_value,
//!     size_t *out_consumed) -> int` — `zig/bridge.h:103-104`, defined at
//!     `zig/bridge.cpp:44-67`;
//!   * `ff_parse_f64(const char *first, const char *last, double *out_value,
//!     size_t *out_consumed) -> int` — `zig/bridge.h:112-113`, defined at
//!     `zig/bridge.cpp:69-82`.
//!
//! That is the whole externally linked ABI of the artifact this package
//! installs (`build_support/graph.zig:bridge_abi_symbols`), so it is also the
//! whole of the generated table: two fields, both functions, no data symbol, and
//! therefore no `NAMEAddr()` accessor and nothing to keep live as an address.
//!
//! There is deliberately no upstream version entry point to ask for a number
//! from. `from_chars` is a C++ template (`include/fast_float/fast_float.h:33-37`)
//! and upstream ships no C ABI and no version symbol at all — the version macro
//! `FASTFLOAT_VERSION_MAJOR/MINOR/PATCH` (`include/fast_float/float_common.h:19-21`)
//! is a header-time constant that is compiled *into* the bridge and cannot be
//! read back out of a shared object. So a provider cannot be asked which
//! upstream release it is, and nothing below pretends otherwise.
//!
//! ## The ABI boundary, stated honestly
//!
//! The boundary is the C ABI this fork declares, and it is narrow. What a
//! provider has to match is:
//!
//!   * **The scalar widths of the six parameters and the return.** Two pointers,
//!     one pointer to the width's own scalar type, one pointer to `size_t`, and
//!     an `int` status. `float` is 32-bit and `double` is 64-bit on every ABI
//!     this SDK builds for, and `size_t` is the platform's pointer width (64-bit
//!     on x86_64, aarch64 and riscv64, 32-bit on wasm32). The one that could
//!     actually differ between two builds of the same host is `size_t`, which is
//!     why the load-time checks below insist on a *byte count coming back
//!     through that pointer* rather than on any value.
//!   * **The status values**, which are `0`, `1` and `2` and are pinned by
//!     `_Static_assert` in `zig/bridge.h:80-84`, checked by the C++ compiler on
//!     every target that builds the bridge. They are this fork's spelling
//!     (`bridge.h:58-68`), not upstream's: upstream has no status enum because it
//!     has no C ABI.
//!   * **The out-parameter convention**, which is the part that is easy to get
//!     wrong and is therefore the part the checks exercise: on `FF_STATUS_OK` and
//!     on `FF_STATUS_RESULT_OUT_OF_RANGE` both out-parameters are written, and on
//!     `FF_STATUS_INVALID_ARGUMENT` neither is (`bridge.h:19-27`,
//!     `bridge.cpp:54-66`).
//!   * **The rounding behaviour**, which is *not* a provider-compatibility
//!     requirement and is deliberately not checked at load. Upstream's rounding
//!     is exact and round-to-nearest-ties-to-even
//!     (`include/fast_float/fast_float.h:12-15`), independent of the FPU rounding
//!     mode (`parse_number.h:78-80`, consulted once at `:216`), and every
//!     correctly-rounded implementation produces the same bit pattern for the
//!     same decimal. The load-time checks therefore use decimals that are
//!     *exactly* representable at the width being checked, so nothing they assert
//!     can depend on which of upstream's several exact algorithms the provider
//!     was compiled to select.
//!   * **No allocator, and no global state.** Upstream states that it "does not
//!     throw and does not allocate memory" (`fast_float.h:22-23`), the bridge
//!     adds none, and both entry points are reentrant: two threads may call them
//!     concurrently on different buffers with no lock. A provider that allocates
//!     would not break this ABI, but it would be a different library from this
//!     one, and nothing in this package links or needs a C++ runtime, a locale
//!     or a threading library to satisfy it.
//!
//! ## What is checked at load time, and what is not
//!
//! Resolving a symbol and translating a header are the boundary. They are not
//! proof that a provider is compatible. Three calls are made after every symbol
//! resolved and before anything is published, and all three are on the ABI's own
//! example numbers:
//!
//!   * `ff_parse_f64` on `"1.5"` must answer `FF_STATUS_OK`, store `1.5` — whose
//!     binary64 pattern is `0x3FF8000000000000` — and report `3` bytes consumed.
//!   * `ff_parse_f32` on `"1.5"` must answer `FF_STATUS_OK`, store `1.5` — whose
//!     binary32 pattern is `0x3FC00000` — and report `3` bytes consumed. This is
//!     the check that proves the `float` overload is present and is not the
//!     `double` one: a provider exporting a mismatched pair would either be
//!     missing the symbol or would store through the wrong width.
//!   * `ff_parse_f64` on `"1e3"` must answer `FF_STATUS_OK`, store `1000.0`
//!     (`0x408F400000000000`) and report `3` bytes consumed, so the exponent is
//!     inside the number. That third check is what makes the first two's byte
//!     counts meaningful rather than coincidental: it shows the count is a
//!     pointer difference and not a fixed constant.
//!
//! Together those three say the exported symbol is callable with this header's
//! calling convention, at both scalar widths, with this header's status values
//! and this header's out-parameter convention. They are checks that the entry
//! points *behave*. They are not, and cannot be, a check of anything the caller
//! and the provider must have compiled from the same header — which is the only
//! thing that can rule out a provider built against a different `zig/bridge.h`.
const rt = @import("rt");

/// The synchronization this loader calls, bound by exact name.
///
/// The names below are `runtime/sync.h` compiled with
/// `RT_SYNC_PREFIX=fast_float_rt`, which is what `runtime/graph.zig` passes. Two
/// spellings of that prefix have to agree: this file names the symbols, and
/// graph.zig defines the macro. A build where they disagree does not link, and
/// that is the whole error report: there is no runtime path that could hide it.
///
/// The core in `runtime/loader.zig` never names a symbol of its own, which is
/// what lets two SDKs, or two configurations of one SDK, hold their own loader
/// state in one process without sharing any of it.
pub const Sync = struct {
    extern fn fast_float_rt_lock() void;
    extern fn fast_float_rt_unlock() void;
    extern fn fast_float_rt_wait() void;
    extern fn fast_float_rt_broadcast() void;
    // `unsigned long long`. Declared as u64, which is the same type in every
    // ABI this SDK targets: 64-bit on x86_64, aarch64, riscv64 and wasm32.
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

/// The decimal every binary64 check below parses.
///
/// 1.5 is 3/2, which a binary format with a leading one bit and a fractional
/// significand holds exactly: the significand is `1.5 - 1 = 0.5`, one bit, and
/// the exponent is 0. So its exact binary64 pattern is the sign and exponent of
/// one with a single significand bit set — `0x3FF8000000000000` — and no
/// rounding decision is involved. That is what makes it usable as an ABI check:
/// the answer cannot depend on which of upstream's exact algorithms the provider
/// compiled, or on the host's rounding mode.
const probe_text = "1.5";

/// The exact binary64 pattern of 1.5, and the exact binary32 one.
const probe_bits64: u64 = 0x3FF8000000000000;
const probe_bits32: u32 = 0x3FC00000;

/// The exact binary64 pattern of 1000.0.
///
/// 1000 = 125 * 2^3, so it needs seven significand bits at exponent 1023 + 3,
/// which every binary format in question has. Its pattern is 0x408F400000000000.
const power_text = "1e3";
const power_bits64: u64 = 0x408F400000000000;

/// The loader's configuration for this SDK, given the dispatch that owns the
/// table.
///
/// `dispatch` is the generated module, passed as a type by the dispatch itself
/// so that this file never has to import it. The direction is one-way on
/// purpose: the descriptor knows what the loader needs, the dispatch knows what
/// the header said, and neither imports the other.
pub fn Config(comptime dispatch: type) type {
    return struct {
        /// Named in the pre-load panic, so the message says which library was
        /// reached for before it was loaded.
        pub const library_name = "fast_float";

        /// The table the generated dispatch declares, and the symbols it needs
        /// to fill it. Both come from the translated header, not from this file.
        pub const table = dispatch.Table;
        pub const symbols = dispatch.symbols;
        pub const optional_symbols = dispatch.optional_symbols;

        /// The project's namespaced synchronization binding.
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

        /// The library-specific check, run after every symbol resolved and before
        /// anything is published.
        ///
        /// Every call below writes into a local of this function and reads a
        /// stack-allocated decimal. Nothing here allocates, takes a lock, touches
        /// a process global or depends on the provider having been initialized
        /// with anything in particular: upstream's entry points are pure functions
        /// of the byte range they are handed
        /// (`include/fast_float/fast_float.h:22-23`), so a call is safe as soon
        /// as the address resolved.
        ///
        /// A failure message is a string literal. There is no number in any of
        /// them to render, so nothing is formatted, nothing is buffered and there
        /// is no allocation whose lifetime this file would have to argue about.
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