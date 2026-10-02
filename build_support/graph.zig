//! How one target's fast_float graph is assembled.
//!
//! `build.zig` decides which steps exist. Everything that turns a
//! (target, optimize) pair into compiled artifacts lives here, so the native
//! graph and each of the six cross-target checks are built by the same code
//! rather than by two copies of it that can drift apart.
//!
//! The library is header-only C++11+. Upstream's own CMakeLists defines an
//! INTERFACE target and installs `include/fast_float`; there is nothing to
//! compile from upstream's tree. The one thing a header-only library can
//! usefully do from a package build is compile its real headers into a
//! library that has external linkage, so this file builds a C ABI bridge over
//! `include/fast_float/*.h`, translates the bridge's C header for Zig, and
//! hands both to a facade module.
//!
//! There is deliberately no `b.systemIntegrationOption`. A header-only library
//! installs no binary, so a "system" fast_float is a directory of headers with
//! no installed ABI to bind to and nothing for a system mode to select; adding
//! the option would advertise a mode that cannot be honoured. The rule is
//! vacuous here, not satisfied. See UPSTREAM.md, "System-library mode".

const std = @import("std");

/// Upstream's public C++ header tree. These nine headers under
/// `include/fast_float/` are the whole of upstream's library; the bridge below
/// compiles them into the artifact this package installs.
pub const upstream_include = "include";

/// The fork's C ABI bridge. `zig/bridge.h` is plain C, is the root source file
/// of the translate-c run, and is the header a C consumer includes. Its own
/// directory is on the translation line because `zig/` is not a system include
/// directory.
pub const bridge_header = "zig/bridge.h";

/// The only C++ translation unit in the package.
pub const bridge_source = "zig/bridge.cpp";

/// The name the bridge header is installed under. `bridge.h` is too generic to
/// publish next to the nine upstream headers, and this is the name a C consumer
/// will `#include`, so it is fixed here once.
pub const bridge_header_install_name = "fast_float_bridge.h";

/// The artifact name. It is also the package name and the public module name,
/// so `zig-out/lib/libfast_float.a`, `@import("fast_float")` and
/// `#include <fast_float_bridge.h>` all name the same thing from three sides.
pub const artifact_name = "fast_float";

pub const facade_root = "zig/root.zig";
pub const tests_root = "tests.zig";
pub const smoke_root = "smoke.zig";

/// The independent known-answer corpus, read from disk at test run time rather
/// than embedded. The corpus is 262 MB across thirteen files; embedding it
/// would put those bytes in the test object once per optimize mode and once
/// per cross target, for a fixture that is read sequentially once.
pub const fixture_data_dir = "testdata/supplemental/data";

/// The module name the test root imports to find that corpus.
pub const fixture_module_name = "fast_float_paths";

/// Compile flags for the bridge.
///
/// `-std=c++17` is a pin, not a preference. Upstream sets
/// `FASTFLOAT_CXX_STANDARD` to 11 and asks for `cxx_std_11`, so C++17 is a
/// strict superset of what upstream asks for and is inside the range upstream's
/// own CI exercises; it is also below the two thresholds that would change how
/// upstream's headers compile themselves, so pinning it here cannot silently
/// select a different algorithm:
///
///   * `include/fast_float/float_common.h:13` includes `<stdfloat>` only when
///     `__cplusplus > 202002L`, so the C++20 float type is off.
///   * `include/fast_float/constexpr_feature_detect.h:17` turns on
///     `FASTFLOAT_HAS_BIT_CAST` only for `__cpp_lib_bit_cast >= 201806L`, which
///     is a C++20 library feature, so `<bit>` stays out.
///
/// Leaving the standard to the compiler default would make the build depend on
/// which clang Zig ships, and a future default bump to C++20 would switch
/// upstream's code paths with no change in this repository.
pub const bridge_flags = [_][]const u8{
    "-std=c++17",
};

/// The cross-target compile matrix. Every entry must compile the C++ bridge,
/// the translated bridge header, the facade, the behavioural tests and the
/// smoke example. Nothing here is skipped and nothing here is pre-judged: if a
/// target cannot be built, the compile is attempted and reports why.
pub const required_targets = [_]std.Target.Query{
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .macos, .abi = .none },
    .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
    .{ .cpu_arch = .riscv64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .wasm32, .os_tag = .wasi },
};

/// One target's compiled artifacts.
pub const Graph = struct {
    /// The C ABI artifact a C or C++ consumer links.
    bridge: *std.Build.Step.Compile,
    /// The Zig facade, with its `c` import bound to the translated bridge
    /// header and the bridge artifact linked in.
    module: *std.Build.Module,
};

/// Builds the C ABI bridge, translates the bridge header, and builds the
/// facade module over both.
///
/// `public` selects between the package module set, which is what a dependent
/// reaches through `dep.module("fast_float")`, and a private module. A cross
/// target check needs the private form: modules are registered by name against
/// the whole build, so registering `fast_float` once per cross target would
/// leave only the last of them reachable and silently stop checking the rest.
pub fn addGraph(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    public: bool,
) Graph {
    const bridge_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        // `<cstring>`, `<cstdlib>` and `<system_error>` come in through
        // upstream's headers.
        .link_libc = true,
        // A real C++ translation unit, so the artifact has C++ linkage
        // requirements and must say so. Setting it once here is enough for
        // every consumer: `Module.linkLibrary` records the bridge in the
        // dependee's module graph (std/Build/Module.zig:649-659), and the
        // driver walks that graph transitively, including through linked
        // libraries, before emitting `-lc++` (std/Build/Step/Compile.zig:
        // 1053-1058 and 1351-1353). A test or example that links this facade
        // therefore gets libc++ without repeating the flag, and a dependent
        // package gets it the same way.
        .link_libcpp = true,
    });
    // The upstream headers have to be on the library's own compile line, not
    // only on the include tree that `installHeadersDirectory` publishes.
    bridge_mod.addIncludePath(b.path(upstream_include));
    bridge_mod.addCSourceFiles(.{
        .files = &.{bridge_source},
        .flags = &bridge_flags,
    });

    const bridge = b.addLibrary(.{
        .name = artifact_name,
        .linkage = .static,
        .root_module = bridge_mod,
    });

    // The whole upstream public header tree goes in beside the bridge, because
    // upstream installs `include/fast_float` wholesale (CMakeLists.txt:78) and a
    // C++ consumer of this package must keep getting `#include
    // <fast_float/fast_float.h>`. Attaching both to the artifact also puts
    // them on the include search path of anything that links it
    // (std/Build/Step/Compile.zig:520-522), so a dependent reaches the headers
    // without reaching into this repository's tree.
    bridge.installHeadersDirectory(
        b.path(upstream_include),
        "",
        .{ .include_extensions = &.{".h"} },
    );
    bridge.installHeader(b.path(bridge_header), bridge_header_install_name);

    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path(bridge_header),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    translate_c.addIncludePath(b.path("zig"));

    const c_module = if (public)
        translate_c.addModule("c")
    else
        translate_c.createModule();

    const module = if (public)
        b.addModule(artifact_name, .{
            .root_source_file = b.path(facade_root),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        })
    else
        b.createModule(.{
            .root_source_file = b.path(facade_root),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
    module.addImport("c", c_module);
    module.linkLibrary(bridge);

    return .{ .bridge = bridge, .module = module };
}

/// The behavioural test binary for one graph.
///
/// The facade is reachable only through this binary on the cross-target path,
/// which is what makes the check a check of the facade: Zig analyses a
/// function body when something calls it, every public facade method is called
/// from `tests.zig`, and so building this binary for a target analyses all of
/// them for that target.
///
/// It is the same artifact either way: `check` compiles it and stops there,
/// `test` compiles it and hands it to a run step. There is no second, reduced
/// test root for the foreign path, so a target that runs these tests runs the
/// whole corpus at both widths and the same thirteen cases as the host.
pub fn addTests(
    b: *std.Build,
    graph: Graph,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    name: []const u8,
    fixtures: *std.Build.Module,
) *std.Build.Step.Compile {
    const test_mod = b.createModule(.{
        .root_source_file = b.path(tests_root),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addImport(artifact_name, graph.module);
    test_mod.addImport(fixture_module_name, fixtures);
    return b.addTest(.{ .name = name, .root_module = test_mod });
}

/// Where the behavioural tests find the known-answer corpus on disk.
///
/// This is a build option module rather than a `@embedFile` and rather than a
/// convention, so the test root never guesses:
///
///   * `addOptionPath` resolves its `LazyPath` inside the options step's make
///     phase (std/Build/Step/Options.zig:448-454), which is where a `LazyPath`
///     built during `build()` is allowed to resolve, and it renders the value
///     through `LazyPath.getPath2`, i.e. relative to the build root.
///   * That relative path is sound at run time because a `Step.Run` with no
///     explicit cwd inherits the build runner's cwd
///     (std/Build/Step/Run.zig:218 and 1228), and `zig build` only runs from the
///     directory holding `build.zig`.
///
/// Only the test root imports this. `smoke.zig` and the consumer package read
/// no fixtures, and the six cross-target checks compile `tests.zig` but never
/// run it, so they carry the import for type-checking and nothing else.
///
/// The path is relative, and that is also what makes it reachable on a foreign
/// runner. A `Run` step that sets no working directory of its own inherits the
/// build runner's (std/Build/Step/Run.zig:218 and 1228), which is the directory
/// `zig build` was invoked from; an external executor -- QEMU user mode, Wine,
/// wasmtime with the working directory preopened -- runs the child in that same
/// directory, so the corpus is reached by the same relative path on every one
/// of them. Nothing here is host-specific and nothing is baked in for a
/// particular target.
pub fn addFixturePaths(b: *std.Build) *std.Build.Module {
    const options = b.addOptions();
    options.addOptionPath("data_dir", b.path(fixture_data_dir));
    return options.createModule();
}

/// The smoke example for one graph. Compiling it, and running it where the
/// target can run, is the cheapest end-to-end proof that the facade, the
/// translated header and the bridge artifact agree on types and symbols.
pub fn addSmoke(
    b: *std.Build,
    graph: Graph,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    name: []const u8,
) *std.Build.Step.Compile {
    const smoke_mod = b.createModule(.{
        .root_source_file = b.path(smoke_root),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    smoke_mod.addImport(artifact_name, graph.module);
    return b.addExecutable(.{ .name = name, .root_module = smoke_mod });
}

/// Compiles the C++ bridge, the translated header, the facade, the tests and
/// the example for one target, and attaches both binaries to `parent`.
///
/// Nothing is run. A cross-built binary cannot be executed on the host, so this
/// is compile evidence and never a claim that a foreign binary executed.
pub fn addTargetCheck(
    b: *std.Build,
    parent: *std.Build.Step,
    query: std.Target.Query,
    optimize: std.builtin.OptimizeMode,
    fixtures: *std.Build.Module,
) void {
    const target = b.resolveTargetQuery(query);
    const graph = addGraph(b, target, optimize, false);

    // Artifact names have to stay unique inside one build graph: the native
    // graph already owns the undecorated names, and six checks in a single
    // invocation would otherwise write six objects to one cache path.
    const label = b.fmt("{s}-{s}", .{ @tagName(target.result.cpu.arch), @tagName(target.result.os.tag) });

    parent.dependOn(
        &addTests(b, graph, target, optimize, b.fmt("{s}-tests-{s}", .{ artifact_name, label }), fixtures).step,
    );
    parent.dependOn(
        &addSmoke(b, graph, target, optimize, b.fmt("{s}-smoke-{s}", .{ artifact_name, label })).step,
    );
}
