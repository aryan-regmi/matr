const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Lib
    const lib = b.addStaticLibrary(.{
        .name = "matr",
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);
    // _ = b.addModule("matr", .{ .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/lib.zig" } } });

    // Dependencies
    const mutt = b.dependency("mutt", .{
        .target = target,
        .optimize = optimize,
    }).module("mutt");
    lib.root_module.addImport("mutt", mutt);

    // Tests
    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_unit_tests.root_module.addImport("mutt", mutt);
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
