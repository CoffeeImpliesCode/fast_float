# fast_float fork notes

## Source differences

| Path | Change |
|---|---|
| `.gitignore` | Keeps upstream entries and appends Zig build-output ignores. |
| `README.md` | Adds package instructions; upstream's README is retained as `README.upstream.md`. |
| `testdata/supplemental/` | Adds a separately licensed parser corpus; four carried `remyoudompheng-fptest-*.txt` files are not read because their patterns are covered by other producers. |
| `testdata/README.md` | Records the corpus attribution and its separate Apache-2.0 grant. |
| `zig/bridge.cpp` | Instantiates the upstream `float` and `double` templates and maps `std::errc` to C statuses because the templates have no linkable C symbols. |
| `zig/bridge.h` | Declares the plain-C bridge that Zig translates. |
| `zig/root.zig` | Adds typed prefix and exact parsers plus explicit provider loading; exact parsing rejects trailing bytes. |
| `runtime/graph.zig` | Builds the runtime-loaded module graph from translated declarations. |
| `runtime/loader.zig` | Adds explicit path- or loader-name-based provider loading with typed failures. |
| `runtime/library.zig` | Binds provider validation and synchronization to the generated dispatch. |
| `runtime/generate.zig` | Generates dispatch code and the patched translation from Zig's translated header. |
| `runtime/sync.c` | Implements loader locking and thread identity with Windows, POSIX, and single-thread WebAssembly backends. |
| `runtime/sync.h` | Declares the prefix-namespaced synchronization ABI used by the loader. |
| `tests.zig` | Adds facade and corpus tests; runtime-loaded tests require `FASTFLOAT_PROVIDER`. |
| `smoke.zig` | Adds a command-line example for prefix, exact, error, and runtime-provider paths. |

The upstream `include/fast_float/`, `tests/`, and licence texts are unchanged. The appended entries in `.gitignore` are the only additions to an upstream file.

The bridge preserves upstream's output writes: success and range-error results write the value and consumed count; invalid-argument results write neither. Typed Zig parsing returns an error without a value on range failure; raw `c` calls expose the bridge outputs.

## Build graph differences

Upstream's CMake target is `INTERFACE` and compiles no library. The Zig graph compiles one C++17 translation unit, `zig/bridge.cpp`, and translates `zig/bridge.h` to provide linkable C symbols and a Zig facade. Upstream requests C++11.

- `-Dlinkage=static|dynamic` selects delivery; static is the default. Both build the same bridge. Shared delivery adds PIC and a soname; ELF and Windows restrict exports to the bridge API.
- `-Druntime=true` selects generated dispatch through an explicitly named provider. It is independent of `-Dlinkage`; the selected artifact is still built, but the module does not link it.
- There is no system-library build option: upstream installs headers, not a binary ABI. Runtime `.system` names a provider for the platform loader; it is not a build-time system-library mode.
- The runtime graph reuses one loader-core module in linked and loaded configurations, so public loader types retain one Zig type identity.
- `zig build check` compiles the tests and example for the six-target matrix, or only `-Dtarget=<triple>` when supplied; it does not run them. `zig build test` schedules execution for the selected target, which needs an external executor when it is not runnable on the host.
- The test graph passes a fixture-directory module and reads corpus files from disk. It reads nine of thirteen data files; the four retained `remyoudompheng-fptest-*.txt` files are not read because other producers cover their patterns.
- The install graph owns the artifact, headers, relocatable `fast_float.pc`, and licence records; the Nix derivation does not regenerate those files.

## Platform boundaries

- `wasm32-wasi` supports static delivery only; a dynamic request fails instead of substituting an archive.
- Runtime loading requires a dynamic provider. A static archive cannot satisfy `load`; with static delivery, the caller must name a separate shared provider.
- Windows supports shared delivery, but `fast_float.dll` must be beside the executable or on `PATH`.
- ELF and Windows shared objects export the two bridge functions. Darwin shared objects have a wider export table.
- Cross-target `check` is compile-only. Running tests for a foreign target requires an external executor.
