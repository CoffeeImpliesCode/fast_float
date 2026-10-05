# fast_float — the C++ correctly-rounded parser, built and wrapped in Zig

This package compiles fast_float **8.3.0** — upstream's own header-only C++,
byte for byte, from the `include/` directory in this repository — into a C ABI
archive with real external linkage — static by default, shared on request — and
publishes a small, allocation-free Zig facade over the translated bridge header.
No part of the parser is reimplemented, nothing is downloaded at build time, and
there is no dependency of any kind in `build.zig.zon`.

Upstream: `https://github.com/fastfloat/fast_float`, tag `v8.3.0`, commit
`b0ab987b3dfdde13fa1915f65ef2a5c068d9208c`. Provenance, licences and the
integrity record are in [`UPSTREAM.md`](UPSTREAM.md), [`NOTICE.md`](NOTICE.md)
and [`UPSTREAM.sha256`](UPSTREAM.sha256).

This file documents the **Zig interface**. The repository's front door is
[`README.md`](README.md), which carries the native-source deviations, the
native-build deviations and their dated history, the current build/run/test
matrix and the consumption routes; upstream's own README is preserved beside it
at [`README.upstream.md`](README.upstream.md), byte for byte. The fork's own
files are licensed `Apache-2.0 OR MIT OR BSL-1.0` on the owner's
authorization — [`FORK-LICENSE.md`](FORK-LICENSE.md) — and the corpus below is
under its own single Apache-2.0 grant.

## Requirements

Zig **0.16.0** — the real compiler, not the bare `zig` on `PATH`, which in
this workspace is a version dispatcher; through the dispatcher the command is
`zig 0.16.0 build`. That is the same line `build.zig.zon` states as
`minimum_zig_version`, so a package manager that enforces the floor enforces
this compiler. Plus a C++ compiler and libc++/libstdc++, both of which
Zig supplies. Nothing is fetched.

The C++ standard is pinned to `-std=c++17` in `build_support/graph.zig`, and
it is pinned rather than preferred; the two upstream thresholds that make a
different standard mean different code are named under "Build modes" below.
A dependent that reaches the library through `dep.module("fast_float")` gets
the compiled archive, libc and the C++ runtime linked with it. A C or C++
consumer of the installed tree links the archive itself; `zig build install`
also generates `lib/pkgconfig/fast_float.pc`, whose `Libs.private` names the C++
runtime for a static delivery and is empty for a shared one that has it linked
in. The installed-surface check in `.github/workflows/verify.yml` builds against
the installed headers and the archive directly, not through that file.

## Commands

| Command | What it does |
|---|---|
| `zig build` | compiles upstream's headers through the C++ bridge, installs the C ABI archive in the default static linkage, `fast_float_bridge.h`, the whole upstream header tree, the generated `fast_float.pc` and the licence records into `zig-out/`, and compiles the example |
| `zig build test` | runs `tests.zig` for the selected target: the nine-file known-answer corpus at both widths, plus the hand-worked cases |
| `zig build test -Doptimize=ReleaseSafe` | the same tests with the optimizer on |
| `zig build smoke` | runs `smoke.zig`, which checks its own answers and exits non-zero on any mismatch |
| `zig build check -Dtarget=<triple>` | compiles the C++ bridge, the translated header, the facade, the tests and the example for one target, running nothing |
| `zig build check` | the same for all six required targets in one graph |
| `cd consumer && zig build run` | the same library, consumed by a package that did not write it |
| `zig build -Dlinkage=static` | the default, stated explicitly: a static `libfast_float.a`. This is what the package has always produced |
| `zig build -Dlinkage=dynamic` | a real shared object with external linkage — `libfast_float.so.0.1.0` with soname `libfast_float.so.0` beside it on ELF, `libfast_float.0.dylib` on Darwin, `fast_float.dll` plus `fast_float.lib` on windows-gnu. Same tree, same bridge, same C ABI. **One refused combination:** `wasm32-wasi` has no dynamic linker, so the build fails for it rather than substituting an archive |
| `zig build -Druntime` | default off. Builds the same facade over a dispatch that resolves the bridge's entry points at run time through one table an explicit `load(source)` fills. The artifact is still built and installed — it is what a provider is |
| `zig build smoke -Druntime -- --provider <path>` | runs the smoke example against a named provider; `--provider` or `FASTFLOAT_PROVIDER` both work, and nothing is loaded by default |

Add `-j8 --summary all`, and `--cache-dir <dir>`, as your workspace does.

The six cross-target checks, one command each, no target skipped and none
pre-judged:

```
zig build check -Dtarget=x86_64-linux-gnu  -j8 --summary all --cache-dir /home/tmp/gertullj/foundation-libs-cache/fast_float/x86_64-linux-gnu
zig build check -Dtarget=aarch64-linux-gnu -j8 --summary all --cache-dir /home/tmp/gertullj/foundation-libs-cache/fast_float/aarch64-linux-gnu
zig build check -Dtarget=aarch64-macos-none -j8 --summary all --cache-dir /home/tmp/gertullj/foundation-libs-cache/fast_float/aarch64-macos-none
zig build check -Dtarget=x86_64-windows-gnu -j8 --summary all --cache-dir /home/tmp/gertullj/foundation-libs-cache/fast_float/x86_64-windows-gnu
zig build check -Dtarget=riscv64-linux-gnu -j8 --summary all --cache-dir /home/tmp/gertullj/foundation-libs-cache/fast_float/riscv64-linux-gnu
zig build check -Dtarget=wasm32-wasi -j8 --summary all --cache-dir /home/tmp/gertullj/foundation-libs-cache/fast_float/wasm32-wasi
```

`zig build check` with no `-Dtarget` walks all six in one graph. Compiled, never
executed: no emulator and no cross linker is assumed, so a green target is
compile evidence and nothing more. **All six were compiled and all six passed**
on the tree as it stood on 2026-10-02 — one command each, 7/7 steps, no target
skipped and none pre-judged — and the same six are green on the current tree as
well: row `baseline-fast_float-check` of
`baselines-and-configs/20261005T014547Z-797a73f2`, 2026-10-05, exit 0,
`Build Summary: 32/32 steps succeeded`, `declared_target_count 6`, all six
triples named in the run's own step lines and `test_pass_lines: []`. That row
runs nothing. Both receipts are named in "Verification status"; neither is a
runtime result, and no row of either may be read as one.

### The full platform matrix

`zig build check` is the fast compile-only baseline over six targets. `test` is
the one that answers a different question — do the tests actually *run* there —
and it builds the same test binary for whichever target was selected and hands
it to a run step, host target included:

```
zig build test -Dtarget=x86_64-linux-gnu -j8 --summary all --cache-dir <dir>
```

How that run is carried out is the caller's decision, not this package's. A
target the host can execute runs directly; a foreign target runs under an
external executor (QEMU user mode, Wine, wasmtime) when one is installed; a
foreign target with no executor is skipped with its compile dependencies intact,
which is **build-only coverage: compiled, never executed, and never a pass**.

`cross-test.profile.sh` carries this package's settings for the
`~/.local/bin/cross-test` matrix driver: the standard `test` step, four build
jobs, a 3,600-second build deadline and a 1,800-second per-test deadline, and
no matrix and no target list of its own, so the published 53-platform
Zig 0.16 table applies unchanged and `--targets` still selects from it. The two
deadlines exist because the corpus case reads all 1,382,483 rows of the nine
selected files at both widths and overran the harness's 300-second default on
three cells of the first full sweep. They raise the deadline only: no file was
dropped, no rows sampled, and Debug was not remapped to an optimized mode. The
profile ships in `.paths` because it is configuration a consumer needs, not
prose.

```
cross-test                      # the full published matrix, settings from the profile
cross-test --list               # the same targets and the runners detected for them
cross-test --targets x86_64-linux
```

The results it reports are not one kind of fact. A target whose executor ran
the tests reports the count; a target compiled but not executed reports
build-only coverage; a target whose executor failed, or whose run exceeded the
deadline, is a failure. A successful foreign *compile* is never reported as a
passing Zig API test. The six-target `check` matrix above stays as the quick
compile-only gate either way.

## Using it

In your `build.zig.zon`:

```zig
.dependencies = .{
    .fast_float = .{ .path = "../fast_float" },
},
```

In your `build.zig`:

```zig
const dep = b.dependency("fast_float", .{ .target = target, .optimize = optimize });
exe_mod.addImport("fast_float", dep.module("fast_float"));
```

Then:

```zig
const fast_float = @import("fast_float");

// The whole buffer is the number. 0.1 has no binary expansion, so this is
// the nearest double, 0x3FB999999999999A, worked out by exact rational
// rounding rather than read out of this library.
const tenth: f64 = try fast_float.parse64Exact("0.1");

// A prefix is a successful parse: this is how a number followed by a unit is
// read. `consumed` says where the number ended, so "9.80665 m/s^2" yields
// 7 bytes consumed and the unit starts at index 7.
const scanned = try fast_float.parse64("9.80665 m/s^2");
const unit = "9.80665 m/s^2"[scanned.consumed..];
// `consumed` is the first byte that was *not* the number, so the separating
// space is inside `unit`. Trimming it is the caller's decision, and getting
// that wrong is a silent bug rather than a wrong number.

// The same question at float width.
const small: f32 = try fast_float.parse32Exact("0.1");

// The error set, when a caller has to handle refusal.
const parsed = fast_float.parse64("not a number") catch |err| switch (err) {
    error.InvalidArgument => return,   // nothing matched; no result is returned
    error.ResultOutOfRange => return,  // it matched, and rounded to inf or 0
    error.StatusNotRecognised => unreachable, // the bridge pins its own codes
};
```

`consumer/` is exactly this, in working form.

That is the whole supported route for a Zig dependent: `b.dependency` and
`dep.module("fast_float")`, with `c` bound and the archive linked for you.
`pub const c` is a supported second route into the same bridge and carries its
own obligations, named under "The C ABI" below. There is no per-target module
name and no relative-import route, so reaching into `zig/root.zig` by path is
not one of them.

## The API

Everything the facade names is read out of upstream's own declarations, and each
one's documentation comment in `zig/root.zig` cites the header and line it came
from. The scope is deliberately narrow: `fast_float::from_chars` for `float` and
`double`, in `chars_format::general`, which is the default upstream instantiates
(`include/fast_float/fast_float.h:33-37`).

What it deliberately leaves out: no allocator, no integer parsing, no
`chars_format` or `parse_options` selection, no formatting, and no
rounding-mode setting. Upstream reaches all of those through
`from_chars_advanced` and the integer overloads in the installed C++ header
tree, which is where they stay: they are templates, so there is no symbol a C
translation could name and this binding would have nothing to call.

| Operation | What it does |
|---|---|
| `parse32(bytes)` | the longest number at the start of `bytes` as an `f32`, plus `consumed` |
| `parse64(bytes)` | the same at `f64` width |
| `parse32Exact(bytes)` | `parse32` plus the requirement that the number filled the whole buffer |
| `parse64Exact(bytes)` | `parse64` plus that requirement |
| `pub const c` | the **complete** translated `bridge.h`, not a filtered view |

`Parsed32` is `{ value: f32, consumed: usize }`; `Parsed64` is the same at `f64`
width. `consumed` is upstream's `from_chars_result::ptr`
(`include/fast_float/float_common.h:80`) measured from the start of the buffer,
which is how `std::from_chars` reports it too: the number is a prefix, and
`bytes[consumed..]` is whatever followed it.

### The format, and what it refuses

`chars_format::general` is fixed or scientific notation and nothing else. All of
the following is upstream's behaviour, not this package's:

* **No leading whitespace and no leading `+`.** `" 1"`, `"\t1"` and `"+1"` are
  all `error.InvalidArgument`. Unlike this parser, `strtod` accepts leading
  whitespace and `+`. `chars_format::general` explains the difference:
  `include/fast_float/float_common.h:56` defines it as `fixed | scientific` and
  nothing else, so neither the `skip_white_space` bit (`:58`, consulted at
  `include/fast_float/parse_number.h:327-331`) nor the `allow_leading_plus` bit
  (`:57`, consulted at `include/fast_float/ascii_number.h:354-358` for a number
  and at `parse_number.h:32-36` for `inf` and `nan`) is set. A caller porting
  from `strtod` has to pre-strip.
* **A leading `-` is accepted**, including negative zero: `"-0"` is
  `0x80000000` at `f32` width, not `0x00000000`.
* **`"inf"`, `"infinity"` and `"nan"` parse successfully**, case insensitively,
  with an optional `-` and with the C++17 `nan(n-char-seq-opt)` payload
  (`include/fast_float/parse_number.h:37-67`). They are not errors. **This
  binding is therefore not a validator for untrusted text**; a caller that must
  reject non-finite input has to check the result itself, or use a different
  parser.
* **Rounding is exact, round-to-nearest, ties to even, independent of the FPU
  rounding mode** (`fast_float.h:12-15`). Upstream reads the FPU mode only to
  decide whether its fast path is valid (`parse_number.h:78-80`, consulted once
  at `:216`) and does the arithmetic itself.
* **Subnormals are produced, not flushed.** A value below the smallest normal
  but above zero rounds into the subnormal range.

### Errors, and what each one leaves behind

`Error` has exactly three members, and each is a claim about a comparison the
code actually made:

| Error | Bridge status behind it | What happened | What the **typed** call leaves behind |
|---|---|---|---|
| `InvalidArgument` | `FF_STATUS_INVALID_ARGUMENT` (`1`) from `parse32`/`parse64`; **no bridge status at all** from `parse32Exact`/`parse64Exact` | from `parse32`/`parse64`: no number matched — empty buffer, leading space or tab, leading `+`, a lone `.` or `-`. From `parse32Exact`/`parse64Exact`: a number **did** match, and it was not the whole buffer | **no result at all.** No `Parsed32`/`Parsed64` is constructed, so your own variables still hold exactly what you put there |
| `ResultOutOfRange` | `FF_STATUS_RESULT_OUT_OF_RANGE` (`2`) | a number did match and did round, but past the largest finite magnitude or below the smallest | **no result at all.** The infinity or zero upstream rounded to, and the byte count it took, existed only in the bridge's out-parameters, which this call drops — read them through `pub const c`, see below |
| `StatusNotRecognised` | none | the bridge returned a value that is not one of the three codes its own header pins | unreachable by construction; an error rather than a panic so a future bridge change is reported instead of aborting |

**The status column describes one entry point at a time; it is not a mapping on
the tag.** `parse32` and `parse64` translate the bridge's status and nothing
else. The exact pair adds a check of its own *after* a successful parse:
`parse32Exact` is `try parse32(bytes)` followed by
`if (parsed.consumed != bytes.len) return error.InvalidArgument`
(`zig/root.zig:478-482`), and `parse64Exact` is the same two lines at `:486-490`.
The bridge behind that rejection returned `FF_STATUS_OK`, and it says so in its
own source rather than only in the facade's arithmetic: `zig/bridge.cpp:62-66`
writes both out-parameters whenever `result.ec != std::errc::invalid_argument`
and then returns `classify(result.ec)`. For `"1.5x"` the parse therefore
succeeded, both out-parameters were written, and `classify` returned
`FF_STATUS_OK` — it is the *facade* that refuses the trailing tail. So
`parse32Exact("1.5x")` is `error.InvalidArgument` with no
`FF_STATUS_INVALID_ARGUMENT` anywhere behind it, and a caller cross-checking a
tag against `c.FF_STATUS_INVALID_ARGUMENT` has to establish which entry point
produced the tag first. The three constants answer "what did the bridge report";
`Error` answers "what did this facade refuse", and those are the same question
only for `parse32` and `parse64`. `Error` is not a second spelling of `ff_status`
and no `pub const` here converts one to the other.

**The typed surface withholds the value on `ResultOutOfRange` on purpose.** It
returns an error rather than a second successful result carrying an infinity or a
zero the caller did not write, and `Parsed32`/`Parsed64` are never constructed on
that path. The value is not lost — it is where the C ABI puts it, and the tag
carries none of it back, so a caller that wants the residue has to make the raw
call again rather than recover it from `error.ResultOutOfRange`.

That is the one asymmetry between the two routes, and it runs in this direction
only: a typed failure writes nothing anywhere, while a raw failure can write
both of its out-parameters.

### The C ABI, and the out-of-range value contract

`pub const c` is the whole translated `zig/bridge.h`:

```c
enum ff_status { FF_STATUS_OK = 0, FF_STATUS_INVALID_ARGUMENT = 1,
                 FF_STATUS_RESULT_OUT_OF_RANGE = 2 };
int ff_parse_f32(const char *first, const char *last, float *out_value, size_t *out_consumed);
int ff_parse_f64(const char *first, const char *last, double *out_value, size_t *out_consumed);
```

**The one asymmetry, stated exactly.** The two out-parameters are written on
different outcomes, and this is the contract a C caller has to know:

| Return | `*out_value` | `*out_consumed` |
|---|---|---|
| `FF_STATUS_OK` | written | written — bytes of `[first, last)` that were the number |
| `FF_STATUS_RESULT_OUT_OF_RANGE` | **written** — the infinity or the zero the parse rounded to | **written** — the bytes it took |
| `FF_STATUS_INVALID_ARGUMENT` | **not written** | **not written** |

The reason is upstream's, not the bridge's: `parse_number.h:288` stores through
`to_float` *before* the range test at `:290-292`, so by the time upstream reports
`result_out_of_range` the value is already in the caller's variable. The two
early exits at `parse_number.h:332-336` and `:347-350` return before `to_float`,
so on `invalid_argument` there is nothing to write and nothing to un-write.

The practical consequence: **a rejected parse is not one thing.** `"not a
number"` leaves your sentinel in place; `"1e400"` replaces it with `INFINITY` and
tells you how many bytes it read. Code that treats "non-zero return" as "out
parameters untouched" is wrong for exactly one of the two rejection paths, and
`tests.zig` and the installed C surface in `verify.yml` both pin the
distinction.

**Ownership and lifetime.** `first` and `last` are the caller's own buffer; the
pair is half-open, as upstream takes it, and neither is copied nor retained.
Nothing in the path allocates: upstream documents that it "does not throw and
does not allocate memory" (`fast_float.h:22-23`) and the bridge adds nothing.
`first == last` is legal, including when both are the address of a zero-length
object; upstream compares them before dereferencing either
(`parse_number.h:332-336`), so an empty range is an ordinary
`FF_STATUS_INVALID_ARGUMENT` and no pointer arithmetic happens over bytes that
do not exist. In Zig, `lastOf` returns `first` unchanged for a zero-length slice
rather than computing `ptr + 0`, for the same reason.

**The pointer obligations, once you call the bridge yourself.** `first` and
`last` must both point into one allocation the caller still owns, and `last`
may equal `first`. `out_value` and `out_consumed` must both be non-null and
writable: the bridge dereferences both without a null check, and there is no
way to drop either one. `parse32`/`parse64` hand the range to the bridge
themselves through this facade's `firstOf` and `lastOf`; a direct
`c.ff_parse_f64(...)` call makes all four of these the caller's to satisfy.

**Bounds.** Every public bound here is an ordinary comparison that survives an
optimized build: `parse*Exact` compares `consumed` against `bytes.len` with `!=`
and returns an error, not a debug assertion. No `std.debug.assert` guards
anything a caller can reach, so nothing in the contract disappears in
ReleaseSafe.

**From C++.** The whole upstream header tree is installed beside the archive, so
a C++ consumer can use fast_float directly and never touch the bridge:

```cpp
#include <fast_float/fast_float.h>
double d;
const auto r = fast_float::from_chars(s, s + n, d);   // r.ec, r.ptr
```

`fast_float_bridge.h` is C-includable and is `extern "C"`-guarded, so including
it from C++ links against the C-built archive rather than declaring the same
symbols under C++ mangling. Both halves of that have been exercised: a
translation unit written outside the build graph, compiled against the
**installed** `include/` and `libfast_float.a`, ran both a direct
`fast_float::from_chars` call — including its own `std::errc::invalid_argument`
path, reached without the bridge — and a real `ff_parse_f64` call on
`"9007199254740995"`, the 16-byte round-half-to-even tie that must return
`consumed == 16` and `2^53 + 4`. That is compile, link and run evidence for the
C++ side of the install, not an include-only check that the symbols are
declared; the receipt is in "Verification status".

## Build modes

* **Bundled (the only source mode).** Compiles upstream's nine real headers
  through `zig/bridge.cpp` into the C ABI archive for the selected linkage,
  whichever target is being built, and installs the upstream header tree next
  to it. Nothing is downloaded, no upstream build system runs, and
  `build.zig.zon` declares no dependencies.
  `-std=c++17` is pinned, not preferred: upstream asks for C++11
  (`FASTFLOAT_CXX_STANDARD` / `cxx_std_11`) and C++17 is a strict superset that
  is still below the two thresholds that would switch upstream's own code paths —
  `float_common.h:13` includes `<stdfloat>` only above `__cplusplus > 202002L`,
  and `constexpr_feature_detect.h:17` turns on `FASTFLOAT_HAS_BIT_CAST` only for
  `__cpp_lib_bit_cast >= 201806L`, a C++20 library feature. Leaving the standard
  to the compiler default would make the build depend on which clang Zig ships.
* **Static or shared is a delivery choice, not a source mode.** `-Dlinkage`
  selects it and defaults to `.static`, which is what this package produced
  before the option existed. Both deliveries compile the same one translation
  unit with the same flags and the same `-std=c++17`; only the link and the
  export surface differ, and the export closure is exactly `ff_parse_f32` and
  `ff_parse_f64`. A target that cannot carry a shared object is **refused**,
  never substituted: `build_support/graph.zig:sharedObjectRefusal` returns the
  reason once, the build fails naming the target, and inside `check` that one
  matrix cell becomes a failing step carrying it while the other five are still
  compiled. See `README.md`, "Platform boundaries".
* **Dispatch is a separate option.** `-Druntime` (default off) resolves the
  bridge's entry points at run time instead of linking them; see "Runtime
  loading" below. It is orthogonal to `-Dlinkage`, which keeps deciding what is
  built and installed. A linked build is unchanged in every respect.

* **System mode: not applicable.** There is no `b.systemIntegrationOption` and no
  system branch. Upstream installs no binary, so a "system" fast_float on a
  machine is a directory of headers: no installed ABI to bind to, no
  versioned symbol set to match, nothing for a system mode to select. The rule
  that applies to this fork is **vacuous rather than satisfied**, and it is
  recorded that way in `UPSTREAM.md` rather than being presented as a passed
  mode. The archive this fork installs is a different thing: it is built here,
  not found elsewhere.

## Runtime loading

`-Druntime` (default off) builds the same facade over a dispatch: each selected
native function becomes a call through one process-lifetime table that an
explicit `load(source)` fills, instead of a link-line reference. The facade keeps
the same translated header and the same public types, and `-Dlinkage` keeps
deciding what is built and installed — under `-Druntime` that artifact is what a
provider *is*, not something the module links.

```zig
const fast_float = @import("fast_float");

try fast_float.load(.{ .path = "/path/to/libfast_float.so.0" });
const tenth: f64 = try fast_float.parse64Exact("0.1");
```

The source is explicit: an absolute `.path`, or a `.system` basename handed to
the platform loader. There is no default provider, no search path and no
fallback to a linked copy, and no path-to-system fallback either — a build that
was not told which file to load says so rather than loading something else.

**The provider contract in this repository.** `smoke.zig` reads
`--provider <path>` or `FASTFLOAT_PROVIDER`; `tests.zig` reads
`FASTFLOAT_PROVIDER` from the environment and stops by name if it is unset; and
`consumer/src/main.zig` reads the same `--provider`, with the consumer package
forwarding both `-Druntime` and its run arguments. Arguments reach the smoke
program through `zig build smoke -Druntime=true -- --provider <path>`, and the
consumer runs as
`cd consumer && zig build run -Druntime=true -- --provider <path>`. Nothing is
loaded by default and no other file is tried.

**What the dispatch does not change.** `pub const c` is still the complete
translated `zig/bridge.h`, `Error` still has the same three members, and the
out-parameter contract in "The C ABI" above is unchanged — the values come from
whichever provider the table was filled from.

The whole runtime route is in this tree, and `runtime/` is in `build.zig.zon`
`.paths`, so a dependent receives all of it. `runtime/graph.zig` wires it:
`runtime/loader.zig` is the reusable core, imported at
`runtime/graph.zig:131-144` so a linked build's `LoadSource` and `LoadError` are
the same types a runtime build dispatches through; `runtime/library.zig` is
this SDK's descriptor; `runtime/generate.zig` is the host program
`runtime/graph.zig:235-244` builds and runs over the translation step's real
output; and `runtime/sync.c` with `runtime/sync.h` is the synchronization
binding compiled with `-DRT_SYNC_PREFIX=fast_float_rt`
(`runtime/graph.zig:215-219`). `build_support/graph.zig:110` is the one seam
between them.

The gate has run for the native host. Eight `-Druntime` configurations — both
linkages in all four optimize modes — compiled, tested, smoked and installed
with exit 0 on 2026-10-04, each naming a provider explicitly and answering the
whole known-answer corpus through the table; the rows in "Verification status"
carry the counts. What those runs do not reach is named there as well: the
provider was this tree's own shared object named by absolute path, and no
basename-named provider, no provider this tree did not build, and no failure,
retry, idempotence or provider-change path has been exercised here.

## Nix packaging and the development environment

`package.nix` is one source-only derivation; `flake.nix` and `devenv.nix` both
consume it, so the two cannot drift. It builds this repository's own tree with
`zig build install` and adds no C or C++ flag of its own: `-std=c++17`, the
upstream include path and the bridge translation unit stay where
`build_support/graph.zig` puts them. Both packages are linked builds:
`-Dlinkage` selects the delivery and `-Druntime` is left at its default off, so
neither Nix package depends on a provider being loadable at build time.

`flake.lock` is committed in this repository, pins exactly the
`github:NixOS/nixpkgs/c7def046b9a883d46974757852106483d741586f` `flake.nix`
declares together with that revision's `narHash`, and is listed in
`build.zig.zon` `.paths`, so it travels with the package: a dependent who
fetched it resolves this nixpkgs rather than the one its machine happens to
carry. `devenv.lock` is not in this tree and is not named; `devenv.yaml` states
what it must pin when it is created.

```
nix build .#static     # this SDK's existing linkage policy, and the flake default
nix build .#shared     # the same SDK delivered as a shared archive
nix develop            # toolchain only; parity, not the canonical route
```

Each output installs the archive, `fast_float_bridge.h`, the whole upstream
header tree, `lib/pkgconfig/fast_float.pc`, and the full licence set under
`share/licenses/fast_float/`: upstream's three texts, `NOTICE.md`,
`FORK-LICENSE.md`, `UPSTREAM.md`, `README.upstream.md`, and the corpus's own
Apache-2.0 copy under the distinct name `testdata-supplemental-LICENSE`. All of
that is installed by `zig build install` itself, from one generator, so the Zig
install and both Nix packages carry the same set; the derivation adds nothing
beside it. The 262 MB known-answer corpus is **not** installed — it is test
input, not installed data — and stays in the derivation's source, where
`zig build test` reaches it.

The two packages are one SDK with one delivery option, not two SDK modules. The
export closure of the shared object is exactly `ff_parse_f32` and `ff_parse_f64`
— a generated version script with `local: *` on ELF, a generated module
definition on windows-gnu, which a COFF DLL needs because it exports nothing
without one, and nothing on Darwin, which this build states rather than papers
over. Upstream installs no library at all — its CMake target is `INTERFACE` — so
the shared object's ABI is this fork's own C ABI, not an upstream release, and
its `0.1.0` version is bumped only when `zig/bridge.h` changes incompatibly.

`wasm32-wasi` has no dynamic linker, so `-Dlinkage=dynamic` is refused for it:
nothing is compiled, nothing is substituted, and the failure names the target.
The default is untouched — no `-Dlinkage` means `static`, which is exactly what
`wasm32-wasi` takes, so `zig build check` with no flag still compiles all six
cells.

`devenv` is the canonical development environment. `devenv shell`, or `.envrc`
where direnv is installed, enters it. The shell carries tools and tasks; its
`outputs.static` and `outputs.shared` are lazy, so entering it builds nothing and
`devenv build outputs.static` is the packaging route:

```
devenv shell sdk:install            # zig build install, into a prefix outside this tree
devenv shell sdk:test               # zig build test, optionally -Dtarget=...
devenv shell sdk:smoke
devenv shell sdk:check
devenv shell provenance:integrity   # sha256sum -c UPSTREAM.sha256
devenv shell sdk:consumer
devenv build outputs.static
devenv build outputs.shared
```

Every task that reads this repository's files changes into this repository's own
directory first, from a path `devenv.nix` evaluates. `devenv --from path:<this
repository>` gives the generated wrapper the *project* directory as its current
directory, and `DEVENV_ROOT` names that project, which holds none of this SDK's
inputs; `package:static` and `package:shared` read no file here and are
unchanged. `sdk:install` writes outside the working copy, defaulting to
`$ZIG_LOCAL_CACHE_DIR/fast_float-install`, falling back to
`$TMPDIR/zig-local-cache/fast_float-install`, taking `PREFIX=...` over both, and
refusing with a message when neither variable is set. `"$@"` reaches
`zig build` unchanged in every task.

Each of those five `zig build` commands carries `-j8`, `--summary all` and
`--cache-dir "$ZIG_LOCAL_CACHE_DIR"` after its own step flags and before
`"$@"`, so a caller's own `-jN`, `--summary` or `--cache-dir` still wins — the
build runner reads the last occurrence of each and every one overwrites the one
before it (`lib/compiler/build_runner.zig:422-427`, pinned 0.16.0). The steps,
the single `--prefix` and the `"$@"` forwarding are otherwise unchanged.

That prefix is needed by `sdk:install` alone, and the step graph says why rather
than convention: the install step depends on the smoke executable, not the
reverse (`build.zig:204`), while `smoke` (`:212`), `test` (`:245`) and `check`
(`:247-257`) and the consumer's `run` (`consumer/build.zig`) each depend only on
their own compile or run step. None of them reaches an install step, writes a
delivery output, or is given a `--prefix` it does not need.

Cache and scratch locations are the caller's to supply. Every task body resolves
both Zig cache directories before its own compiler starts, because
`devenv tasks run --mode single <name>` runs a body without the `enterShell`
hook. An exported variable is kept; a missing one is filled from
`XDG_CACHE_HOME` and then from `$TMPDIR` under this SDK's existing names —
`zig-global` and `zig-local`, `zig-global-cache` and `zig-local-cache` — and a
caller who named neither gets the variables to export and a stop, not a
`.zig-cache` in this tree. `enterShell` still applies the same
`XDG_CACHE_HOME` default to an interactive session, and it never unsets one. No
Nix file in this repository names a host account, a node, a store path or a
scratch mount.

Nothing in this section has been run. It is `PENDING-VERIFICATION`.

## Verification status

Every `observed` row below was run by the driver with the pinned 0.16.0
compiler, not predicted, and each names the receipt it came from. The rows that
are not `observed` say so and claim nothing.

| Gate | State | Receipt |
|---|---|---|
| `test` (Debug) | **observed, exit 0 — 13/13.** `zig build test smoke install -Doptimize=Debug -j8 --summary all --color off`, native, 2026-10-02, 12/12 steps. The corpus test consumed all 1,382,483 lines at both widths and printed all nine per-file line counts; `smoke` printed the bit patterns worked out in `smoke.zig`'s own comment; `install` wrote into an approved prefix outside the repository. The same tests ran in an earlier round: `…-fast_float-final-debug-97.log` | `local://foundation-cross-test-stable-fast_float-native-Debug.log` |
| `test` (ReleaseSafe) | **observed, exit 0 — 13/13.** `zig build test smoke -Doptimize=ReleaseSafe -j8 --summary all --color off`, native, 2026-10-02, 10/10 steps — the same corpus test with the optimizer on, plus its own smoke run. Earlier round: `…-fast_float-final-releasesafe-100.log` | `local://foundation-cross-test-stable-fast_float-native-ReleaseSafe.log` |
| `smoke` | **observed, exit 0** as part of both native steps above; every printed bit pattern matched the value worked out in `smoke.zig`'s own comment, and each refusal behaved as written. Run on its own in an earlier round: `…-fast_float-final-smoke-92.log` | the two stable native logs above |
| consumer | **observed, exit 0** — all eight constants matched, the unit line reported 7 bytes consumed and suffix `" m/s^2"`, and the exact-parse and leading-`+` refusals behaved as written. Re-run against this tree on 2026-10-02 with `zig build run -j8 --summary all --color off` from `consumer/`, 6/6 steps. Earlier round: `…-fast_float-consumer-repair-proof-112.log` | `local://foundation-cross-test-stable-fast_float-native-consumer.log` |
| install | **observed, exit 0**, `-j8 --summary all` into an approved prefix outside the repository, and a real uncached build of the archive rather than a reused object (`compile lib fast_float Debug native success 10s`). `libfast_float.a` is 770,530 bytes and defines `ff_parse_f32` and `ff_parse_f64`; beside it sit `fast_float_bridge.h` and the whole nine-header upstream tree | `…-fast_float-installed-artifact-gruenau8-176.log` |
| installed C surface | **observed, exit 0** — the installed header compiled as C11, linked against the installed archive and ran, including both round-half-to-even ties, the invalid-argument path that writes nothing and the overflow path that writes both out-parameters | `…-fast_float-installed-C-surface-181.log` |
| installed C++ surface | **observed, exit 0** — a real `ff_parse_f64("9007199254740995", …)` call returning `consumed == 16` and `2^53 + 4`, alongside a direct `fast_float::from_chars` call and its `std::errc::invalid_argument` path | `…-fast_float-installed-upstream-Cpp-surface-corrected-extraction-196.log` |
| `check`, six cross targets | **observed, exit 0 for all six**, 7/7 steps each, one command per target, in two rounds. The first: `…-matrix-x86_64-linux-gnu-133.log`, `-aarch64-linux-gnu-137`, `-aarch64-macos-none-140`, `-x86_64-windows-gnu-143`, `-riscv64-linux-gnu-146`, `-wasm32-wasi-149`. The second, against this tree on 2026-10-02 with `zig build check -Dtarget=<triple> -Doptimize=Debug -j8 --summary all --color off`, 2.9 s to 5.2 s each: `local://foundation-cross-test-baseline-fast_float-x86_64-linux-gnu.log`, `-aarch64-linux-gnu.log`, `-aarch64-macos-none.log`, `-x86_64-windows-gnu.log`, `-riscv64-linux-gnu.log`, `-wasm32-wasi.log` | those six, and the six baseline logs |
| `sha256sum -c UPSTREAM.sha256` | **observed, exit 0** — 73 records, no failures, on the tree as it stood on 2026-10-02 | `…-fast_float-immutable-source-integrity-124.log` |
| `git diff --exit-code b0ab987b… -- include LICENSE-APACHE LICENSE-BOOST LICENSE-MIT` | **observed, exit 0 — empty output.** Upstream's nine library headers and its three licence texts in this working tree are byte-identical to the pinned commit `b0ab987b3dfdde13fa1915f65ef2a5c068d9208c`. Run directly by the driver, not through CI; it covers these four path groups and not the job's wider list | `…-fast_float-pinned-native-pristine-diff-269.log` |
| `zig fetch` (materialised package) | **observed, exit 0, historical.** printing `fast_float-8.3.0-IdJv95QQZhDN1SQSHpQFuzW1cE-hqYLTHqBmiM9QW4yG`. Run by the driver from a separate scratch build root outside this repository, not from the package source root, with `--global-cache-dir` pointing at the driver's own package cache. What it copies is the manifest-filtered package. It describes the tree **before** this wave's run-step and profile edits, so it is history and not a claim about what ships today | `…-fast_float-external-driver-package-fetch-326.log` |
| `sha256sum -c UPSTREAM.sha256` **inside the materialised package** | **observed, exit 0 — all 73 records `OK`, historical.** Every path the record names is present in the filtered copy a dependent receives, which is the `.paths` closure claim and not something a check run in this checkout can show. Same round as the row above, hence the same caveat | `…-fast_float-materialized-package-integrity-335.log` |
| consumer, materialised package | **observed, exit 0, historical** — run from inside the fetched copy rather than from this tree, so `consumer/`'s relative `.path` resolved against a package this repository's build graph never produced: all eight constants matched, the unit line reported 7 bytes consumed and suffix `" m/s^2"`, and the exact-parse and leading-`+` refusals behaved as written. Same round as above | `…-fast_float-materialized-package-consumer-342.log` |
| `zig fetch` from the package source root | **superseded.** exit 1, `error: unable to copy directory '/vol/fob-vol7/mi19/gertullj/foundation-libs/fast_float': IllegalFileTypeInPackage`. The passing row above is the same absolute package path fetched from an external scratch build root; no byte of this tree changed between the two, and no cause is asserted here for the difference | `…-fast_float-materialized-package-fetch-262.log` |
| materialised package, final round against this tree | **Driver-owned closure proof.** Filtered fetch, source/fetched integrity and fetched consumer run after SDK documents settle. Current result and identity are in the workspace ledger's `cross_test_wave.materialized_packages.fast_float`; the historical rows above predate the run-step/profile changes. Identities stay outside package-local documents | `local://foundation-cross-test-package-regression.json` |
| `verify.yml` `provenance` job | **The whole job has never been executed in this workspace.** The hand-run diff does not prove the commit-in-history check, fork-record presence, licence-filename greps in `NOTICE.md` and upstream's preserved `README.upstream.md`, or the wider pristine path set (`tests benchmarks cmake ci docs script fuzz`, `CMakeLists.txt`, `BUILD.bazel`, `MODULE.bazel`, `.bazelrc`, `.clang-format`, `clang-format-ignore.txt`, `AUTHORS`, `CONTRIBUTORS`, `README.upstream.md`, `SECURITY.md`). The job now diffs `README.upstream.md` rather than `README.md`, because `README.md` is this fork's own. No current workflow step greps `testdata/README.md` | — |
| `cross-test`, 53-platform matrix, before this correction | **observed failure, exit 1.** `cross-test --no-profile --targets x86_64-linux --jobs 1 --build-jobs 4 --build-timeout 900` reported `build=pass`, `run=fail`, `reason=no_test_results` — it compiled the test binary for that target and ran none of the 13 tests, because `Query.isNative()` is false for every query that names a target and `-Dtarget` always names one. This is the run that put the run step on every target; it is kept because it is why the correction was made | before: `/home/tmp2/gertullj/scratch/foundation-libs/cross-test-01a0f400/before/fast_float/cross-test-summary.json` |
| `cross-test`, 53-platform matrix, first full sweep | **observed, exit 1 — 17 pass, 33 build-only, 3 fail.** All 53 targets compiled. On `x86_64-linux` (5m98.837ms), `aarch64-linux` (5m18.377s) and `aarch64_be-linux` (5m1.042s) the test `every selected corpus file matches its recorded bit patterns at both widths` hit the harness's 300-second per-test deadline, 12/13 passed and one timed out on each; the other 17 cells ran the whole suite, 13/13. Kept rather than erased, because it is what the deadline change answers | `local://foundation-cross-test-matrix-fast_float-x86_64-linux.log`, `-aarch64-linux.log`, `-aarch64_be-linux.log` |
| `cross-test`, 53-platform matrix, corrected deadlines | **observed, exit 0 — 20 pass, 33 build-only, 0 fail.** `cross-test --jobs 2 --build-jobs 4 --build-timeout 3600` under this package's profile (`CROSS_TIMEOUT=1800`), run `20261002-060543-20930-1891`, Zig 0.16.0, `zig-build` mode, 2026-10-02. Each of the 20 cells with an executor reported 13/13 and printed all nine per-file line counts — all 1,382,483 rows at both widths, `x86_64-linux` in 2 s natively and `aarch64-linux` in 32 s under `/bin/qemu-aarch64`. The 33 remaining cells are `runtime_unavailable`: compiled, never executed, never counted as a pass | `local://foundation-cross-test-corrected-fast_float.json` and the per-target logs beside it |
| `cross-test`, 53-platform matrix, source-bound cohort on the current tree | **observed, exit 0 — `status: partial`, raw `pass=20 fail=0 build_only=33 partial=0`.** Receipt `20261004T221720228710Z-45046/fast_float-53-target-8.json`, 2026-10-04, `source_stamp_before == source_stamp_after` (`bc692cd7…`), `zig_version 0.16.0`, `mode zig-build`, `target_count 53`, `target_jobs 8`, `jobs_per_build 8`, `bookkeeping_failure false`. Every executed cell reports `tests=13`; `x86_64-linux` ran natively and `aarch64-linux` under `/bin/qemu-aarch64`, as in the 2026-10-02 sweep above. **Thirty-three `build_only` cells compiled and ran nothing** and are not passes. This row is the current one; the 2026-10-02 sweep is kept beside it because it is what the deadline profile was measured against, and its counts happen to agree | `20261004T221720228710Z-45046/fast_float-53-target-8.json` |
| `check` over the six required targets, compile-only, current tree | **observed, exit 0 — `Build Summary: 32/32 steps succeeded`.** Row `baseline-fast_float-check` of `baselines-and-configs/20261005T014547Z-797a73f2`, 2026-10-05: `declared_target_count 6`, all six triples named in the run's own step lines, `test_pass_lines: []`, `failing_step_lines 0`. The 2026-10-02 row above walked the same six one command at a time at 7/7 steps each; both are compile evidence and neither runs anything | `baselines-and-configs/20261005T014547Z-797a73f2` |
| system mode | not applicable, vacuously; see "Build modes" | — |
| linked native `test smoke install -Druntime=false`, both linkages, four optimize modes | **observed on this tree, exit 0 for all eight** — `13/13 tests passed` in each, `Build Summary: 22/22 steps succeeded` in the four static cells and `23/23` in the four dynamic ones, with all nine per-file corpus line counts printed in every cell, so all 1,382,483 rows were consumed at both widths in all eight. Each dynamic cell's configure line names `shared object, soname libfast_float.so.0 exporting only the two bridge entry points`, and `install` wrote into a prefix outside this repository in every cell | `local://foundation-current-native-index.json`, rows `fast_float-current-native-{dynamic,static}-{Debug,ReleaseSafe,ReleaseFast,ReleaseSmall}` |
| runtime loading under `-Druntime` on the native host, both linkages, four optimize modes | **observed on this tree, exit 0 for all eight** — `13/13 tests passed` in each, `23/23` steps for the four static cells and `24/24` for the four dynamic ones. Every configure line states `runtime-loaded dispatch (-Druntime=true); no library is linked into the module`, `smoke` reports `runtime-loaded build` and prints the provider it resolved, and `tests.zig` — which stops by name when `FASTFLOAT_PROVIDER` is unset — read all nine corpus files at both widths in every cell, so the suite answered through the dispatch rather than beside it. The four static cells also print that an archive is a file a loader cannot open, so a provider has to be a shared object. **Still `PENDING-VERIFICATION`**: a provider named by basename, a provider this tree did not build, the pre-initialization call, failure and refusal, explicit retry, idempotence, provider change, and the allocator check at load time | the same index, rows `fast_float-current-loaded-{dynamic,static}-{Debug,ReleaseSafe,ReleaseFast,ReleaseSmall}` |
| the provider those eight loaded runs used | **This tree's own shared object, named by absolute path** — the `libfast_float.so` the four dynamic runs installed into their prefix. No external provider and no basename-named provider has been loaded here, and no row above should be read as covering either | the same sixteen per-gate files, each recording its own `FASTFLOAT_PROVIDER` |
| the shared object's export table, and the Darwin and windows-gnu deliveries | **PENDING-VERIFICATION.** The soname and the export closure are the build graph's own printed statement; nothing in these receipts reads an installed object with `nm`, `objdump` or `dumpbin`, and no Darwin or windows-gnu delivery has been installed on this host | — |
| the installed closure on this tree: archive or shared object, `fast_float_bridge.h`, the upstream header tree, `lib/pkgconfig/fast_float.pc`, `share/licenses/fast_float/` | **Partly observed.** Every one of the sixteen runs above ran `install` into a prefix outside this repository and no install step failed, and each install step list names the generated pkg-config file and all eight licence records — the closure `FORK-NOTES.md` 22 recorded as silently absent from the install is present on this tree. What stays `PENDING-VERIFICATION` is the assertion half: `package.nix` re-checks that closure and fails the derivation when anything promised is missing, and no `nix` command has been run here | the same sixteen rows |
| `sha256sum -c UPSTREAM.sha256` against this tree | **PENDING-VERIFICATION.** The two integrity rows above are 2026-10-02 evidence for an earlier tree; no replay over this tree's current bytes is recorded | — |
| static and shared Nix derivations, `devenv` shell, fetched filtered package | **PENDING-VERIFICATION, nothing run.** Both Nix packages consume `-Dlinkage`, which now exists; neither has been built. See `README.md` §3b for the whole pending table | — |

Every `…-…` prefix above is `local://foundation-expansion-fast_float`; the
fully written `local://foundation-cross-test-…` and
`local://foundation-current-native-index.json` names are this wave's receipts and
are spelled out rather than prefixed. The current index carries one file per
gate; its sixteen `fast_float-current-*` rows are the runs reported above as
observed on this tree, and the 2026-10-02 rows are earlier rounds.

**The materialised package, and what those rows prove.** The next three
paragraphs describe the earlier round, against the tree as it stood before this
wave's run-step and profile edits; they are history. The current closure proof
is recorded in the workspace ledger as described above. In the earlier round,
`zig fetch` copied this package, as `.paths` filters
it, into the driver's package cache and printed the identity above. Running
`sha256sum -c UPSTREAM.sha256` **inside that copy** and getting all 73 records
`OK` is the `.paths` closure claim, and
it is a different claim from the in-tree row. A checkout can hold a file the
manifest does not list, so a green check here would not show that the record is
still checkable where a dependent actually keeps it. The materialised copy
carries all nine upstream headers, all 48 upstream C++ test-tree files and all
sixteen vendored corpus files the record names, each the byte this repository
holds.

The consumer then built and ran from inside that filtered copy. **No registry,
no remote, no publication**: the fetch is over a local absolute path, nothing
here resolves a URL, a registry, a git remote or a published hash, no
publication has been authorised, and the identity string is what this compiler
printed for this directory — not a hash a downstream can fetch today.

**The direct diff and the CI job are different claims.** The pristine diff the
`provenance` job performs was run here by hand over `include` and the three
licence texts and is clean. The job itself has still never run, and it covers
more than that hand-run diff did. A green hand-run diff is not a green job and
this table does not report it as one.

**The two red gates this package once had are closed, and the corrections were
to the expectations, not to the library.** Both are recorded in full in
`FORK-NOTES.md` notes 3 and 4; the short form is that the parser was right in
both cases:

1. `tests.zig:381` — the long-significand oracle was wrong, not the parser. The
   input `9007199254740995` is `2^53 + 3`, exactly halfway between `2^53 + 2`
   (`0x4340000000000001`, odd significand) and `2^53 + 4`
   (`0x4340000000000002`, even significand), so round-half-to-even must land on
   the even one. The old literal `0x4340000000000001` is **withdrawn**, not
   replaced by a new one; the test now expects `0x4340000000000002`, which is
   what the parser produced all along and what the installed C++ surface returns
   for the same 16-byte input. The independent check of the tie — both
   neighbours' significand parities and the nearest-even result — is in
   `local://foundation-expansion-float-tie-proof.json`.
2. `consumer/src/main.zig` — the unit expectation dropped a byte that was
   genuinely in the buffer. `"9.80665 m/s^2"` parses 7 bytes and the separating
   space at index 7 is not part of the number, so the consumer now compares the
   tail at `consumed` against the tail that is really there, `" m/s^2"`, and
   checks `consumed` separately against `"9.80665".len`. The parse it is
   checking is unchanged and was always correct.

The earlier failing receipts (`…-corrected-debug-38.log`,
`…-corrected-releasesafe-41.log`, `…-corrected-consumer-46.log`) are kept
because a red receipt is the evidence for the diagnosis; they describe the files
as they stood before these corrections and are superseded by the rows above.

## Testing approach

The primary oracle is an **independent** known-answer corpus, not this
library's own output: `testdata/supplemental/data`, thirteen files and
5,268,191 lines vendored from `fastfloat/supplemental_test_files` at commit
`088643e8d5010bd3d1540fe48685601b43b9a3e5` — a separate Apache-2.0 work, not
part of upstream's licence triple, with the data credited to Nigel Tao in the
corpus's own vendored README. Each line is a decimal string with its exact
binary32 and binary64 bit patterns recorded beside it by *other* projects —
Google's double-conversion, Ryū, IBM's fpgen, Wuffs, FreeType, Lemire's parsers,
RapidJSON — so agreeing with it is this binding agreeing with implementations it
shares no code with.

`tests.zig` reads **nine** of the thirteen data files in full, every line, at
both widths: 564,745 + 599,458 + 102,792 + 94,313 + 10,744 + 3,566 + 3,299 +
3,563 + 3 = **1,382,483 lines**, and every one of those lines was consumed in
both the Debug and the ReleaseSafe run and in each of the 20 matrix cells whose
executor ran the suite. It also pins each file's line count, so
a fixture that was truncated, extended or reordered fails instead of passing
quietly on the lines that remain. The four `remyoudompheng-fptest-*.txt` files
are carried and hashed but deliberately not read: they are 3,885,708 lines from
a single generator, and their bit patterns are covered by eight independent
producers at a fraction of the cost. Not reading them does not put their licence
in doubt — they sit inside the same corpus the same Apache-2.0 grant covers,
which `testdata/README.md` states explicitly rather than leaving assumed.

`testdata/README.md` records the format, the line counts, the range-outcome
convention and an independent two-way cross-check of every recorded bit
pattern in all thirteen files, including the sixteen lines
where NumPy's binary32 conversion and an exact rational conversion disagree.

The hand-worked tests cover what the corpus does not isolate: the halfway
ties, the largest finite value and the next decimal out, the smallest subnormal
and half of it, the subnormal/normal boundary, prefix versus whole-buffer, the
format refusals (`+`, leading space, lone `.`), `inf`/`nan` and negative zero,
and the out-parameter ownership of each of the three statuses.

Every public method on the facade — `parse32`, `parse64`, `parse32Exact`,
`parse64Exact` — is called from `tests.zig`, which is what makes building the
test binary a real check of the facade rather than of an unreferenced C archive.
`smoke.zig` re-derives its own expected patterns from exact rational rounding
and exits non-zero on any disagreement, so its exit code is the semantic check
rather than a restatement of what the library just did.

## Integrity

```
sha256sum -c UPSTREAM.sha256
```

73 records covering every immutable byte the package compiles or reads —
upstream's nine library headers, upstream's 48-file C++ test tree, and the
sixteen vendored corpus files (fifteen vendored from the donor repository, plus
the Apache-2.0 text this fork sourced from the producer) — and nothing else, so
the same command works in a clone and in an unpacked package. Digests were
produced by reading each file as raw bytes with Bun and hashing with
`node:crypto`; no shell hashing command and no git command was used. **The
check has been run and passed: 73 records, no failures** — on the tree as it
stood on 2026-10-02; a replay over this tree's current bytes is
`PENDING-VERIFICATION`. See [`UPSTREAM.md`](UPSTREAM.md) for the exact scope, the
stated exclusions and what the record does and does not prove.

`UPSTREAM.sha256` is listed in `build.zig.zon` `.paths`, so the check travels
with the package rather than living only in this repository — and that half is
now observed rather than argued: the same command run inside a package
`zig fetch` materialised from this tree reports all 73 records `OK`
(`…-fast_float-materialized-package-integrity-335.log`), so every path the
record names is present in the filtered copy a dependent receives. See
"Verification status" for what that does not cover.

## Licence

Upstream is `Apache-2.0 OR MIT OR BSL-1.0`; all three texts ship verbatim as
`LICENSE-APACHE`, `LICENSE-MIT` and `LICENSE-BOOST`, and `NOTICE.md` records all
three by name so no downstream can be left with only one. Upstream's library
includes code adapted from Google Wuffs (written by Nigel Tao) under Apache-2.0,
and that obligation is discharged by the whole `LICENSE-APACHE` text.

The known-answer corpus is a **separate** work with a **single** Apache-2.0
grant, credited to Nigel Tao in the corpus's own vendored README; the Boost and
MIT alternatives are not offered for it. Its licence text sits at
`testdata/supplemental/LICENSE` and is byte-distinct from `LICENSE-APACHE`, and
`testdata/README.md` records which of the sixteen vendored files came from the
donor and which this fork sourced. `NOTICE.md` lists all sixteen one by one,
including the four the tests deliberately do not read, because a file this fork
redistributes is under the grant whether or not it is read.

**This fork's own files — the Zig build, the facade, the C ABI bridge, the
tests, the example, the consumer package, the Nix and devenv packaging and the
documentation — are licensed `Apache-2.0 OR MIT OR BSL-1.0`**, on the owner's
explicit authorization for this wave. That is the same three-way alternative
upstream offers rather than a new selection, and it adds no requirement for a
downstream to choose between alternatives it already had. An earlier revision of
this README offered these files under Apache-2.0 alone because the text already
shipped here; that was a grant nobody authorized, it was withdrawn and recorded
as unassigned, and it is now superseded by an actual grant.
[`FORK-LICENSE.md`](FORK-LICENSE.md) states the SPDX identifier, the
authorization, the per-file scope and — just as important — the material the
grant does **not** cover. Copyright in those files is held by the downstream that
owns this repository; no individual is named and none is asserted, and no
upstream author is credited with them.

Attribution, every file this fork adds or edits, the Apache-2.0 obligations the
two carried works impose on whoever redistributes them, and the patent-grant
termination clause are all in [`NOTICE.md`](NOTICE.md). Upstream's preserved
[`README.upstream.md`](README.upstream.md) carries the triple licence grant and
the Wuffs credit, and travels with the package.
