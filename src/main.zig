const std = @import("std");
const math = std.math;
const rl = @import("raylib");
const rlm = rl.math;
const Vector2 = rl.Vector2;

// GLOBALS
const Window = struct {
    const WIDTH = 640 * 2;
    const HEIGHT = 480 * 2;
    const FPS = 60.0;
};

const State = struct {
    /// Current time (accumulation of delta time where delta time = time in seconds for last frame drawn)
    ship: Ship,
    asteroids: []Asteroid,
    allocator: std.mem.Allocator,
    now: f32 = 0.0,
    delta_time: f32 = 0.0,
    rand: *const std.Random,
    quit: bool = false,

    const Self = @This();
    fn init(rand: *const std.Random, allocator: std.mem.Allocator) !Self {
        var asteroids = std.ArrayList(Asteroid).init(allocator);
        for (0..50) |_| {
            const astroid = try Asteroid.init(
                Vector2.init(
                    rand.float(f32) * Window.WIDTH,
                    rand.float(f32) * Window.HEIGHT,
                ),
                rand.enumValue(AsteroidSize),
                rand.int(u64),
            );
            try asteroids.append(astroid);
        }
        return Self{
            .ship = Ship.init(),
            .rand = rand,
            .asteroids = asteroids.items,
            .allocator = allocator,
        };
    }

    fn deinit(self: *Self) void {
        self.allocator.free(self.asteroids);
    }
};
var state: State = undefined;

const Ship = struct {
    const SPEED = 32;
    const ROTATION_SPEED = math.tau;

    position: Vector2,
    velocity: Vector2 = Vector2.init(0, 0),
    rotation: f32 = 0.0,

    const Self = @This();
    fn init() Self {
        return Self{
            .position = rlm.vector2Scale(
                Vector2.init(
                    Window.WIDTH,
                    Window.HEIGHT,
                ),
                0.5,
            ),
        };
    }

    fn direction(self: *Self) Vector2 {
        // Current rotation is 90 degrees off the head of the ship,
        // so we remove 90 degrees to get direction ship is facing
        // NOTE: 90 degress = pi / 2
        const dir_angle = self.rotation - math.pi * 0.5;
        return Vector2.init(math.cos(dir_angle), math.sin(dir_angle));
    }

    fn draw(self: *Self, booster: bool) void {
        draw_lines(
            self.position,
            Line.SCALE,
            self.rotation,
            &.{
                // Tip of ship
                Vector2.init(0.0, -0.62),
                // Left wing of ship
                Vector2.init(-0.42, 0.62),
                // Left sub-wing of ship
                Vector2.init(-0.21, 0.48),
                // Right sub-wing of ship
                Vector2.init(0.21, 0.48),
                // Right wing of ship
                Vector2.init(0.42, 0.62),
            },
        );

        if (booster) {
            draw_lines(
                self.position,
                Line.SCALE,
                self.rotation,
                &.{
                    // Left sub-wing of ship
                    Vector2.init(-0.21, 0.48),
                    // Bottom tip of booster
                    Vector2.init(0.0, 0.96),
                    // Right sub-wing of ship
                    Vector2.init(0.21, 0.48),
                },
            );
        }
    }
};

const Line = struct {
    const THICKNESS = 2.0;
    const SCALE = 24.0;
};

const Asteroid = struct {
    size: AsteroidSize,
    position: Vector2,
    seed: u64,

    const Self = @This();
    fn init(position: Vector2, size: AsteroidSize, seed: u64) !Self {
        return Self{
            .size = size,
            .position = position,
            .seed = seed,
        };
    }

    fn draw(self: *const Self) void {
        var rng = std.Random.DefaultPrng.init(self.seed);
        var rand = rng.random();

        var points = std.BoundedArray(Vector2, 16).init(0) catch unreachable;
        const n = rand.intRangeAtMost(usize, 10, 16);

        // We generate each point in a circular fashion, where each point is evenly spaced apart
        for (0..n) |i| {
            // Minimum angle of current point is defined as:
            //  (360 degrees / number of angles) * i
            // NOTE: tau = 2 * pi = 360 degrees
            const min_angle = ((math.tau / @as(f32, @floatFromInt(n))) * @as(f32, @floatFromInt(i)));

            // Randomly generate an offset amount for randomness.
            // Without doing this, asteroids will be circles!
            const offset = math.pi * 0.125 * rand.float(f32);
            const angle = min_angle + offset;

            // Radius is minimum 0.5 + additional random offset
            var radius = 0.5 + (0.3 * rand.float(f32));

            // Decrement radius 30% of the time to allow for sharper edges.
            // Without doing this, asteroids end up abit too round
            if (rand.float(f32) < 0.2) {
                radius -= 0.2;
            }

            const x = math.cos(angle); // x = r * cos(θ)
            const y = math.sin(angle); // y = r * sin(θ)
            const point = rlm.vector2Scale(
                Vector2.init(x, y),
                radius,
            );

            // `n` will ALWAYS be less than max buffer capacity of 16
            // so we assume appending will never error
            points.append(point) catch unreachable;
        }

        draw_lines(
            self.position,
            Line.SCALE * self.size.size(),
            0.0,
            points.slice(),
        );
    }
};

const AsteroidSize = enum {
    Big,
    Medium,
    Small,

    const Self = @This();
    fn size(self: Self) f32 {
        return switch (self) {
            .Big => 3.69,
            .Medium => 1.42,
            .Small => 0.69,
        };
    }

    fn velocity(self: Self) f32 {
        return switch (self) {
            .Big => 0.32,
            .Medium => 0.75,
            .Small => 1.5,
        };
    }
};

/// Draws a slice of points in relation to the provided `origin` and `scale
fn draw_lines(origin: Vector2, scale: f32, rotation: f32, points: []const Vector2) void {
    var clone_x: i32 = 0;
    var clone_y: i32 = 0;

    var drawn_points = std.BoundedArray(Vector2, 32).init(0) catch |err| {
        std.debug.print("draw_lines: failed to init drawn_points bounded array {any}", .{err});
        return;
    };

    // Calculate actual points to be drawn on screen after transforms, etc
    for (0..points.len) |i| {
        const currPoint = points[i];
        const currTransformed = transform(
            origin,
            scale,
            rotation,
            currPoint,
        );
        const currDrawn = Vector2.init(
            currTransformed.x,
            currTransformed.y,
        );

        drawn_points.append(currDrawn) catch |err| {
            std.debug.print("draw_lines: failed to add drawing point to bounded array due to overflow {any}", .{err});
            continue;
        };

        if (currDrawn.x < 0) {
            clone_x = -1;
        }

        if (currDrawn.y < 0) {
            clone_y = -1;
        }

        if (currDrawn.x > Window.WIDTH) {
            clone_x = 1;
        }

        if (currDrawn.y > Window.HEIGHT) {
            clone_y = 1;
        }
    }

    // Draw points
    for (0..points.len) |i| {
        var currDrawn = drawn_points.get(i);
        const next_idx = (i + 1) % points.len;
        var nextDrawn = drawn_points.get(next_idx);
        rl.drawLineEx(
            currDrawn,
            nextDrawn,
            Line.THICKNESS,
            .white,
        );

        // If any point is beyond the window's borders, we draw another cloned
        // version for the opposite border to simulate screen-wrapping of objects
        if (clone_x != 0 or clone_y != 0) {
            const x_offset: f32 = if (clone_x == 1) -Window.WIDTH else if (clone_x == -1) Window.WIDTH else 0;
            const y_offset: f32 = if (clone_y == 1) -Window.HEIGHT else if (clone_y == -1) Window.HEIGHT else 0;
            currDrawn.x += x_offset;
            currDrawn.y += y_offset;
            nextDrawn.x += x_offset;
            nextDrawn.y += y_offset;
            rl.drawLineEx(
                currDrawn,
                nextDrawn,
                Line.THICKNESS,
                .white,
            );
        }
    }
}

/// Generates a point in relation to the provided `origin`, `scale` and `point`
fn transform(origin: Vector2, scale: f32, rotation: f32, point: Vector2) Vector2 {
    return rlm.vector2Add(
        origin,
        rlm.vector2Rotate(
            rlm.vector2Scale(
                point,
                scale,
            ),
            rotation,
        ),
    );
}

/// Rotations per second
const DRAG = 0.03;

fn update() void {
    // Quit game
    if (rl.isKeyDown(.q)) {
        state.quit = true;
        return;
    }

    state.delta_time = rl.getFrameTime();
    state.now += state.delta_time;

    // ***** SHIP *****

    // Rotate left
    if (rl.isKeyDown(.a) or rl.isKeyDown(.left)) {
        state.ship.rotation -= Ship.ROTATION_SPEED * state.delta_time;
    }

    // Rotate right
    if (rl.isKeyDown(.d) or rl.isKeyDown(.right)) {
        state.ship.rotation += Ship.ROTATION_SPEED * state.delta_time;
    }

    // Update move direction
    if (rl.isKeyDown(.w) or rl.isKeyDown(.up)) {
        const ship_dir = state.ship.direction();
        state.ship.velocity = rlm.vector2Add(
            state.ship.velocity,
            rlm.vector2Scale(
                ship_dir,
                Ship.SPEED * state.delta_time,
            ),
        );
    }

    // Add drag (resistance) to slow ship down over time
    state.ship.velocity = rlm.vector2Scale(state.ship.velocity, 1 - DRAG);

    // Update ship position
    state.ship.position = rlm.vector2Add(state.ship.position, state.ship.velocity);

    // Handle ship position wrap-around in case ship goes off-screen
    state.ship.position = Vector2.init(
        @mod(state.ship.position.x, Window.WIDTH),
        @mod(state.ship.position.y, Window.HEIGHT),
    );

    // ***** ASTEROIDS *****

    // Update asteroid positions
    for (state.asteroids) |*asteroid| {
        asteroid.position = rlm.vector2Add(
            asteroid.position,
            Vector2.init(
                asteroid.size.velocity(),
                asteroid.size.velocity(),
            ),
        );
        asteroid.position = Vector2.init(
            @mod(asteroid.position.x, Window.WIDTH),
            @mod(asteroid.position.y, Window.HEIGHT),
        );
    }
}

const BOOSTER_TICK_RATE = 24.0;

fn render() void {
    // Draw ship
    const moving = rl.isKeyDown(.w);
    const booster_tick = @mod(@as(i32, @intFromFloat(state.now * BOOSTER_TICK_RATE)), 2) == 0;
    const booster = moving and booster_tick;
    state.ship.draw(booster);

    // Draw asteroids
    for (state.asteroids) |*asteroid| {
        asteroid.draw();
    }
}

pub fn main() !void {
    // Initialization
    //--------------------------------------------------------------------------------------
    rl.initWindow(
        Window.WIDTH,
        Window.HEIGHT,
        "raylib-zig [core] example - basic window",
    );
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.setTargetFPS(Window.FPS); // Set our game to run at 60 frames-per-second
    //--------------------------------------------------------------------------------------

    var rng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
    const rand = rng.random();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    state = try State.init(&rand, allocator);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        if (state.quit) {
            break;
        }

        // Update
        update();

        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(.black);

        render();
    }
}

test "asteroids" {
    const gpa = std.testing.allocator;

    var asteroids = std.ArrayList(Asteroid).init(gpa);
    defer asteroids.deinit();

    _ = try Asteroid.init(
        Vector2.init(
            @as(f32, @floatFromInt(0)) * 50 + 50,
            @as(f32, @floatFromInt(0)) * 50 + 50,
        ),
        .Medium,
    );
}
