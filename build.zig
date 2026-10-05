//! Build for the fast_float Zig package.
//!
//! fast_float 8.3.0 is a header-only C++11+ library: upstream's own CMakeLists
//! defines an INTERFACE target, installs `include/fast_float`, and compiles
//! nothing of the library itself. There are no generated inputs and no tables
//! to generate -- upstream ships the committed headers it ships.
//!
//! What this package does with that is the only thing a header-only library
//! can usefully do from a package build: it compiles the genuine upstream
//! headers into a C ABI artifact that has external linkage, installs the
//! upstream header tree next to it, and translates the bridge's C header for
//! Zig. `build_support/graph.zig` owns that graph and every install path this
//! build owns; this file owns the steps and the options.
//!
//! There is deliberately no `b.systemIntegrationOption`. A header-only library
//! installs no binary, so a "system" fast_float is a directory of headers: no
//! installed ABI to bind to, no versioned symbol set to match, and nothing for
//! a system mode to select. Offering the option would advertise a mode that
//! cannot be honoured honestly. The rule is vacuous for this fork rather than
//! satisfied by it. See UPSTREAM.md, "System-library mode".
//!
//! Steps:
//!   (default)  install the C ABI artifact in the selected linkage, the bridge
//!              header, the whole upstream header tree, the pkg-config record
//!              and the licence material, and compile the smoke example
//!   test       build the behavioural tests for the selected target and run
//!              them, for every target including the host
//!   smoke      run the smoke example and check its own answers
//!   check      compile the bridge, the facade, the tests and the example for
//!              all six required targets without running any of them; an
//!              explicit -Dtarget narrows this to that one target
//!
//! `test` builds the same graph for whichever target was selected and hands the
//! binary to a `Run` step unconditionally. Deciding whether that binary can be
//! executed -- natively, through an external executor, or not at all -- belongs
//! to whoever drives the build; `cross-test.profile.sh` is this package's
//! settings half of that arrangement.
//!
//! The behavioural tests read upstream's independent known-answer corpus from
//! disk at run time. `build_support/graph.zig` hands them its location as the
//! module `fast_float_paths`, whose single declaration is
//! `pub const data_dir: []const u8`: the corpus directory, written relative to
//! the build root, which is the working directory every run step inherits.
//! Nothing else imports it -- the smoke example and the consumer package read
//! no fixtures.
//!
//! Options
//! -------
//!   -Dlinkage=static    a static archive, `libfast_float.a`. This is the
//!                       default and it is what this package produced before
//!                       the option existed, so a caller who passes nothing
//!                       changes nothing.
//!   -Dlinkage=dynamic   a real shared object: `libfast_float.so.0.1.0` with
//!                       `libfast_float.so.0` and `libfast_float.so` beside it,
//!                       `libfast_float.0.dylib` on Darwin, `fast_float.dll`
//!                       with its import library on Windows-gnu. It is the
//!                       same C++ translation unit over the same upstream
//!                       headers at the same `-std=c++17`, position independent
//!                       and exporting exactly the two bridge entry points;
//!                       see "Static and shared delivery" in
//!                       `build_support/graph.zig`.
//!   -Dtarget=<triple>   build for one target; `zig build check` then checks
//!                       that target only instead of the whole matrix.
//!
//!   -Druntime=true     resolve the two bridge entry points at run time
//!                       instead of linking them. The facade keeps the same
//!                       translated header and the same public types; each
//!                       native function becomes a dispatch through one
//!                       process-lifetime table that an explicit
//!                       `load(source)` fills, and the module links no
//!                       archive. Independent of `-Dlinkage`, which still
//!                       decides which artifact this build delivers and
//!                       installs -- the artifact is built and installed in
//!                       both configurations, because under `-Druntime` it is
//!                       what a provider *is*, not something the module links.
//!                       Default off, and a linked build is unchanged in every
//!                       respect. The dispatch itself is `runtime/graph.zig`,
//!                       which the API role owns;
//!                       `build_support/graph.zig` names the exact seam.
//!
//! One platform boundary belongs to `-Dlinkage` rather than to the code, and it
//! is a refusal rather than a downgrade. WASI has no dynamic linker --
//! `std.Target.DynamicLinker.kind` is `.none` for it
//! (`lib/std/Target.zig:2385`) -- and this package's own matrix walks a WASI
//! target, so `-Dlinkage=dynamic` **cannot** be delivered there. Asking for it
//! fails: for the selected target here, at configure time, and for that one
//! matrix cell inside `check`, as a failing step carrying the reason. Nothing is
//! substituted, so a caller who asked for a shared object never receives an
//! archive with a warning beside it. The default is untouched and distinct:
//! no `-Dlinkage` means `static`, which is exactly what `wasm32-wasi` takes, so
//! `zig build check` with no flag still compiles all six matrix cells, WASI
//! included. The reason is resolved in one place
//! (`build_support/graph.zig:sharedObjectRefusal`) and the default is not
//! second-guessed anywhere.

const std = @import("std");
const graph = @import("build_support/graph.zig");

/// `build.zig.zon` itself. `@import` of the manifest is how a build script
/// reads `.version` without a second copy of it; `blake3/build.zig:254` uses
/// the same import.
const manifest = @import("build.zig.zon");

/// `build.zig.zon .version`, parsed.
///
/// The parse is the loud part: a manifest whose `.version` is not a semantic
/// version fails to configure here rather than being silently compared as
/// something else.
const manifest_version = std.SemanticVersion.parse(manifest.version) catch
    @panic("build.zig.zon: .version is not a semantic version");

/// Whether the caller named a target on the command line.
///
/// `standardTargetOptions` cannot answer this: it folds `-Dtarget=X` and "no
/// -Dtarget at all" into the same resolved value, so comparing the query
/// against the host would report a host-native cross target as "not selected"
/// and check all six when the caller asked for one. The raw option table can,
/// because `standardTargetOptionsQueryOnly` registers the `target` option by
/// exactly this name (std/Build.zig:1474-1478) and every `-Dname=value` the
/// user passed is a key in it (std/Build.zig:1167).
fn target_was_named(b: *const std.Build) bool {
    return b.user_input_options.contains("target");
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // `build.zig.zon .version`, the version read out of upstream's own headers
    // and `CMakeLists.txt`, and the version the installed `fast_float.pc` states
    // are one fact. The comparison catches a manifest edited without the source
    // it describes -- the failure mode `spglib/build.zig:104-106` already
    // guards against in this workspace -- rather than letting three documents
    // name three different releases.
    if (manifest_version.order(graph.upstream_version) != .eq) {
        @panic("build.zig.zon .version no longer matches the version read out " ++
            "of include/fast_float/float_common.h and CMakeLists.txt; see UPSTREAM.md");
    }

    const linkage = b.option(
        std.builtin.LinkMode,
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

    // A requested artifact this target cannot carry is refused, never replaced.
    // The check is here, once, before any graph is built: a downgrade decided
    // deeper down would hand back an archive for a request that named a shared
    // object, and the only trace of that would be a line of output beside a
    // zero exit status. `addTargetCheck` applies the same refusal per matrix
    // cell, so the two paths cannot disagree about which targets can carry one.
    if (linkage == .dynamic) {
        if (graph.sharedObjectRefusal(b, target)) |reason| @panic(reason);
    }

    // `-Druntime` selects the *dispatch*, and it is orthogonal to
    // `-Dlinkage`: that option says which artifact this build delivers and
    // installs, this one says whether the facade calls it through a link line
    // or through a table an explicit `load(source)` fills. Default off, and a
    // linked build is unchanged in every respect.
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

    // Built once and shared: the corpus directory is the same for the test run
    // of whichever target was selected, for the six cross-target compiles of
    // the same test root, and for every target of an external matrix driver.
    const fixtures = graph.addFixturePaths(b);

    // `zig build` installs the whole closure, not just the archive. A C or C++
    // consumer gets `#include <fast_float_bridge.h>` and `#include
    // <fast_float/fast_float.h>` beside `libfast_float.a` without reaching into
    // this repository; a C consumer handed the prefix gets an answer from
    // pkg-config; and the binary travels with the licence material that covers
    // it, which a private repository does not remove.
    b.installArtifact(native.bridge);
    graph.addPkgConfig(b, linkage);
    graph.installLicenceRecords(b);

    const smoke_exe = graph.addSmoke(b, native, target, optimize, "fast_float-smoke");
    // Compiled but not run by the default step: installing is `zig build`'s
    // job, and a default step that executes a program is a side effect nobody
    // asked for. `zig build smoke` runs it.
    b.getInstallStep().dependOn(&smoke_exe.step);

    const run_smoke = b.addRunArtifact(smoke_exe);
    // The smoke example's whole purpose is to execute and compare known
    // answers. Without this flag a Run step whose inputs did not change is
    // served from the cache and the program never runs, which would let a
    // second `zig build smoke` report success without observing anything.
    run_smoke.has_side_effects = true;
    b.step("smoke", "Run the smoke example and check its answers").dependOn(&run_smoke.step);

    const tests = graph.addTests(b, native, target, optimize, "fast_float-tests", fixtures);
    const test_step = b.step("test", "Run the fast_float behavioural tests for the selected target");

    // Unconditional, for every target the caller selected, the host included.
    // The guard this replaced asked `target.query.isNative()`, and in Zig 0.16
    // that is false for *every* query that names a target at all:
    // std/Target/Query.zig:392-398 defines `isNative()` as
    // `isNativeTriple() and ofmt == null`, and `isNativeTriple()` requires
    // `cpu_arch`, `os_tag` and `abi` all null (`:377-394`). So
    // `zig build test -Dtarget=x86_64-linux` on an x86_64 Linux host took the
    // compile-only branch, compiled all thirteen tests and ran none of them --
    // and `cross-test`, which always passes `-Dtarget`, read that build as
    // `no_test_results`.
    //
    // What then happens to the run is the caller's business, and each outcome
    // is reportable as what it is. A host target executes. A foreign target
    // executes through whatever external executor the driver supplies. A
    // foreign target with no executor available is skipped with its compile
    // dependencies intact, which is build-only coverage and never a pass
    // (std/Build/Step/Run.zig:1247-1374 turns a foreign spawn it cannot perform
    // into `error.MakeSkipped`). Deciding that policy belongs to the driver
    // that owns the step, not to this graph.
    const run_tests = b.addRunArtifact(tests);
    // A test run whose compile step is unchanged is otherwise served from the
    // run cache and never executes: `.zig_test` carries no side effects
    // (std/Build/Step/Run.zig:707-713). For a binary whose one real test reads
    // its fixture corpus off disk that would report a pass without reading
    // anything, because those files are not inputs to the run step's hash.
    // Same reasoning as `run_smoke` above, and the same price: a two-second run
    // against a compile that dominates it either way.
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

    // Which artifact this configuration hands back is a fact worth reading out
    // of the build rather than inferring from a cache directory. These are
    // configure-time lines, not gate results: nothing has been compiled when
    // they print.
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
        // Dispatch is a separate fact from delivery, and a runtime-loaded build
        // links nothing into the module: the caller names a provider with an
        // explicit `load(source)` and the symbols arrive through the platform
        // loader. Printing it here is what keeps "the library is still built and
        // installed" from reading as "the module links it".
        std.debug.print(
            "fast_float: runtime-loaded dispatch (-Druntime=true); no library " ++
                "is linked into the module, and a provider is named by an " ++
                "explicit load(source). The artifact above is still built and " ++
                "installed; it is what a .path or .system load may name.\n",
            .{},
        );
        if (linkage == .static) {
            // A fact about this combination, not a correction of it: the two
            // options are orthogonal and this one is legal. An archive cannot be
            // opened by a loader, so the artifact this build installs is not
            // itself a usable provider here; the provider a caller names is a
            // shared object, either the one `-Dlinkage=dynamic` installs or one
            // this tree never built. Saying so here is cheaper than a caller
            // discovering it as a missing file from the loader.
            std.debug.print(
                "fast_float: -Dlinkage=static with -Druntime: the installed " ++
                    "artifact is an archive, which a loader cannot open. A " ++
                    "provider has to be a shared object -- the one " ++
                    "-Dlinkage=dynamic installs, or one named by the caller.\n",
                .{},
            );
        }
    }

    // Forwarded so a runtime-loading smoke run can be told which provider to
    // open: `zig build smoke -Druntime=true -- --provider <path>` reaches
    // `smoke.zig`, which reads exactly that and refuses to guess. With no
    // arguments this is inert, so a linked build's invocation is unchanged.
    if (b.args) |args| run_smoke.addArgs(args);
}