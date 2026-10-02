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

    const dep = b.dependency("fast_float", .{
        .target = target,
        .optimize = optimize,
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
    const run_step = b.step("run", "Build and run the consumer program");
    run_step.dependOn(&run_exe.step);
}
