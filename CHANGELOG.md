# CHANGELOG

- Clarified the Zig API contract for facade errors, bridge statuses, prefix and exact parsing, buffer lifetimes, and runtime loading.
- Shipped `flake.lock` with the package to pin the flake's nixpkgs input.
- Added opt-in runtime-loaded dispatch with `-Druntime`; callers select a provider with `--provider` or `FASTFLOAT_PROVIDER`.
- `-Dlinkage=dynamic` now rejects `wasm32-wasi` instead of substituting a static artifact.
- Fixed `zig build install` to include `fast_float.pc` and all licence records.
- Added source-only Nix `static` and `shared` packages and a tools-only development environment; the default Nix package remains static.
- Authorized `Apache-2.0 OR MIT OR BSL-1.0` for fork-authored files; upstream and supplemental-corpus grants remain separate.
- `zig build test -Dtarget=...` now attaches a run step to every selected target; without an executor, foreign targets are build-only, not test passes.
- Corrected supplemental-corpus provenance: 15 donor files plus a separately sourced Apache-2.0 licence; the corpus grant covers all 16 files, including four unread fixtures.
- Added `UPSTREAM.sha256` to `.paths`, so fetched packages include the integrity record.
- Added the upstream known-answer corpus to the package for `zig build test`.
- Added the dependency-free `fast_float` Zig package with a C++17 bridge, module `fast_float`, `libfast_float.a`, `fast_float_bridge.h`, and upstream headers; no system-library mode is provided.
