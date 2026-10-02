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
