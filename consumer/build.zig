const std = @import("std");

/// A package that consumes `fast_float` from outside.
///
/// This exists to prove one thing: that a dependent needs nothing but
/// `dep.module("fast_float")` and gets a working, correctly linked parser whose
/// answer is the IEEE 754 value the decimal names. If the published module
/// stopped carrying the compiled C++ bridge, or if the translated `bridge.h`
/// stopped matching the C++ the module was built from, this would stop building
/// or stop producing the bit patterns below, and nothing inside the library
/// would notice.
///
/// Run it with `zig build run`. Every expected value is worked out by exact
/// rational rounding and written into `src/main.zig` with its reason, so a
/// mismatch is a real fault and not a restatement of what the library just did.
/// Any mismatch exits non-zero.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // This package's own option, defaulting to the same `static` the library
    // has always produced, and forwarded to the dependency: `zig build run
    // -Dlinkage=dynamic` builds and runs this consumer against the library's
    // shared delivery and proves that the published module reaches a working
    // artifact that way too. That is the one thing the library's own gates
    // cannot see, because they all build from inside the package.
    const linkage = b.option(
        std.builtin.LinkMode,
        "linkage",
        "Build this consumer against the library's static (default) or shared delivery",
    ) orelse .static;

    // Forwarded for the same reason, and it reaches the consumer program's own
    // `--provider <path>`, which `consumer/src/main.zig` reads in a
    // runtime-loading build and refuses to guess without. With no arguments
    // this is inert, so a linked run is unchanged.
    const runtime_loaded = b.option(
        bool,
        "runtime",
        "Build this consumer against the library's runtime-loaded dispatch, where the native entry points are resolved through one process-lifetime table that an explicit load(source) fills",
    ) orelse false;

    const dep = b.dependency("fast_float", .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
        .runtime = runtime_loaded,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("fast_float", dep.module("fast_float"));

    const exe = b.addExecutable(.{
        .name = "fast_float-consumer",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    // Forwarded so `zig build run -Druntime=true -- --provider <path>` reaches
    // `src/main.zig`, which reads exactly that and refuses to guess without.
    // With no arguments this is inert, so a linked run is unchanged.
    if (b.args) |args| run_exe.addArgs(args);
    const run_step = b.step("run", "Build and run the consumer program");
    run_step.dependOn(&run_exe.step);
}
