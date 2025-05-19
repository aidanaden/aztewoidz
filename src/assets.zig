const std = @import("std");
const assets = @import("assets");

// kv pair type used to fill ComptimeStringMap
const EmbeddedAsset = struct {
    []const u8,
    []const u8,
};

fn generate_asset_map() [assets.files.len]EmbeddedAsset {
    var embedded_assets: [assets.files.len]EmbeddedAsset = undefined;
    comptime var i = 0;
    inline for (assets.files) |file| {
        embedded_assets[i][0] = file;
        embedded_assets[i][1] = @embedFile("assets/" ++ file);
        i += 1;
    }
    return embedded_assets;
}

pub const embedded_files_map = std.StaticStringMap([]const u8).initComptime(generate_asset_map());
