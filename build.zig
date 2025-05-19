const std = @import("std");
const builtin = @import("builtin");
const rlz = @import("raylib_zig");

// A file is just a struct, which can contain functions and other structs nested in it.
// A module is a collection of structs, accessible via a root source file.
// A package is a collection of modules, libraries, and build logic.
// A library is a static or shared library file, e.g. .a, .dll, .so.

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    if (target.query.os_tag != null and target.query.os_tag.? == .emscripten) {
        build_web(b, optimize);
        return;
    }
    build_native(b, target, optimize);
}

fn build_native(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const dep_raylib = b.dependency(
        "raylib_zig",
        .{
            .target = target,
            .optimize = optimize,
        },
    );
    const raylib = dep_raylib.module("raylib");
    const raylib_artifact = dep_raylib.artifact("raylib");

    const mod_exe = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe_name = b.option(
        []const u8,
        "exe_name",
        "Name of the executable",
    ) orelse "aztewoidz";

    const exe = b.addExecutable(.{
        .name = exe_name,
        .root_module = mod_exe,
    });
    exe.linkLibrary(raylib_artifact);
    exe.root_module.addImport("raylib", raylib);

    // Add linux system paths
    if (builtin.os.tag == .linux) {
        const triple = builtin.target.linuxTriple(b.allocator) catch unreachable;
        raylib_artifact.addLibraryPath(.{ .src_path = .{
            .owner = b,
            .sub_path = b.fmt("/usr/lib/{s}", .{triple}),
        } });
        raylib_artifact.addSystemIncludePath(.{ .src_path = .{
            .owner = b,
            .sub_path = "/usr/include",
        } });
        exe.addLibraryPath(.{ .src_path = .{
            .owner = b,
            .sub_path = b.fmt("/usr/lib/{s}", .{triple}),
        } });
        exe.addSystemIncludePath(.{ .src_path = .{
            .owner = b,
            .sub_path = "/usr/include",
        } });
    }

    // Explicitly link system paths when target is specified
    // NOTE: system paths must be explicitly linked in cross-compile mode
    switch (target.result.os.tag) {
        .macos => {
            // Include xcode_frameworks for cross compilation
            if (b.lazyDependency("macos_sdk", .{})) |dep| {
                exe.addSystemFrameworkPath(dep.path("Frameworks"));
                exe.addSystemIncludePath(dep.path("include"));
                exe.addLibraryPath(dep.path("lib"));
            }
        },
        .linux => {
            raylib_artifact.linkSystemLibrary("GLX");
            raylib_artifact.linkSystemLibrary("X11");
            raylib_artifact.linkSystemLibrary("Xcursor");
            raylib_artifact.linkSystemLibrary("Xext");
            raylib_artifact.linkSystemLibrary("Xfixes");
            raylib_artifact.linkSystemLibrary("Xi");
            raylib_artifact.linkSystemLibrary("Xinerama");
            raylib_artifact.linkSystemLibrary("Xrandr");
            raylib_artifact.linkSystemLibrary("Xrender");
            raylib_artifact.linkSystemLibrary("EGL");
            raylib_artifact.linkSystemLibrary("wayland-client");
            raylib_artifact.linkSystemLibrary("xkbcommon");
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
    add_assets(b, exe, target, optimize) catch |err| {
        std.log.err("Problem adding assets: {!}", .{err});
    };

    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the aztewoidz compiled natively");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = mod_exe,
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}

fn build_web(b: *std.Build, optimize: std.builtin.OptimizeMode) void {
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .cpu_model = .{ .explicit = &std.Target.wasm.cpu.mvp },
        .cpu_features_add = std.Target.wasm.featureSet(&.{
            .atomics,
            .bulk_memory,
        }),
        .os_tag = .emscripten,
    });

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = wasm_target,
        .optimize = optimize,
    });
    const raylib = raylib_dep.module("raylib");
    const raylib_artifact = raylib_dep.artifact("raylib");

    const exe_lib = rlz.emcc.compileForEmscripten(b, "aztewoidz", "src/main.zig", wasm_target, optimize) catch |err| {
        std.log.err("Problem compiling executable for emscripten: {!}", .{err});
        return;
    };
    exe_lib.linkLibrary(raylib_artifact);
    exe_lib.root_module.addImport("raylib", raylib);
    exe_lib.shared_memory = false;
    exe_lib.root_module.single_threaded = false;

    // Embed asset files into the output binary
    add_assets(b, exe_lib, wasm_target, optimize) catch |err| {
        std.log.err("Problem adding assets: {!}", .{err});
    };

    // Note that raylib itself is not actually added to the exe_lib output file, so it also needs to be linked with emscripten.
    const link_step = rlz.emcc.linkWithEmscripten(b, &[_]*std.Build.Step.Compile{ exe_lib, raylib_artifact }) catch |err| {
        std.log.err("Problem linking executable and raylib with emscripten: {!}", .{err});
        return;
    };

    // Embedding stores the specified files inside the wasm file,
    // while preloading packages them in a bundle on the side.
    // Embedding files is more efficient than preloading because
    // there isn’t a separate file to download and copy, but
    // preloading enables the option to separately host the data.
    link_step.addArg("--embed-file");
    link_step.addArg("src/assets/");

    // Use custom HTML template
    link_step.addArg("--shell-file");
    link_step.addArg("shell.html");

    // Linking  options
    link_step.addArgs(&.{
        "-sWASM_MEM_MAX=128MB", // Going higher than that seems not to work on iOS browsers ¯\_(ツ)_/¯
        "-sTOTAL_MEMORY=128MB",
        "-sFULL-ES3=1", // Forces support for all GLES3 features, not just the WebGL2-friendly subset. This automatically turns on FULL_ES2 and WebGL2 support.
        "-sUSE_GLFW=3", // Use GLFW 3 (better performance)
        "-sSTACK_SIZE=6553600", // Required to not instantly crash (large stack size (~60MB) required since everything is stored in the stack)
        "-sEXPORTED_RUNTIME_METHODS=ccall,cwrap,HEAPF32",
    });

    b.getInstallStep().dependOn(&link_step.step);
    const run_step = rlz.emcc.emscriptenRunStep(b) catch |err| {
        std.log.err("Problem creating emscripten run step: {!}", .{err});
        return;
    };
    run_step.step.dependOn(&link_step.step);
    const run_option = b.step("run", "Run aztewoidz compiled with emscripten");
    run_option.dependOn(&run_step.step);
}

/// Add all files within the `src/assets` folder into the executable binary
fn add_assets(b: *std.Build, exe: *std.Build.Step.Compile, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) !void {
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
