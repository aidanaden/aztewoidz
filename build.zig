const std = @import("std");

// A file is just a struct, which can contain functions and other structs nested in it.
// A module is a collection of structs, accessible via a root source file.
// A package is a collection of modules, libraries, and build logic.
// A library is a static or shared library file, e.g. .a, .dll, .so.

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    buildNative(b);
}

// for web builds, the Zig code needs to be built into a library and linked with the Emscripten linker
// fn buildWeb(b: *std.Build, opts: std.Options) !void {
// const lib = b.addStaticLibrary(.{
//     .name = "pacman",
//     .root_module = opts.mod,
// });
//
// const raylib = opts.dep_raylib.module("raylib");
// const raylib_artifact = opts.dep_raylib.artifact("raylib");
// exe.linkLibrary(raylib_artifact);
// exe.root_module.addImport("raylib", raylib);
// lib.step.dependOn(&shd.step);

// // create a build step which invokes the Emscripten linker
// const emsdk = opts.dep_sokol.builder.dependency("emsdk", .{});
// const link_step = try sokol.emLinkStep(b, .{
//     .lib_main = lib,
//     .target = opts.mod.resolved_target.?,
//     .optimize = opts.mod.optimize.?,
//     .emsdk = emsdk,
//     .use_webgl2 = true,
//     .use_emmalloc = true,
//     .use_filesystem = false,
//     .shell_file_path = opts.dep_sokol.path("src/sokol/web/shell.html"),
// });
// // attach Emscripten linker output to default install step
// b.getInstallStep().dependOn(&link_step.step);
// // ...and a special run step to start the web build output via 'emrun'
// const run = sokol.emRunStep(b, .{ .name = "pacman", .emsdk = emsdk });
// run.step.dependOn(&link_step.step);
// b.step("run", "Run pacman").dependOn(&run.step);
// }

fn buildNative(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dep_raylib = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });
    const raylib = dep_raylib.module("raylib");
    const raylib_artifact = dep_raylib.artifact("raylib");

    const mod_asteroids = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const exe = b.addExecutable(.{
        .name = "asteroids_zig",
        .root_module = mod_asteroids,
    });
    exe.linkLibrary(raylib_artifact);
    exe.root_module.addImport("raylib", raylib);

    // Explicitly link system paths when target is specified
    // NOTE: system paths must be explicitly linked in cross-compile mode
    switch (target.result.os.tag) {
        .macos => {
            const dep_macos_sdk = b.dependency("macos_sdk", .{ .target = target });
            exe.addIncludePath(dep_macos_sdk.path("include"));
            exe.addFrameworkPath(dep_macos_sdk.path("Frameworks"));
            exe.addLibraryPath(dep_macos_sdk.path("lib"));
        },
        .linux => {
            exe.linkSystemLibrary("GLX");
            exe.linkSystemLibrary("X11");
            exe.linkSystemLibrary("Xcursor");
            exe.linkSystemLibrary("Xext");
            exe.linkSystemLibrary("Xfixes");
            exe.linkSystemLibrary("Xi");
            exe.linkSystemLibrary("Xinerama");
            exe.linkSystemLibrary("Xrandr");
            exe.linkSystemLibrary("Xrender");
            exe.linkSystemLibrary("EGL");
            exe.linkSystemLibrary("wayland-client");
            exe.linkSystemLibrary("xkbcommon");
        },
        else => {},
    }

    // Embed asset files into the output binary
    add_assets_option(b, exe, target, optimize) catch |err| {
        std.log.err("Problem adding assets: {!}", .{err});
    };

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = mod_asteroids,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}

fn add_assets_option(b: *std.Build, exe: *std.Build.Step.Compile, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) !void {
    var options = b.addOptions();
    var files = std.ArrayList([]const u8).init(b.allocator);
    defer files.deinit();

    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try std.fs.cwd().realpath("src/assets", buf[0..]);

    var dir = try std.fs.openDirAbsolute(path, .{
        .iterate = true,
    });
    var dir_iter = dir.iterate();
    while (try dir_iter.next()) |file| {
        if (file.kind != .file) {
            continue;
        }
        try files.append(b.dupe(file.name));
    }

    options.addOption([]const []const u8, "files", files.items);
    exe.step.dependOn(&options.step);

    const assets = b.addModule("assets", .{
        .root_source_file = options.getOutput(),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("assets", assets);
}
