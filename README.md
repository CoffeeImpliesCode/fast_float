# fast_float — a Zig SDK over upstream's correctly-rounded decimal-to-binary parser

This repository is upstream fast_float's own tree plus a Zig 0.16 package built
around it. Upstream's parser is compiled from the `include/` directory here,
byte for byte, into a C ABI archive with real external linkage; a small Zig
facade and a separate C header sit on top of it. No part of the parser is
reimplemented, nothing is downloaded at build time, and `build.zig.zon` declares
no dependencies.

| | |
|---|---|
| Upstream | `https://github.com/fastfloat/fast_float`, annotated tag `v8.3.0`, commit `b0ab987b3dfdde13fa1915f65ef2a5c068d9208c` |
| Library version built here | `8.3.0` — `CMakeLists.txt:4`, and `FASTFLOAT_VERSION_*` at `include/fast_float/float_common.h:19-21` |
| Compiler | Zig 0.16.0 (`build.zig.zon` `minimum_zig_version`) |
| Upstream's own README | [`README.upstream.md`](README.upstream.md) — byte for byte, `sha256 80d3197381d1a3fe7de55ac450e62b89a6d7141069b88eeca645f0543a6b2a3b` |
| Zig interface documentation | [`README.zig.md`](README.zig.md) |
| Provenance | [`UPSTREAM.md`](UPSTREAM.md), [`NOTICE.md`](NOTICE.md), [`FORK-LICENSE.md`](FORK-LICENSE.md) |
| Integrity | [`UPSTREAM.sha256`](UPSTREAM.sha256) — 73 records, one per immutable upstream and donor byte |
| Upstream licences | `Apache-2.0 OR MIT OR BSL-1.0` — `LICENSE-APACHE`, `LICENSE-MIT`, `LICENSE-BOOST`, all shipped whole |
| This fork's own files | `Apache-2.0 OR MIT OR BSL-1.0`, on the owner's authorization — [`FORK-LICENSE.md`](FORK-LICENSE.md) |
| Known-answer corpus | Apache-2.0 only, no alternatives — a separate work, credited to Nigel Tao; see [`testdata/README.md`](testdata/README.md) |

---

## 1. Native-source deviations

**None.** No upstream source file, header, test, licence text, or byte of the
known-answer corpus is modified, reformatted, reordered or deleted. Upstream's
CMake, Bazel, benchmark, fuzz, tooling and documentation trees are carried
whole, and upstream's own CI is left driving the upstream maintainers'
infrastructure rather than retargeted here.

`UPSTREAM.sha256` is the check, and it names only files that a build compiles or
a test reads: upstream's nine library headers, upstream's 48-file C++ test tree,
and the sixteen vendored corpus files. Run it from a clone or from an unpacked
package — the paths it names are all inside the package:

```
sha256sum -c UPSTREAM.sha256
```

**One upstream file is edited, and only by appending.** `.gitignore` keeps
upstream's own list verbatim and unedited, and this fork adds six Zig ignore
entries below it. That is why the file is absent from `UPSTREAM.sha256` and
absent from the pristine-diff path list in `.github/workflows/verify.yml`: a
digest of a file this fork edits by design would be a record of the fork rather
than of upstream. The append is recorded in [`NOTICE.md`](NOTICE.md).

**One upstream tool is affected by this repository's layout, and is not run.**
`script/release.py` rewrites `README.md` in place to stamp a new version. In
this repository `README.md` is the fork's README and upstream's bytes live at
`README.upstream.md`, so that script would edit the wrong file. Nothing in this
package runs upstream's release tooling, and
[`.gitignore` and the packaging](#2-native-build-deviations) are unchanged in
consequence; the note is here so that a future re-sync does not discover it by
running the script.

---

## 2. Native-build deviations

Upstream's `CMakeLists.txt` declares an `INTERFACE` target and compiles none of
the library, because all of it is templates in headers
(`include/fast_float/fast_float.h:33-37`). Everything below is what this fork had
to decide to turn that into something a C, C++ or Zig consumer can link.

| # | Deviation | What and why |
|---|---|---|
| B1 | **A compiled artifact exists at all** | A template has no symbol until something instantiates it in C++. `zig/bridge.cpp` is the only C++ translation unit: it includes `<fast_float/fast_float.h>`, calls `fast_float::from_chars<float>` and `<double>` once each, and classifies the result. Header-only upstream does **not** mean nothing to build. |
| B2 | **A C ABI that upstream has no equivalent of** | `zig/bridge.h` is plain C — no C++ types, no `enum class`, no defaults — so `addTranslateC` can read it with no C++ front end. It exports `ff_parse_f32`, `ff_parse_f64` and a three-valued `ff_status`, with `_Static_assert`s pinning the values. The status enum is this fork's spelling; upstream declares no enum because it has no C ABI. |
| B3 | **`-std=c++17`, pinned** | Upstream asks for C++11 (`FASTFLOAT_CXX_STANDARD` / `cxx_std_11`). C++17 is a strict superset and sits below the two thresholds that would switch upstream's own code paths: `float_common.h:13` includes `<stdfloat>` only above `__cplusplus > 202002L`, and `constexpr_feature_detect.h:17` turns on `FASTFLOAT_HAS_BIT_CAST` only for `__cpp_lib_bit_cast >= 201806L`. Leaving the standard to the compiler default would make the build depend on which clang Zig ships. |
| B4 | **The whole upstream header tree is installed beside the archive** | Upstream installs `include/fast_float` wholesale, so a C++ consumer of this package keeps getting `#include <fast_float/fast_float.h>` and can bypass the bridge entirely. |
| B5 | **No system-library mode** | A header-only library installs no binary. A "system" fast_float is a directory of headers: no installed ABI to bind to, no versioned symbol set to match, nothing for such a mode to select. There is deliberately no `b.systemIntegrationOption`; the rule is **vacuous here, not satisfied**, and [`UPSTREAM.md`](UPSTREAM.md) says so rather than presenting it as a passed mode. |
| B6 | **`test` gets a run step for every selected target** | `Target.Query.isNative()` is false for *every* query that names a target (`lib/std/Target/Query.zig:377-398` requires `cpu_arch`, `os_tag` and `abi` all null), so a guard on it meant `zig build test -Dtarget=x86_64-linux` compiled thirteen tests and ran none. What then happens to the run is the driver's: a host target executes, a foreign target executes through whatever executor is available, and a foreign target with no executor is build-only coverage and never a pass. |
| B7 | **`cross-test.profile.sh` raises two deadlines** | The corpus case reads 1,382,483 rows at two widths. The first full 53-platform sweep had three cells hit the harness's 300-second default. The profile sets `CROSS_BUILD_TIMEOUT=3600` and `CROSS_TIMEOUT=1800` and changes nothing else: no file dropped, no rows sampled, Debug not remapped. |
| B8 | **Static is the default, and one option selects the delivery** | `zig build` produces a static archive, which is what this package has always produced, and that stays the default. `-Dlinkage=static\|dynamic` selects the delivery. Upstream installs no library at all — its CMake target is `INTERFACE` — so both deliveries are this fork's own C ABI, versioned `0.1.0` and bumped only when `zig/bridge.h` changes incompatibly. The shared object's export closure is exactly `ff_parse_f32` and `ff_parse_f64`: a generated version script with `local: *` on ELF, a generated module definition on windows-gnu (a COFF DLL exports nothing without one), nothing on Darwin, and this build says so rather than implying parity it does not have. A target that cannot carry a shared object is **refused**, never substituted — see "Platform boundaries" |
| B9 | **The known-answer corpus is vendored** | `testdata/supplemental/` is a separate Apache-2.0 work, not upstream's tree and not under its triple. It is carried whole because `zig build test` reads it from disk at run time. |
| B10 | **Dispatch is a second option, orthogonal to delivery** | `-Druntime` (default off) makes each selected native entry point a call through one process-lifetime table that an explicit `load(source)` fills, instead of a link-line reference. The facade keeps the same translated header and the same public types; the dispatch itself is `runtime/graph.zig`, and `build_support/graph.zig` owns the single seam. `-Dlinkage` keeps deciding what is built and installed: under `-Druntime` that artifact is what a *provider is*, not something the module links. A linked build is unchanged in every respect |

### History

Every one of these, with its condition, its decision and its receipts, is in
[`CHANGELOG.md`](CHANGELOG.md); the problems that forced them are in
[`FORK-NOTES.md`](FORK-NOTES.md). The most recent entry is **25 — 2026-10-04**:
an error tag on this facade's `Error` set is not a bridge status, and two of the
four parse entry points prove it — `parse32Exact("1.5x")` is
`error.InvalidArgument` with `FF_STATUS_OK` behind it. Entry **24** records the
current native and runtime-loaded evidence, the withdrawal of a status that said
the runtime loader core was still elsewhere, and the lock file that now travels
with the package.

### Platform boundaries

| Target | Boundary |
|---|---|
| `wasm32-wasi` | its OS has no dynamic linker (`std.Target.DynamicLinker.kind` is `.none`, `lib/std/Target.zig:2385`), so a shared object there is a file nothing can load. `-Dlinkage=dynamic` is therefore **refused** for it: the build fails naming the target and the reason, nothing is compiled for it and nothing is substituted or relabelled. Inside `zig build check -Dlinkage=dynamic` that one matrix cell becomes a failing step carrying the reason, and the other five are still compiled |

The default is untouched and separate: no `-Dlinkage` means `static`, which is
exactly what `wasm32-wasi` takes, so `zig build check` with no flag still
compiles all six cells, `wasm32-wasi` included. The reason is resolved once, in
`build_support/graph.zig:sharedObjectRefusal`.

---

## 3. Current build, run and test matrix

### 3a. Observed before this migration — historical

These receipts predate the 2026-10 contract migration. They describe the tree as
it stood before the delivery option, the runtime-loading work and the Nix set
below were added. They are kept because they are what the corrections were made
against, not because they describe what ships today.

| Gate | Result then | Receipt |
|---|---|---|
| `test`, Debug | exit 0, 13/13; all 1,382,483 corpus lines at both widths | `local://foundation-cross-test-stable-fast_float-native-Debug.log` |
| `test`, ReleaseSafe | exit 0, 13/13, same corpus | `local://foundation-cross-test-stable-fast_float-native-ReleaseSafe.log` |
| `smoke` | exit 0, every printed bit pattern matched the value worked out in `smoke.zig` | the two logs above |
| consumer package | exit 0; eight constants, 7 bytes consumed, suffix `" m/s^2"` | `local://foundation-cross-test-stable-fast_float-native-consumer.log` |
| `install` | exit 0; `libfast_float.a` 770,530 bytes defining `ff_parse_f32` and `ff_parse_f64`, beside `fast_float_bridge.h` and the nine upstream headers | `local://foundation-expansion-fast_float-installed-artifact-gruenau8-176.log` |
| installed C surface | exit 0; C11 compile, link, run, both round-half-to-even ties and both rejection paths | `local://foundation-expansion-fast_float-installed-C-surface-181.log` |
| installed C++ surface | exit 0; a real `ff_parse_f64("9007199254740995", …)` returning `consumed == 16` and `2^53 + 4`, plus a direct `fast_float::from_chars` and its `invalid_argument` path | `local://foundation-expansion-fast_float-installed-upstream-Cpp-surface-corrected-extraction-196.log` |
| `check`, six targets | exit 0 for all six, 7/7 steps each | `local://foundation-cross-test-baseline-fast_float-{x86_64-linux-gnu,aarch64-linux-gnu,aarch64-macos-none,x86_64-windows-gnu,riscv64-linux-gnu,wasm32-wasi}.log` |
| `sha256sum -c UPSTREAM.sha256` | exit 0, 73 records, no failures | `local://foundation-expansion-fast_float-immutable-source-integrity-124.log` |
| pristine diff of `include` and the three licence texts against the pinned commit | exit 0, empty output | `local://foundation-expansion-fast_float-pinned-native-pristine-diff-269.log` |
| `cross-test`, 53 platforms, corrected deadlines | exit 0 — 20 executed with 13/13 each, 33 build-only with reason `runtime_unavailable`, 0 fail | `local://foundation-cross-test-corrected-fast_float.json` |
| `zig fetch` + in-package `sha256sum -c` + consumer run from the fetched copy | exit 0 — all 73 records `OK` in the materialised copy; consumer passed there too | `local://foundation-expansion-fast_float-materialized-package-integrity-335.log`, `-consumer-342.log` |
| `.github/workflows/verify.yml` `provenance` job | **never executed in this workspace.** A hand-run diff is not a green job | — |

The three red gates this package once had — a wrong long-significand oracle in
`tests.zig`, a wrong unit expectation in `consumer/src/main.zig`, and a `test`
step that ran nothing on a named target — were all corrections to the
expectations, not to the parser. Their diagnosis is `FORK-NOTES.md` notes 3, 4
and 14 and their receipts are kept.

### 3b. This migration — observed on this tree, and still pending

The driver ran the first block on **this** tree on 2026-10-04 and recorded
command, optimize mode, linkage, exit code, date and receipt for each gate;
every count in it is the count printed by the run named in its row. Those two
rows are the sixteen cells of `native-final-evidence/20261004T233628757747Z-69351/run.json`
(`route: native`) and `loaded-final-evidence/20261004T232823091897Z-23133/run.json`
(`route: loaded`), taken under `zig build test smoke install` with `-j8
--summary all`. The rows below the second table are the ones that had no gate
behind them; two of them have since been given one and say so.

| Gate | Observed result | Receipt |
|---|---|---|
| `test smoke install -Druntime=false`, both linkages, four optimize modes | **exit 0 for all eight** — `13/13 tests passed` in each, in a fully green `Build Summary`: `22/22` steps for the four static cells, `23/23` for the four dynamic ones. The corpus test printed all nine per-file line counts in every cell, so all 1,382,483 rows were consumed at both widths eight times over; `smoke` printed every bit pattern worked out in `smoke.zig`'s own comment; and `install` wrote into a prefix outside the repository, its step list naming `lib/pkgconfig/fast_float.pc` and all eight records under `share/licenses/fast_float/`. The four dynamic cells name their artifact in the configure line — `shared object, soname libfast_float.so.0 exporting only the two bridge entry points` | `local://foundation-current-native-index.json`, rows `fast_float-current-native-{dynamic,static}-{Debug,ReleaseSafe,ReleaseFast,ReleaseSmall}` |
| `test smoke install -Druntime=true`, both linkages, four optimize modes, provider named by `FASTFLOAT_PROVIDER` | **exit 0 for all eight** — `13/13 tests passed` in each, `23/23` steps for the four static cells and `24/24` for the four dynamic ones. Every configure line states `runtime-loaded dispatch (-Druntime=true); no library is linked into the module`; `smoke` reports `runtime-loaded build` and prints the provider path it resolved; and `tests.zig`, which stops by name when `FASTFLOAT_PROVIDER` is unset, read all nine corpus files at both widths in all eight cells, so the suite answered through the dispatch rather than beside it. The four static cells also print the reason a static artifact cannot serve as a provider: an archive is a file a loader cannot open, so a provider has to be a shared object | the same index, rows `fast_float-current-loaded-{dynamic,static}-{Debug,ReleaseSafe,ReleaseFast,ReleaseSmall}` |
| the provider those eight loaded runs used | **This tree's own shared object, named by absolute path** — the `libfast_float.so` the four dynamic runs installed into their prefix. No row above covers a provider this tree did not build, or one named by basename, and neither is claimed | the same sixteen per-gate files, each recording its own `FASTFLOAT_PROVIDER` |

| Gate | State |
|---|---|
| `check` over the six required targets, compile-only, against this tree | **observed.** Row `baseline-fast_float-check` of `baselines-and-configs/20261005T014547Z-797a73f2`, 2026-10-05: exit 0, `Build Summary: 32/32 steps succeeded`, `declared_target_count 6`, all six triples named in the run's own step lines, `test_pass_lines: []`. The six `check` rows in §3a stay as history for an earlier tree. This row runs nothing and derives no runtime result under any exit code |
| `check -Dlinkage=dynamic` refusing `wasm32-wasi` while the other five cells compile | PENDING-VERIFICATION. The refusal is stated from the build graph; no such cell has been run |
| the shared object's export table read from the artifact, and the Darwin and windows-gnu deliveries | PENDING-VERIFICATION. The soname and the export closure above are the build graph's own printed statement; nothing in these receipts reads an installed object with `nm`, `objdump` or `dumpbin`, and no Darwin or windows-gnu delivery has been installed on this host |
| typed and raw Zig consumers, own and external, in both linkages and under `-Druntime` | PENDING-VERIFICATION |
| installed C consumer and installed C++ consumer against the prefixes those sixteen runs wrote | PENDING-VERIFICATION |
| fetched, manifest-filtered Zig consumer | PENDING-VERIFICATION |
| canonical `devenv` shell | PENDING-VERIFICATION |
| `nix build .#static` and `nix build .#shared`, and the output dependency records | PENDING-VERIFICATION |
| `cross-test` full 53-platform matrix | **observed.** Receipt `20261004T221720228710Z-45046/fast_float-53-target-8.json`, 2026-10-04: **exit 0**, `status: partial`, raw `pass=20 fail=0 build_only=33 partial=0`, `source_stamp_before == source_stamp_after` (`bc692cd7…`), `zig_version 0.16.0`, `mode zig-build`, `target_count 53`, `target_jobs 8`, `jobs_per_build 8`. Every executed cell reports `tests=13`. Thirty-three `build_only` cells compiled and ran nothing because no executor was available; that is compile evidence, not a runtime pass, and the counts are bounded to that source epoch |
| system-library mode | **not applicable** — see B5. Vacuous, not passed |

---

## 4. Consumption

### Zig

```zig
// build.zig.zon
.dependencies = .{
    .fast_float = .{ .path = "../fast_float" },
},
```

```zig
// build.zig
const dep = b.dependency("fast_float", .{ .target = target, .optimize = optimize });
exe_mod.addImport("fast_float", dep.module("fast_float"));
```

```zig
const fast_float = @import("fast_float");

// 0.1 has no binary expansion, so this is the nearest double,
// 0x3FB999999999999A, worked out by exact rational rounding.
const tenth: f64 = try fast_float.parse64Exact("0.1");

// A prefix is a successful parse. `consumed` is the first byte that was *not*
// the number, so the separating space belongs to what follows.
const scanned = try fast_float.parse64("9.80665 m/s^2");
const unit = "9.80665 m/s^2"[scanned.consumed..];

const parsed = fast_float.parse64("not a number") catch |err| switch (err) {
    error.InvalidArgument => return,   // nothing matched
    error.ResultOutOfRange => return,  // it matched, and rounded to inf or 0
    error.StatusNotRecognised => unreachable,
};
```

`consumer/` is exactly this, in working form, as a separate package that reaches
this one by relative path. The full interface, its error and out-parameter
contract, and the raw `pub const c` surface are in
[`README.zig.md`](README.zig.md).

### Runtime loading

`-Druntime` builds the same facade over a dispatch that resolves the bridge's
entry points through one process-lifetime table instead of a link line. The
caller names the provider explicitly, by absolute path or by basename for the
platform loader, and then calls the facade normally:

```zig
const fast_float = @import("fast_float");

try fast_float.load(.{ .path = "/path/to/libfast_float.so.0" });
const tenth: f64 = try fast_float.parse64Exact("0.1");
```

There is no default provider, no search path and no fallback to a linked copy: a
build that was not told which file to load says so rather than loading
something else. `-Dlinkage` is orthogonal and still decides what is built and
installed — under `-Druntime` that artifact is what a provider *is*.

The route's own six sources are in this repository and travel with the package:
`runtime/graph.zig`, `runtime/library.zig`, `runtime/loader.zig`,
`runtime/generate.zig`, `runtime/sync.c` and `runtime/sync.h`. `runtime/` is in
`build.zig.zon` `.paths`, all six carry this fork's SPDX triple on line 1, and
all six are named in [`FORK-LICENSE.md`](FORK-LICENSE.md) and
[`NOTICE.md`](NOTICE.md). The gate has now run for the native host: eight
`-Druntime` configurations — both linkages in all four optimize modes —
compiled, tested, smoked and installed with exit 0, each reaching the provider
it was given and answering the whole known-answer corpus through the table
(§ 3b). What those runs do not reach is named there too — the provider was this
tree's own shared object named by absolute path, and no basename-named provider,
no external provider and no failure, retry or idempotence path has been
exercised here.

The three programs this repository ships all take the provider the same way:
`smoke.zig` reads `--provider <path>` or `FASTFLOAT_PROVIDER`, and
`tests.zig` reads `FASTFLOAT_PROVIDER` from the environment and stops by name if
it is unset. Arguments reach the smoke program through
`zig build smoke -Druntime=true -- --provider <path>`, and the consumer package
forwards both the option and its run arguments, so
`cd consumer && zig build run -Druntime=true -- --provider <path>` works the same
way.

### C and C++

`zig build` installs the archive, `fast_float_bridge.h`, the whole upstream header
tree and a generated `lib/pkgconfig/fast_float.pc` into `zig-out/`. A C consumer
includes the bridge header and links what `pkg-config --libs --static` reports —
the C++ runtime for a static archive, nothing extra for a shared one that has it
linked in. A C++ consumer can include `<fast_float/fast_float.h>` and use
`fast_float::from_chars` directly, without the bridge at all.

`-Dlinkage=dynamic` installs `libfast_float.so.0.1.0` with soname
`libfast_float.so.0` and `libfast_float.so` beside it on ELF,
`libfast_float.0.dylib` on Darwin, `fast_float.dll` plus `fast_float.lib` on
windows-gnu. `wasm32-wasi` cannot carry one and the build refuses rather than
substituting, as recorded under "Platform boundaries".

```c
#include <fast_float_bridge.h>
float value; size_t consumed;
if (ff_parse_f32(first, last, &value, &consumed) == FF_STATUS_OK) { /* … */ }
```

**One asymmetry a C caller must know.** On `FF_STATUS_OK` and on
`FF_STATUS_RESULT_OUT_OF_RANGE` both out-parameters are written; on
`FF_STATUS_INVALID_ARGUMENT` neither is. That is upstream's behaviour, not the
bridge's: `include/fast_float/parse_number.h:288` stores through `to_float`
before the range test at `:290-292`, so by the time upstream reports
`result_out_of_range` the value is already in your variable.

The typed surface draws a second line over this one. `parse32Exact` and
`parse64Exact` return `error.InvalidArgument` for a trailing tail with **no**
bridge status behind it, because that refusal is the facade's own
`consumed != bytes.len` check rather than anything upstream reported; the error
table in [`README.zig.md`](README.zig.md) gives the whole mapping.

### Nix

`package.nix` is one uncurried function returning one derivation. `flake.nix` and
`devenv.nix` both call it through `pkgs.callPackage` with
`zig = pkgs.zig_0_16`, so the two entry points cannot drift.

`flake.lock` is committed in this repository and is listed in
`build.zig.zon` `.paths`, so it travels with the package: it pins exactly the
`github:NixOS/nixpkgs/c7def046b9a883d46974757852106483d741586f` `flake.nix`
declares, together with that revision's `narHash`. A dependent who fetched this
package therefore resolves this nixpkgs rather than the one its machine happens
to carry. `devenv.lock` is not in this tree and is not named anywhere;
`devenv.yaml` states what it must pin when it is created.

```
nix build .#static     # this SDK's existing linkage policy
nix build .#shared     # the same SDK, delivered as a shared archive
nix develop            # toolchain only, for a machine without devenv
```

The two variants are one SDK with one delivery option, not two SDK modules. Each
output carries exactly what `zig build install` installs, because `zig build
install` is what installs it: the archive, `fast_float_bridge.h`, the upstream
header tree, `lib/pkgconfig/fast_float.pc` with a relocatable `prefix`, and the
full licence set — upstream's three texts, [`NOTICE.md`](NOTICE.md),
[`FORK-LICENSE.md`](FORK-LICENSE.md), [`UPSTREAM.md`](UPSTREAM.md),
[`README.upstream.md`](README.upstream.md) and the corpus's own Apache-2.0 text
under the distinct name `testdata-supplemental-LICENSE`. One writer per path:
the derivation adds no copy that could disagree with the graph's.

The known-answer corpus is **not** installed into `$out`: it is 262 MB of test
fixtures that no runtime consumer reads. It stays in the derivation's source,
where `zig build test` can reach it.

No Nix output is claimed to be a wholly static closure. The dependency record is
whatever `nix-store --query --references` reports on a realised build, and that
report has not been taken.

### Development

`devenv` is the canonical environment; `devenv shell` and, where direnv is
installed, `.envrc` both enter it. The shell carries tools and tasks, never the
SDK: `outputs.static` and `outputs.shared` are lazy, so entering the shell builds
nothing, and `devenv build outputs.static` is the packaging route.

```
devenv shell sdk:install            # zig build install, into a prefix outside this tree
devenv shell sdk:test               # zig build test, optionally -Dtarget=...
devenv shell sdk:smoke
devenv shell sdk:check
devenv shell provenance:integrity   # sha256sum -c UPSTREAM.sha256
devenv shell sdk:consumer
devenv build outputs.static         # the Nix package
devenv build outputs.shared
```

Each of those tasks changes into this repository's own directory before it runs
anything, from a path `devenv.nix` evaluates rather than one it reads out of the
environment. `devenv --from path:<this repository>` runs the generated wrapper
with the *project* directory as its current directory, and `DEVENV_ROOT` names
that project — a directory holding no `build.zig`, no `UPSTREAM.sha256` and no
`consumer/` — so a task that trusted `DEVENV_ROOT` searched for this
repository's inputs where this repository is not. The two Nix entry points,
`package:static` and `package:shared`, read no file in this tree and are
unchanged.

`sdk:install` delivers to a prefix **outside** this working copy. It defaults to
`$ZIG_LOCAL_CACHE_DIR/fast_float-install`, falls back to
`$TMPDIR/zig-local-cache/fast_float-install` when the caller exported no Zig
local cache, and takes `PREFIX=...` for anything else. If neither variable is
set it stops and says so: there is then no external location it may write to,
and `zig-out/` inside this repository is not one. `"$@"` reaches `zig build`
unchanged in every task, so `-Dtarget=`, `-Doptimize=`, `-Dlinkage=`, `-j8` and
`--summary all` pass through exactly as they did.

Every one of those five `zig build` commands names its own flags before `"$@"`:
`-j8`, `--summary all`, and `--cache-dir "$ZIG_LOCAL_CACHE_DIR"` pointing at the
cache that command's own preamble resolved. The placement is the point — `"$@"`
is still last, so a caller who passes `-jN`, `--summary` or a `--cache-dir` of
their own still has the last word, since Zig's build runner reads the last
occurrence of each and every one overwrites the one before it
(`lib/compiler/build_runner.zig:422-427` in the pinned 0.16.0 compiler). The
steps, the single `--prefix` and the `"$@"` forwarding are otherwise unchanged.

`sdk:install` is the only one of these that needs that treatment, and that is a
fact about this repository's step graph rather than a preference. The install
step depends on the smoke executable, not the reverse (`build.zig:204`), and
`smoke` (`:212`), `test` (`:245`) and `check` (`:247-257`) each depend on their
own compile or run step alone, as the consumer's `run` depends on its
executable alone (`consumer/build.zig`). None of them reaches an install step,
so none of them writes a delivery output and none of them is handed a `--prefix`
it does not need.

Cache and scratch locations are the caller's to supply. Each task body resolves
both Zig cache directories before its compiler starts, because
`devenv tasks run --mode single <name>` executes a body without the
`enterShell` hook and the rule therefore cannot live only in the hook. A
variable the caller already exported is kept; a missing one is filled from
`XDG_CACHE_HOME` and then from `$TMPDIR`, under this SDK's existing names —
`zig-global` and `zig-local`, `zig-global-cache` and `zig-local-cache` — and a
caller who named neither is told which variables to export and stops there,
rather than getting a `.zig-cache` inside this tree. `enterShell` still applies
the same `XDG_CACHE_HOME` default to an interactive session, and neither it nor
any task body ever unsets a caller's value; no Nix file in this repository names
a host account, a node, a store path or a scratch mount.

---

## 5. Where everything else is

| File | What it holds |
|---|---|
| [`README.upstream.md`](README.upstream.md) | upstream's README, byte for byte, including its own triple-licence grant and the Wuffs credit |
| [`README.zig.md`](README.zig.md) | the Zig interface: the API, the format, the error and out-parameter contract, the C ABI, build modes, testing approach, integrity, licences |
| [`UPSTREAM.md`](UPSTREAM.md) | the pinned ref, the archive receipt, what is upstream's and what is the fork's, system-library mode, how to re-sync |
| [`NOTICE.md`](NOTICE.md) | upstream attribution, all three grants, the corpus inventory, the Apache-2.0 obligations, every file this fork adds or edits |
| [`FORK-LICENSE.md`](FORK-LICENSE.md) | the actual grant for the files this fork authored, its authorization, and what it does not cover |
| [`UPSTREAM.sha256`](UPSTREAM.sha256) | 73 digests over the immutable upstream and donor bytes |
| [`CHANGELOG.md`](CHANGELOG.md) | numbered fork-only divergences, newest last |
| [`FORK-NOTES.md`](FORK-NOTES.md) | the problems met and what each one forced |
| [`testdata/README.md`](testdata/README.md) | the known-answer corpus: provenance, credit, format, line counts, the independent cross-check |
| `LICENSE-APACHE`, `LICENSE-MIT`, `LICENSE-BOOST` | upstream's three licence texts, verbatim and distinct |