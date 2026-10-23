# NOTICE

## Attribution

fast_float is the work of the fast_float authors. The upstream licence texts state `Copyright 2021 The fast_float authors`.

Authors: Daniel Lemire and João Paulo Magalhaes.

Contributors: Eugene Golushkov, Maksim Kita, Marcin Wojdyr, Neal Richardson, Tim Paine, Fabio Pellacini, Lénárd Szolnoki, Jan Pharago, Maya Warrier, Taha Khokhar, and Anders Dalvander.

Security contact: Daniel Lemire.

`README.upstream.md` states: “The library includes code adapted from Google Wuffs (written by Nigel Tao) which was originally published under the Apache 2.0 license.” It also credits “Rémy Oudompheng first implemented a fast path we use in the case of long digits” and credits Michael Eisel and Nigel Tao for the research the library grew out of.

`testdata/supplemental/README.md` states: “Supplemental data files for testing floating parsing (credit: Nigel Tao for the data)” and “LICENSE file (Apache 2): https://github.com/nigeltao/parse-number-fxx-test-data/blob/main/LICENSE”.

## Licence and file scope

Upstream states the choice “of Apache License, Version 2.0 … or MIT license … or BOOST license”. The three upstream texts ship verbatim and unedited.

| Path | Licence and scope |
|---|---|
| `include/fast_float/**` (9 headers), `tests/**` (48 files), `benchmarks/`, `cmake/`, `docs/`, `script/`, `fuzz/`, `CMakeLists.txt`, `BUILD.bazel`, `MODULE.bazel`, `.bazelrc`, `.clang-format`, `clang-format-ignore.txt`, `AUTHORS`, `CONTRIBUTORS`, `SECURITY.md` | `Apache-2.0 OR BSL-1.0 OR MIT`; upstream files |
| `README.upstream.md` | Same upstream grant; byte-preserved upstream README |
| `LICENSE-APACHE`, `LICENSE-BOOST`, `LICENSE-MIT` | Upstream licence texts, verbatim; Apache-2.0, BSL-1.0, and MIT respectively |
| Original entries in `.gitignore` | Same upstream grant; unchanged |
| Fork-authored paths listed below | At the owner's election, any one of `Apache-2.0 OR MIT OR BSL-1.0`, with no additional term or condition; authorized by the repository owner; copyright held by the private downstream, with no individual asserted |
| Appended block of `.gitignore` | Same fork grant; fork-authored ignore entries |
| `testdata/supplemental/**` (16 files) | Apache-2.0 only; neither upstream's alternatives nor the fork grant apply; the corpus grant covers all files, including four `remyoudompheng-fptest-*.txt` files not read by the tests |

The corpus contains 13 donor data files, the donor's `README.md` and `CMakeLists.txt`, and a separately sourced `LICENSE`. The 15 donor files are from `fastfloat/supplemental_test_files` at commit `088643e8d5010bd3d1540fe48685601b43b9a3e5`; the licence text came from the producer's copy at the URL above. The corpus README credits “the data” without naming a subset. No separate permission for the generator is claimed.

Fork-authored paths under the fork grant:

- `build.zig`, `build.zig.zon`, `build_support/graph.zig`
- `zig/bridge.h`, `zig/bridge.cpp`, `zig/root.zig`
- `runtime/graph.zig`, `runtime/library.zig`, `runtime/loader.zig`, `runtime/generate.zig`, `runtime/sync.c`, `runtime/sync.h`
- `tests.zig`, `smoke.zig`, `consumer/`, `cross-test.profile.sh`
- `README.md`, `README.zig.md`, `CHANGELOG.md`, `FORK-NOTES.md`, `NOTICE.md`, `UPSTREAM.md`, `FORK-LICENSE.md`, `UPSTREAM.sha256`, `testdata/README.md`
- `package.nix`, `flake.nix`, `devenv.nix`, `devenv.yaml`, `.envrc`
