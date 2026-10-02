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
//! Zig. `build_support/graph.zig` owns that graph; this file owns the steps.
//!
//! There is deliberately no `b.systemIntegrationOption`. A header-only library
//! installs no binary, so a "system" fast_float is a directory of headers: no
//! installed ABI to bind to, no versioned symbol set to match, and nothing for
//! a system mode to select. Offering the option would advertise a mode that
//! cannot be honoured honestly. The rule is vacuous for this fork rather than
//! satisfied by it. See UPSTREAM.md, "System-library mode".
//!
//! Steps:
//!   (default)  install the C ABI artifact, the bridge header and the upstream
//!              header tree, and compile the smoke example
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

const std = @import("std");
const graph = @import("build_support/graph.zig");

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

    const native = graph.addGraph(b, target, optimize, true);

    // Built once and shared: the corpus directory is the same for the test run
    // of whichever target was selected, for the six cross-target compiles of
    // the same test root, and for every target of an external matrix driver.
    const fixtures = graph.addFixturePaths(b);

    // `zig build` installs the C ABI artifact, the bridge header and the whole
    // upstream header tree, so a C or C++ consumer gets `#include
    // <fast_float_bridge.h>` and `#include <fast_float/fast_float.h>` next to
    // `libfast_float.a` without reaching into this repository.
    b.installArtifact(native.bridge);

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
        graph.addTargetCheck(b, check_step, target.query, optimize, fixtures);
    } else {
        for (graph.required_targets) |query| {
            graph.addTargetCheck(b, check_step, query, optimize, fixtures);
        }
    }
}
