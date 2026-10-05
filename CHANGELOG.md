# CHANGELOG — fork-only divergences

Upstream's release history lives in its own repository. This file records **only**
what this fork changed relative to fast_float `8.3.0`
(`b0ab987b3dfdde13fa1915f65ef2a5c068d9208c`), and it is written so a re-sync can
replay it. Numbers are stable identifiers; never renumber them.

Statuses below are the workspace's: **observed** means the driver ran a gate and
the output is in the named receipt; **pending** means the change has landed and
no gate has looked at it yet; **not run** means no receipt exists at all.
Receipts are named in full at least once and by `…-` prefix thereafter; the
prefix is `local://foundation-expansion-fast_float` for this fork's own gates.

## 1. Added the Zig 0.16 package

`build.zig`, `build.zig.zon`, `build_support/graph.zig`, `zig/bridge.h`,
`zig/bridge.cpp`, `zig/root.zig`, `tests.zig`, `smoke.zig`, `consumer/` and
`.github/workflows/verify.yml` are new. New module: `fast_float`. New artifact:
`libfast_float.a`, plus the installed `fast_float_bridge.h` and the whole
upstream header tree under `zig-out/include/fast_float/`. `build.zig.zon`
declares no dependencies and nothing is downloaded. No upstream source, test,
licence or fixture file is touched.

## 2. Wrote a real C ABI bridge instead of re-exporting the templates

**Decision.** `fast_float::from_chars` is a template
(`include/fast_float/fast_float.h:33-37`), so it has no symbol to link against
and `zig translate-c` cannot see it. `zig/bridge.cpp` is the only C++ translation
unit in the package: it includes `<fast_float/fast_float.h>`, instantiates
`from_chars<float>` and `from_chars<double>` at their own calls, and classifies
the returned `std::errc` into the three `ff_status` values. No parsing, rounding
or range logic is written there.

**Why this matters for a header-only library.** Upstream compiles none of the
library itself — `CMakeLists.txt` declares an `INTERFACE` target. The archive
this package installs is real compiled upstream code, built on every target of
the required matrix, not a shim or a stub.

**Status.** `observed` — the install gate produced it
(`local://foundation-expansion-fast_float-native-install-40.log`, exit 0), and
again into an approved prefix outside the repository later
(`…-fast_float-installed-artifact-gruenau8-176.log`, exit 0). The installed
archive is 770,530 bytes and defines `ff_parse_f32` and `ff_parse_f64` with C
linkage.

## 3. Pinned the C++ standard to `-std=c++17`

Upstream sets `FASTFLOAT_CXX_STANDARD` to 11 and asks for `cxx_std_11`. C++17 is
a strict superset of that and is still below the two thresholds that would switch
upstream's own code paths: `include/fast_float/float_common.h:13` includes
`<stdfloat>` only when `__cplusplus > 202002L`, and
`include/fast_float/constexpr_feature_detect.h:17` enables
`FASTFLOAT_HAS_BIT_CAST` only for `__cpp_lib_bit_cast >= 201806L`, a C++20
library feature. Leaving the standard to the compiler default would make the
build depend on which clang Zig ships, and a future default bump to C++20 would
switch upstream's algorithm with no change in this repository.

**Status.** `observed` on the native host and on all six cross targets, each
compiled with `-std=c++17`: `…-matrix-x86_64-linux-gnu-133.log`,
`-aarch64-linux-gnu-137`, `-aarch64-macos-none-140`, `-x86_64-windows-gnu-143`,
`-riscv64-linux-gnu-146`, `-wasm32-wasi-149`, all exit 0. Compiled, not run.

## 4. Declared no system-library mode, and said so

**Decision.** There is no `b.systemIntegrationOption` and no system branch. A
header-only library installs no binary, so a "system" fast_float is a directory
of headers: no installed ABI to bind to, no versioned symbol set to match, and
nothing for a system mode to select. The rule is **vacuous for this fork rather
than satisfied by it**, and `UPSTREAM.md` § "System-library mode" states that
with the reason. A flag that is never read is a claim; a flag that is read and
always takes the bundled path is worse.

**Status.** `source-confirmed` (`build.zig:14-19`, `build_support/graph.zig:16-20`).
Not applicable, so no gate can be run for it and none is claimed.

## 5. Vendored the independent known-answer corpus

`testdata/supplemental/` is a copy of `fastfloat/supplemental_test_files` at
commit `088643e8d5010bd3d1540fe48685601b43b9a3e5` — the same corpus upstream's
own `tests/basictest.cpp` reads. It is **not** under upstream's licence triple:
it is a separate work with a single Apache-2.0 grant, the data credited to
Nigel Tao in the corpus's own vendored `supplemental/README.md`. It is carried
in `.paths` because a consumer that runs `zig build test` needs the fixture
bytes to be there.

Thirteen data files, 5,268,191 lines, 274,299,340 bytes. Fifteen files in the
directory are donor bytes, vendored byte for byte; the sixteenth,
`supplemental/LICENSE`, was sourced by this fork from the producer's own copy of
the Apache-2.0 text at the URL the donor README names, because the donor
repository ships no licence of its own. See entry 12.

`testdata/README.md` (fork-authored) records the provenance and credit, the
per-file line counts, the column format measured over all 5,268,191 lines, the
range-outcome convention, and an independent two-way cross-check of every
recorded bit pattern — including the sixteen lines where NumPy's binary32
conversion and an exact rational round-half-to-even conversion disagree, and
where the exact rational conversion is the one that agrees with the corpus.

**Status.** `observed` — the Debug and ReleaseSafe receipts both print the
per-file line count of all nine files read, so the corpus is present, complete
and at the recorded sizes, and `sha256sum -c UPSTREAM.sha256` covers all
sixteen vendored files.

## 6. Appended Zig entries to `.gitignore`

Upstream's own ignore list is kept verbatim and unedited; the fork appends
`.zig-cache/`, `zig-cache/`, `zig-out/`, `consumer/.zig-cache/`,
`consumer/zig-cache/` and `consumer/zig-out/`, each with a comment saying why.
This is the only upstream file this fork edits, so it is deliberately absent
from `UPSTREAM.sha256` and from `verify.yml`'s diff list; the append is recorded
in `NOTICE.md` instead.

**Status.** `source-confirmed`.

## 7. Wrote this fork's own `verify.yml` and left upstream's twenty-one others alone

Upstream drives GitHub Actions, Cirrus, Travis and AppVeyor on the upstream
maintainers' own infrastructure. None of those twenty-one workflows is
retargeted. `.github/workflows/verify.yml` is new, names only this repository,
and has five jobs: provenance (licence texts, pinned commit, upstream diff),
native (build, both test modes, smoke, whole-matrix check), c-surface (the
*installed* C and C++ surfaces compiled, linked and run from outside the build
graph), cross (the six required targets, one job per target, `fail-fast: false`,
no `continue-on-error`, no pre-judgement) and consumer.

**Status.** `source-confirmed` (read out of the file). The `c-surface` job
itself has not run here, but both of its two translation units have been
compiled, linked and run by hand against the installed headers and archive —
see entry 14. The `provenance` job itself has never been executed here either,
and still is not reported as run: it reads git history. The pristine diff it
performs has since been run directly over four path groups — see entry 17,
which also lists what the job still does that the direct diff did not.

## 8. Added the provenance, integrity and documentation set

`UPSTREAM.md`, `UPSTREAM.sha256` (73 records), `NOTICE.md`, `README.zig.md`,
`CHANGELOG.md`, `FORK-NOTES.md`, `testdata/README.md`.

`UPSTREAM.sha256` hashes the immutable bytes the package compiles or reads:
upstream's nine library headers, upstream's 48-file C++ test tree, and the
sixteen vendored corpus files — fifteen vendored from the donor, plus the
separately sourced Apache-2.0 text (entry 12) — including the four the tests
deliberately do not read. It does not hash the fork's own files, `.gitignore`
(appended to), itself, or any build output, and it does not hash the three
upstream licence texts — `verify.yml`'s provenance job already diffs those three
by name against the pinned commit, which is a stronger statement than a digest
of the working tree.

**Method.** Each file was read as raw bytes with
`Bun.file(path).arrayBuffer()` and hashed with `createHash("sha256")` from
`node:crypto`, on 2026-10-01. No shell hashing command and no git command was
used. All 73 records were then re-derived from the written file and compared
against the tree, and the path set was compared against a fresh walk of the three
subtrees, before these documents were written.

**Status.** `observed` — `sha256sum -c UPSTREAM.sha256` reports 73 records and
no failures
(`local://foundation-expansion-fast_float-immutable-source-integrity-124.log`).

## 9. Manifest integration, closed: `UPSTREAM.sha256` is in `.paths`

`build.zig.zon` `.paths` originally listed the five fork records but not
`UPSTREAM.sha256`, so `sha256sum -c UPSTREAM.sha256` worked in this repository
and in a clone but a dependent who fetched the package did not receive the
record — and a record naming files the package does not ship would fail anyway.

**Done.** `.paths` now lists `"UPSTREAM.sha256"` next to the other fork
records, so the check travels with the package.

**Status.** `observed`.

## 10. Two wrong expectations in the fork's own test files, both corrected

Neither was a parser defect. Both were corrected in the test files, and both
gates re-run; the red receipts are kept, because the wrong oracle and the red
run are the record of what was replaced.

1. **`tests.zig:381` — long-significand rounding oracle, withdrawn.** The test
   parsed `9007199254740995` (`2^53 + 3`) and expected `0x4340000000000001`
   (`2^53 + 2`, significand field `1`, odd). The input is exactly halfway
   between `2^53 + 2` and `2^53 + 4` (`0x4340000000000002`, significand field
   `2`, even), so round-half-to-even must land on the even one. The test's own
   comment three lines above the literal already said so, and the literal
   contradicted it. The red receipt read `expected 4845873199050653697, found
   4845873199050653698` — the parser was right.

   **The oracle `0x4340000000000001` is withdrawn, not relaxed.** The single
   literal changed to `0x4340000000000002`; no bound was widened and no new cap
   was introduced. The assertions either side are untouched, so the test still
   pins `2^53 + 2 → 0x…01` and `2^53 + 4 → 0x…02`. The tie was derived
   independently of this parser in
   `local://foundation-expansion-float-tie-proof.json`, and the same value came
   back out of the installed archive from C++ (entry 14).

   **Status.** `observed` red at 12/13 in both modes
   (`…-corrected-debug-38.log`, `…-corrected-releasesafe-41.log`), then green at
   13/13 in both (`…-final-debug-97.log`, `…-final-releasesafe-100.log`), with
   the corpus test consuming all 1,382,483 lines at both widths and printing all
   nine per-file line counts.
2. **`consumer/src/main.zig` — unit-separator whitespace.** The measurement is
   `"9.80665 m/s^2"`; the parse correctly reports `consumed == 7`
   (`"9.80665".len`), so the tail from `consumed` is `" m/s^2"` **with** its
   separating space, and the consumer compared it against `"m/s^2"`.

   **Done.** `consumed` is now checked separately against `"9.80665".len`, and
   the tail is compared against the tail that is really there. Nothing is
   trimmed and the fixture is unchanged, and the same line is then sent through
   `parse64Exact`, which must refuse it.

   **Status.** `observed` red — `…-corrected-consumer-46.log`, exit 1,
   `error.UnitMismatch` after all eight constants matched — then green:
   `…-consumer-repair-proof-112.log`, exit 0, reporting
   `7 bytes consumed, suffix " m/s^2"`.

## 11. The six cross-target compiles, all run

`zig build check -Dtarget=<triple>` for `x86_64-linux-gnu`,
`aarch64-linux-gnu`, `aarch64-macos-none`, `x86_64-windows-gnu`,
`riscv64-linux-gnu` and `wasm32-wasi`, one command each, no target skipped and
none pre-judged. The exact commands are in `README.zig.md`.

**Status.** `observed` — all six exit 0 at 7/7 steps:
`…-matrix-x86_64-linux-gnu-133.log`, `-aarch64-linux-gnu-137`,
`-aarch64-macos-none-140`, `-x86_64-windows-gnu-143`, `-riscv64-linux-gnu-146`,
`-wasm32-wasi-149`. Compile evidence only: no foreign binary was run, because no
emulator and no cross linker is assumed.

## 12. Corrected the corpus licence provenance in every record

**Correction.** The records used to describe `testdata/supplemental/` as sixteen
files "vendored byte for byte" from `fastfloat/supplemental_test_files` at
`088643e8d5010bd3d1540fe48685601b43b9a3e5`, with `LICENSE` among the donor
files, and to lump the corpus under upstream's licence triple.

**What is actually true.** The donor repository at that commit has **fifteen**
files — thirteen data files, `README.md` and `CMakeLists.txt` — and **no
`LICENSE` of its own**. `testdata/supplemental/LICENSE` is therefore not a donor
byte: it is the Apache-2.0 text this fork took from the producer's own copy at
the URL the donor's `README.md` names. It is byte-distinct from this
repository's `LICENSE-APACHE` (11,323 bytes against 10,767; the fork's copy
carries upstream's copyright line, the corpus copy does not). The corpus is a
separate work under a **single** Apache-2.0 grant — the data credited to Nigel
Tao in the corpus's own README — and is **not** under upstream's triple, which
is unchanged.

**Records corrected.** `NOTICE.md`, `UPSTREAM.md`, `FORK-NOTES.md` (new note 12),
`README.zig.md` and `testdata/README.md` all now say the same thing in the same
shape: fifteen donor files, plus one separately sourced licence text, sixteen
hashed records. The four `remyoudompheng-fptest-*.txt` files this fork carries
but does not read are stated to be inside the same grant, so their licence is
answered rather than assumed.

**No vendored byte changed.** This is a correction to what the records *claim*,
not to what the tree contains; only fork-authored documentation was edited, and
`sha256sum -c UPSTREAM.sha256` still reports 73 records and no failures.

**Status.** `source-confirmed` from the vendored directory, the file sizes, the
differing digests of the two Apache-2.0 texts, and the dates on the sixteen
files.

## 13. Withdrew the invented licence grant for this fork's own files

**Withdrawn.** The records previously stated that everything this fork wrote —
the Zig build graph, the facade, the C ABI bridge, the tests, the example, the
consumer package and the documentation — was "a new contribution … offered under
the Apache-2.0 grant" already shipped here. Nobody authorised this fork to make
that grant, so the claim is withdrawn rather than left standing.

**What replaces it.** `NOTICE.md` and `README.zig.md` now record the licence of
those files as **unassigned**: no term is stated, and none may be inferred from
its absence. Nothing else moved — the three upstream licence texts still ship
verbatim and are still named in `NOTICE.md`; the corpus licence text still
sits beside the corpus; the change statement, the attribution and the
Apache-2.0 §4 obligations owed by the two carried works are all still recorded.
Those duties are owed to the works being redistributed, not to the
redistribution, so they are met either way.

**Status.** `observed`, by reading the current `NOTICE.md` and `README.zig.md`.

## 14. Proved the installed C++ surface with a real bridge call

**Addition to `verify.yml`'s `c-surface` job.** The C++ translation unit now
also calls the bridge, not only upstream's C++ API: `ff_parse_f64` on the
16-byte string `"9007199254740995"` must return `consumed == 16` and
`9007199254740996.0` — the round-half-to-even tie from entry 10, reached
through the exported C ABI from a C++ caller. It still makes a direct
`fast_float::from_chars` call, including upstream's own
`std::errc::invalid_argument` path, so both halves of the install are proved
independently.

**This is compile, link and run evidence, not an include-only check.** A
declaration that merely exists would satisfy an `extern` link line; only a call
that returns the right value rules out a declaration the archive does not
define and a bridge that does not round correctly.

**Status.** `observed` —
`local://foundation-expansion-fast_float-installed-upstream-Cpp-surface-corrected-extraction-196.log`,
exit 0, compiled and linked against the installed headers and archive from
outside the build graph. The C half is
`…-fast_float-installed-C-surface-181.log`, also exit 0. The install they
consume is `…-fast_float-installed-artifact-gruenau8-176.log`, exit 0, into an
approved prefix outside the repository.

## 15. Corrected the fixture-path description

The `build.zig.zon` comment now describes the corpus as runtime data located
through the generated `fast_float_paths` module, rather than an `@embedFile`
input. The data files, path resolver and parsing checks are unchanged.

## 16. Fetched this package and consumed the materialised copy

`zig fetch` was run over this package's absolute path from a separate scratch
build root outside this repository, that root carrying its own `build.zig` and
`build.zig.zon`, with `--global-cache-dir` pointing at the driver's own package
cache. It exits 0 and prints the package identity:

```
fast_float-8.3.0-IdJv95QQZhDN1SQSHpQFuzW1cE-hqYLTHqBmiM9QW4yG
```

What it copied is the manifest-filtered package — exactly what `build.zig.zon`
`.paths` names, and nothing else from this tree. Two gates then ran against
that copy rather than against this working tree.

* **`sha256sum -c UPSTREAM.sha256` inside the materialised package** — exit 0,
  all 73 records `OK`. This is the `.paths` closure claim, and entry 8's
  in-tree run cannot make it: a checkout can hold a file the manifest does not
  list, so the record has to be checked where a dependent keeps it. Every path
  the record names — the nine upstream headers, the 48-file upstream C++ test
  tree and the sixteen vendored corpus files — is present in the filtered copy
  and is the byte this repository holds. No fixture value changed to produce
  this; nothing under `include/` or `testdata/` was touched.
* **`consumer/` built and run from inside the materialised copy** — exit 0. The
  consumer's relative `.path` dependency resolved against a package this
  repository's build graph never produced, so the boundary crossed here is the
  one a dependent crosses. The receipt ends with all eight constants at the
  bit patterns worked out in `consumer/src/main.zig`, `9.80665 m/s^2` reporting
  7 bytes consumed and the suffix `" m/s^2"`, and the exact-parse and
  leading-`+` refusals behaving as written.

Nothing in this entry is a publication claim. The fetch is over a local
absolute path: no URL, registry, git remote or published hash was resolved, no
publication has been authorised, and the identity string above is what this
compiler printed for this directory — not a hash a downstream can fetch today.

**The earlier failure is kept as history.** Run from the package source root,
the same absolute path failed with
`error: unable to copy directory '/vol/fob-vol7/mi19/gertullj/foundation-libs/fast_float': IllegalFileTypeInPackage`
(`…-fast_float-materialized-package-fetch-262.log`, exit 1). No byte of this
tree changed between the two runs; the working directory did. Which of those
differences made the difference is not established here, and nothing is
generalised from it to any other tree, host or filesystem.

**Status.** `observed` — the fetch
(`local://foundation-expansion-fast_float-external-driver-package-fetch-326.log`,
exit 0, identity recorded verbatim), the in-package integrity run
(`…-fast_float-materialized-package-integrity-335.log`, exit 0) and the
in-package consumer
(`…-fast_float-materialized-package-consumer-342.log`, exit 0).

## 17. Ran the pristine-commit diff directly, and left the CI job unrun

The diff `.github/workflows/verify.yml`'s `provenance` job performs was run by
hand over the paths this fork edits or would be suspected of editing:

```
git diff --exit-code b0ab987b3dfdde13fa1915f65ef2a5c068d9208c -- \
    include LICENSE-APACHE LICENSE-BOOST LICENSE-MIT
```

It exits 0 with empty output: upstream's nine library headers and its three
licence texts in this working tree are byte-identical to the pinned commit. It
is read-only — it changed nothing and asks nothing of the fixtures.

**This is not the job, and it does not stand in for it.** The job additionally
requires the pinned commit to be present in the clone, checks that the fork's
records are present and non-empty, greps `README.md` and `NOTICE.md` for the
three licence names, and diffs a wider path list than the four groups above —
`tests benchmarks cmake ci docs script fuzz`, `CMakeLists.txt`, `BUILD.bazel`,
`MODULE.bazel`, `.bazelrc`, `.clang-format`, `clang-format-ignore.txt`,
`AUTHORS`, `CONTRIBUTORS`, `README.md`, `SECURITY.md`. Those paths are
**uncompared** by the direct diff. **The job itself has still never been
executed**: no run of this repository's CI has produced anything, and this
entry does not change that. A green hand-run diff is not a green job.

**Status.** `observed` for the direct diff
(`local://foundation-expansion-fast_float-pinned-native-pristine-diff-269.log`,
exit 0, empty output). `not run` for the `provenance` job, as it was before.

## 18. `test` runs on every selected target, not only an unnamed one

**Decision.** `build.zig` no longer branches on `target.query.isNative()`. The
`test` step attaches a run step to the compiled test binary unconditionally, for
the host and for every foreign target alike.

**Why the branch was wrong.** In Zig 0.16 `std.Target.Query.isNative()` is
`isNativeTriple() and ofmt == null` (`lib/std/Target/Query.zig:396-398`), and
`isNativeTriple()` requires `cpu_arch`, `os_tag` **and** `abi` to be null
(`:392-394`, with `isNativeCpu`/`isNativeOs`/`isNativeAbi` at `:377-390`). Any
`-Dtarget=<triple>` fills at least the first two in, so the branch was false for
every explicitly targeted build — including `x86_64-linux` on an x86_64 Linux
host. The old comment claimed `standardTargetOptions` was the thing that could
not see `-Dtarget`; the query behind `isNative()` cannot see it either, and that
is the same bug one level down.

**Observed, before this change.** `cross-test --no-profile --targets
x86_64-linux --jobs 1 --build-jobs 4 --build-timeout 900` exited 1 with
`build=pass`, `run=fail`, `reason=no_test_results`. Its build log shows
`Build Summary: 6/6 steps succeeded` with `compile test fast_float-tests Debug
x86_64-linux success` under `test success` and **no `run test` step anywhere in
the tree**: all 13 tests were compiled and none of them ran, on the host
architecture, under a driver that reports a build with no executed test as a
failure. Receipt:
`/home/tmp2/gertullj/scratch/foundation-libs/cross-test-01a0f400/before/fast_float/`.

**What replaced it.** `b.addRunArtifact(tests)` with no condition. What then
happens to that run belongs to whoever drives the build, and each outcome stays
reportable as what it is:

* a host target executes;
* a foreign target executes under an external executor the driver supplies
  (QEMU user mode, Wine, wasmtime);
* a foreign target with no executor is skipped with its compile dependencies
  intact — **build-only coverage, never a pass**.

No matrix narrowing, no `cross_build_command`/`cross_artifact` hook, no second
and reduced test root: the artifact `check` compiles is the artifact `test`
runs, so a target that executes these tests executes the whole corpus.

`run_tests.has_side_effects = true` is set as well, for the same reason
`run_smoke` already carries it. Zig gives a `.zig_test` run step no side
effects by construction (`lib/std/Build/Step/Run.zig:707-713`), so an unchanged
compile is served from the run cache and the binary never executes — which for
a test whose substance is a fixture corpus read off disk would report a pass
without reading anything, those files not being inputs to the run step's
hash. `zig build test` with no `-Dtarget` already ran natively and still does;
only the targeted case changed.

**Also added.** `cross-test.profile.sh`: a settings-only profile carrying
`CROSS_BUILD_STEP=test` and `CROSS_BUILD_JOBS=4` — no `CROSS_MATRIX`, no
`TARGETS`, no hook, no path on this host — so the published 53-platform Zig 0.16
table applies unchanged and `--targets` still selects from
it. It is shipped in `.paths` because a fetched copy of the package would
otherwise silently fall back to the harness defaults, and `NOTICE.md` records it
among this fork's own files under no grant. Two deadline settings were added to
the same file afterwards; see entry 19, which is where the current contents are
described.

**Deliberately unchanged.** The corpus is not shrunk: the same nine files,
1,382,483 rows, every line at both widths, on whichever runner executes them,
and the fixture path stays relative to the working directory every run step
inherits. The six-target `check` matrix, its compile-only meaning and its graph
are untouched, so it remains the fast compile-only gate. No upstream or donor
byte changed, so `UPSTREAM.sha256` is unchanged and still `sha256sum -c` clean.

**Status.** `observed`. The cross-target result this entry was waiting for now
exists: the first full 53-platform sweep after the change compiled all 53
targets and executed the suite in 17 of them, 13/13 each, with 33 build-only
cells; the corrected sweep executed it in 20, again 13/13 each, with the same 33
build-only cells and no failure (entry 19). The native `test` result on this
tree is `zig build test smoke install -Doptimize=Debug`, exit 0 with 13/13, the
whole 13-test binary including the corpus in 2 s
(`local://foundation-cross-test-stable-fast_float-native-Debug.log`).

## 19. Raised the matrix profile's two deadlines, and changed nothing else

**Decision.** `cross-test.profile.sh` gained `CROSS_BUILD_TIMEOUT=3600` and
`CROSS_TIMEOUT=1800`. The file is still settings only — four ordinary
assignments, no command, no probe, no path naming a host — and still carries no
`CROSS_MATRIX` and no `TARGETS`, so the published 53-platform Zig 0.16 table
applies unchanged and `--targets` still selects from it rather than adding to
it.

**Why.** The corpus test reads all 1,382,483 rows of the nine selected files at
both widths, and `cross-test`'s standard `zig-build` mode hands every target a
300-second per-test deadline. The first full 53-platform sweep under this
profile (`run 20261002-040251-43214-11311`, exit 1) compiled all 53 targets and
executed the suite in 17 of them, 13/13 each, but three cells hit that deadline
instead of finishing: `x86_64-linux` at 5m98.837ms, `aarch64-linux` at
5m18.377s and `aarch64_be-linux` at 5m1.042s, each reporting `12/13 tests
passed (1 timed out)` with the same corpus test named. No receipt from that
sweep shows a wrong bit pattern; the failures were wall clock. Those three logs
are kept as history, because they are what the deadline answers.

**Deliberately unchanged.** The corpus is not shrunk and not sampled: the same
nine files, 1,382,483 rows, every line at both widths, on whichever runner
executes them. Debug was **not** remapped to an optimized mode to buy time, no
test was skipped, no vector was narrowed, and the six-target `check` matrix
keeps its compile-only meaning as the fast gate. No upstream or donor byte
changed, so `UPSTREAM.sha256` is unchanged; it was not re-run as part of this
entry and its 73 records carry their earlier receipt.

**Status.** `observed` — `cross-test --jobs 2 --build-jobs 4 --build-timeout
3600` under this profile, run `20261002-060543-20930-1891`, Zig 0.16.0,
`zig-build` mode, 2026-10-02: **20 pass, 33 build-only, 0 fail** over 53
targets. Every one of the 20 executed cells reported 13/13 and printed all nine
per-file line counts; `x86_64-linux` finished natively in 2 s and `aarch64-linux`
under `/bin/qemu-aarch64` in 32 s. The 33 remaining cells carry reason
`runtime_unavailable`: compiled, never executed, never counted as a pass.
Receipt `local://foundation-cross-test-corrected-fast_float.json`, with the
per-target logs beside it.

**Still pending.** A fresh materialised-package round — `zig fetch`, the
in-package `sha256sum -c UPSTREAM.sha256`, and a consumer run from inside the
fetched copy — has not been run against this tree. The receipts in entry 16
pre-date the run-step and profile changes and are kept as history, not as a
claim about what ships today.

## 20. Zig API contract alignment — 2026-10-03

**Condition.** A typed parse error returns no `Parsed` value. The raw bridge
has a separate out-parameter contract: invalid input leaves outputs unchanged;
range failure writes the rounded infinity/zero and consumed length.

**Fix.** Distinguish those channels, prefix versus exact parsing, pointer
ranges, input lifetime and the absence of retention/allocation. Correct
parser and bridge citations and state the supported module/raw/artifact routes.

**Verification and bound.** Zig 0.16.0, native Linux x86-64: install,
Debug/ReleaseSafe tests, smoke, package consumer and module example pass.
The compile-only `check` matrix passes. A separate consumer passes in all four
modes: raw invalid/range residue, both widths, and typed prefix/exact errors.
No C++ bridge, header, native parser or generated binding changed.

## 21. Standalone Nix and devenv packaging, the fork's licence grant, and the README relocation — 2026-10-04

**Condition.** The contract migration requires every SDK to be standalone: one
source-only per-SDK derivation callable by both a flake and a devenv
environment, separate static and shared variants, no sibling import and no
build-time native download; canonical development through devenv; a real
installed closure carrying licence material rather than a shell environment. It
also requires the README order to be native-source deviations, native-build
deviations with dated history, the current matrix, then consumption, with the
Zig interface documented separately and upstream's own README preserved. And it
requires an actual grant for the files this fork authored, replacing the
withdrawn attempt recorded in entry 13.

**Fix.**

* `README.md` is now the fork's README, in the canonical order. Upstream's bytes
  are preserved at `README.upstream.md`, `sha256
  80d3197381d1a3fe7de55ac450e62b89a6d7141069b88eeca645f0543a6b2a3b`, which is
  upstream's `README.md` at commit `b0ab987b3dfdde13fa1915f65ef2a5c068d9208c`
  unchanged. Every citation of the licence grant and the Wuffs credit moved to
  the preserved name: `UPSTREAM.md`, `NOTICE.md`, `README.zig.md`,
  `UPSTREAM.sha256`'s header and the workflow's provenance step. Zig interface
  documentation stays in `README.zig.md` and is not duplicated.
* `package.nix` — one source-only derivation, `linkage` argument, `zig_0_16`
  passed in explicitly by its callers. It builds with `zig build install` and
  restates no C or C++ flag; the native build graph in
  `build_support/graph.zig` owns those. The pkg-config file and the full licence
  set are installed by `zig build install` itself — `prefix=\${pcfiledir}/../..`
  for the `.pc`, and the corpus's distinct Apache-2.0 copy under the distinct
  name `testdata-supplemental-LICENSE` — so the derivation installs nothing
  beside it and there is no second copy that could overwrite a relocatable
  prefix with a fixed one. Root filtering drops `.git`, caches, outputs,
  `result` symlinks, direnv state and devenv state, and keeps every source and
  fixture a build or test needs: the 262 MB known-answer corpus is source here,
  not a cache.
* `flake.nix` — one fixed nixpkgs input, `static` and `shared` packages built
  from the same derivation and the same source tree, `default = static` to
  preserve this SDK's existing linkage policy, and a tools-only development
  shell for parity. The SDK is not a package of that shell.
* `devenv.nix`, `devenv.yaml`, `.envrc` — the canonical environment. Tools and
  explicit tasks, never the SDK itself. Cache and scratch locations are resolved
  at shell entry from `HOST_SCRATCH_ROOT` or `XDG_CACHE_HOME` and are never
  baked in; when neither is set the shell says so on stderr.
* `FORK-LICENSE.md` — the actual grant for the files this fork authored:
  `Apache-2.0 OR MIT OR BSL-1.0`, on the owner's explicit authorization. That is
  upstream's own three-way alternative rather than a new selection, so no
  downstream's choice among upstream's alternatives is narrowed. Copyright in
  those files is held by the downstream that owns this repository; no individual
  is named and none is asserted, and no upstream author is credited with them.
  The file states what the grant does not cover, file group by file group.
* `NOTICE.md` — the unassigned-fork-licence paragraph is replaced by the actual
  grant; the known-answer corpus gains a sixteen-row per-file inventory saying
  which files the tests read, which are carried unread, and which single
  Apache-2.0 grant covers all of them; the installed-output licence layout is
  stated.
* `.github/workflows/verify.yml` — the provenance step's fork-record list gains
  `FORK-LICENSE.md`, `README.md` and `README.upstream.md`; the three
  licence-name greps and the pinned-commit diff move from `README.md` to
  `README.upstream.md`; a check for the fork's own SPDX identifier joins them.
  No build, test, cross or consumer step was touched.
* `build.zig.zon` `.paths` grew with the above, by the native-delivery owner:
  `FORK-LICENSE.md` and `README.upstream.md` beside the other fork records, and
  `package.nix`, `flake.nix`, `devenv.nix`, `devenv.yaml` and `.envrc` as the
  standalone packaging. Without `README.upstream.md` a fetched package loses the
  only place the licence grant is stated. `README.md` was already listed and
  stays, and now names the fork's README rather than upstream's. The lock files
  are deliberately absent until the driver creates them: naming a path that is
  not there would make `zig fetch` hash a missing entry.
* `.gitignore`, likewise by the native-delivery owner, appends `result`,
  `result-*`, `.devenv/`, `.devenv.flake.nix`, `.devenv.flakes/` and
  `devenv.local.nix`, and records that `flake.lock` and `devenv.lock` are real
  inputs and deliberately not ignored.

The native-delivery owner also took the install paths over, which changed this
role's own answer mid-entry: `build.zig` now generates and installs
`lib/pkgconfig/fast_float.pc` and the whole `share/licenses/fast_float/` set, so
`package.nix` installs nothing beside `zig build install` and `NOTICE.md` and
`FORK-LICENSE.md` were corrected to say so. `FORK-NOTES.md` note 21 records the
correction and the lesson.

**Verification and bound.** `PENDING-VERIFICATION` for the packaging. No Nix
command, no devenv command, no test and no consumer was run. Both Nix packages
consume `-Dlinkage=static|dynamic`, which the native-delivery owner landed with
the existing `.static` default preserved; neither package has been built, and
the `wasm32-wasi` behaviour for a shared request — that target has no dynamic
linker — was recorded at the time as a static fallback; entry 23 replaces that
with the refusal the build now performs.
Bound: nixpkgs
`github:NixOS/nixpkgs/c7def046b9a883d46974757852106483d741586f` for the flake,
`github:cachix/devenv-nixpkgs/c2f38fe7f9e04d9aadd354d380f2bd40531d9737` for
devenv, and `pkgs.zig_0_16` for the compiler.

**One exception, disclosed.** A `zig build install` was run accidentally in this
package root — a double-quoted grep pattern contained backticks, and the shell
executed the backticked text. It is not a gate, nothing here claims a result
from it, and no verification field moved because of it. It happened to reveal
that `lib/pkgconfig/fast_float.pc` and `share/licenses/fast_float/` were not
reaching the install prefix, which the native-delivery owner then diagnosed and
fixed; see entry 22 and `FORK-NOTES.md` 22.

## 22. Corrected Nix and devenv packaging, install-step repair, and licence prose — 2026-10-04

**Condition.** The canonical packaging corrections applied to every SDK. For
fast_float: the derivation's phase and cache handling, the devenv entry point,
and prose that presented staged work as if it were permanent.

**Fix.**

* `package.nix` is one uncurried function returning one derivation, called the
  same way by both entry points with `zig = pkgs.zig_0_16`. It now sets
  `dontBuild` alongside `dontConfigure` so the hook's default build cannot run
  once with hook flags and the variant again at install, and explicitly does not
  set `dontInstall`, which would disable the real `installPhase`. Both Zig
  caches are exported under the Nix-provided `TMPDIR`, outside the read-only
  source tree, and the single `zig build install` passes `-j"${NIX_BUILD_CORES:-1}"`,
  `-Dcpu=baseline`, one `-Doptimize`, `-Dlinkage=<variant>` and
  `--prefix "$out"`. The source filter also drops `zig-pkg` and `.devenv.flakes`.
* `devenv.nix` gains lazy `outputs.static` and `outputs.shared` calling exactly
  that derivation, plus `outputs.default` preserving the native policy. The
  shell still holds tools only, so entering it builds nothing and
  `devenv build outputs.static` is the packaging route. The bare script keys are
  gone in favour of namespaced tasks: `sdk:install`, `sdk:test`, `sdk:smoke`,
  `sdk:check`, `sdk:consumer`, `provenance:integrity`, `package:static`,
  `package:shared`. Cache variables are defaulted only when the caller supplied
  neither them nor a location, and are never unset, so a caller-supplied scratch
  is respected rather than replaced.
* `flake.nix` is unchanged in shape — `static`, `shared`, `default = static`, a
  tools-only devShell — and its shell hook now also respects a caller-supplied
  `ZIG_LOCAL_CACHE_DIR`.
* The native-delivery owner found that `addInstallFileWithDir` only creates a
  `Step.InstallFile` and returns it without attaching it to the install step, so
  the generated pkg-config file and the whole licence set never installed while
  `zig build` still exited 0. Both now use `b.installFile`. The same defect was
  reported across other SDKs.
* Licence prose is shorter. `FORK-LICENSE.md` states the grant, the
  authorization, the SPDX identifier, the file groups it covers and does not
  cover, the obligations and the installed paths, and no longer argues about
  which term is legally required. `FORK-NOTES.md` 19 was rewritten: the lesson
  is that withdrawing an unauthorized grant does not authorize its replacement
  and that leaving a record blank pushes an invented default onto every reader.
  No grant, text, exception, path or obligation was changed.
* `README.md` and `README.zig.md` no longer carry an "in flight" section or rows
  describing a missing feature as a state of this project; the pending matrix
  remains and still says `PENDING-VERIFICATION` on every row.

**Verification and bound.** `PENDING-VERIFICATION`: no Nix, devenv, build, test
or consumer command was run for this entry. `package.nix`, `flake.nix` and
`devenv.nix` are unevaluated. The lock files remain the driver's.

## 23. A target that cannot carry the requested delivery is refused, and the runtime route is in scope — 2026-10-04

**Condition.** Two decisions changed under the driver. `-Dlinkage=dynamic` no
longer substitutes an archive for a target that cannot hold a shared object, and
`-Druntime` — runtime-loaded dispatch — is now a first-class delivery mode rather
than a later addition.

**Fix.**

* **The refusal replaces the substitution.** `wasm32-wasi` has no dynamic linker
  (`std.Target.DynamicLinker.kind` is `.none`, `lib/std/Target.zig:2385`), so a
  `.so` there is a file nothing can load. `-Dlinkage=dynamic` now fails for that
  target, naming it and the reason; inside `zig build check -Dlinkage=dynamic`
  that one matrix cell becomes a failing step carrying the reason while the
  other five are still compiled. Nothing is compiled for the refused cell and
  nothing is relabelled. `build_support/graph.zig:deliveredLinkage` is gone; the
  reason comes from `sharedObjectRefusal`. What is unchanged and load-bearing:
  the default is `static`, that is exactly what `wasm32-wasi` takes, and
  `zig build check` with no `-Dlinkage` still compiles all six cells.
* **`-Druntime` exists** — a bool, default off, orthogonal to `-Dlinkage`, which
  still decides what is built and installed. Under `-Druntime` that artifact is
  what a provider *is*, not something the module links. The API role landed
  `runtime/graph.zig` and `runtime/library.zig` (sync prefix `fast_float_rt`),
  `build_support/graph.zig` imports the former at the top level and owns the one
  seam, and `runtime/` is in `.paths`.
* **Provider contract, with no default.** `smoke.zig` reads `--provider <path>`
  or `FASTFLOAT_PROVIDER`; `tests.zig` reads `FASTFLOAT_PROVIDER` and stops by
  name when it is unset; `consumer/src/main.zig` reads the same `--provider`, and
  the consumer package forwards both `-Druntime` and its run arguments, so
  `zig build smoke -Druntime=true -- --provider <path>` and
  `zig build run -Druntime=true -- --provider <path>` both work.
* **Documentation corrected to match.** `README.md` gained deviation B10 for
  the second option, a rewritten "Platform boundaries" that states the refusal
  rather than the substitution, a "Runtime loading" consumption section with the
  provider contract, and two revised pending-matrix rows. `README.zig.md` gained
  a "Runtime loading" section, `-Druntime` command rows, and corrected Build
  modes, boundary and pending rows; the stale `deliveredLinkage` name is gone.
  `FORK-NOTES.md` 20 is rewritten around the refusal, and note 23 records why the
  substitution was the wrong answer.

**Verification and bound.** `PENDING-VERIFICATION`: no build, test, smoke, cross
or consumer command was run for this entry, and no configuration has been
exercised. The graph and descriptor are in the tree; the loader core
(`runtime/loader.zig`, `runtime/generate.zig`, `runtime/sync.c`,
`runtime/sync.h`) is distributed separately and until it arrives no `-Druntime`
configuration compiles in either linkage. No CI step was added that would gate on
files that do not exist.

**Superseded in part by entry 24.** The bound above is kept as the record of
what was written when this entry was. Its second sentence — that the loader
core "is distributed separately and until it arrives no `-Druntime`
configuration compiles" — described the wave's division of labour rather than
the tree, and it is withdrawn. The core is in `runtime/`; entry 24 reports the
sixteen configurations that compiled and ran.

## 24. Sixteen configurations run on this tree, a status withdrawn, and the lock shipped — 2026-10-04

**Condition.** Two current claims had outlived the files they described. Entry
23's bound above, and `FORK-NOTES.md` note 23's status, said the runtime loader
core was distributed separately and that no `-Druntime` configuration could
compile until it arrived; the four files were in `runtime/` and in
`build.zig.zon` `.paths`. Entries 21 and 22 said the lock files were the
driver's to create and deliberately absent; `flake.lock` is in the tree.

**What the driver ran.** `zig build test smoke install -Druntime=<bool>
-Dlinkage=<static|dynamic> -Doptimize=<mode> -j8 --summary all --prefix <a
prefix outside this repository>`, from this package root with the pinned 0.16.0
compiler: four optimize modes — Debug, ReleaseSafe, ReleaseFast, ReleaseSmall —
in both linkages with `-Druntime=false`, and the same eight with
`-Druntime=true` and `FASTFLOAT_PROVIDER` exported. **All sixteen exit 0.**

**Fix and record.**

* **The evidence.** Every one of the sixteen reports `13/13 tests passed` in a
  fully green `Build Summary` — `22/22` steps for the four linked-static cells,
  `23/23` for the four linked-dynamic and the four loaded-static ones, `24/24`
  for the four loaded-dynamic ones — and every cell printed all nine per-file
  corpus line counts, so all 1,382,483 rows were consumed at both widths in
  every run. The loaded cells each print `runtime-loaded dispatch
  (-Druntime=true); no library is linked into the module`, and `tests.zig`,
  which stops by name when `FASTFLOAT_PROVIDER` is unset, read the corpus in
  all eight of them, so the suite answered through the dispatch. Receipts: the
  sixteen `fast_float-current-*` rows of
  `local://foundation-current-native-index.json`, one file per gate.
* **The limits, stated rather than implied.** The provider was this tree's own
  `libfast_float.so`, named by absolute path: no external provider and no
  basename-named provider was loaded. The shared object's soname and export
  closure are the build graph's own printed statement, not a reading of the
  installed object, and no Darwin or windows-gnu delivery exists on this host.
  The six-target `check`, the 53-cell `cross-test`, the consumers, the installed
  C and C++ surfaces, the fetched filtered package, `nix build`, the devenv
  shell and `.github/workflows/verify.yml` are all still
  `PENDING-VERIFICATION`.
* **The false status is withdrawn and replaced with what is true.** The loader
  core is in this tree — `runtime/loader.zig`, `runtime/generate.zig`,
  `runtime/sync.c` and `runtime/sync.h` beside `runtime/graph.zig` and
  `runtime/library.zig`, all six under a `.paths` directory — and the sixteen
  runs above compiled and executed every one of them. `FORK-NOTES.md` note 23's
  status is corrected in place with this entry named, note 24 records what the
  mistake was, and entry 23's bound is left above as dated history with a
  pointer to here.
  The licence records agree with the tree: `NOTICE.md`'s file table and
  `FORK-LICENSE.md`'s covered-files table each name all six runtime sources, and
  `FORK-LICENSE.md` states the line-1 SPDX form for each of them — Zig comment
  for the four `.zig` files, C comment for `sync.c` and `sync.h`.
* **The install closure is no longer an argument.** Each of the sixteen install
  steps names the generated `lib/pkgconfig/fast_float.pc` and all eight records
  under `share/licenses/fast_float/`, which is what entry 22 and
  `FORK-NOTES.md` 22 recorded as silently missing. Entry 22's
  `PENDING-VERIFICATION` for the Zig install is superseded for this tree; the
  derivation-side assertion in `package.nix` is still unexercised.
* **`flake.lock` is committed, pins the flake's own input, and travels with the
  package.** It resolves `nixpkgs` to
  `c7def046b9a883d46974757852106483d741586f` with `narHash`
  `sha256-6RSEDHIWQtesQKWSu5qRai8L2h4KgCgMEfJHstW99G4=` — the revision
  `flake.nix` declares — and `build.zig.zon` `.paths` lists it beside
  `flake.nix`, `package.nix`, `devenv.nix`, `devenv.yaml` and `.envrc`, so a
  fetched copy resolves this nixpkgs rather than the machine's. `flake.nix`'s
  header comment said the lock was "the driver's to create" and now describes
  the committed lock. `devenv.lock` is absent and stays absent: it is not in
  this tree and `devenv.yaml` states what it must pin when it is created.
  Entries 21 and 22 keep their dated sentences about the locks; this entry is
  the current state.
* **The documentation follows the evidence.** `README.md` §3b is now an
  observed block over the sixteen gates with a pending table beside it, its
  "Runtime loading" section says what the gate reached and what it did not, its
  C section points at the typed `parse32Exact`/`parse64Exact` refusal — the
  facade's own `consumed != bytes.len` check, with no bridge status behind it —
  and its Nix section states the committed lock. `README.zig.md` says the same
  in "Runtime loading" and "Verification status", and its six-target sentence
  now names the tree it describes. No upstream byte, licence text, test or
  fixture changed; only fork-authored documentation and one comment in
  `flake.nix` did.

**Verification and bound.** `observed` for the sixteen gates above, from the
receipts cited, and nothing else. No `check`, `cross-test`, consumer, installed-C,
installed-C++, fetch, `nix`, `devenv` or CI command was run for this entry, and
no Nix file was evaluated.

## 25. An error tag on this facade is not a bridge status — 2026-10-04

**Condition.** `pub const Error`'s documentation asserted a status behind every
tag, and the tag's own member comment described `InvalidArgument` as one thing.
Both read as exhaustive statements about all four published parse entry points,
and both are false for two of them.

**The defect.** The before-text read: "The status behind each one is one of the
three `FF_STATUS_*` values `bridge.h` declares, which translate-c hands Zig as
top-level `c_int` constants rather than as a tag type: there is deliberately no
second spelling of those three values here", and `InvalidArgument` was
"`c.FF_STATUS_INVALID_ARGUMENT`: the buffer does not begin with a number this
format accepts. That is the empty buffer, a leading space or tab, a leading `+`,
and a lone `.` or `-`." `parse32Exact` and `parse64Exact` are `try parse32` /
`try parse64` plus `if (parsed.consumed != bytes.len) return
error.InvalidArgument` (`zig/root.zig:480`, `:488`), so by the time that
comparison runs the bridge has already stored both out-parameters
(`zig/bridge.cpp:62-66`) and `classify` has already returned `FF_STATUS_OK`.
`parse32Exact("1.5x")` is therefore `error.InvalidArgument` with
`FF_STATUS_OK` behind it and no `FF_STATUS_INVALID_ARGUMENT` anywhere in it. No
error member was wrong and no spelling was wrong; what each tag *meant* was.

**Fix.** Documentation, in `zig/root.zig` only: two doc comments inside
`pub const Error`. No executable line, no signature, no member added or removed,
and `Error` still has exactly three members. A distinct tag for the trailing
tail was deliberately **not** invented — the defect is in the documented
contract, and adding API would have replaced one wrong record with a different
one.

* The `Error` doc comment now states that the bridge's three `FF_STATUS_*`
  values reach Zig as top-level `c_int` constants and are not this declaration;
  that a tag is not a status; that `parse32` and `parse64` translate one into the
  other and nothing else; that the exact pair adds one comparison of its own
  after a successful parse, so a tag can arrive with no `FF_STATUS_*` behind it
  at all; and that which half produced a tag is settled by which entry point the
  caller called.
* `Error.InvalidArgument`'s comment now names its two producers. From
  `parse32`/`parse64` it is `c.FF_STATUS_INVALID_ARGUMENT`, neither
  out-parameter is written (`zig/bridge.h:20-27`) and no result is constructed.
  From `parse32Exact`/`parse64Exact` it is the facade's own
  `consumed != bytes.len` comparison, reached only after a parse that succeeded,
  with the value and the byte count written into the bridge's out-parameters and
  dropped here.
* Nothing was added to convert a tag into a status, in code or in the record:
  the three constants answer "what did the bridge report" and `Error` answers
  "what did this facade refuse", and those are the same question only for
  `parse32` and `parse64`.
* `README.zig.md`'s error table and the paragraph under it already carried the
  per-entry-point shape and were left as they are; their citations
  `zig/root.zig:478-482` and `:486-490` are the corrected file's lines.

**Verification and bound.** `SOURCE-CONFIRMED` for the citation set —
`zig/root.zig:480`, `:488`, `zig/bridge.cpp:62-66`, `zig/bridge.h:20-27`, and
the status values and their `_Static_assert` pins at `zig/bridge.h:58-68` and
`:80-84` — and for the corrected comments. `PENDING-VERIFICATION` for
everything else: no build, test, smoke, install, `check`, `cross-test`,
consumer, `nix`, `devenv` or git command was run for this entry, and this
record asserts nothing observed. The change is comment-only, so no existing gate
result should move; if one does, that is a finding rather than a consequence of
this correction. The claim was found by reading source, including the pinned
0.16 APIs a throwaway probe under the workspace scratch would use, which were
likewise read from `lib/std` rather than compiled; that probe is scratch, is not
wiring, and its run is the parent's to report.

## 26. The canonical tasks looked for this SDK in the scratch project — 2026-10-04

**Condition.** The workspace runs one canonical `devenv` gate per SDK from a
scratch *project* directory with `devenv --from path:<this SDK>` and the cwd set
to that project, so that `.devenv/`, the autolock and the cache stay off the
repository and its mount. That is the correct runner and it is unchanged. What
it means for a task body is that neither the cwd nor `DEVENV_ROOT` names this
SDK, and two files in this tree were written as if they did.

**The first defect is observed, and it took the whole environment down.**
`devenv.yaml` declared `flake: false` on its nixpkgs input. With that key the
input resolves to a bare source tree with no `lib`, and devenv's own bootstrap
dies before it reads this repository at all:
`x Failed to get attribute 'config.cachix.enable':`, then
`bootstrapLib.nix:54: lib = nixpkgs.lib;` → `error: attribute 'lib' missing`,
exit 1, byte-identical in all six `devenv` gate receipts. The comment above the
key claimed `flake: false` "matches what devenv resolves"; this run disproves
it. Removed: the key, and the comment that asserted it.

**The second defect is source-confirmed here and observed in the same run for
ten other SDKs.** All six canonical execs opened with `cd "$DEVENV_ROOT"` (and
`cd "$DEVENV_ROOT/consumer"`), so they ran `zig build`, `sha256sum -c
UPSTREAM.sha256` and `zig build run` in a directory holding no `build.zig`, no
`UPSTREAM.sha256` and no `consumer/`. In the run of 2026-10-04T17:53:28Z that
produced, in every SDK that reached it,
`sha256sum: UPSTREAM.sha256: No such file or directory` and
`error: no build.zig file found, in the current directory or any parent
directories`. It is not in this SDK's own receipts because the `flake:` defect
above killed all six of its `devenv` gates first.

**Fix.** Two executable files — `devenv.yaml` and `devenv.nix` — and nothing
else in the build or packaging path. The documentation that describes them is
corrected with them, below.

* `devenv.yaml` keeps `inputs.nixpkgs.url` at
  `github:cachix/devenv-nixpkgs/c2f38fe7f9e04d9aadd354d380f2bd40531d9737` and
  loses the `flake:` key and the comment that described it. The pin is
  unchanged; only the input kind is.
* `devenv.nix` gains two `let` bindings, `sdkRoot` and `consumerRoot`, written
  `pkgs.lib.escapeShellArg (builtins.toString ./.)` and
  `pkgs.lib.escapeShellArg (builtins.toString ./. + "/consumer")`, and the six
  exec bodies change their first line to `cd ${sdkRoot} || exit 1` or
  `cd ${consumerRoot} || exit 1`. `./.` is the directory of the file that names
  it, so each task finds this SDK by construction and not by the caller's
  location. `builtins.toString` yields the path's string rather than leaving a
  path value in the generated wrapper; `lib.escapeShellArg` is the quoting
  convention `htscodecs/package.nix` already uses in this workspace. Whether Nix
  renders that string as this working tree or as a store copy of it was not
  observed — no `devenv` command ran for this entry — and either rendering
  carries the `build.zig`, `UPSTREAM.sha256` and `consumer/` these tasks read.
* Task names are unchanged and none was renamed: `sdk:install`, `sdk:test`,
  `sdk:smoke`, `sdk:check`, `sdk:consumer`, `provenance:integrity`,
  `package:static`, `package:shared`. Every one still ends in `"$@"`, so
  `-Dtarget=`, `-Doptimize=`, `-Dlinkage=`, `-j8` and `--summary all` reach
  `zig build` exactly as before. `package:static` and `package:shared` read no
  file in this tree and are byte-identical.
* `sdk:install` was the one task that wrote a delivery artefact, and its
  `--prefix` default was `$PWD/zig-out` — the repository itself. It now defaults
  to `$ZIG_LOCAL_CACHE_DIR/fast_float-install`, falls back to
  `$TMPDIR/zig-local-cache/fast_float-install` (the name `enterShell` and
  `package.nix` already use here) when the caller exported no Zig local cache,
  keeps `PREFIX=...` as the caller's override, and stops with a message when
  neither variable is set. No installed output is written into this working copy
  or onto its mount by any task now.
* The other four bodies deliberately take no `--prefix`, and that is a read of
  this repository's step graph, not a preference: the install step depends on
  the smoke executable rather than the reverse (`build.zig:204`), `smoke`
  (`:212`), `test` (`:245`) and `check` (`:247-257`) each depend only on their
  own compile or run step, and the consumer's `run` depends on its executable
  alone (`consumer/build.zig`). None of `addTests`, `addSmoke` or
  `addTargetCheck` attaches anything to `getInstallStep()`. So no other
  canonical body reaches an install step, writes no delivery output, and is not
  handed a flag it does not need. `SOURCE-CONFIRMED` from those lines; no gate
  observed them.
* `README.md` §"Development" and `README.zig.md` §"Nix packaging and the
  development environment" carry the new `sdk:install` comment line, the
  self-location rule, the prefix order and the refusal. Their
  `PENDING-VERIFICATION` rows are not promoted: nothing here has been run.
* Not touched: `build.zig`, `build_support/`, `zig/bridge.h`, `zig/bridge.cpp`,
  `zig/root.zig`, `runtime/`, `tests.zig`, `smoke.zig`, `consumer/`,
  `package.nix`, `flake.nix`, `flake.lock`, `.envrc`, `UPSTREAM.sha256`, every
  upstream byte, header, test, fixture and licence text. No C or C++ source and
  no public header changed.

**Verification and bound.** `OBSERVED` for the `flake:` defect and its
byte-identical failure across six gates, from the run named above;
`SOURCE-CONFIRMED` for the six `cd "$DEVENV_ROOT"` lines and for the two bindings
and the rewritten bodies that replace them. `PENDING-VERIFICATION` for
everything else: no `devenv`, `nix`, `zig`, build, test, smoke, install, `check`,
consumer or integrity command was run for this entry, and this record asserts no
green result. The first run after it lands should say which rendering
`builtins.toString ./.` produced, because that decides whether these tasks
execute against this working tree or against a read-only store copy of it. The
runner itself is not in question and must not be moved.

## 27. Every canonical `zig build` in this SDK's tasks names its own flags, and its own caches — 2026-10-04

**Decision.** The five task bodies in `devenv.nix` that reach `zig build` named a
step and forwarded `"$@"`, and left the job count, the summary mode and the
cache location to whatever the caller passed or to Zig's own defaults. A
canonical route is run by name and by nothing else, so what a caller happened to
type was what the gate ran with — and with no cache named at all, a task invoked
as `devenv tasks run --mode single <name>` created `.zig-cache` inside this
tree, because that invocation executes a body without the `enterShell` hook.
Each of the five now carries `-j8`, `--summary all` and an explicit
`--cache-dir "$ZIG_LOCAL_CACHE_DIR"`, and each resolves both cache variables
itself before its compiler starts.

**Placement.** After that step's own flags and before `"$@"`, so the forwarding
this SDK has always documented is unchanged and a caller who does pass `-jN`,
`--summary` or a `--cache-dir` of their own still decides. `SOURCE-CONFIRMED` in
the pinned compiler: the build runner parses `-j` as
`mem.cutPrefix(u8, arg, "-j")` and assigns, so the last occurrence on the
command line is the one that counts
(`lib/compiler/build_runner.zig:422-427`, Zig 0.16.0); `--summary` and
`--cache-dir` are read the same way, last one wins.

**Caches.** One `let` binding, `cacheDirs`, carries the whole rule, and every
body that starts a compiler runs it after its `cd` and before `zig build`:

* a `ZIG_GLOBAL_CACHE_DIR` or `ZIG_LOCAL_CACHE_DIR` the caller already exported
  is kept and never written to;
* a missing one is filled from `XDG_CACHE_HOME`, and failing that from `$TMPDIR`,
  under this SDK's own existing names — `zig-global` and `zig-local` beneath the
  XDG directory (`enterShell`), `zig-global-cache` and `zig-local-cache` beneath
  `TMPDIR` (`package.nix:83-84`);
* a caller who exported neither variable and named no `XDG_CACHE_HOME` and no
  `TMPDIR` is told which variables to export, on stderr, and the task stops
  before the compiler runs.

No cache directory is invented, no new variable alias is introduced, and neither
`/tmp`, `/var/tmp`, this repository nor a network mount is among the candidates.
`sdk:install`'s private `TMPDIR` fill and its private refusal are gone as
duplicates: its prefix default still reads
`$ZIG_LOCAL_CACHE_DIR/fast_float-install`, which that binding has already
resolved, and the refusal is now the shared one. `enterShell` is unchanged and
still applies the XDG default to an interactive session, and no task body
depends on it having run.

* `devenv.nix`, and nothing else in the build or packaging path:
  * `sdk:install` — `cd ${sdkRoot}`, `${cacheDirs}`, then `zig build install
    --prefix "$PREFIX" -j8 --summary all --cache-dir "$ZIG_LOCAL_CACHE_DIR" "$@"`.
    The prefix rule is untouched and still resolves before the flags:
    `PREFIX=`, else `$ZIG_LOCAL_CACHE_DIR/fast_float-install`, else
    `$TMPDIR/zig-local-cache/fast_float-install`, else the refusal above.
  * `sdk:test` — `cd ${sdkRoot}`, `${cacheDirs}`, then `zig build test -j8
    --summary all --cache-dir "$ZIG_LOCAL_CACHE_DIR" "$@"`.
  * `sdk:smoke` — `cd ${sdkRoot}`, `${cacheDirs}`, then `zig build smoke -j8
    --summary all --cache-dir "$ZIG_LOCAL_CACHE_DIR" "$@"`.
  * `sdk:check` — `cd ${sdkRoot}`, `${cacheDirs}`, then `zig build check -j8
    --summary all --cache-dir "$ZIG_LOCAL_CACHE_DIR" "$@"`.
  * `sdk:consumer` — `cd ${consumerRoot}`, `${cacheDirs}`, then `zig build run
    -j8 --summary all --cache-dir "$ZIG_LOCAL_CACHE_DIR" "$@"`. It still runs in
    `consumer/`, and that build's cache is the same approved directory rather
    than a `consumer/.zig-cache`.
* `--prefix` was added to nothing. The four non-install bodies still take no
  prefix, for the reason the step graph gives below, and the install body still
  takes exactly the one it took.
* Task names are unchanged and none was added: `sdk:install`, `sdk:test`,
  `sdk:smoke`, `sdk:check`, `sdk:consumer`, `provenance:integrity`,
  `package:static`, `package:shared`. `provenance:integrity` runs
  `sha256sum -c UPSTREAM.sha256` and reaches no compiler, so it gained nothing.
  `package:static` and `package:shared` call `devenv build`, which is a Nix
  build governed by the driver's own job flags, not a `zig build`; both are
  byte-identical.
* Every one of the six bodies that reads a file in this tree still begins
  `cd ${sdkRoot} || exit 1` or `cd ${consumerRoot} || exit 1` — the `let`
  bindings from entry 26 are unchanged, and the `cd` is still the first line of
  the body rather than something `enterShell` sets up.
* No canonical command in this SDK invokes `cross-test`, so no
  `--jobs 8 --build-jobs 8` pair applies here. `cross-test.profile.sh` is the
  matrix harness's own settings file (`CROSS_BUILD_STEP`, `CROSS_BUILD_JOBS`,
  two deadlines), not a devenv task or script, and its four build jobs are the
  recorded configuration of the 53-platform sweep in entries 19 and 20. It is
  unchanged, and entry 20's receipt still describes what ran.
* `.github/workflows/verify.yml` runs `zig build … --summary all` on GitHub's
  own runners and is a separate gate on a separate machine; it is unchanged.
* `README.md` §"Development" and `README.zig.md` §"Nix packaging and the
  development environment" carry the three flags, their placement, the
  last-occurrence rule, and the cache order with its refusal. Their
  `PENDING-VERIFICATION` rows are not promoted.
* Not touched: `build.zig`, `build_support/`, `consumer/`, `package.nix`,
  `flake.nix`, `flake.lock`, `devenv.yaml`, `.envrc`, `cross-test.profile.sh`,
  `.github/`, `UPSTREAM.sha256`, `testdata/`, and every upstream byte, header,
  test and licence text. No C or C++ source and no public header changed, and
  no line of `UPSTREAM.sha256` was rewritten.

**Verification and bound.** `SOURCE-CONFIRMED` for the five edited bodies, for
the `cacheDirs` binding, and for the last-occurrence rule read out of the pinned
compiler's `build_runner.zig`. `PENDING-VERIFICATION` for everything else: no
`devenv`, `nix`, `zig`, build, test, smoke, install, `check`, consumer or
integrity command was run for this entry, and this record asserts no green
result. What a gate actually runs at, and which directory its cache lands in,
are questions for the first run after it lands. No earlier receipt in this file
moves: each `zig build` row above names its own `-j8`, the installed C and C++
surface rows were compiled outside this graph, and the 53-platform sweep ran
under the harness settings this SDK still ships.

## 28. The 53-cell matrix and the six-target check are now observed on this tree — 2026-10-05

**Scope.** Documentation only. No build file, no source file, no upstream header,
no corpus row and no licence text changed, and no gate was run for this entry;
the numbers are read out of two existing driver receipts.

**Observed.**

- The 53-cell cohort, receipt `20261004T221720228710Z-45046/fast_float-53-target-8.json`,
  2026-10-04: **exit 0**, `status: partial`, raw `pass=20 fail=0 build_only=33
  partial=0`, `source_stamp_before == source_stamp_after` (`bc692cd7…`),
  `zig_version 0.16.0`, `mode zig-build`, `target_count 53`, `target_jobs 8`,
  `jobs_per_build 8`, `bookkeeping_failure false`. Every executed cell reports
  `tests=13`.
- The compile-only six-target `check` baseline, row `baseline-fast_float-check`
  of `baselines-and-configs/20261005T014547Z-797a73f2`, 2026-10-05: exit 0,
  `Build Summary: 32/32 steps succeeded`, `declared_target_count 6`, all six
  triples named in the run's own step lines, `test_pass_lines: []`,
  `failing_step_lines 0`.

**What this promotes.** `README.md` §3b listed "cross-test full 53-platform
matrix" and "`check` over the six required targets, compile-only, against this
tree" as `PENDING-VERIFICATION`. Both now carry the receipts above, and
`README.zig.md` "Verification status" gains a current 53-cell row beside the
2026-10-02 one it was measured against.

**Bounds.** Thirty-three `build_only` cells compiled and ran nothing because no
executor was available; that is compile evidence, not a runtime pass, and no row
here may be read as one. The six-target `check` baseline runs nothing — it is
compile-only by construction and by the receipt's own
`runtime_pass_claimed: false`, and `test_pass_lines` is empty because that run
printed no test count. The cohort's counts are bounded to the source it stamped:
an edit to this graph, its build-support module or its profile that landed after
`20261004T221720228710Z-45046` is not covered by them, and the 2026-10-02 sweep
stays in this file as the record the deadline profile was measured against.
`-Dlinkage=dynamic` on `check`, the export table read from an installed object,
the Darwin and windows-gnu deliveries, both Zig consumers, the installed C and
C++ consumers, the fetched filtered package, the devenv shell and both Nix
derivations remain `PENDING-VERIFICATION`.
