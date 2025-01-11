const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const raylib_dep = b.dependency("raylib-zig", .{
        .target = target,
        .optimize = optimize,
    });

    const module = b.createModule(.{ .root_source_file = b.path("src/solis.zig") });
    module.addImport("solis", module);
    module.addImport("raylib", raylib_dep.module("raylib"));
    module.addImport("raygui", raylib_dep.module("raygui"));
    module.linkLibrary(raylib_dep.artifact("raylib"));

    // const lib = b.addStaticLibrary(.{
    //     .name = "Solis",
    //     .root_source_file = b.path("src/solis.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });
    // lib.root_module.addImport("solis", module);
    // b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "Solis",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("solis", module);

    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // const lib_unit_tests = b.addTest(.{
    //     .root_source_file = b.path("src/root.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });
    //
    // const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    // test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);

    buildExample(b, target, optimize, module, "ecs/hello.zig", "hello_ecs");
    buildExample(b, target, optimize, module, "game.zig", "game");
}

pub fn buildExample(
    builder: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.Mode,
    module: *std.Build.Module,
    path: []const u8,
    name: []const u8,
) void {
    const exe = builder.addExecutable(.{
        .name = name,
        .root_source_file = builder.path(builder.fmt("examples/{s}", .{path})),
        .target = target,
        .optimize = optimize,
    });
    exe.linkSystemLibrary("c");
    builder.installArtifact(exe);
    exe.root_module.addImport("ecs", builder.createModule(.{ .root_source_file = builder.path("src/ecs/ecs.zig") }));
    exe.root_module.addImport("solis", module);

    const run_cmd = builder.addRunArtifact(exe);

    const builder_install_step = builder.getInstallStep();
    run_cmd.step.dependOn(builder_install_step);

    const run_step = builder.step(builder.fmt("run-{s}", .{name}), builder.fmt("Run the {s} example", .{name}));
    run_step.dependOn(&run_cmd.step);
}
