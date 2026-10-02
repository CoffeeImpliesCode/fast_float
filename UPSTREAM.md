# UPSTREAM.md — what this fork is a fork of

## Upstream

| | |
|---|---|
| Project | fast_float, a fast header-only C++11 correctly-rounded decimal-to-binary parser |
| Canonical repository | `https://github.com/fastfloat/fast_float.git` |
| Pinned ref | annotated tag `v8.3.0` |
| Pinned commit | `b0ab987b3dfdde13fa1915f65ef2a5c068d9208c` |
| Version of the C++ library built here | `8.3.0` |
| Licence | `Apache-2.0 OR BSL-1.0 OR MIT` |
| Copyright | `Copyright 2021 The fast_float authors` |

Where each of those comes from, read out of the carried tree:

* The version is `CMakeLists.txt:4`, `project(fast_float VERSION 8.3.0
  LANGUAGES CXX)`, and independently `include/fast_float/float_common.h:19-21`,
  which defines `FASTFLOAT_VERSION_MAJOR 8`, `FASTFLOAT_VERSION_MINOR 3`,
  `FASTFLOAT_VERSION_PATCH 0`. It is the version of the C++ library, not a
  version of the Zig wrapper, and it is what `build.zig.zon` carries in
  `.version`.
* The licence triple is `README.md:675-677`: "Licensed under either of … Apache
  License, Version 2.0 … or MIT license … or BOOST license". All three texts
  ship, unedited and distinct: `LICENSE-APACHE`, `LICENSE-MIT`, `LICENSE-BOOST`.
  Upstream puts no per-file notice in its headers, so the grant itself lives
  only in that README line, which is why the README travels with the package.
* The copyright line is the one the two licence texts carry for themselves
  (`LICENSE-APACHE:178`, `LICENSE-MIT:3`): "Copyright 2021 The fast_float
  authors". `AUTHORS` names Daniel Lemire and João Paulo Magalhaes;
  `CONTRIBUTORS` names eleven further people.
* `README.md:661-670` also records two credits that are not the same as a
  licence grant and are not lost: the library "includes code adapted from
  Google Wuffs (written by Nigel Tao) which was originally published under the
  Apache 2.0 license", and Rémy Oudompheng's fast path for long digits is
  upstream's own. The Apache-2.0 obligation that travels with the adapted Wuffs
  code is satisfied by `LICENSE-APACHE`, which is shipped whole.

**Tag signature: not verified here.** No GPG key was consulted while this file
was written and no git command was run, so nothing here is an observation of
the clone's own state. Treat the commit id and the archive digest below as the
provenance anchors, not as a signature check.

## Archive receipt

The workspace delivery record `local://foundation-expansion-source-archives.json`
holds a SHA-256 receipt for the deterministic `git archive` stream of the **full
tree** at that commit. For this library it reads, verbatim:

```
8ab440aef85519ec938b6515c2b0f0640768c4d9c666b4946139122aaf8b4d68  -
```

The trailing `-` is `sha256sum`'s name for standard input: the digest is of the
archive stream as it was piped past the hasher, not of any file in this
repository. It was produced by the driver when the fork was imported, and is
recorded so a later re-fetch can be compared against the same bytes.

## The known-answer corpus is a second repository

`testdata/supplemental/` is not part of fast_float's own repository, is not this
fork's work, and is **not** under upstream's licence triple — it is a separate
Apache-2.0 work. It is a copy of `fastfloat/supplemental_test_files` at commit
`088643e8d5010bd3d1540fe48685601b43b9a3e5`. It is the corpus upstream's own test
suite reads (`tests/basictest.cpp` carries `TEST_CASE("supplemental")` at `:557`
and iterates it), and it is the corpus this fork's `tests.zig` reads in full at
both widths.

**Fifteen of the sixteen vendored files are donor bytes; one is not.** The donor
repository at that commit holds the thirteen data files, its `README.md` and its
`CMakeLists.txt`, and no `LICENSE` of its own. Those fifteen are vendored byte
for byte. The sixteenth, `testdata/supplemental/LICENSE`, was taken by this fork
from the producer's own copy of the Apache-2.0 text at the URL the donor's
`README.md` names, so it is a copy of the same licence rather than a donor byte;
it is byte-distinct from this repository's `LICENSE-APACHE`, which carries
upstream's copyright line and this one does not.

**The credit and the grant are the corpus's own words.** The vendored
`supplemental/README.md` reads "Supplemental data files for testing floating
parsing (credit: Nigel Tao for the data)" and then "LICENSE file (Apache 2):
https://github.com/nigeltao/parse-number-fxx-test-data/blob/main/LICENSE". That
grant covers the corpus as vendored, the four `remyoudompheng-fptest-*.txt` files
this fork carries but does not read included: the credit is for "the data", not
for a named subset of it.

Provenance, the per-file line counts, the column format, the range-outcome
convention and the independent cross-check of the recorded bit patterns are in
`testdata/README.md`. That file is fork-authored and is not hashed by
`UPSTREAM.sha256`; the sixteen vendored files it describes are — fifteen from the
donor, plus the separately sourced licence text.

## Import mechanism

A full clone of the canonical repository, so upstream's Git history is present.
The workspace delivery record states that every fork in this wave keeps the
upstream remote named `upstream`, a local `main`, and complete upstream history.
This fork adds no patch series on top of that history: the Zig package is a set
of new files in new regions, and the one upstream file that is edited at all is
`.gitignore`, which gains appended ignore entries (see `NOTICE.md`).

## What this fork is

A Zig package that compiles upstream's real header-only C++ library into a
static C ABI artifact with external linkage, translates one plain-C bridge
header for Zig, and publishes a small Zig facade over it. Nothing of the parser
is reimplemented, re-derived or reconfigured: `zig/bridge.cpp` calls
`fast_float::from_chars` once per width and reports what upstream returned, and
that call is the only place a number is ever parsed. `build.zig.zon` declares no
dependencies and nothing is downloaded at build time. `NOTICE.md` lists every
file this fork adds or edits.

**Header-only does not mean nothing to build.** Upstream's `CMakeLists.txt`
declares an `INTERFACE` target and installs `include/fast_float`; it compiles
none of the library, because all of it is templates in headers
(`include/fast_float/fast_float.h:33-37` declares `from_chars` as a template
over `float`/`double`). A template has no symbol, so there is nothing for a C
or Zig consumer to link against until something instantiates it in C++. That
something is `zig/bridge.cpp`, and it is built on every target of the required
matrix. The artifact this package installs, `libfast_float.a`, is real compiled
code containing upstream's real algorithm; it is not a shim, a stub or a
re-declaration.

## System-library mode

**Not applicable, and vacuous rather than satisfied.** There is deliberately no
`b.systemIntegrationOption` in `build.zig` and no system branch in
`build_support/graph.zig`. A header-only library installs no binary, so a
"system" fast_float on a machine is a directory of headers: there is no
installed ABI to bind to, no versioned symbol set to match, and nothing for a
system mode to select or to check. Offering the option would advertise a mode
that cannot be honoured honestly — a flag that is never read is a claim, and a
flag that is read and always takes the bundled path is worse. The rule that
applies to this fork is therefore satisfied by its own inapplicability, and it
is stated here rather than being presented as a passed gate.

This is the one required shared interface with no implementation to point at.
It is not an omission and not a deferral: there is no state in which this fork
could gain a working system mode without first becoming a different kind of
package.

## What is upstream's and is shipped unmodified

Everything named in `build.zig.zon` `.paths` that this fork did not write:

| Path | What it is |
|---|---|
| `include/` | upstream's public C++ header tree — the whole of the library, nine headers. `zig/bridge.cpp` compiles these, and they are installed wholesale so a C++ consumer keeps getting `#include <fast_float/fast_float.h>` |
| `tests/` | upstream's own C++ test suite, carried whole. Nothing in it is built by this package and none of it is deleted; it needs a C++11 test framework that is not vendored here |
| `testdata/` | the independent known-answer corpus above — Apache-2.0, **not** under upstream's triple — plus the fork's `testdata/README.md` describing it. Of the sixteen vendored files, fifteen are donor bytes and one, the licence text, was separately sourced |
| `LICENSE-APACHE`, `LICENSE-BOOST`, `LICENSE-MIT` | upstream's three licence texts, verbatim and distinct |
| `README.md` | upstream's project README, which carries the triple licence grant and the Wuffs credit |
| `benchmarks/`, `cmake/`, `ci/`, `docs/`, `script/`, `fuzz/` | upstream's benchmarks, CMake packaging, CI script, project page, release and analysis tooling, and fuzz driver, carried so the package is upstream's tree plus this fork's Zig graph rather than a subset of it |
| `CMakeLists.txt`, `BUILD.bazel`, `MODULE.bazel`, `.bazelrc`, `.clang-format`, `clang-format-ignore.txt`, `AUTHORS`, `CONTRIBUTORS`, `SECURITY.md` | upstream's own build definitions, formatting config, authorship record and security contact |

## What is carried but is not part of the package

Upstream's GitHub Actions (`.github/workflows/`, 22 files including this fork's
own `verify.yml`), its Travis and Cirrus configurations (`.travis.yml`,
`.cirrus.yml`), `dependabot.yml` and the issue and pull-request templates stay
in this repository for provenance and audit. Upstream's own CI is **not**
retargeted at this fork: those workflows keep driving the upstream maintainers'
infrastructure, and the one file under `.github/workflows/` that this fork wrote
is `verify.yml`, which names only this repository. None of the carried
configuration is in `.paths`, none of it is referenced by the build, and none of
it is hashed by `UPSTREAM.sha256`; a dependent that fetches this package will
not receive it.

## Integrity

`UPSTREAM.sha256` holds 73 records: the SHA-256 of every immutable byte this
package compiles or reads, one `<hex>  <path>` line each, in `sha256sum`
format. The set is three groups — upstream's nine library headers, upstream's
48-file C++ test tree, and the sixteen vendored corpus files (the thirteen data
files plus the donor's `README.md` and `CMakeLists.txt`, and the separately
sourced Apache-2.0 text), including the four `remyoudompheng-fptest-*.txt` files
that `tests.zig` deliberately does not read. Check it with:

```
sha256sum -c UPSTREAM.sha256
```

Because the record names only files `.paths` ships, the same command works in a
cloned repository *and* in an unpacked package fetched by a dependent. The
`#`-prefixed lines in the file's own header state, per path, why anything is
excluded; the exclusions are `.gitignore` (appended to, therefore not
byte-identical), this fork's own files, this record, and the build-output
directories (absent from `.paths`, ignored by `.gitignore`, and outside all
three enumerated subtrees by construction).

Upstream's three licence texts are deliberately **not** byte-hashed in that
record. They are already pinned by name: `verify.yml`'s provenance job runs
`git diff --name-only` against the pinned commit over
`LICENSE-APACHE LICENSE-BOOST LICENSE-MIT` and fails on any difference, which is
a stronger statement than a digest of the working tree. The corpus licence
text *is* hashed, because no gate compares it — and it is the one vendored file
this fork sourced rather than copied, so it is the one a digest is most needed
for.

**How the digests were produced.** Each file was read as raw bytes with Bun's
`Bun.file(path).arrayBuffer()` and hashed with `createHash("sha256")` from
`node:crypto`, on 2026-10-01. No shell hashing command and no git command was
used to produce them. Every one of the 73 records was then re-derived from the
written file and compared against the tree it names, and the path set was
compared against a fresh walk of the three subtrees, before this file was
written.

**What the record establishes.** It has been run, and it passed: 73 records, no
failures
(`local://foundation-expansion-fast_float-immutable-source-integrity-124.log`).
So the bytes a build compiles and the fixture its tests read are the bytes this
record pins, and any later edit to one of those 73 files fails the check loudly.

**What it does not establish.** It is not a signature, not a Git object id, and
not a re-derivation from commit `b0ab987b3dfdde13fa1915f65ef2a5c068d9208c`: it
is a hash of this working tree. That the tree equals that commit rests on the
import and on the archive digest above, both of which the driver recorded, not
on anything computed while writing this file. Replaying the check against
upstream is the parent's job and needs a re-fetch:

```
git -C <clone> archive --format=tar b0ab987b3dfdde13fa1915f65ef2a5c068d9208c | sha256sum
```

The output must read `8ab440aef85519ec938b6515c2b0f0640768c4d9c666b4946139122aaf8b4d68  -`,
and `sha256sum -c UPSTREAM.sha256` must then report 73 records and no failures.
The first is what `local://foundation-expansion-source-archives.json` records
for this commit; the second is what this workspace observed.

**Packaging note, now closed.** `UPSTREAM.sha256` was a new file at the package
root that `.paths` did not name, so the check worked in a clone but a dependent
who fetched the package would not have received the record. `build.zig.zon`
`.paths` now lists `"UPSTREAM.sha256"` next to the other fork records, so the
check travels with the package. `CHANGELOG.md` entry 9 and `FORK-NOTES.md`
note 9b recorded it as outstanding; both are closed.

## Synchronising with a new upstream release

1. `git fetch upstream`, then check out the new tag and read
   `include/fast_float/float_common.h` `FASTFLOAT_VERSION_*`; those macros, not
   the tag spelling, are the version.
2. Replace `include/` and `tests/` wholesale from the new commit. Do not
   hand-patch upstream files to make a build problem go away.
3. Copy `LICENSE-APACHE`, `LICENSE-BOOST`, `LICENSE-MIT` and `README.md` from
   the new commit if they changed, and re-read the licence grant there.
4. Refresh `UPSTREAM.sha256` over the same path set and bump the record count
   and the byte totals in its header comment if either moved. The donor corpus
   in `testdata/supplemental/` is a separate repository: bump it only by
   re-vendoring that repository at a new commit, and record the new commit in
   both this file and `testdata/README.md`.
5. Re-check `build.zig` and `build_support/graph.zig` against the new tree: they
   name file names, upstream line references and upstream's own CMake recipes
   in their comments, and those are the things a release moves. In particular a
   default C++ standard bump upstream would have to be re-checked against the
   two thresholds named in `bridge_flags`.
6. Bump `.version` in `build.zig.zon` to the new string, update the pin in this
   file and in `README.zig.md` and in `verify.yml`'s `UPSTREAM_COMMIT`, and add
   one numbered `CHANGELOG.md` entry.

## See also

* `NOTICE.md` — attribution, the licence choice, every file this fork adds or
  edits, and the obligations that apply to them.
* `README.zig.md` — how to build, import and call the package, and the observed
  gate state.
* `CHANGELOG.md` — numbered fork-only divergences.
* `FORK-NOTES.md` — the problems met while doing this and what was decided.
* `testdata/README.md` — the known-answer corpus in full.
