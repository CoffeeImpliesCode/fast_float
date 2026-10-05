# NOTICE

## Upstream work

fast_float is the work of the fast_float authors. The copyright notice the
upstream licence texts carry for themselves reads, in `LICENSE-APACHE:178` and
in `LICENSE-MIT:3`:

```
Copyright 2021 The fast_float authors
```

`AUTHORS` names **Daniel Lemire** and **João Paulo Magalhaes** as the authors,
and `CONTRIBUTORS` names eleven further contributors: Eugene Golushkov, Maksim
Kita, Marcin Wojdyr, Neal Richardson, Tim Paine, Fabio Pellacini, Lénárd
Szolnoki, Jan Pharago, Maya Warrier, Taha Khokhar and Anders Dalvander.
`SECURITY.md` names Daniel Lemire as the security contact.

Upstream repository: `https://github.com/fastfloat/fast_float`. This fork builds
annotated tag `v8.3.0`, commit
`b0ab987b3dfdde13fa1915f65ef2a5c068d9208c`.

## The grants, and which applies where

Upstream offers three grants and states the choice in `README.upstream.md:675-677`: "of
Apache License, Version 2.0 … or MIT license … or BOOST license". All three
texts ship in this repository, byte for byte, and are not edited, shortened,
merged or restated here:

| File | Grant |
|---|---|
| `LICENSE-APACHE` | Apache License, Version 2.0 |
| `LICENSE-BOOST` | Boost Software License, Version 1.0 |
| `LICENSE-MIT` | MIT License |

* Everything this fork did **not** write that is **upstream's** — the whole of
  `include/`, `tests/`, the three licence texts, upstream's `README.upstream.md` and the
  remaining carried upstream trees — stays under that full upstream triple
  choice, unchanged. This fork narrows nothing and re-grants nothing; a
  downstream may take any of the three.
* **Upstream's README lives at `README.upstream.md`, byte for byte.** This
  repository's `README.md` is the fork's own README, authored here, in the
  canonical order: native-source deviations, native-build deviations and dated
  history, the current build/run/test matrix, then consumption. The preserved
  copy is `sha256 80d3197381d1a3fe7de55ac450e62b89a6d7141069b88eeca645f0543a6b2a3b`,
  which is upstream's own `README.md` at commit `b0ab987b3dfdde13fa1915f65ef2a5c068d9208c`.
  Everything upstream's README says — the triple licence grant, the Wuffs credit,
  the benchmark instructions — is still in this repository, and the workflow's
  provenance step reads the preserved copy rather than the fork's.
* `testdata/supplemental/` is **not** in that group and never was. It is a
  separate work with a single Apache-2.0 grant of its own, recorded under "The
  known-answer corpus is a separate Apache-2.0 work" below. The Boost-1.0 and
  MIT alternatives are not offered for it, and nothing here re-grants it.
* The licence covering **this fork's own files** — the Zig build graph, the
  facade, the C ABI bridge, the tests, the example, the consumer package, the
  `cross-test` settings profile, the Nix and devenv packaging, and this
  documentation — is **`Apache-2.0 OR MIT OR BSL-1.0`**, granted on the owner's
  explicit authorization for this wave, with its scope and SPDX identifier
  recorded in [`FORK-LICENSE.md`](FORK-LICENSE.md). An earlier revision of this
  file recorded these files as unassigned, after withdrawing an unauthorized
  Apache-2.0-only grant; that withdrawal is superseded by the present grant, and
  the history is in `CHANGELOG.md` 13 and 21.

This repository is a private downstream. That removes no obligation: the
copyright notice, all three upstream licence texts, and this file travel with
the source and with any binary or archive built from it. The corpus licence
text travels with the corpus.

## Credits upstream records, which are not the same as a grant

`README.upstream.md:661-670` records two further credits and this fork does not drop
either:

* "The library includes code adapted from Google Wuffs (written by **Nigel
  Tao**) which was originally published under the Apache 2.0 license." The
  Apache-2.0 obligation that travels with that adapted code is discharged by
  `LICENSE-APACHE`, shipped whole and unedited.
* "Rémy Oudompheng first implemented a fast path we use in the case of long
  digits", and Michael Eisel and Nigel Tao are credited for the research the
  library grew out of.

## The known-answer corpus is a separate Apache-2.0 work

`testdata/supplemental/` is **not** fast_float's own work, not this fork's, and
not under the upstream triple above. It is a copy of
`https://github.com/fastfloat/supplemental_test_files` at commit
`088643e8d5010bd3d1540fe48685601b43b9a3e5` — the corpus upstream's own
`tests/basictest.cpp` reads. Its grant is Apache-2.0, and only Apache-2.0.

* **The data is Nigel Tao's, and the corpus says so itself.** The vendored
  `testdata/supplemental/README.md` reads, in the donor's own words,
  "Supplemental data files for testing floating parsing (credit: Nigel Tao for
  the data)", and then names the licence and where to read it: "LICENSE file
  (Apache 2): https://github.com/nigeltao/parse-number-fxx-test-data/blob/main/LICENSE".
  That README is the corpus's grant, and it covers the corpus as vendored —
  including the four `remyoudompheng-fptest-*.txt` files this fork carries but
  does not read, which are part of the same corpus rather than a second work.
  `fastfloat/supplemental_test_files` is a hosting location, not the identity
  of the work, so the credit goes to the producer.
* **The donor repository has no licence file of its own at that commit.**
  `fastfloat/supplemental_test_files` at `088643e8` contains the thirteen data
  files, its `README.md` and its `CMakeLists.txt` — and no `LICENSE`. So the
  text at `testdata/supplemental/LICENSE` was not copied from the donor, and
  describing it as the donor's licence would be false. It is the Apache License
  2.0 text this fork took from the producer's own copy at the URL the donor
  README names, which makes the corpus's grant a copy of that licence rather
  than a restatement of it. It is unedited and it is byte-distinct from this
  repository's own `LICENSE-APACHE` (11,323 bytes against 10,767: the fork's
  copy carries upstream's `Copyright 2021 The fast_float authors` line, the
  corpus copy does not).
* **Counting what was vendored.** Thirteen data files plus the donor's
  `README.md` and `CMakeLists.txt` are **fifteen donor files**, byte for byte
  from the donor. The licence text is the sixteenth file in the directory and
  is the one that is not a donor file. `UPSTREAM.sha256` records all sixteen, so
  the separately sourced text cannot be dropped without the record failing.
* Provenance, per-file line counts, the column format and the independent
  cross-check of the recorded bit patterns are in `testdata/README.md`, which
  this fork authored.

### Every file the corpus contributes, and what covers it

Sixteen files, sixteen rows, one grant. Nothing below is under upstream's
triple, and nothing below is re-granted by this repository.

| File | Read by `tests.zig` | Origin |
|---|---|---|
| `testdata/supplemental/README.md` | n/a — it is the grant itself | donor repository, byte for byte |
| `testdata/supplemental/CMakeLists.txt` | n/a | donor repository, byte for byte |
| `testdata/supplemental/LICENSE` | n/a | **not a donor byte** — this fork's copy of the Apache-2.0 text at the URL the donor's own `README.md` names |
| `testdata/supplemental/data/google-double-conversion.txt` | yes, 564,745 lines | donor repository, byte for byte |
| `testdata/supplemental/data/ulfjack-ryu.txt` | yes, 599,458 lines | donor repository, byte for byte |
| `testdata/supplemental/data/ibm-fpgen.txt` | yes, 102,792 lines | donor repository, byte for byte |
| `testdata/supplemental/data/lemire-fast-double-parser.txt` | yes, 94,313 lines | donor repository, byte for byte |
| `testdata/supplemental/data/google-wuffs.txt` | yes, 10,744 lines | donor repository, byte for byte |
| `testdata/supplemental/data/freetype-2-7.txt` | yes, 3,566 lines | donor repository, byte for byte |
| `testdata/supplemental/data/lemire-fast-float.txt` | yes, 3,299 lines | donor repository, byte for byte |
| `testdata/supplemental/data/tencent-rapidjson.txt` | yes, 3,563 lines | donor repository, byte for byte |
| `testdata/supplemental/data/more-test-cases.txt` | yes, 3 lines | donor repository, byte for byte |
| `testdata/supplemental/data/remyoudompheng-fptest-0.txt` | **no** — carried and hashed only | donor repository, byte for byte |
| `testdata/supplemental/data/remyoudompheng-fptest-1.txt` | **no** — carried and hashed only | donor repository, byte for byte |
| `testdata/supplemental/data/remyoudompheng-fptest-2.txt` | **no** — carried and hashed only | donor repository, byte for byte |
| `testdata/supplemental/data/remyoudompheng-fptest-3.txt` | **no** — carried and hashed only | donor repository, byte for byte |

Every row is covered by the **single** Apache-2.0 grant the corpus states about
itself, credited to Nigel Tao for "the data" without naming files. Read and
unread are the same question here: this fork redistributes all sixteen, and the
grant is on the corpus. The Boost-1.0 and MIT alternatives upstream offers for
its own library are **not** offered for any of them, and no separate permission
for Rémy Oudompheng's generator is claimed or needed.

## Apache-2.0 obligations this repository meets

Two Apache-2.0 works are carried here — upstream's, under whichever of its three
alternatives a downstream elects, and the corpus, which has only one — and both
put the same §4 duties on whoever redistributes them: a copy of the licence (all
three upstream texts ship, and the corpus text ships beside the corpus),
a statement of the changes (§ "What this fork changed" below, which is what §4(b)
asks for), retention of the notices (§4(c), satisfied because no upstream
source, test or licence file and no donor byte is edited), and, where the work
carries a `NOTICE` file, that downstream copies carry the attribution above
(§4(d), this file).

Those duties are owed to the works being redistributed, not to the
redistribution, so they are met whether or not anyone elects the Apache-2.0
alternative. The fork's own files now carry the same three-way grant, so no
part of this repository is unlabelled.

### Patent grant

`LICENSE-APACHE` §3 grants a patent licence that terminates on patent
litigation against the work. This fork has added no code to the parsing,
rounding, big-integer or digit-comparison logic: `zig/bridge.cpp` calls
`fast_float::from_chars` once per width and reports the result, so it makes no
patent claim of its own and introduces only the risk that a modified
distribution of upstream's work would.

### The alternative grants are not narrowed

A private downstream that takes Boost-1.0 or MIT instead of Apache-2.0 removes
no obligation of its own, because the attribution, the licence texts and the
change statement here are required by the Apache-2.0 path and are kept for all
three. `verify.yml`'s provenance job checks that all three texts are present and
that this file names each of them, precisely so that a future edit cannot quietly
reduce the shipped alternatives to one.

The fork's own grant is the same three-way election: Apache-2.0 is the
alternative this repository administers against, and the §4 material this file
carries is what that alternative asks for.

## What this fork changed

**No upstream source file, header, test, licence text or donor byte is
modified.** `UPSTREAM.sha256` records the SHA-256 of all 73 immutable files the
package compiles or reads — upstream's nine library headers, upstream's 48-file
C++ test tree, and the sixteen vendored corpus files (fifteen from the donor,
plus the separately sourced licence text), including the four the tests
deliberately do not read. `sha256sum -c UPSTREAM.sha256` is the check, and it
has been run: 73 records, no failures
(`local://foundation-expansion-fast_float-immutable-source-integrity-124.log`).
`.github/workflows/verify.yml`'s provenance job separately diffs every carried
upstream path against the pinned commit, and names the three licence texts
there by file name.

One upstream file is edited, and only by appending:

| File | Change |
|---|---|
| `.gitignore` | upstream's own ignore list — `build/*`, `Testing/*`, `.cache/`, `compile_commands.json`, `bazel-*`, the Visual Studio entries, `/out/`, `*.sln`, `*.vcxproj*`, `*.psess`, `*.vsp*`, `*.diagsession`, `*.hint` and `/CMakeSettings.json` — is kept verbatim and unedited; the fork appends `.zig-cache/`, `zig-cache/`, `zig-out/`, `consumer/.zig-cache/`, `consumer/zig-cache/` and `consumer/zig-out/`, each with a comment saying why. Because the file is therefore not byte-identical to upstream's, it is deliberately absent from `UPSTREAM.sha256` and from `verify.yml`'s diff list, and the append is recorded here instead |

Everything else this fork adds is new, in new files and new regions:

| File | What it is |
|---|---|
| `build.zig` | Zig 0.16 build: compiles upstream's real headers through the C++ bridge, installs `libfast_float.a`, `fast_float_bridge.h` and the whole upstream header tree, and defines the `test`, `smoke` and `check` steps |
| `build.zig.zon` | package manifest, dependency-free, `.paths` = what a dependent receives |
| `cross-test.profile.sh` | the matrix driver's settings for this package: the standard `test` build step, four build jobs, a 3,600-second build deadline and a 1,800-second per-test deadline, with no matrix, no target list and no path on this host. It is this fork's own configuration file and carries the fork grant recorded in `FORK-LICENSE.md`, not any upstream term |
| `build_support/graph.zig` | how one target's graph is assembled; the native graph and all six cross-target checks are built by the same code |
| `zig/bridge.h` | the plain-C ABI the package exports; the single header `addTranslateC` translates, with `_Static_assert`s pinning the three status values |
| `zig/bridge.cpp` | the only C++ translation unit: includes `<fast_float/fast_float.h>`, instantiates `from_chars` at both widths, and classifies the result. No parsing, rounding or range logic is written here |
| `zig/root.zig` | the Zig facade: `parse32`, `parse64`, `parse32Exact`, `parse64Exact`, the `Error` set, and `pub const c` for the complete raw translated surface |
| `runtime/graph.zig`, `runtime/library.zig`, `runtime/loader.zig`, `runtime/generate.zig`, `runtime/sync.c`, `runtime/sync.h` | the whole runtime-loading route `-Druntime` builds, six fork-authored files that each carry the SPDX triple on line 1: `graph.zig` wires the three modules and the generated dispatch (`runtime/graph.zig:131-221`), `library.zig` is this SDK's descriptor and the only fork-specific file in the route, `loader.zig` is the reusable core a linked build imports for `LoadSource` and `LoadError`, `generate.zig` is the build-time generator that reads what the translation step actually produced, and `sync.c` with `sync.h` is the synchronization binding compiled with `-DRT_SYNC_PREFIX=fast_float_rt` (`runtime/graph.zig:215-219`). `build_support/graph.zig:110` is the one seam, and `runtime/` is in `build.zig.zon` `.paths`, so a dependent receives all six |
| `tests.zig` | 13 behavioural tests: the nine-file known-answer corpus at both widths, plus the hand-worked halfway, range, subnormal, prefix, format and ownership cases |
| `smoke.zig` | the deterministic example behind `zig build smoke`; it checks its own answers and exits non-zero on any mismatch |
| `consumer/` | a separate package that depends on this one by relative path and runs it |
| `.github/workflows/verify.yml` | this fork's own verification workflow: provenance, native, the installed C **and C++** surfaces, the six-target cross matrix and the consumer. Upstream's twenty-one other workflows are left untouched and unretargeted |
| `README.md` | the fork's README, in the canonical order: native-source deviations, native-build deviations and dated history, the current build/run/test matrix, then consumption |
| `README.upstream.md` | upstream's README, byte for byte, `sha256 80d31973…`, preserved beside the fork's |
| `UPSTREAM.md`, `UPSTREAM.sha256`, `NOTICE.md`, `FORK-LICENSE.md`, `README.zig.md`, `CHANGELOG.md`, `FORK-NOTES.md`, `testdata/README.md` | provenance, integrity, licence and fork documentation |
| `package.nix`, `flake.nix` | the standalone Nix packaging: one source-only derivation, consumed by the flake for its `static` and `shared` packages |
| `devenv.nix`, `devenv.yaml`, `.envrc` | the canonical development environment definition and its direnv entry point |

### Licence material in an installed output

`zig build install` installs all of these, so every delivery of this package --
the Zig install and the Nix `static` and `shared` packages alike -- carries the
same licence set from one generator. The corpus's distinct copy of the
Apache-2.0 text is named distinctly rather than being called `LICENSE-APACHE`:
it is a different file and calling it by that name would be false.

| Path in the output | Content |
|---|---|
| `$out/share/licenses/fast_float/LICENSE-APACHE` | upstream's Apache-2.0 text, verbatim |
| `$out/share/licenses/fast_float/LICENSE-MIT` | upstream's MIT text, verbatim |
| `$out/share/licenses/fast_float/LICENSE-BOOST` | upstream's BSL-1.0 text, verbatim |
| `$out/share/licenses/fast_float/NOTICE.md` | this file |
| `$out/share/licenses/fast_float/FORK-LICENSE.md` | the fork's own grant |
| `$out/share/licenses/fast_float/UPSTREAM.md` | provenance and the integrity record's scope |
| `$out/share/licenses/fast_float/README.upstream.md` | upstream's README, byte for byte — the grant it states travels with the output |
| `$out/share/licenses/fast_float/testdata-supplemental-LICENSE` | the corpus's own Apache-2.0 text |

The known-answer corpus itself is **not** installed into `$out` — it is 262 MB
of test fixtures that no runtime consumer reads — and it stays in the Nix
derivation's source, where `zig build test` reaches it. `zig build install` is
the only writer of this table's paths; the derivation installs nothing beside it,
so there is no second copy that could disagree.

## Correctness and security notes that survive from upstream

* **This binding parses untrusted text with upstream's `chars_format::general`
  semantics, and that includes `inf`, `infinity` and `nan`.** A caller that must
  reject non-finite input has to pre-check, or use a different parser. See
  `README.zig.md`, "The API".
* **A failed parse does not always leave the caller's out-parameters
  untouched.** On `FF_STATUS_INVALID_ARGUMENT` neither out-parameter is
  written; on `FF_STATUS_RESULT_OUT_OF_RANGE` both are, because upstream has
  already stored the infinity or zero it rounded to. This is the one asymmetry
  in the C contract, it is upstream's (`include/fast_float/parse_number.h:288`
  stores via
  `to_float` before the range test at `:290-292`), and `NOTICE.md` records it so
  a C caller does not have to rediscover it.
* **Rounding is exact and round-to-nearest, ties to even, independent of the
  FPU rounding mode** (`include/fast_float/fast_float.h:12-15`). Upstream reads
  the FPU mode only to decide whether its fast path is valid
  (`include/fast_float/parse_number.h:78-80`).

## Status of this record

The fork grant, the README relocation and the Nix output layout above are
`PENDING-VERIFICATION`: the files that state them are in the tree and no gate
has observed them. Every other statement in this file predates them and rests on
the receipts named above.
