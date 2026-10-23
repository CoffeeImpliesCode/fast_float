# fast_float

fast_float is a Zig package for upstream fast_float 8.3.0, a header-only C++ decimal-to-binary parser.
It builds the upstream parser into a C ABI library and provides a Zig facade.
The package requires Zig 0.16.0 and has no build-time dependencies.

## Source deviations from upstream

- `include/`, `tests/`, and upstream licence texts are unchanged.
- `.gitignore` keeps upstream entries and adds Zig-specific ignores.
- This `README.md` is fork-authored. Upstream's README is preserved as `README.upstream.md`.
- `zig/` adds a C++ bridge, a C ABI header, and the Zig facade. `runtime/` adds provider loading.
- `testdata/supplemental/` is a separate Apache-2.0 corpus from `fastfloat/supplemental_test_files`. See `testdata/README.md`.

## Build deviations

Upstream's CMake target is `INTERFACE`. Its templates do not produce a library.

`zig/bridge.cpp` instantiates `from_chars<float>` and `from_chars<double>`. `zig/bridge.h` exposes their results through a plain C ABI, which Zig translates.

Upstream requests C++11. This package pins C++17.

`zig build` builds and installs the selected library, `fast_float_bridge.h`, upstream headers, `fast_float.pc`, and licence records.

The package has no system-library mode. Upstream provides no binary ABI to link against.

`-Druntime=true` selects explicit run-time dispatch. The selected library is still built and installed, but the module does not link it.

## Support matrix

| Target | Static | Shared |
|---|---:|---:|
| `x86_64-linux-gnu` | yes | yes |
| `aarch64-linux-gnu` | yes | yes |
| `aarch64-macos-none` | yes | yes |
| `x86_64-windows-gnu` | yes | yes |
| `riscv64-linux-gnu` | yes | yes |
| `wasm32-wasi` | yes | no |

`zig build check` compiles all six targets. Pass `-Dtarget=<triple>` to compile one target. It does not run programs.

`zig build test -Dtarget=<triple>` builds and runs tests for one target. A foreign target needs an external executor. Compilation alone is not a test pass.

The build refuses `-Dlinkage=dynamic` for `wasm32-wasi`. It does not substitute a static archive.

On ELF and Windows, shared libraries export the two C ABI functions. Darwin shared libraries export a wider symbol set. On Windows, make `fast_float.dll` available beside the executable or on `PATH`.

## Consumption

Add the package to `build.zig.zon`:

```zig
.dependencies = .{
    .fast_float = .{ .path = "../fast_float" },
},
```

Import the module in `build.zig`:

```zig
const dep = b.dependency("fast_float", .{ .target = target, .optimize = optimize });
exe_mod.addImport("fast_float", dep.module("fast_float"));
```

The package and Zig module are named `fast_float`. The default artifact is `libfast_float.a`. Shared artifacts are `libfast_float.so.0.1.0` on ELF, `libfast_float.0.dylib` on Darwin, and `fast_float.dll` with `fast_float.lib` on Windows GNU.

`zig build install` installs `fast_float_bridge.h`, the upstream C++ headers, and the relocatable `fast_float.pc` file. C++ consumers can include `<fast_float/fast_float.h>` directly. C consumers can use `fast_float_bridge.h` and `pkg-config --libs --static` for static linkage.

| Option | Default | Effect |
|---|---|---|
| `-Dlinkage=static\|dynamic` | `static` | Select the installed artifact. |
| `-Druntime=true` | `false` | Use explicit run-time dispatch instead of link-time symbols. |
| `-Dtarget=<triple>` | host | Select a target. Without it, `check` uses the full matrix. |
| `-Doptimize=<mode>` | Zig default | Select the optimization mode. |

See `README.zig.md` for the facade API. The Nix flake provides `.#static` and `.#shared` outputs.
