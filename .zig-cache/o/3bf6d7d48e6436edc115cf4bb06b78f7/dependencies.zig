pub const packages = struct {
    pub const @"N-V-__8AABHMqAWYuRdIlflwi8gksPnlUMQBiSxAqQAAZFms" = struct {
        pub const available = true;
        pub const build_root = "/Users/aidan/.cache/zig/p/N-V-__8AABHMqAWYuRdIlflwi8gksPnlUMQBiSxAqQAAZFms";
        pub const deps: []const struct { []const u8, []const u8 } = &.{};
    };
    pub const @"N-V-__8AALRTBQDo_pUJ8IQ-XiIyYwDKQVwnr7-7o5kvPDGE" = struct {
        pub const available = false;
    };
    pub const @"N-V-__8AAPZ7UgBpukXNy27vajQpyiPrEZpV6jOLzI6-Otc_" = struct {
        pub const build_root = "/Users/aidan/.cache/zig/p/N-V-__8AAPZ7UgBpukXNy27vajQpyiPrEZpV6jOLzI6-Otc_";
        pub const deps: []const struct { []const u8, []const u8 } = &.{};
    };
    pub const @"raylib-5.5.0-whq8uGZGzQDi3_L7tJzgEINoZN-HwmOs0zkkc2g7ysIZ" = struct {
        pub const build_root = "/Users/aidan/.cache/zig/p/raylib-5.5.0-whq8uGZGzQDi3_L7tJzgEINoZN-HwmOs0zkkc2g7ysIZ";
        pub const build_zig = @import("raylib-5.5.0-whq8uGZGzQDi3_L7tJzgEINoZN-HwmOs0zkkc2g7ysIZ");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "xcode_frameworks", "N-V-__8AABHMqAWYuRdIlflwi8gksPnlUMQBiSxAqQAAZFms" },
            .{ "emsdk", "N-V-__8AALRTBQDo_pUJ8IQ-XiIyYwDKQVwnr7-7o5kvPDGE" },
        };
    };
    pub const @"raylib_zig-5.6.0-dev-KE8REHguBQAE0xoNkra7mtEqr8cCZHk7k_03txLZB-cZ" = struct {
        pub const build_root = "/Users/aidan/.cache/zig/p/raylib_zig-5.6.0-dev-KE8REHguBQAE0xoNkra7mtEqr8cCZHk7k_03txLZB-cZ";
        pub const build_zig = @import("raylib_zig-5.6.0-dev-KE8REHguBQAE0xoNkra7mtEqr8cCZHk7k_03txLZB-cZ");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "raylib", "raylib-5.5.0-whq8uGZGzQDi3_L7tJzgEINoZN-HwmOs0zkkc2g7ysIZ" },
            .{ "raygui", "N-V-__8AAPZ7UgBpukXNy27vajQpyiPrEZpV6jOLzI6-Otc_" },
        };
    };
};

pub const root_deps: []const struct { []const u8, []const u8 } = &.{
    .{ "raylib_zig", "raylib_zig-5.6.0-dev-KE8REHguBQAE0xoNkra7mtEqr8cCZHk7k_03txLZB-cZ" },
};
