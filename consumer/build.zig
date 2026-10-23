const std = @import("std");

/// Defines the external consumer package.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const linkage = b.option(
        std.builtin.LinkMode,
        "linkage",
        "Build this consumer against the library's static (default) or shared delivery",
    ) orelse .static;

    // Forward consumer arguments to the provider request parser.
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
    // Forward provider arguments to `main`.
    if (b.args) |args| run_exe.addArgs(args);
    const run_step = b.step("run", "Build and run the consumer program");
    run_step.dependOn(&run_exe.step);
}
