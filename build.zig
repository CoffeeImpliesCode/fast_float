//! Build graph for the fast_float package.

const std = @import("std");
const graph = @import("build_support/graph.zig");

const manifest = @import("build.zig.zon");

const manifest_version = std.SemanticVersion.parse(manifest.version) catch
    @panic("build.zig.zon: .version is not a semantic version");

/// True when `-Dtarget` was passed; the resolved target alone does not show whether it was explicit.
fn target_was_named(b: *const std.Build) bool {
    return b.user_input_options.contains("target");
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Keep the manifest, upstream source, and installed pkg-config version aligned.
    if (manifest_version.order(graph.upstream_version) != .eq) {
        @panic("build.zig.zon .version no longer matches the version read out " ++
            "of include/fast_float/float_common.h and CMakeLists.txt; see UPSTREAM.md");
    }

    const linkage = b.option(
        std.lang.LinkMode,
        "linkage",
        "Deliver the C ABI bridge as a static archive (the default, and what " ++
            "this package has always produced) or as a real shared object with " ++
            "a soname and an export surface of exactly the two bridge entry " ++
            "points. Both variants compile the same upstream headers through " ++
            "the same C++ translation unit at the same -std=c++17; the option " ++
            "selects the delivery and never the dispatch. A target whose OS " ++
            "has no dynamic linker -- wasm32-wasi, which this package's own " ++
            "matrix walks -- cannot deliver a shared object, and asking for " ++
            "one there fails rather than falling back to an archive.",
    ) orelse .static;

    // Refuse unsupported linkage before graph construction; never substitute an archive for a shared request.
    if (linkage == .dynamic) {
        if (graph.sharedObjectRefusal(b, target)) |reason| @panic(reason);
    }

    // Dispatch selection is independent of delivered linkage.
    const runtime_loaded = b.option(
        bool,
        "runtime",
        "Resolve the bridge's native entry points at run time instead of " ++
            "linking them. The facade keeps the same translated header and the " ++
            "same public types; each selected native function becomes a " ++
            "dispatch through one process-lifetime table that an explicit " ++
            "load(source) fills, and the module links no archive. Independent " ++
            "of -Dlinkage, which still decides which artifact this build " ++
            "delivers and installs -- under -Druntime that artifact is built " ++
            "and installed as it always is, because it is what a provider is. " ++
            "Default off, and a linked build is unchanged in every respect.",
    ) orelse false;

    const native = graph.addGraph(b, target, optimize, linkage, graph.artifact_name, true, runtime_loaded);

    // Tests share the known-answer corpus through the fixture-path module.
    const fixtures = graph.addFixturePaths(b);

    b.installArtifact(native.bridge);
    graph.addPkgConfig(b, linkage);
    graph.installLicenceRecords(b);

    const smoke_exe = graph.addSmoke(b, native, target, optimize, "fast_float-smoke");
    // Installation compiles the smoke executable; the separate step below runs it.
    b.getInstallStep().dependOn(&smoke_exe.step);

    const run_smoke = b.addRunArtifact(smoke_exe);
    // Smoke checks must execute instead of reusing a cached run result.
    run_smoke.has_side_effects = true;
    b.step("smoke", "Run the smoke example and check its answers").dependOn(&run_smoke.step);

    const tests = graph.addTests(b, native, target, optimize, "fast_float-tests", fixtures);
    const test_step = b.step("test", "Run the fast_float behavioural tests for the selected target");

    // Always create a Run step for the selected target. The caller or executor decides whether a foreign binary can run.
    const run_tests = b.addRunArtifact(tests);
    run_tests.has_side_effects = true;
    test_step.dependOn(&run_tests.step);

    const check_step = b.step(
        "check",
        "Compile the C++ bridge, the translated header, the facade, the tests and the example for all six required targets without running them",
    );
    if (target_was_named(b)) {
        graph.addTargetCheck(b, check_step, target.query, optimize, linkage, runtime_loaded, fixtures);
    } else {
        for (graph.required_targets) |query| {
            graph.addTargetCheck(b, check_step, query, optimize, linkage, runtime_loaded, fixtures);
        }
    }

    std.debug.print("fast_float: upstream {f}, {s}\n", .{
        graph.upstream_version,
        switch (linkage) {
            .static => "static archive, libfast_float.a (default)",
            .dynamic => b.fmt("shared object, soname lib{s}.so.{d} exporting only the two bridge entry points", .{
                graph.artifact_name,
                graph.abi_version.major,
            }),
        },
    });
    if (runtime_loaded) {
        std.debug.print(
            "fast_float: runtime-loaded dispatch (-Druntime=true); no library " ++
                "is linked into the module, and a provider is named by an " ++
                "explicit load(source). The artifact above is still built and " ++
                "installed; it is what a .path or .system load may name.\n",
            .{},
        );
        if (linkage == .static) {
            // Static delivery needs a separate shared provider; a loader cannot open the archive.
            std.debug.print(
                "fast_float: -Dlinkage=static with -Druntime: the installed " ++
                    "artifact is an archive, which a loader cannot open. A " ++
                    "provider has to be a shared object -- the one " ++
                    "-Dlinkage=dynamic installs, or one named by the caller.\n",
                .{},
            );
        }
    }

    run_smoke.addPassthruArgs();
}
