# fast_float — the C++ correctly-rounded parser, built and wrapped in Zig

This package compiles fast_float **8.3.0** — upstream's own header-only C++,
byte for byte, from the `include/` directory in this repository — into a static
C ABI archive with real external linkage, and publishes a small, allocation-free
Zig facade over the translated bridge header. No part of the parser is
reimplemented, nothing is downloaded at build time, and there is no dependency
of any kind in `build.zig.zon`.

Upstream: `https://github.com/fastfloat/fast_float`, tag `v8.3.0`, commit
`b0ab987b3dfdde13fa1915f65ef2a5c068d9208c`. Provenance, licences and the
integrity record are in [`UPSTREAM.md`](UPSTREAM.md), [`NOTICE.md`](NOTICE.md)
and [`UPSTREAM.sha256`](UPSTREAM.sha256).

## Requirements

Zig **0.16.0** — the real compiler, not the bare `zig` on `PATH`, which in
this workspace is a version dispatcher; through the dispatcher the command is
`zig 0.16.0 build`. Plus a C++ compiler and libc++/libstdc++, both of which
Zig supplies. Nothing is fetched.

## Commands

| Command | What it does |
|---|---|
| `zig build` | compiles upstream's headers through the C++ bridge, installs `libfast_float.a`, `fast_float_bridge.h` and the whole upstream header tree into `zig-out/`, and compiles the example |
| `zig build test` | runs `tests.zig` for the selected target: the nine-file known-answer corpus at both widths, plus the hand-worked cases |
| `zig build test -Doptimize=ReleaseSafe` | the same tests with the optimizer on |
| `zig build smoke` | runs `smoke.zig`, which checks its own answers and exits non-zero on any mismatch |
| `zig build check -Dtarget=<triple>` | compiles the C++ bridge, the translated header, the facade, the tests and the example for one target, running nothing |
| `zig build check` | the same for all six required targets in one graph |
| `cd consumer && zig build run` | the same library, consumed by a package that did not write it |

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
compile evidence and nothing more. **All six have been compiled in this
workspace and all six passed** — one command each, 7/7 steps, no target
skipped and none pre-judged; see "Verification status" for the receipts.

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
    error.InvalidArgument => return,   // nothing matched; nothing was written
    error.ResultOutOfRange => return,  // it matched, and rounded to inf or 0
    error.StatusNotRecognised => unreachable, // the bridge pins its own codes
};
```

`consumer/` is exactly this, in working form.

## The API

Everything the facade names is read out of upstream's own declarations, and each
one's documentation comment in `zig/root.zig` cites the header and line it came
from. The scope is deliberately narrow: `fast_float::from_chars` for `float` and
`double`, in `chars_format::general`, which is the default upstream instantiates
(`include/fast_float/fast_float.h:33-37`).

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
  all `error.InvalidArgument`. `from_chars` differs from `strtod` here on
  purpose: `include/fast_float/fast_float.h:11-15` says so, and
  `include/fast_float/parse_number.h:31` quotes C++17 20.19.3.(7.1), which
  forbids a `+` at this position. This is a deliberate difference from every
  C-locale conversion function, and a caller porting from `strtod` has to
  pre-strip.
* **A leading `-` is accepted**, including negative zero: `"-0"` is
  `0x80000000` at `f32` width, not `0x00000000`.
* **`"inf"`, `"infinity"` and `"nan"` parse successfully**, case insensitively,
  with an optional `-` and with the C++17 `nan(n-char-seq-opt)` payload
  (`include/fast_float/parse_number.h:37-56`). They are not errors. **This
  binding is therefore not a validator for untrusted text**; a caller that must
  reject non-finite input has to check the result itself, or use a different
  parser.
* **Rounding is exact, round-to-nearest, ties to even, independent of the FPU
  rounding mode** (`fast_float.h:12-15`). Upstream reads the FPU mode only to
  decide whether its fast path is valid (`parse_number.h:78-80`, consulted once
  at `:216`) and does the arithmetic itself.
* **Subnormals are produced, not flushed.** A value below the smallest normal
  but above zero rounds into the subnormal range.

### Errors, and what each one means for your variables

`Error` has exactly three members, and each is a claim about a comparison the
code actually made:

| Error | Bridge status | What happened | What you can read afterwards |
|---|---|---|---|
| `InvalidArgument` | `FF_STATUS_INVALID_ARGUMENT` (`1`) | no number matched: empty buffer, leading space or tab, leading `+`, a lone `.` or `-` | **nothing was written.** Your out-variables still hold what you put there |
| `ResultOutOfRange` | `FF_STATUS_RESULT_OUT_OF_RANGE` (`2`) | a number did match and did round, but past the largest finite magnitude or below the smallest | the infinity or zero upstream rounded to, through `pub const c` — see below |
| `StatusNotRecognised` | none | the bridge returned a value that is not one of the three codes its own header pins | unreachable by construction; an error rather than a panic so a future bridge change is reported instead of aborting |

**The typed surface withholds the value on `ResultOutOfRange` on purpose.** It
returns an error rather than a second successful result carrying an infinity or a
zero the caller did not write, and `Parsed32`/`Parsed64` are never constructed on
that path. The value is not lost — it is where the C ABI puts it.

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

* **Bundled (the only mode).** Compiles upstream's nine real headers through
  `zig/bridge.cpp` into `libfast_float.a` for whatever target is being built, and
  installs the upstream header tree next to it. Nothing is downloaded, no
  upstream build system runs, and `build.zig.zon` declares no dependencies.
  `-std=c++17` is pinned, not preferred: upstream asks for C++11
  (`FASTFLOAT_CXX_STANDARD` / `cxx_std_11`) and C++17 is a strict superset that
  is still below the two thresholds that would switch upstream's own code paths —
  `float_common.h:13` includes `<stdfloat>` only above `__cplusplus > 202002L`,
  and `constexpr_feature_detect.h:17` turns on `FASTFLOAT_HAS_BIT_CAST` only for
  `__cpp_lib_bit_cast >= 201806L`, a C++20 library feature. Leaving the standard
  to the compiler default would make the build depend on which clang Zig ships.
* **System mode: not applicable.** There is no `b.systemIntegrationOption` and no
  system branch. A header-only library installs no binary, so a "system"
  fast_float is a directory of headers: no installed ABI to bind to, no
  versioned symbol set to match, nothing for a system mode to select. The rule
  that applies to this fork is **vacuous rather than satisfied**, and it is
  recorded that way in `UPSTREAM.md` rather than being presented as a passed
  mode. A header-only library has no honest system mode; this one does not
  pretend to have one.

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
| `sha256sum -c UPSTREAM.sha256` | **observed, exit 0** — 73 records, no failures | `…-fast_float-immutable-source-integrity-124.log` |
| `git diff --exit-code b0ab987b… -- include LICENSE-APACHE LICENSE-BOOST LICENSE-MIT` | **observed, exit 0 — empty output.** Upstream's nine library headers and its three licence texts in this working tree are byte-identical to the pinned commit `b0ab987b3dfdde13fa1915f65ef2a5c068d9208c`. Run directly by the driver, not through CI; it covers these four path groups and not the job's wider list | `…-fast_float-pinned-native-pristine-diff-269.log` |
| `zig fetch` (materialised package) | **observed, exit 0, historical.** printing `fast_float-8.3.0-IdJv95QQZhDN1SQSHpQFuzW1cE-hqYLTHqBmiM9QW4yG`. Run by the driver from a separate scratch build root outside this repository, not from the package source root, with `--global-cache-dir` pointing at the driver's own package cache. What it copies is the manifest-filtered package. It describes the tree **before** this wave's run-step and profile edits, so it is history and not a claim about what ships today | `…-fast_float-external-driver-package-fetch-326.log` |
| `sha256sum -c UPSTREAM.sha256` **inside the materialised package** | **observed, exit 0 — all 73 records `OK`, historical.** Every path the record names is present in the filtered copy a dependent receives, which is the `.paths` closure claim and not something a check run in this checkout can show. Same round as the row above, hence the same caveat | `…-fast_float-materialized-package-integrity-335.log` |
| consumer, materialised package | **observed, exit 0, historical** — run from inside the fetched copy rather than from this tree, so `consumer/`'s relative `.path` resolved against a package this repository's build graph never produced: all eight constants matched, the unit line reported 7 bytes consumed and suffix `" m/s^2"`, and the exact-parse and leading-`+` refusals behaved as written. Same round as above | `…-fast_float-materialized-package-consumer-342.log` |
| `zig fetch` from the package source root | **superseded.** exit 1, `error: unable to copy directory '/vol/fob-vol7/mi19/gertullj/foundation-libs/fast_float': IllegalFileTypeInPackage`. The passing row above is the same absolute package path fetched from an external scratch build root; no byte of this tree changed between the two, and no cause is asserted here for the difference | `…-fast_float-materialized-package-fetch-262.log` |
| materialised package, final round against this tree | **Driver-owned closure proof.** Filtered fetch, source/fetched integrity and fetched consumer run after SDK documents settle. Current result and identity are in the workspace ledger's `cross_test_wave.materialized_packages.fast_float`; the historical rows above predate the run-step/profile changes. Identities stay outside package-local documents | `local://foundation-cross-test-package-regression.json` |
| `verify.yml` `provenance` job | **The whole job has never been executed in this workspace.** The hand-run diff does not prove the commit-in-history check, fork-record presence, licence-filename greps in `NOTICE.md` and upstream `README.md`, or the wider pristine path set (`tests benchmarks cmake ci docs script fuzz`, `CMakeLists.txt`, `BUILD.bazel`, `MODULE.bazel`, `.bazelrc`, `.clang-format`, `clang-format-ignore.txt`, `AUTHORS`, `CONTRIBUTORS`, `README.md`, `SECURITY.md`). No current workflow step greps `testdata/README.md` | — |
| `cross-test`, 53-platform matrix, before this correction | **observed failure, exit 1.** `cross-test --no-profile --targets x86_64-linux --jobs 1 --build-jobs 4 --build-timeout 900` reported `build=pass`, `run=fail`, `reason=no_test_results` — it compiled the test binary for that target and ran none of the 13 tests, because `Query.isNative()` is false for every query that names a target and `-Dtarget` always names one. This is the run that put the run step on every target; it is kept because it is why the correction was made | before: `/home/tmp2/gertullj/scratch/foundation-libs/cross-test-01a0f400/before/fast_float/cross-test-summary.json` |
| `cross-test`, 53-platform matrix, first full sweep | **observed, exit 1 — 17 pass, 33 build-only, 3 fail.** All 53 targets compiled. On `x86_64-linux` (5m98.837ms), `aarch64-linux` (5m18.377s) and `aarch64_be-linux` (5m1.042s) the test `every selected corpus file matches its recorded bit patterns at both widths` hit the harness's 300-second per-test deadline, 12/13 passed and one timed out on each; the other 17 cells ran the whole suite, 13/13. Kept rather than erased, because it is what the deadline change answers | `local://foundation-cross-test-matrix-fast_float-x86_64-linux.log`, `-aarch64-linux.log`, `-aarch64_be-linux.log` |
| `cross-test`, 53-platform matrix, corrected deadlines | **observed, exit 0 — 20 pass, 33 build-only, 0 fail.** `cross-test --jobs 2 --build-jobs 4 --build-timeout 3600` under this package's profile (`CROSS_TIMEOUT=1800`), run `20261002-060543-20930-1891`, Zig 0.16.0, `zig-build` mode, 2026-10-02. Each of the 20 cells with an executor reported 13/13 and printed all nine per-file line counts — all 1,382,483 rows at both widths, `x86_64-linux` in 2 s natively and `aarch64-linux` in 32 s under `/bin/qemu-aarch64`. The 33 remaining cells are `runtime_unavailable`: compiled, never executed, never counted as a pass | `local://foundation-cross-test-corrected-fast_float.json` and the per-target logs beside it |
| system mode | not applicable, vacuously; see "Build modes" | — |

Every `…-…` prefix above is `local://foundation-expansion-fast_float`; the
fully written `local://foundation-cross-test-…` names are this wave's receipts
and are spelled out rather than prefixed.

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
check has been run and passed: 73 records, no failures.** See
[`UPSTREAM.md`](UPSTREAM.md) for the exact scope, the stated exclusions and what
the record does and does not prove.

`UPSTREAM.sha256` is listed in `build.zig.zon` `.paths`, so the check travels
with the package rather than living only in this repository — and that half is
now observed rather than argued: the same command run inside a package
`zig fetch` materialised from this tree reports all 73 records `OK`
(`…-fast_float-materialized-package-integrity-335.log`), so every path the
record names is present in the filtered copy a dependent receives. See
"Verification status" for what that does not cover.

## Licence

Upstream is `Apache-2.0 OR BSL-1.0 OR MIT`; all three texts ship verbatim as
`LICENSE-APACHE`, `LICENSE-BOOST` and `LICENSE-MIT`, and `NOTICE.md` records all
three by name so no downstream can be left with only one. Upstream's library
includes code adapted from Google Wuffs (written by Nigel Tao) under Apache-2.0,
and that obligation is discharged by the whole `LICENSE-APACHE` text.

The known-answer corpus is a **separate** work with a **single** Apache-2.0
grant, credited to Nigel Tao in the corpus's own vendored README; the Boost and
MIT alternatives are not offered for it. Its licence text sits at
`testdata/supplemental/LICENSE` and is byte-distinct from `LICENSE-APACHE`, and
`testdata/README.md` records which of the sixteen vendored files came from the
donor and which this fork sourced.

**This fork's own files — the Zig build, the facade, the C ABI bridge, the
tests, the example, the consumer package and the documentation — carry no
stated licence.** An earlier revision of this README offered them under
Apache-2.0 because that text already ships here; that was a grant nobody
authorised this fork to make, so it is withdrawn and recorded as unassigned in
[`NOTICE.md`](NOTICE.md) rather than left standing. Attribution, the files this
fork adds or edits, the Apache-2.0 obligations the two carried works impose on
whoever redistributes them, and the patent-grant termination clause are all in
that file. Upstream's `README.md` also carries the triple licence grant and the
Wuffs credit, and travels with the package.
