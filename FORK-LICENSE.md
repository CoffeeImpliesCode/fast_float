# FORK-LICENSE.md — the licence of the files this fork authored

This file records the grant covering the files **this fork wrote**, as distinct
from the files it carried. It does not restate or replace any licence text.

## The grant

```
SPDX-License-Identifier: Apache-2.0 OR MIT OR BSL-1.0
```

The fork-authored files listed below are licensed, at the owner's election,
under **any one** of the three terms upstream offers for the library itself, with
no additional term or condition. The three texts ship verbatim and unedited:
`LICENSE-APACHE`, `LICENSE-MIT`, `LICENSE-BOOST`. **Apache-2.0 is the
alternative this repository administers against** — the one whose §4 duties
`NOTICE.md` and `CHANGELOG.md` are written to discharge — but no downstream is
required to take it, and nothing here narrows the other two.

**Authorization.** The owner of this workspace authorized per-project licensing
for fork-authored additions in this wave and required that the authorization and
the resulting grant both be recorded here and in `NOTICE.md`. This is that
record. It covers fork-authored files only; every carried file keeps its own
terms, below.

**Copyright.** Held by the private downstream that owns this repository. No
individual is named in this record and none is asserted. Upstream authors are not
credited with anything in the fork-authored set; their authorship of the carried
work is recorded in `NOTICE.md` and in `AUTHORS`/`CONTRIBUTORS`.

## What the grant covers

| Path | What it is |
|---|---|
| `build.zig`, `build.zig.zon`, `build_support/graph.zig` | build graph entry point, manifest, per-target assembly |
| `zig/bridge.h`, `zig/bridge.cpp`, `zig/root.zig` | the plain-C ABI header, the only C++ translation unit, the Zig facade |
| `runtime/graph.zig`, `runtime/library.zig`, `runtime/loader.zig`, `runtime/generate.zig`, `runtime/sync.c`, `runtime/sync.h` | the whole runtime-loading route `-Druntime` builds: the build wiring, this SDK's descriptor, the reusable loader core, the build-time dispatch generator, and the namespaced synchronization binding |
| `tests.zig`, `smoke.zig` | behavioural test root, smoke example |
| `consumer/` | the separate package that consumes this one by relative path |
| `cross-test.profile.sh` | settings for the `cross-test` matrix driver |
| `.github/workflows/verify.yml` | this fork's verification workflow |
| `README.md` | this fork's README (upstream's bytes are `README.upstream.md`) |
| `README.zig.md` | Zig interface documentation |
| `CHANGELOG.md`, `FORK-NOTES.md`, `NOTICE.md`, `UPSTREAM.md`, `FORK-LICENSE.md`, `UPSTREAM.sha256`, `testdata/README.md` | provenance, integrity, licence and documentation records |
| `package.nix`, `flake.nix`, `devenv.nix`, `devenv.yaml`, `.envrc` | standalone Nix packaging and development environment |
| the appended block of `.gitignore` | the fork's Zig ignore entries, below upstream's own list, which is kept verbatim |

## What the grant does not cover

Material carried, not authored, keeps its own terms. A file's licence is the
licence of the file.

| Path | Actual term |
|---|---|
| `include/fast_float/**` (9 headers) | `Apache-2.0 OR MIT OR BSL-1.0` — upstream `v8.3.0` |
| `tests/**` (48 files) | `Apache-2.0 OR MIT OR BSL-1.0` — upstream `v8.3.0` |
| `benchmarks/`, `cmake/`, `ci/`, `docs/`, `script/`, `fuzz/` | `Apache-2.0 OR MIT OR BSL-1.0` — upstream `v8.3.0` |
| `CMakeLists.txt`, `BUILD.bazel`, `MODULE.bazel`, `.bazelrc`, `.clang-format`, `clang-format-ignore.txt`, `AUTHORS`, `CONTRIBUTORS`, `SECURITY.md`, `.travis.yml`, `.cirrus.yml` | `Apache-2.0 OR MIT OR BSL-1.0` — upstream `v8.3.0` |
| `README.upstream.md` | `Apache-2.0 OR MIT OR BSL-1.0` — upstream `v8.3.0`, byte-preserved copy of upstream's `README.md` |
| `LICENSE-APACHE`, `LICENSE-MIT`, `LICENSE-BOOST` | Apache-2.0 / MIT / BSL-1.0 respectively — upstream, verbatim |
| `.github/workflows/*` other than `verify.yml` (21 files), `.github/dependabot.yml`, `.github/ISSUE_TEMPLATE/*`, `.github/pull_request_template.md` | `Apache-2.0 OR MIT OR BSL-1.0` — upstream; carried for provenance, not retargeted, not built |
| `testdata/supplemental/**` (16 files) | **Apache-2.0 only, no alternatives** — `fastfloat/supplemental_test_files` at `088643e8d5010bd3d1540fe48685601b43b9a3e5`; the grant and the Nigel Tao data credit are the corpus's own words in `testdata/supplemental/README.md` |
| the upstream portion of `.gitignore` | `Apache-2.0 OR MIT OR BSL-1.0` — upstream, verbatim and unedited |

The corpus is inventoried file by file in `NOTICE.md`, including the four
`remyoudompheng-fptest-*.txt` files that are carried, hashed and deliberately not
read. Reading fewer of them does not narrow their grant: the corpus's own README
credits "the data" without naming a subset.

## Obligations that survive the election

The `OR` is a choice for whoever takes this material. It does not release what is
already owed to the works being redistributed:

* All three upstream texts ship whole and unedited, and are named in `NOTICE.md`
  and `UPSTREAM.md` so the shipped alternatives cannot quietly reduce to one.
* **Apache-2.0 §4(b), a statement of changes**, is `NOTICE.md`'s "What this fork
  changed" with `CHANGELOG.md`. No upstream source, header, test, licence text or
  donor byte is modified, so the change statement for the carried works is the
  appended `.gitignore` block and nothing else.
* **§4(c), retention of notices**, holds because no carried file is edited.
* **§4(d), attribution**, is `NOTICE.md`.
* **The patent grant in `LICENSE-APACHE` §3 terminates on patent litigation
  against the work.** This fork adds no parsing, rounding, big-integer or
  digit-comparison code — `zig/bridge.cpp` calls `fast_float::from_chars` once
  per width and reports the result.
* **The corpus's single Apache-2.0 grant has no alternative and is not
  re-granted here.** Its text ships at `testdata/supplemental/LICENSE`,
  byte-distinct from this repository's `LICENSE-APACHE`, and every delivery
  installs both under distinct names.

## Where these terms appear in an installed output

`zig build install` writes every path below, so the Zig install and both Nix
packages carry the same set from one writer. `$out` stands for whichever install
prefix is in use.

| Path under the install prefix | Content |
|---|---|
| `$out/share/licenses/fast_float/LICENSE-APACHE` | upstream's Apache-2.0 text, verbatim |
| `$out/share/licenses/fast_float/LICENSE-MIT` | upstream's MIT text, verbatim |
| `$out/share/licenses/fast_float/LICENSE-BOOST` | upstream's BSL-1.0 text, verbatim |
| `$out/share/licenses/fast_float/NOTICE.md` | attribution, the grants and which applies where, the corpus inventory, the Apache-2.0 obligations |
| `$out/share/licenses/fast_float/FORK-LICENSE.md` | this file |
| `$out/share/licenses/fast_float/UPSTREAM.md` | provenance and the integrity record's scope |
| `$out/share/licenses/fast_float/README.upstream.md` | upstream's README, byte for byte |
| `$out/share/licenses/fast_float/testdata-supplemental-LICENSE` | the corpus's own Apache-2.0 text, under a distinct name because it is a distinct copy |

## Where these terms appear in source

Every fork-authored source and build file added by this wave carries the SPDX
identifier `Apache-2.0 OR MIT OR BSL-1.0` on its first line, which includes all
six runtime-route files: `runtime/graph.zig:1`, `runtime/library.zig:1`,
`runtime/loader.zig:1` and `runtime/generate.zig:1` as a Zig comment, and
`runtime/sync.c:1` and `runtime/sync.h:1` as the same identifier in a C comment.
Files that existed before this wave keep whatever header form they already had;
the grant is recorded per file group above.

## Related records

* `NOTICE.md` — upstream attribution, all three grants, the corpus inventory,
  every file this fork adds or edits, and the Apache-2.0 obligations.
* `UPSTREAM.md` — the pinned ref and the integrity record's scope.
* `UPSTREAM.sha256` — 73 digests over every immutable upstream and donor byte.
* `README.md` — the fork's README. `README.upstream.md` — upstream's, byte for byte.