# UPSTREAM

## Identity

| Field | Value |
|---|---|
| Project | fast_float |
| Repository | `https://github.com/fastfloat/fast_float.git` |
| Pinned ref | Annotated tag `v8.3.0` |
| Commit | `b0ab987b3dfdde13fa1915f65ef2a5c068d9208c` |
| C++ library version | `8.3.0` |
| Upstream grant | `Apache-2.0 OR BSL-1.0 OR MIT` |
| Copyright | `Copyright 2021 The fast_float authors` |
| Source | Full clone of the canonical repository at the pinned tag |
| Full-tree archive SHA-256 | `8ab440aef85519ec938b6515c2b0f0640768c4d9c666b4946139122aaf8b4d68` |

The version is the C++ library version, not an independent Zig release.

## Imported upstream paths

| Path | Inventory and state |
|---|---|
| `include/fast_float/` | 9 public headers; unchanged |
| `tests/` | 48 upstream test files; unchanged |
| `benchmarks/`, `cmake/`, `docs/`, `script/`, `fuzz/` | Carried upstream trees; unchanged |
| `CMakeLists.txt`, `BUILD.bazel`, `MODULE.bazel`, `.bazelrc`, `.clang-format`, `clang-format-ignore.txt`, `AUTHORS`, `CONTRIBUTORS`, `SECURITY.md` | Carried upstream files; unchanged |
| `README.upstream.md` | Upstream `README.md`, byte-preserved; SHA-256 `80d3197381d1a3fe7de55ac450e62b89a6d7141069b88eeca645f0543a6b2a3b` |
| `LICENSE-APACHE`, `LICENSE-BOOST`, `LICENSE-MIT` | Upstream licence texts, verbatim |
| Upstream entries in `.gitignore` | Unchanged; fork entries are appended |

Removed upstream files: not stated in the source record. The only retained upstream path with fork additions is `.gitignore`; its upstream entries are unchanged. New fork files are listed in `NOTICE.md` and `FORK-LICENSE.md`.

## Separate test corpus

`testdata/supplemental/` is a separate work from `fastfloat/supplemental_test_files`, commit `088643e8d5010bd3d1540fe48685601b43b9a3e5`. It contains 15 donor files—13 data files, `README.md`, and `CMakeLists.txt`—plus a separately sourced `LICENSE` from the producer's copy. The corpus has 16 files under its own Apache-2.0 grant, not fast_float's upstream grant. Four `remyoudompheng-fptest-*.txt` files are carried but not read by the tests. `NOTICE.md` records the corpus attribution and scope.

## Integrity record

`UPSTREAM.sha256` contains 73 records: 9 upstream headers, 48 upstream test files, and 16 corpus files. It excludes fork-authored files, `.gitignore` with its appended entries, and the record itself.
