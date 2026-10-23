# FORK-LICENSE.md — fork-authored files

## Grant

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

This grant covers fork-authored files only; carried files retain their own terms.

**Copyright.** Held by the private downstream that owns this repository. No
individual is named in this record and none is asserted. Upstream authors are not
credited with anything in the fork-authored set; their authorship of the carried
work is recorded in `NOTICE.md` and in `AUTHORS`/`CONTRIBUTORS`.

## Paths covered by this grant

| Path |
|---|
| `build.zig`, `build.zig.zon`, `build_support/graph.zig` |
| `zig/bridge.h`, `zig/bridge.cpp`, `zig/root.zig` |
| `runtime/graph.zig`, `runtime/library.zig`, `runtime/loader.zig`, `runtime/generate.zig`, `runtime/sync.c`, `runtime/sync.h` |
| `tests.zig`, `smoke.zig` |
| `consumer/` |
| `cross-test.profile.sh` |
| `.github/workflows/verify.yml` |
| `README.md` (fork README; upstream's README is `README.upstream.md`) |
| `README.zig.md` |
| `CHANGELOG.md`, `FORK-NOTES.md`, `NOTICE.md`, `UPSTREAM.md`, `FORK-LICENSE.md`, `UPSTREAM.sha256`, `testdata/README.md` |
| `package.nix`, `flake.nix`, `devenv.nix`, `devenv.yaml`, `.envrc` |
| The appended block of `.gitignore`; upstream's list is retained verbatim |

## Carried files and their terms

| Path | Licence and origin |
|---|---|
| `include/fast_float/**` (9 headers), `tests/**` (48 files), `benchmarks/`, `cmake/`, `ci/`, `docs/`, `script/`, `fuzz/`, `CMakeLists.txt`, `BUILD.bazel`, `MODULE.bazel`, `.bazelrc`, `.clang-format`, `clang-format-ignore.txt`, `AUTHORS`, `CONTRIBUTORS`, `SECURITY.md`, `.travis.yml`, `.cirrus.yml` | `Apache-2.0 OR MIT OR BSL-1.0`; upstream `v8.3.0` |
| `README.upstream.md` | Same terms; byte-preserved copy of upstream `README.md` from `v8.3.0` |
| `LICENSE-APACHE`, `LICENSE-MIT`, `LICENSE-BOOST` | Upstream Apache-2.0, MIT and BSL-1.0 texts, respectively; verbatim |
| `.github/workflows/*` other than `verify.yml` (21 files), `.github/dependabot.yml`, `.github/ISSUE_TEMPLATE/*`, `.github/pull_request_template.md` | `Apache-2.0 OR MIT OR BSL-1.0`; upstream files carried for provenance |
| `testdata/supplemental/**` (16 files) | Apache-2.0 only, no alternatives; `fastfloat/supplemental_test_files` at `088643e8d5010bd3d1540fe48685601b43b9a3e5`. Its grant and Nigel Tao data credit are in `testdata/supplemental/README.md`. |
| The upstream portion of `.gitignore` | `Apache-2.0 OR MIT OR BSL-1.0`; upstream, verbatim and unedited |

The supplemental corpus keeps its own Apache-2.0 grant. It is not re-granted
here; every delivery installs its licence separately from this repository's
`LICENSE-APACHE`.

## Apache-2.0 obligations

* §4(b): `NOTICE.md` and `CHANGELOG.md` state the fork's changes. Changes to
  carried work are limited to the appended `.gitignore` block.
* §4(c): notices remain because no carried file is edited. §4(d) attribution is
  in `NOTICE.md`.
* §3 terminates the patent grant on patent litigation against the work. The fork
  adds no parsing, rounding, big-integer or digit-comparison code; `zig/bridge.cpp`
  calls `fast_float::from_chars` once per width and reports its result.
