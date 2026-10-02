# FORK-NOTES.md — what actually went wrong, and what was decided

Problems met while packaging fast_float as a Zig 0.16 package, and the decisions
they forced. Written in the shape a later wave can reuse: **condition, symptom,
cause, fix, what it is bound to**. Statuses are the workspace's: `OBSERVED` (a
driver run printed it, receipt named), `SOURCE-CONFIRMED` (read out of a file,
never executed), `PENDING-VERIFICATION` (landed, no gate has looked at it), `NOT
RUN` (no receipt exists at all). Receipts are named in full at least once and
by `…-` prefix thereafter; the prefix is `local://foundation-expansion`.

Two of the entries below are not build problems at all: they were wrong
expectations in this fork's own test files. Neither was a defect in the parser.
Both have since been corrected and re-run, and both gates are green; the
entries keep the diagnosis and record the correction, because the wrong oracle
and the red receipt are the evidence for the lesson.

---

## 1. A template has no symbol, so "header-only" is not "nothing to build"

**Condition.** fast_float is header-only. Its public entry points are templates
(`include/fast_float/fast_float.h:33-37`), its `CMakeLists.txt` declares an
`INTERFACE` target, and it compiles none of the library.

**Symptom.** Not a failure — a question with no obvious answer. There is no
library to compile, no archive to link, and `zig translate-c` cannot see a
template, so the obvious packaging (translate the public header, publish it) has
nothing to translate.

**Cause.** A template is instantiated by a caller, and the caller has to be
C++. Until some C++ translation unit instantiates `from_chars` for a concrete
type, the code has no external linkage and no symbol a C or Zig consumer can
name.

**Fix.** `zig/bridge.cpp` is that translation unit. It includes
`<fast_float/fast_float.h>`, calls `from_chars` once per width, and maps the
returned `std::errc` onto three `ff_status` values. `zig/bridge.h` is the plain-C
declaration of the same three, and is the only thing `addTranslateC` reads. The
installed `libfast_float.a` is therefore real compiled upstream code, built on
every target of the matrix — not a shim.

**Bound to.** The fact that fast_float is header-only and templated. It does not
apply to a fork that has a `.c` or `.cpp` file to compile, and it does not
disappear by pinning a newer version unless upstream stops being templated.

**Status.** `OBSERVED` — the install gate produced the archive
(`local://foundation-expansion-fast_float-native-install-40.log`, exit 0; again
`…-fast_float-installed-artifact-gruenau8-176.log`, exit 0), it compiles on all
six matrix targets, and both installed surfaces link and run against it.

---

## 2. The out-of-range path writes its out-parameters; the invalid path does not

**Condition.** Two rejection statuses come back from the same entry point, and
both look like "the call failed" to a caller that only checks the return value.

**Symptom.** Not observed as a failure — a contract that is easy to get wrong and
invisible until a caller's sentinel is silently replaced.

**Cause.** Upstream's own ordering. `include/fast_float/parse_number.h:288`
stores through `to_float` *before* the range test at `:290-292`, so when upstream
reports `result_out_of_range` the value is already in the caller's variable. The
two early exits at `:332-336` and `:347-350` return before `to_float`, so on
`invalid_argument` there is nothing to write and nothing to un-write.

**Fix.** No code change; a decision about what the package *promises*. The bridge
passes the asymmetry through unchanged (`if (result.ec !=
std::errc::invalid_argument)` guards both writes), the Zig facade converts the
out-of-range status into `error.ResultOutOfRange` and deliberately does **not**
construct a `Parsed64` — so a caller is never handed a value it did not write —
and the value stays reachable through `pub const c`. Both halves are pinned by
tests: `tests.zig` ("an out-of-range parse still consumed the whole number and
stored the rounded value", "a parse that matches nothing leaves the caller's
out-parameters unwritten") and the installed C surface in `verify.yml`, which
sends `INFINITY` and a byte count through the `"1e400"` case and a sentinel
through the `"not a number"` case.

**Bound to.** upstream's ordering in `parse_number.h`. If a future release moved
the `to_float` call after the range test, this table in `README.zig.md` and
`NOTICE.md` would be wrong and both tests would fail — which is the point of
having them.

**Status.** `SOURCE-CONFIRMED` from the upstream line references; the two tests
are among the 13 that pass in both observed modes.

---

## 3. A hand-worked halfway case is still a hand-worked case, and it was wrong

**Condition.** `tests.zig:372-395` pins rounding with more digits than the
significand can hold, using the integers just above `2^53` and `2^24`, where a
double's gap is 2 and a float's is 1.

**Symptom.** Both native test gates red with the same single failure:

```
error: 'tests.test.more digits than the significand can hold change the answer
       only when they should' failed:
       expected 4845873199050653697, found 4845873199050653698
```

12 pass, 1 fail, in Debug and in ReleaseSafe.

**Cause.** The expected literal at `tests.zig:381` is wrong. The input is
`9007199254740995` = `2^53 + 3`. The two neighbouring doubles are `2^53 + 2`,
encoded `0x4340000000000001` with significand field `1` (odd), and `2^53 + 4`,
encoded `0x4340000000000002` with significand field `2` (even). The input is
exactly halfway, so round-half-to-even must land on the even one,
`0x4340000000000002` = 4845873199050653698. The test's own comment three lines
above the literal already states this — "whose significand ends in a 1, and
`2^53 + 4` ends in a 0" — and the literal on the next line contradicts the
comment. The value the parser produced is the correctly rounded one.

**Fix.** Applied. The single literal at `tests.zig:381` changed from
`0x4340000000000001` to `0x4340000000000002`. The old oracle is **withdrawn**,
not superseded by a new cap or a looser bound: `9007199254740995` is now expected
to produce exactly `2^53 + 4`, and the three assertions either side of it are
untouched, so the test still pins `2^53 + 2 → 0x…01` and `2^53 + 4 → 0x…02`.
Both gates were re-run, because the two red receipts above describe the file as
it stood before the change and do not cover it after.

**Independent check of the tie.** `local://foundation-expansion-float-tie-proof.json`
records the derivation without reference to this parser: the input
`9007199254740995` sits a distance of 1 from each neighbour, the lower
neighbour's significand parity is 1 and the upper's is 0, so the nearest-even
result is `9007199254740996`, bits `0x4340000000000002`. The same value came back
out of the *installed* archive later, from a C++ translation unit compiled
outside the build graph against the installed headers and archive — the
`installed upstream C++ surface` row of note 11.

**Lesson worth keeping.** The comment was right and the literal was wrong, in the
same test, about the same case. A derivation written next to an expected value
is only worth what the derivation is worth — the comment is not checked by
anything. Where a case is a genuine tie, write the two neighbouring *values* and
the parity of their significands into the expectation as well as the prose, or
write the case as a computed assertion instead of a literal.

**Bound to.** Nothing. This is arithmetic, and it is version-independent: the
IEEE 754 round-half-to-even rule at `2^53` has not changed and will not.

**Status.** `OBSERVED`, twice over. Red first —
`local://foundation-expansion-fast_float-corrected-debug-38.log` and
`…-corrected-releasesafe-41.log`, 12 pass / 1 fail of 13 each. Then, after the
one-line correction, green — `…-fast_float-final-debug-97.log` and
`…-fast_float-final-releasesafe-100.log`, 13/13 in both modes, with the corpus
test consuming all 1,382,483 lines at both widths and printing all nine
per-file line counts. The red receipts are kept: they are the evidence for the
diagnosis, and a corrected expectation with no record of what it replaced is
indistinguishable from one that was never wrong.

---

## 4. The parser stops at the number; the separator is not part of it

**Condition.** `consumer/src/main.zig` parses `"9.80665 m/s^2"` to show the
prefix behaviour, then compares the remainder against `"m/s^2"`.

**Symptom.** The consumer gate red, after all eight constants matched:

```
the measurement: unit is  m/s^2, expected m/s^2
error: UnitMismatch
```

**Cause.** Not a parsing error. `scanned.consumed` is 7, the length of
`"9.80665"`, so `measurement[7..]` is `" m/s^2"` **with** the separating space —
byte 7 is the space. The library is right: it consumed exactly the number and
stopped. The expectation drops a byte that is genuinely still in the buffer.

**Fix.** Applied, on the first of the two options. `consumer/src/main.zig` now
checks `scanned.consumed` separately against `"9.80665".len` and compares
`measurement[consumed..]` against the tail that is really there, `" m/s^2"`,
with its leading space. Nothing is trimmed and the fixture is unchanged, so
what the test asserts is what happened: the parser consumed exactly the number
and the separator is the caller's byte. The same line is then sent through
`parse64Exact`, which must refuse it, which is the half of the contract the
old comparison never reached.

**Lesson worth keeping.** A prefix parse answers "where did the number end", and
everything from `consumed` onwards belongs to the caller. When a test slices at
`consumed` and compares against a hand-written string, the hand-written string
is an expectation about the *whole tail*, separator included — and whitespace is
the byte most often forgotten. This is the same class of defect as note 3: the
library is fine and the oracle is not, and the receipt looks like a library
failure because that is how every receipt looks.

**Bound to.** Nothing. `from_chars` will keep stopping at the first byte that is
not part of the number, because that is what C++17 20.19.3 specifies.

**Status.** `OBSERVED`, and now closed. The correction was applied, and the
consumer re-ran green: eight constants matched, then
`9.80665 m/s^2 -> double 0x40239D013A92A305, 7 bytes consumed, suffix " m/s^2"`
(`local://foundation-expansion-fast_float-consumer-repair-proof-112.log`, exit 0).
The red receipt is kept as the evidence for the diagnosis:
`…-fast_float-corrected-consumer-46.log`, exit 1.

---

## 5. A header-only library has no honest system mode

**Fact.** The shared package contract asks for a genuine system-library mode
where one exists, and for a stated "not applicable" with evidence where one
cannot.

**Decision.** No `b.systemIntegrationOption` and no system branch. A system
fast_float is a directory of headers: no installed ABI, no versioned symbol set,
nothing to bind to and nothing for a mode to select. Adding the option would
advertise a switch that either does nothing or silently takes the bundled path.
`UPSTREAM.md` § "System-library mode" states this as **vacuous rather than
satisfied**, which is the honest status for it.

**Bound to.** fast_float being header-only. If a future release ever shipped a
compiled library, this entry would have to be revisited rather than inherited.

**Status.** `SOURCE-CONFIRMED` (`build.zig:14-19`, `build_support/graph.zig:16-20`).
Not applicable, so no gate can be run and none is claimed.

---

## 6. A 262 MB corpus is read once, sequentially — do not embed it

**Fact.** `testdata/supplemental/data` is 274,299,340 bytes over thirteen files.
`@embedFile` would put those bytes in the test object once per optimize mode and
once per cross target, to be read once from start to finish.

**Decision.** The tests read the corpus from disk at run time, and the build
hands them its location as a module `fast_float_paths` whose single declaration
is `pub const data_dir: []const u8`. It is an options-path module rather than a
convention so the test root never guesses a relative path, and rather than
`@embedFile` so the bytes are not duplicated per mode and per target. The
relative path is sound because a `Step.Run` with no explicit cwd inherits the
build runner's cwd, and `zig build` only runs from the directory holding
`build.zig`.

**Also.** `smoke.zig` and the consumer read no fixtures. The six cross-target
checks compile `tests.zig` but never run it, so they carry the `fast_float_paths`
import for type-checking and nothing else.

**Status.** `SOURCE-CONFIRMED` (`build_support/graph.zig:52-59`, `223-244`) and
`OBSERVED`: both test gates read the corpus from disk and printed all nine
per-file line counts, with no embedding in the test object.

---

## 7. Nine of thirteen corpus files, and the reason is cost

**Decision.** `tests.zig` reads nine data files in full — 1,382,483 lines — and
does not read the four `remyoudompheng-fptest-{0,1,2,3}.txt` files, which are
3,885,708 lines. The four are all generated by one producer (Rémy Oudompheng's
fptest generator) and their bit patterns are already covered by eight
independent producers. Reading them would roughly quadruple the cost of the
fixture loop to re-confirm patterns the other eight files already assert.

**Why it is recorded rather than left implicit.** The four files are carried and
hashed, and "we shipped 274 MB of fixtures and only read half of it" reads as an
oversight unless the reason is written down. `testdata/README.md` states it, and
`UPSTREAM.sha256` includes all sixteen vendored corpus files precisely so a
preserved byte is preserved whether or not this fork reads it.

**Not reading them is not a licence question.** They are inside the same corpus
directory the same Apache-2.0 grant covers — the vendored
`supplemental/README.md` credits Nigel Tao for "the data" without naming a
subset, and these four are part of that data, vendored from the same donor
commit as the other thirteen. So the grant that covers the nine read files
covers the four unread ones, and no separate permission for Rémy Oudompheng's
generator is claimed or needed. `testdata/README.md` says this outright so the
answer is not left to inference. See note 12.

**Also.** The line count of each file is part of the expectation, not
bookkeeping: a file that stopped being read halfway would otherwise pass every
line it did read.

**Status.** `OBSERVED` — the Debug and ReleaseSafe receipts print
`google-double-conversion.txt: 564745 lines` and the other eight, which sum to
1,382,483, at both widths, in both modes.

---

## 8. The cross matrix needs one private module per target

**Fact.** `b.addModule(name, …)` registers the module under that name against
the whole build. Six matrix targets all registering `fast_float` would leave the
last registration reachable and would silently stop checking the other five.

**Decision.** `addGraph(..., public)` takes a flag. The published graph uses
`b.addModule("fast_float", …)`, and every cross-target check uses
`b.createModule(…)` with a private name, because a check needs the module
compiled *for that target*, not published once. Artifact names are decorated
per target (`fast_float-tests-x86_64-linux`), so six steps with one name do not
make `--summary all` unreadable and do not write six objects to one cache path.

**Also.** The check compiles `tests.zig` and `smoke.zig` for each target, not
just the archive: Zig analyses a function body only when something calls it, so
a `check` that compiled an unreferenced archive would prove nothing about the
facade. And `build.zig` cannot use `standardTargetOptions` to detect that
`-Dtarget` was named, because that folds "named" and "not named" into one
resolved value — a host-native cross target would be reported as "not selected"
and all six would be checked when the caller asked for one. It reads
`b.user_input_options` instead.

**Status.** `SOURCE-CONFIRMED` (`build.zig:41-52`, `95-105`;
`build_support/graph.zig:106-195`, `271-292`) and now `OBSERVED`: all six
targets compiled, one command each, 7/7 steps every time —
`…-matrix-x86_64-linux-gnu-133.log`, `-aarch64-linux-gnu-137`,
`-aarch64-macos-none-140`, `-x86_64-windows-gnu-143`, `-riscv64-linux-gnu-146`,
`-wasm32-wasi-149`, all exit 0. That is compile evidence and nothing more: no
foreign binary was run, because no emulator and no cross linker is assumed.

---

## 9. Two integration mismatches, both since closed

Found while wiring the documentation and the integrity record to what the
package actually ships. Both were reported rather than fixed at the time,
because the files involved belonged to other owners. Both owners have since
acted; the diagnosis is kept because the shape of both is worth recognising.

### 9a. A grep literal one character away from the text it was looking for

`verify.yml`'s provenance job used to contain:

```sh
grep -q 'Apache 2' testdata/README.md || {
  echo "testdata/README.md no longer records the corpus licence" >&2; exit 1; }
```

`testdata/README.md` read `Licence: Apache-2.0; the licence text is
\`supplemental/LICENSE\`, …`. There was no occurrence of `Apache 2` with a space
anywhere in that file, so the grep matched nothing and the provenance job would
have failed on a licence that *was* recorded. The intent of the check was sound;
the literal was one character away from the text it was looking for.

**Closed.** The grep is gone. The provenance job now checks the three upstream
licence texts by name in `NOTICE.md` and in upstream's own `README.md`, and
checks corpus integrity by running `sha256sum -c UPSTREAM.sha256` outright —
which is a stronger statement than any substring match, because it reads the
bytes rather than a sentence about them. So neither side needed the one-token
spelling fix that was originally offered.

### 9b. `UPSTREAM.sha256` was not in `build.zig.zon` `.paths`

`.paths` listed `UPSTREAM.md`, `NOTICE.md`, `CHANGELOG.md`, `FORK-NOTES.md` and
`README.zig.md`, and not the integrity record. The check
`sha256sum -c UPSTREAM.sha256` therefore worked in this repository and in a
clone, but a dependent who fetched the package did not receive the record — and
a record that names files the package does not ship would fail anyway, which is
why the record's scope was drawn to `.paths` in the first place.

**Closed.** `build.zig.zon` `.paths` now lists `"UPSTREAM.sha256"` next to the
other fork records, so `sha256sum -c UPSTREAM.sha256` works in an unpacked
package as well as in a clone. The check has been run and passed: 73 records, no
failures (`…-fast_float-immutable-source-integrity-124.log`).

**Status.** Both `OBSERVED` as closed, by reading the current `verify.yml` and
`build.zig.zon` and by running the integrity check. Neither `verify.yml` job has
been run in this workspace, because the provenance job reads git history and no
run here does.

---

## 10. What the integrity record covers, and what it does not

**Decision.** `UPSTREAM.sha256` holds 73 records in three groups: upstream's nine
library headers (177,467 bytes), upstream's 48-file C++ test tree (299,185
bytes), and the sixteen vendored corpus files — 274,299,340 bytes of data, the
donor's own `README.md` and `CMakeLists.txt` (657 bytes), and one Apache-2.0
text this fork sourced rather than copied (11,323 bytes). Fifteen of those
sixteen are donor bytes; the sixteenth is not, which is why note 12 exists.

*Why not every upstream-owned `.paths` entry.* `benchmarks/`, `cmake/`, `ci/`,
`docs/`, `script/`, `fuzz/` and the loose upstream build files are carried for
provenance and are compiled or read by nothing in this package. Hashing them
would make the record a hash of the repository rather than of the library, and
would add 21 files whose loss could not change a build result. A record is
useful in proportion to what it protects.

*Why `.gitignore` is absent.* It is the one upstream file this fork edits
(entries appended), so it is not byte-identical to upstream and a digest would
bless the fork's own text as if it were upstream's. The append is recorded in
`NOTICE.md`.

*Why the three upstream licence texts are absent.* They are already pinned
better than a digest could pin them: `verify.yml`'s provenance job runs
`git diff --name-only` against the pinned commit over `LICENSE-APACHE`,
`LICENSE-BOOST` and `LICENSE-MIT` by name. Hashing the working tree would only
prove the tree has not changed since this file was written, which is the weaker
statement.

*Why the corpus licence text is present, and why it is the important one.* No
gate compares it by name — `verify.yml` checks the three upstream texts by name
and leaves the corpus to `sha256sum -c` — so a dropped corpus licence would
otherwise pass every job and still be an Apache-2.0 distribution failure. It is
also the only vendored file this fork sourced rather than copied from a pinned
donor commit, so it is the one where "the same bytes as upstream" is not
available as a substitute for a digest.

*Why the record does not hash itself.* A checksum file cannot contain its own
digest.

*Why build output cannot appear.* The record enumerates the three source
subtrees explicitly rather than walking the repository root, and
`.zig-cache/`, `zig-cache/`, `zig-out/` and the `consumer/` equivalents are
absent from `.paths` and ignored by `.gitignore`.

*How the digests were produced.* Each file was read as raw bytes with
`Bun.file(path).arrayBuffer()` and hashed with `createHash("sha256")` from
`node:crypto`, on 2026-10-01. No shell hashing command and no git command was
used. All 73 records were then re-derived from the written file and compared
against the bytes on disk, and the record's path set was compared against a fresh
walk of the three subtrees — no missing path, no extra path — before this note
was written.

*What it proves.* That the bytes a build compiles and the fixture its tests read
are the bytes this record pins. *What it does not prove.* That they equal commit
`b0ab987b3dfdde13fa1915f65ef2a5c068d9208c`: that rests on the import and on the
`git archive` stream digest recorded in `UPSTREAM.md`, both produced by the
driver, not by anything computed here.

**Status.** `OBSERVED` for the gate as well as the file set:
`sha256sum -c UPSTREAM.sha256` reports 73 records and no failures
(`…-fast_float-immutable-source-integrity-124.log`).

---

## 11. What has been observed, and what has not

Recorded so a later reader does not mistake silence for a result, in either
direction. `README.zig.md` § "Verification status" carries the same rows in the
form a reader is more likely to look at first; this table adds the reason.

| Gate | State | Note |
|---|---|---|
| `zig build test` (Debug) | `OBSERVED` green, 13/13 | `local://foundation-cross-test-stable-fast_float-native-Debug.log` (this wave: `zig build test smoke install -Doptimize=Debug -j8 --summary all --color off`, 12/12 steps); `…-final-debug-97.log` in the earlier round; was red at 12/13, note 3 |
| `zig build test` (ReleaseSafe) | `OBSERVED` green, 13/13 | `local://foundation-cross-test-stable-fast_float-native-ReleaseSafe.log` (this wave: `zig build test smoke -Doptimize=ReleaseSafe -j8 --summary all --color off`, 10/10 steps); `…-final-releasesafe-100.log` earlier; same case, same note |
| `zig build smoke` | `OBSERVED` green | ran inside both stable native steps above, and on its own at `…-final-smoke-92.log`; reads no fixture and no test oracle, so notes 3 and 4 could not have affected it |
| `zig build run` in `consumer/` | `OBSERVED` green | `local://foundation-cross-test-stable-fast_float-native-consumer.log` (this wave, 6/6 steps); `…-consumer-repair-proof-112.log` earlier; was red at the unit comparison, note 4 |
| `zig build` (install, approved prefix) | `OBSERVED` green, 6/6 | `…-installed-artifact-gruenau8-176.log` |
| installed C surface, from outside the graph | `OBSERVED` green | `…-installed-C-surface-181.log`; both round-to-even ties, the write-nothing path and the write-both path |
| installed upstream C++ surface, from outside the graph | `OBSERVED` green | `…-installed-upstream-Cpp-surface-corrected-extraction-196.log`; a direct `from_chars` call, its `invalid_argument` path, and a real 16-byte bridge call on the tie |
| `zig build check`, six targets | `OBSERVED` green ×6, 7/7 steps each | `…-matrix-*-133/137/140/143/146/149.log`, and again this wave as the SDK-correction baseline: `local://foundation-cross-test-baseline-fast_float-{x86_64-linux-gnu,aarch64-linux-gnu,aarch64-macos-none,x86_64-windows-gnu,riscv64-linux-gnu,wasm32-wasi}.log`, all six exit 0, 2.9 s to 5.2 s each. Note 8. Compile evidence only — no foreign binary is run by any of them |
| `sha256sum -c UPSTREAM.sha256` | `OBSERVED` green, 73/73 | `…-immutable-source-integrity-124.log`; note 10 |
| `cross-test`, 53 platforms, first full sweep | `OBSERVED` red: 17 pass / 33 build-only / 3 fail | `local://foundation-cross-test-matrix-fast_float-{x86_64,aarch64,aarch64_be}-linux.log` — three per-test deadline timeouts, note 15 |
| `cross-test`, 53 platforms, corrected deadlines | `OBSERVED` green: 20 pass / 33 build-only / 0 fail, 13/13 on every executed cell | `local://foundation-cross-test-corrected-fast_float.json`; note 15 |
| `zig fetch`, in-package integrity and in-package consumer, final round | `NOT RUN` | the earlier round's receipts stay history; a fresh fetch, digest and consumer round against this tree has not run |
| `verify.yml` `provenance` job | `NOT RUN` | reads git history, which no run in this workspace has done; note 9a |
| `verify.yml` `c-surface` job | `NOT RUN` | the same two surfaces were built and run here by hand (rows above), but the job itself has not executed |
| system mode | not applicable | note 5 |

Nothing in the green rows is a system-wide claim. A cross target that compiles
is compile evidence and nothing more, and no gate anywhere in this workspace
compares against a system-installed fast_float, because there is no such thing
to compare against.

---

## 12. The donor repository has no licence of its own

**Condition.** `testdata/supplemental/` was described, in the first draft of
every record here, as a copy of `fastfloat/supplemental_test_files` at
`088643e8d5010bd3d1540fe48685601b43b9a3e5` "vendored byte for byte", sixteen
files, "the donor's own `LICENSE`" among them.

**Symptom.** Not a failure — a provenance claim that does not survive contact
with the tree. The donor repository at that commit has fifteen files: the
thirteen data files, its `README.md` and its `CMakeLists.txt`. There is no
`LICENSE` in it. The file dates say so independently: every donor file carries
the donor commit's date, and `testdata/supplemental/LICENSE` alone carries the
date this fork was assembled.

**Cause.** The donor is a *hosting* repository, not the producer. Its README
points at the producer and at the producer's licence and vendors no copy of its
own — which is exactly the right thing for a repository of other people's
fixtures to do, and easy to misread from the outside as a missing file.

**Fix.** The corpus's grant is now stated as the corpus's own words rather than
as a byte-for-byte property of the donor. The vendored `supplemental/README.md`
credits Nigel Tao for "the data" and links
`https://github.com/nigeltao/parse-number-fxx-test-data/blob/main/LICENSE`; that
link is where this fork took the Apache-2.0 text it ships at
`supplemental/LICENSE`. `NOTICE.md`, `UPSTREAM.md` and `testdata/README.md` all
now say the same thing in the same shape: fifteen donor files, plus one
separately sourced licence text, sixteen hashed records. The shipped text is
byte-distinct from this repository's `LICENSE-APACHE` — 11,323 bytes against
10,767, because the fork's copy carries upstream's copyright line and the
corpus copy does not — so neither can be mistaken for the other, or for a
donor byte.

**What that grant covers, stated rather than assumed.** The credit is for "the
data", not for a named subset of it, and the four `remyoudompheng-fptest-*.txt`
files this fork carries but does not read are part of that data. So the same
single Apache-2.0 grant covers the nine files read and the four not read
(note 7), and the corpus has no alternative grant to choose between — unlike
upstream, whose triple is untouched by any of this.

**Lesson worth keeping.** "Vendored byte for byte" is a claim about a
comparison, and the comparison has to be against something real. When the only
copy of a licence is the one you wrote, saying it came from the upstream
repository is not a small inaccuracy: it is the whole basis on which the
redistribution is lawful.

**Bound to.** The pinned donor commit. A future re-vendor has to redo this
check, because a repository that ships no licence at one commit may ship one at
another, and the two cases need different sentences.

**Status.** `SOURCE-CONFIRMED` — read out of the vendored directory, the file
sizes, the differing digests of the two Apache-2.0 texts, and the dates on the
sixteen files — and `OBSERVED` in the sense that `sha256sum -c UPSTREAM.sha256`
passes over all sixteen, which is what keeps the separately sourced text
pinned.

---

## 13. Zig 0.16.0 moved two things this build graph had reached into

**Condition.** The package targets Zig 0.16.0 specifically, and the build graph
is written against that release's `std.Build`. Two of the APIs it needed were
not where an earlier release had them, and one of them fails to *compile* —
which is a useful property, because a build-graph mistake is caught before it
can be mistaken for a library defect.

**Symptom.** The first build of this fork did not compile at all:

```
build.zig:51:20: error: no field named 'user_input_options' in struct 'Build.Graph'
    return b.graph.user_input_options.contains("target");
                   ^~~~~~~~~~~~~~~~~~
build_support/graph.zig:284:53: error: expected enum or union; found '?Target.Cpu.Arch'
    const label = b.fmt("{s}-{s}", .{ @tagName(query.cpu_arch), @tagName(query.os_tag) });
```

**Cause.** Two different mistakes, same release. `user_input_options` hangs off
`*std.Build`, not off `b.graph` — `b.graph` is a `std.Build.Graph` and has no
such field, and the error names the struct to say so. And `query.cpu_arch` is
`?std.Target.Cpu.Arch` on an unresolved `Target.Query`, so `@tagName` has
nothing to take a tag of; the arch only becomes a plain enum once the query is
resolved.

**Fix.** `build.zig:51` reads `b.user_input_options.contains("target")`. The
`standardTargetOptionsQueryOnly` call registers the option under exactly that
name (`std/Build.zig:1474-1478`) and every `-Dname=value` the user passed is a
key in that map (`std/Build.zig:1167`), so the test is sound against this
release. `graph.zig:284` calls `b.resolveTargetQuery(query)` first and takes
`@tagName(target.result.cpu.arch)` from the resolved value, which is the same
arch the compiler will actually use, not the one the caller guessed.

**Also worth recording.** Both manifests carry a `.fingerprint`, which Zig
0.16.0 requires: `build.zig.zon` has `0xbcccf847f76fd221` for `.fast_float`, and
`consumer/build.zig.zon` has `0xae533587b6809f99` for `.fast_float_consumer`.
The two are deliberately different — they are different packages with different
names, and a shared value would be a collision, not a shortcut. The consumer's
existence at all is the point of it: a separate package with its own
fingerprint, depending on this one by relative path, is what makes
`dep.module("fast_float")` a claim about a published module rather than a
within-tree import.

**Bound to.** Zig 0.16.0. Both line references and both field paths are
release-specific, and `build.zig.zon` pins `.minimum_zig_version = "0.16.0"`, so
a future re-sync has to re-check them against the release it moves to.

**Status.** `OBSERVED` —
`local://foundation-expansion-fast_float-initial-debug-17.log`, exit 2, is the
failing run; `…-fast_float-final-debug-97.log`, exit 0 with 13/13, and the six
matrix receipts, are the run after the fix.

## 14. `isNative()` is false for every query that names a target

**Condition.** A build graph that wants to behave differently for "the host" and
"some other target" has to ask the resolved target which one it is. The obvious
question is `target.query.isNative()`, and it is the wrong question.

**Symptom.** `cross-test --no-profile --targets x86_64-linux --jobs 1
--build-jobs 4 --build-timeout 900` exited 1 with `build=pass`, `run=fail`,
`reason=no_test_results` — on an x86_64 Linux host, for the x86_64 Linux target.
The build log has no `run test` step anywhere in the summary tree: 6/6 steps
succeeded, `compile test fast_float-tests Debug x86_64-linux success` hangs off
`test success`, and nothing ran. Thirteen tests were compiled and zero executed.
Receipt:
`/home/tmp2/gertullj/scratch/foundation-libs/cross-test-01a0f400/before/fast_float/`.

**Cause.** In Zig 0.16.0, `std.Target.Query.isNative()` is
`isNativeTriple() and ofmt == null` (`lib/std/Target/Query.zig:396-398`), and
`isNativeTriple()` is `isNativeCpu() and isNativeOs() and isNativeAbi()`
(`:392-394`) — all three of which test for a **null** field (`:377-390`).
`isNative` therefore answers "did the caller name a target?", not "is this the
machine I am on?". `-Dtarget=x86_64-linux` sets `cpu_arch` and `os_tag`, so the
answer is false even when the result is bit-for-bit the host target. A
cross-compilation driver that *always* passes `-Dtarget` therefore never takes
the "I can run this" branch, for any target, including its own.

The related mistake one layer out is worth naming, because the file already
half-knew this. `build.zig`'s `target_was_named` comment observed that
`standardTargetOptions` folds `-Dtarget=X` and "no `-Dtarget` at all" into one
resolved value, and reached for `b.user_input_options` to tell them apart.
That is correct and is still needed for `check` — but it works around the
question at the outer layer while the inner layer kept asking the broken one.
`check` was never affected: it iterates `graph.required_targets` explicitly and
never asks about nativeness at all.

**Fix.** `build.zig` no longer asks. `test` attaches
`b.addRunArtifact(tests)` unconditionally, and the question of who executes that
binary is left to the caller: natively for a host target, through an external
executor (QEMU user mode, Wine, wasmtime) for a foreign one, and as
build-only coverage — skipped, compile dependencies intact, never a pass — where
no executor exists. A package that has to answer this question for itself can
compare the resolved `std.Target` against `std.zig.system.NativeTargetInfo.detect`,
which is what `isNative()` does *not* do.

**Targets bound.** Zig 0.16.0, by line number and by the shape of the query
struct; a future release may redefine what `isNative` means. The lesson itself is
not version-bound: a build-graph branch on "am I native" is suspect whenever the
driver that invokes the build passes a target on every invocation, which is what
every cross-compilation matrix driver does. Check the summary tree for the run
step before concluding that a test binary executed.

**Status.** `OBSERVED`, on both sides. The failure is
`/home/tmp2/gertullj/scratch/foundation-libs/cross-test-01a0f400/before/fast_float/`,
exit 1, `reason=no_test_results`, 6/6 steps and no `run test` step in the tree.
The cause is `SOURCE-CONFIRMED`
(`lib/std/Target/Query.zig:377-398` in the pinned compiler). The fix is
`OBSERVED`: the first full 53-platform sweep after it compiled all 53 targets
and executed the suite in 17 of them, and the corrected sweep executed it in
20, 13/13 on every one — see note 15 for the three cells that failed on the
deadline rather than on a wrong answer.

---

## 15. A fixed-cost fixture loop needs a deadline set from the slowest cell

**Condition.** `cross-test`'s standard `zig-build` mode passes `--test-timeout
300s` to every target's `zig build test`, and the settings profile this package
ships can raise it. The corpus test — `every selected corpus file matches its
recorded bit patterns at both widths` — reads 1,382,483 rows at two widths, so
its work is fixed and known in advance rather than dependent on the target.

**Symptom.** Observed, not predicted. The first full 53-platform sweep (run
`20261002-040251-43214-11311`, exit 1) compiled all 53 targets and executed the
whole suite in 17 of them, 13/13 each. Three cells failed on the deadline, not
on a wrong answer: `x86_64-linux` after 5m98.837ms, `aarch64-linux` after
5m18.377s, `aarch64_be-linux` after 5m1.042s — `Build Summary: 5/7 steps
succeeded (1 failed); 12/13 tests passed (1 timed out)` on each, with the same
test named as the one that timed out.

**Cause.** What changed between the red sweep and the green one is the deadline,
not the test: the same nine files, the same rows, the same widths and the same
Debug mode ran in both, and no receipt from either sweep shows a wrong bit
pattern. Two of the three cells ran under `/bin/qemu-aarch64` rather than
natively, which is a plausible part of the story. **Why the natively executed
`x86_64-linux` cell was also among the three is not established here**: that
sweep ran two targets at a time with four build jobs each on a shared host and
captured no per-cell CPU accounting. What the receipts do establish is that the
corpus completed and agreed wherever it was given the time.

**Fix.** `cross-test.profile.sh` now sets `CROSS_BUILD_TIMEOUT=3600` and
`CROSS_TIMEOUT=1800` beside `CROSS_BUILD_STEP=test` and `CROSS_BUILD_JOBS=4`.
Nothing else moved: no file dropped out of the nine, no rows sampled, no width
skipped, and Debug was not remapped to an optimized mode to buy wall clock. The
three timeout receipts are kept — they are the evidence that the deadline, and
not the corpus, is what this note is about.

**Targets bound.** The harness's default per-test deadline in this `cross-test`
version, and the relative speed of emulated cells on one host. The lesson is not
"raise timeouts". It is that a per-test deadline has to be set from the slowest
cell the matrix will actually run rather than inherited from a default, and that
the honest evidence for a deadline change is the timeout receipts it replaces,
kept rather than erased.

**Status.** `OBSERVED` — `cross-test --jobs 2 --build-jobs 4 --build-timeout
3600` under this profile, run `20261002-060543-20930-1891`, exit 0: 20 targets
`pass` with 13/13 each, 33 `build_only` with reason `runtime_unavailable`, 0
fail (`local://foundation-cross-test-corrected-fast_float.json`, per-target logs
beside it). `x86_64-linux` finished natively in 2 s and `aarch64-linux` under
`/bin/qemu-aarch64` in 32 s, each printing all nine per-file line counts at both
widths.

