const std = @import("std");
const math = std.math;
const rl = @import("raylib");
const rlm = rl.math;
const Vector2 = rl.Vector2;
const assets = @import("assets.zig").embedded_files_map;

// GLOBALS
const Window = struct {
    const WIDTH = 1400;
    const HEIGHT = 1080;
    const FPS = 60.0;
};

const Sound = struct {
    const AsteroidSound = struct {
        small: rl.Sound,
        medium: rl.Sound,
        large: rl.Sound,
    };
    const ShipSound = struct {
        fire: rl.Sound,
        thrust: rl.Sound,
    };
    const SaucerSound = struct {
        small: rl.Sound,
        large: rl.Sound,
    };
    const BeatSound = struct {
        first: rl.Sound,
        second: rl.Sound,
    };
    const VOLUME: f32 = 0.5;

    ship: ShipSound,
    asteroid: AsteroidSound,
    saucer: SaucerSound,
    beat: BeatSound,

    const Self = @This();
    const InitParams = struct {
        ship: struct {
            fire: [:0]const u8,
            thrust: [:0]const u8,
        },
        asteroid: struct {
            small: [:0]const u8,
            medium: [:0]const u8,
            large: [:0]const u8,
        },
        saucer: struct {
            small: [:0]const u8,
            large: [:0]const u8,
        },
        beat: struct {
            first: [:0]const u8,
            second: [:0]const u8,
        },
    };
    fn init(params: InitParams) !Self {
        return Self{
            .ship = .{
                .fire = rl.loadSoundFromWave(try rl.loadWaveFromMemory(
                    ".wav",
                    assets.get(params.ship.fire).?,
                )),
                .thrust = rl.loadSoundFromWave(try rl.loadWaveFromMemory(
                    ".wav",
                    assets.get(params.ship.thrust).?,
                )),
            },
            .asteroid = .{
                .small = rl.loadSoundFromWave(try rl.loadWaveFromMemory(
                    ".wav",
                    assets.get(params.asteroid.small).?,
                )),
                .medium = rl.loadSoundFromWave(try rl.loadWaveFromMemory(
                    ".wav",
                    assets.get(params.asteroid.medium).?,
                )),
                .large = rl.loadSoundFromWave(try rl.loadWaveFromMemory(
                    ".wav",
                    assets.get(params.asteroid.large).?,
                )),
            },
            .saucer = .{
                .small = rl.loadSoundFromWave(try rl.loadWaveFromMemory(
                    ".wav",
                    assets.get(params.saucer.small).?,
                )),
                .large = rl.loadSoundFromWave(try rl.loadWaveFromMemory(
                    ".wav",
                    assets.get(params.saucer.large).?,
                )),
            },
            .beat = .{
                .first = rl.loadSoundFromWave(try rl.loadWaveFromMemory(
                    ".wav",
                    assets.get(params.beat.first).?,
                )),
                .second = rl.loadSoundFromWave(try rl.loadWaveFromMemory(
                    ".wav",
                    assets.get(params.beat.second).?,
                )),
            },
        };
    }
    fn deinit(self: *Self) void {
        rl.unloadSound(self.ship.fire);
        rl.unloadSound(self.ship.thrust);
        rl.unloadSound(self.asteroid.small);
        rl.unloadSound(self.asteroid.medium);
        rl.unloadSound(self.asteroid.large);
        rl.unloadSound(self.saucer.small);
        rl.unloadSound(self.saucer.large);
        rl.unloadSound(self.beat.first);
        rl.unloadSound(self.beat.second);
    }
};
var sound: ?Sound = null;

const State = struct {
    const MAX_ASTEROIDS = 1000;
    const MAX_PARTICLES = 1000;
    const MAX_PROJECTILES = 10;
    const MAX_ALIENS = 5;
    const DRAG = 0.03;

    /// Current time (accumulation of delta time where delta time = time in seconds for last frame drawn)
    ship: Ship,
    asteroids: std.BoundedArray(Asteroid, MAX_ASTEROIDS),
    particles: std.BoundedArray(Particle, MAX_PARTICLES),
    aliens: std.BoundedArray(Alien, MAX_ALIENS),
    now: f32 = 0.0,
    delta_time: f32 = 0.0,
    last_beat_time: f32 = 0.0,
    prev_beat_idx: u32 = 0,
    rand: *const std.Random,
    score: Score = Score.init(0),
    level: Level,
    quit: bool = false,

    const Self = @This();
    fn init(rand: *const std.Random) !Self {
        const asteroids = try std.BoundedArray(Asteroid, MAX_ASTEROIDS).init(0);
        const particles = try std.BoundedArray(Particle, MAX_PARTICLES).init(0);
        const aliens = try std.BoundedArray(Alien, MAX_ALIENS).init(0);
        var new_state = Self{
            .ship = Ship.init(),
            .level = Level{
                .difficulty = .Easy,
                .max_score = 0,
                .score = 0,
            },
            .rand = rand,
            .asteroids = asteroids,
            .particles = particles,
            .aliens = aliens,
        };
        new_state.generate_asteroids();
        new_state.generate_alien();
        return new_state;
    }

    fn level_up(self: *Self) void {
        reset(self, .{
            .reset_score = false,
            .difficulty = self.level.difficulty.increment(),
        });
        state.ship.lives += 1;
    }

    fn reset(self: *Self, options: struct { reset_score: ?bool = true, difficulty: ?Level.Difficulty = .Easy }) void {
        self.level.difficulty = options.difficulty.?;
        if (options.reset_score.?) {
            self.score.reset();
        }
        state.particles.clear();
        state.ship.respawn();
        state.generate_asteroids();
        state.generate_alien();
    }

    fn add_score(self: *Self, value: u32) void {
        self.score.value += value;
        self.level.score += value;
    }

    fn generate_asteroids(self: *Self) void {
        self.asteroids.clear();

        const num_asteroids = self.level.difficulty.num_asteroids();
        var level_score: u32 = 0;
        for (0..num_asteroids) |_| {
            const angle = math.tau * self.rand.float(f32);
            const size = self.rand.enumValue(Asteroid.Size);
            const velocity = rlm.vector2Scale(
                Vector2.init(math.cos(angle), math.sin(angle)),
                size.velocity() + (1.0 * self.rand.float(f32)),
            );
            const asteroid = try Asteroid.init(
                Vector2.init(
                    self.rand.float(f32) * Window.WIDTH,
                    self.rand.float(f32) * Window.HEIGHT,
                ),
                velocity,
                size,
                self.rand.int(u64),
            );
            level_score += asteroid.size.total_score();
            self.asteroids.append(asteroid) catch unreachable;
        }

        self.level.score = 0;
        self.level.max_score = level_score;
    }

    fn generate_alien(self: *Self) void {
        if (self.aliens.len == Self.MAX_ALIENS) {
            return;
        }
        const position =
            Vector2.init(
                if (self.rand.boolean()) 0.0 else Window.WIDTH * 1.5,
                self.rand.float(f32) * Window.HEIGHT,
            );
        self.aliens.append(
            Alien.init(position, Alien.Size.Small),
        ) catch unreachable;
    }
};
var state: State = undefined;

const Level = struct {
    const MAX_GENERATED = 42;

    difficulty: Difficulty = .Easy,
    score: u32,
    max_score: u32,

    const Difficulty = enum(u8) {
        Easy = 0,
        Medium = 1,
        Hard = 2,

        const Self = @This();
        fn num_asteroids(self: Difficulty) usize {
            return switch (self) {
                .Easy => 20,
                .Medium => 32,
                .Hard => MAX_GENERATED,
            };
        }

        fn increment(self: Difficulty) Difficulty {
            return if (self == .Hard) self else (@enumFromInt(@intFromEnum(self) + 1));
        }
    };
};

const Ship = struct {
    const SPEED = 32;
    const ROTATION_SPEED = math.tau;
    const POINTS = .{
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
    };
    const BOOSTER_POINTS = .{
        // Left sub-wing of ship
        Vector2.init(-0.21, 0.48),
        // Bottom tip of booster
        Vector2.init(0.0, 0.96),
        // Right sub-wing of ship
        Vector2.init(0.21, 0.48),
    };
    const BOOSTER_TICK_RATE = 24.0;
    const MAX_LIVES = 3;

    position: Vector2,
    velocity: Vector2 = Vector2.init(0, 0),
    rotation: f32 = 0.0,
    death_time: f32 = 0.0,
    lives: usize = MAX_LIVES,
    projectiles: std.BoundedArray(Projectile, State.MAX_PROJECTILES),

    const Self = @This();
    fn init() Self {
        const projectiles = std.BoundedArray(Projectile, State.MAX_PROJECTILES).init(0) catch unreachable;
        return Self{
            .projectiles = projectiles,
            .position = rlm.vector2Scale(
                Vector2.init(
                    Window.WIDTH,
                    Window.HEIGHT,
                ),
                0.5,
            ),
        };
    }

    fn respawn(self: *Self) void {
        self.death_time = 0;
        self.position = rlm.vector2Scale(
            Vector2.init(
                Window.WIDTH,
                Window.HEIGHT,
            ),
            0.5,
        );
        self.velocity = Vector2.init(0, 0);
        self.rotation = 0.0;
        self.projectiles.clear();
    }

    fn is_dead(self: *Self, now: f32) bool {
        return self.death_time > 0 and self.death_time <= now;
    }

    fn die(self: *Self, now: f32) void {
        self.death_time = now;
        if (self.lives > 0) {
            self.lives -= 1;
        }

        if (sound != null) {
            rl.playSound(sound.?.asteroid.small);
        }
    }

    fn direction(self: *Self) Vector2 {
        // Current rotation is 90 degrees off the head of the ship,
        // so we remove 90 degrees to get direction ship is facing
        // NOTE: 90 degress = pi / 2
        const dir_angle = self.rotation - math.pi * 0.5;
        return Vector2.init(math.cos(dir_angle), math.sin(dir_angle));
    }

    fn update(self: *Self, delta_time: f32, drag: f32) void {
        // Rotate left
        if (rl.isKeyDown(.a) or rl.isKeyDown(.left)) {
            self.rotation -= Ship.ROTATION_SPEED * delta_time;
        }

        // Rotate right
        if (rl.isKeyDown(.d) or rl.isKeyDown(.right)) {
            self.rotation += Ship.ROTATION_SPEED * delta_time;
        }

        // Update move direction
        if (rl.isKeyDown(.w) or rl.isKeyDown(.up)) {
            const ship_dir = self.direction();
            self.velocity = rlm.vector2Add(
                self.velocity,
                rlm.vector2Scale(
                    ship_dir,
                    Ship.SPEED * delta_time,
                ),
            );

            // Play thrust sound if available
            if (sound != null) {
                const thrust_sound = sound.?.ship.thrust;

                // Only play thrust sound if not playing, otherwise it'll
                // force restart the sound midway and cause a 'pop' sound
                if (!rl.isSoundPlaying(thrust_sound)) {
                    rl.playSound(thrust_sound);
                }
            }
        }

        // Add drag (resistance) to slow ship down over time
        self.velocity = rlm.vector2Scale(self.velocity, 1 - drag);

        // Update ship position
        self.position = rlm.vector2Add(self.position, self.velocity);

        // Handle ship position wrap-around in case ship goes off-screen
        self.position = Vector2.init(
            @mod(self.position.x, Window.WIDTH),
            @mod(self.position.y, Window.HEIGHT),
        );
    }

    fn drawn_points(self: *const Self) std.BoundedArray(Vector2, 32) {
        return get_drawn_points(
            self.position,
            Line.SCALE,
            self.rotation,
            &Ship.POINTS,
        );
    }

    fn draw(self: *const Self, booster: bool) void {
        draw_lines(
            self.position,
            Line.SCALE,
            self.rotation,
            &Ship.POINTS,
            true,
            true,
        );

        if (booster) {
            draw_lines(
                self.position,
                Line.SCALE,
                self.rotation,
                &Ship.BOOSTER_POINTS,
                true,
                true,
            );
        }
    }

    const NUM_DEBRIS_LINES = 5;
    const NUM_DEBRIS_DOTS = 20;
    const NUM_DEBRIS_PARTICLES = NUM_DEBRIS_LINES + NUM_DEBRIS_DOTS;
    fn debris(self: *const Self, rand: *const std.Random) [NUM_DEBRIS_PARTICLES]Particle {
        const particles: [NUM_DEBRIS_PARTICLES]Particle = Particle.generate(
            .LINE,
            self.position,
            rand,
            NUM_DEBRIS_LINES,
            null,
        ) ++ Particle.generate(
            .DOT,
            self.position,
            rand,
            NUM_DEBRIS_DOTS,
            null,
        );
        return particles;
    }

    fn check_collision_poly(self: *const Self, poly_points: []const Vector2) bool {
        for (self.drawn_points().slice()) |point| {
            // Collision detection based on https://jeffreythompson.org/collision-detection/poly-point.php
            const collision = rl.checkCollisionPointPoly(
                point,
                poly_points,
            );
            // If collision found, end collision check and generate debris
            if (collision) {
                return true;
            }
        }
        return false;
    }

    fn shoot(self: *Self) void {
        if (self.projectiles.len == State.MAX_PROJECTILES) {
            return;
        }

        state.ship.projectiles.append(Projectile{
            .ttl = 1.5,
            .position = rlm.vector2Add(
                state.ship.position,
                rlm.vector2Scale(
                    state.ship.direction(),
                    Line.SCALE * 0.55,
                ),
            ),
            .velocity = rlm.vector2Scale(
                state.ship.direction(),
                5.0,
            ),
        }) catch unreachable;

        // Play shoot sound if available
        if (sound != null) {
            rl.playSound(sound.?.ship.fire);
        }
    }
};

const Line = struct {
    const THICKNESS = 2.0;
    const SCALE = 24.0;
};

const Asteroid = struct {
    const MIN_POINTS = 10;
    const MAX_POINTS = 16;

    const Size = enum(u8) {
        Small = 0,
        Medium = 1,
        Big = 2,

        const Self = @This();
        fn size(self: Size) f32 {
            return switch (self) {
                .Big => Line.SCALE * 3.69,
                .Medium => Line.SCALE * 1.42,
                .Small => Line.SCALE * 0.69,
            };
        }

        fn velocity(self: Size) f32 {
            return switch (self) {
                .Big => 0.32,
                .Medium => 0.75,
                .Small => 1.5,
            };
        }

        // Score obtained from destroying asteroid of current size
        fn score(self: Size) u32 {
            return switch (self) {
                .Big => 20,
                .Medium => 50,
                .Small => 100,
            };
        }

        // Max obtainable score from destroying asteroid of current size and all sizes smaller
        fn total_score(self: Size) u32 {
            if (self == .Small) {
                return self.score();
            }
            return self.score() + (2 * total_score(@enumFromInt(@intFromEnum(self) - 1)));
        }

        fn play_sound(self: Size) ?rl.Sound {
            if (sound == null) {
                return null;
            }
            return switch (self) {
                .Big => sound.?.asteroid.large,
                .Medium => sound.?.asteroid.medium,
                .Small => sound.?.asteroid.small,
            };
        }
    };

    size: Size,
    position: Vector2,
    velocity: Vector2,
    points: std.BoundedArray(Vector2, MAX_POINTS),
    remove: bool = false,

    const Self = @This();
    fn init(position: Vector2, velocity: Vector2, size: Size, seed: u64) !Self {
        var rng = std.Random.DefaultPrng.init(seed);
        var rand = rng.random();

        var points = std.BoundedArray(Vector2, MAX_POINTS).init(0) catch unreachable;
        const n = rand.intRangeAtMost(usize, MIN_POINTS, MAX_POINTS);

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

        return Self{
            .position = position,
            .velocity = velocity,
            .size = size,
            .points = points,
        };
    }

    fn drawn_points(self: *Self) std.BoundedArray(Vector2, 32) {
        return get_drawn_points(
            self.position,
            self.size.size(),
            0.0,
            self.points.slice(),
        );
    }

    fn draw(self: *const Self) void {
        draw_lines(
            self.position,
            self.size.size(),
            0.0,
            self.points.slice(),
            true,
            true,
        );
    }

    const NUM_DEBRIS_DOTS = 12;
    fn debris(self: *const Self, rand: *const std.Random) [NUM_DEBRIS_DOTS]Particle {
        return Particle.generate(
            .DOT,
            self.position,
            rand,
            NUM_DEBRIS_DOTS,
            null,
        );
    }
};

const Alien = struct {
    const POINTS = .{
        // Right base of saucer head
        Vector2.init(0.2, -0.2),
        // Right corner of saucer head
        Vector2.init(0.1, -0.4),
        // Left corner of saucer head
        Vector2.init(-0.1, -0.4),
        // Left base of saucer head
        Vector2.init(-0.2, -0.2),
        // Left corner of saucer body
        Vector2.init(-0.3, -0.2),
        // Left tip of saucer body
        Vector2.init(-0.5, 0),
        // Left corner of saucer body
        Vector2.init(-0.3, 0.2),
        // Right corner of saucer body
        Vector2.init(0.3, 0.2),
        // Right tip of saucer body
        Vector2.init(0.5, 0),
        // Right corner of saucer body
        Vector2.init(0.3, -0.2),
        // Left corner of saucer body
        Vector2.init(-0.3, -0.2),
        // Left tip of saucer body
        Vector2.init(-0.5, 0),
        // Right tip of saucer body
        Vector2.init(0.5, 0),
    };
    size: Size,
    position: Vector2,
    velocity: Vector2 = Vector2.init(0, 0),
    remove: bool = false,
    last_shot: f32 = 0.0,
    last_moved: f32 = 0.0,
    projectiles: std.BoundedArray(Projectile, State.MAX_PROJECTILES),

    const Size = enum(u8) {
        Small = 0,
        Big = 1,

        const Self = @This();
        fn size(self: Size) f32 {
            return switch (self) {
                .Big => Line.SCALE * 2.5,
                .Small => Line.SCALE * 1.5,
            };
        }

        fn speed(self: Size) f32 {
            return switch (self) {
                .Big => 1.5,
                .Small => 3,
            };
        }

        // Score obtained from destroying asteroid of current size
        fn score(self: Size) u32 {
            return switch (self) {
                .Big => 200,
                .Small => 1000,
            };
        }

        fn play_sound(self: Size) ?rl.Sound {
            if (sound == null) {
                return null;
            }
            return switch (self) {
                .Big => sound.?.saucer.large,
                .Small => sound.?.saucer.small,
            };
        }

        /// Interval between movement in seconds
        fn move_interval(self: Size) f32 {
            return switch (self) {
                .Big => 3,
                .Small => 1.5,
            };
        }

        /// Interval between movement in seconds
        fn shoot_interval(self: Size) f32 {
            return switch (self) {
                .Big => 5,
                .Small => 2.5,
            };
        }
    };

    const Self = @This();
    fn init(position: Vector2, size: Alien.Size) Self {
        const projectiles = std.BoundedArray(Projectile, State.MAX_PROJECTILES).init(0) catch unreachable;
        return Self{
            .position = position,
            .size = size,
            .projectiles = projectiles,
        };
    }

    fn update(self: *Self, now: f32, _: f32, ship_pos: Vector2) void {
        // Determine direction randomly
        const can_move = (now - self.last_moved) > self.size.move_interval();
        if (can_move) {
            const angle = math.tau * state.rand.float(f32);
            const dir = Vector2.init(math.cos(angle), math.sin(angle));
            self.velocity = rlm.vector2Add(
                self.velocity,
                rlm.vector2Scale(
                    dir,
                    self.size.speed(),
                ),
            );
            self.last_moved = now;
        }

        const can_shoot = (now - self.last_shot) > self.size.shoot_interval();
        if (can_shoot) {
            const dir = rlm.vector2Normalize(rlm.vector2Subtract(ship_pos, self.position));
            const ttl = 3;
            const projectile = Projectile{
                .ttl = ttl,
                .position = rlm.vector2Add(
                    rlm.vector2Add(rlm.vector2Scale(dir, 5.0), self.position),
                    rlm.vector2Scale(
                        dir,
                        Line.SCALE * 0.55,
                    ),
                ),
                .velocity = rlm.vector2Scale(
                    dir,
                    3.0,
                ),
            };
            self.projectiles.append(projectile) catch unreachable;
            self.last_shot = now;

            // Play shoot sound if available
            if (sound != null) {
                rl.playSound(sound.?.ship.fire);
            }
        }

        // Add drag (resistance) to slow alien down over time
        self.velocity = rlm.vector2Scale(self.velocity, 1 - State.DRAG);

        // Update position
        self.position = rlm.vector2Add(self.position, self.velocity);

        // Handle ship position wrap-around in case alien goes off-screen
        self.position = Vector2.init(
            @mod(self.position.x, Window.WIDTH),
            @mod(self.position.y, Window.HEIGHT),
        );

        // Play saucer sound if available
        if (self.size.play_sound()) |saucer_sound| {
            if (!rl.isSoundPlaying(saucer_sound)) {
                rl.playSound(saucer_sound);
            }
        }
    }

    fn drawn_points(self: *const Self) std.BoundedArray(Vector2, 32) {
        return get_drawn_points(
            self.position,
            self.size.size(),
            0.0,
            &Alien.POINTS,
        );
    }

    fn draw(self: *const Self) void {
        draw_lines(
            self.position,
            self.size.size(),
            0.0,
            &Alien.POINTS,
            false,
            true,
        );
    }

    const NUM_DEBRIS_DOTS = 12;
    fn debris(self: *Self, rand: *const std.Random) [NUM_DEBRIS_DOTS]Particle {
        const particles: [NUM_DEBRIS_DOTS]Particle = Particle.generate(
            .DOT,
            self.position,
            rand,
            NUM_DEBRIS_DOTS,
            null,
        );
        return particles;
    }

    fn check_collision_poly(self: *const Self, poly_points: []const Vector2) bool {
        for (self.drawn_points().slice()) |point| {
            // Collision detection based on https://jeffreythompson.org/collision-detection/poly-point.php
            const collision = rl.checkCollisionPointPoly(
                point,
                poly_points,
            );
            // If collision found, end collision check and generate debris
            if (collision) {
                return true;
            }
        }
        return false;
    }
};

/// Ship debris generated when ship is destroyed
const Particle = struct {
    const Type = enum {
        LINE,
        DOT,
    };
    const Data = union(Type) {
        LINE: struct {
            rotation: f32,
            length: f32,
        },
        DOT: struct {
            radius: f32,
        },
    };
    const MIN_TTL = 0.42;
    const RAND_TTL = 1.0;
    const MIN_VEL = 0.42;
    const RAND_VEL = 0.42;
    const RAND_OFFSET = 0.33;

    position: Vector2,
    velocity: Vector2 = Vector2.init(0, 0),
    ttl: f32,
    type: Type,
    data: Data,

    const Self = @This();

    fn generate(comptime particle_type: Type, position: Vector2, rand: *const std.Random, comptime amount: usize, ttl: ?f32) [amount]Particle {
        return switch (particle_type) {
            .DOT => generate_dots(position, rand, amount, ttl),
            .LINE => generate_lines(position, rand, amount, ttl),
        };
    }

    fn generate_dots(position: Vector2, rand: *const std.Random, comptime amount: usize, ttl: ?f32) [amount]Particle {
        var particles: [amount]Particle = undefined;
        inline for (0..amount) |i| {
            // Minimum angle of current point is defined as:
            //  (360 degrees / number of angles) * i
            // NOTE: tau = 2 * pi = 360 degrees
            const min_angle = ((math.tau / @as(f32, @floatFromInt(amount))) * @as(f32, @floatFromInt(i)));
            // Randomly generate an offset amount for randomness.
            // Without doing this, dots will distributed in an exact circle!
            const offset = min_angle * RAND_OFFSET * rand.float(f32);
            const angle = min_angle + offset;

            const actual_ttl = ttl orelse MIN_TTL + (RAND_TTL * rand.float(f32));
            const debris = Particle{
                .ttl = actual_ttl,
                .position = rlm.vector2Add(
                    position,
                    Vector2.init(rand.float(f32), rand.float(f32)),
                ),
                .velocity = rlm.vector2Scale(
                    Vector2.init(math.cos(angle), math.sin(angle)),
                    MIN_VEL + RAND_VEL * rand.float(f32),
                ),
                .type = .DOT,
                .data = .{ .DOT = .{ .radius = 1 } },
            };
            particles[i] = debris;
        }
        return particles;
    }

    fn generate_lines(position: Vector2, rand: *const std.Random, comptime amount: usize, ttl: ?f32) [amount]Particle {
        var particles: [amount]Particle = undefined;
        inline for (0..amount) |i| {
            const angle = math.tau * rand.float(f32);
            const actual_ttl = ttl orelse MIN_TTL + (RAND_TTL * rand.float(f32));
            const debris = Particle{
                .ttl = actual_ttl,
                .position = rlm.vector2Add(
                    position,
                    Vector2.init(rand.float(f32), rand.float(f32)),
                ),
                .velocity = rlm.vector2Scale(
                    Vector2.init(math.cos(angle), math.sin(angle)),
                    1.0 + rand.float(f32),
                ),
                .type = .LINE,
                .data = .{ .LINE = .{
                    .rotation = rand.float(f32) * math.tau,
                    .length = Line.SCALE * (0.6 + (0.4 * rand.float(f32))),
                } },
            };
            particles[i] = debris;
        }
        return particles;
    }

    fn is_drawable(self: *const Self) bool {
        return self.ttl > 0;
    }

    fn draw(self: *const Self) void {
        switch (self.data) {
            .LINE => |line_data| {
                draw_lines(
                    self.position,
                    line_data.length,
                    line_data.rotation,
                    &.{
                        Vector2.init(0.5, 0),
                        Vector2.init(-0.5, 0),
                    },
                    true,
                    true,
                );
            },
            .DOT => |dot_data| {
                rl.drawCircleV(
                    self.position,
                    dot_data.radius,
                    rl.Color.white,
                );
            },
        }
    }
};

const Projectile = struct {
    const RADIUS = @max(Line.SCALE * 0.05, 1);

    position: Vector2,
    velocity: Vector2 = Vector2.init(0, 0),
    ttl: f32,
    remove: bool = false,

    const Self = @This();

    fn is_drawable(self: *const Self) bool {
        return self.ttl > 0;
    }

    fn draw(self: *const Self) void {
        rl.drawCircleV(
            self.position,
            RADIUS,
            rl.Color.white,
        );
    }

    fn check_collision_poly(self: *const Self, poly_points: []const Vector2) bool {
        for (0..poly_points.len) |j| {
            const next_idx = (j + 1) % poly_points.len;
            const p1 = poly_points[j];
            const p2 = poly_points[next_idx];

            // Check if projectile collided against side of polygon
            //
            // NOTE: this check is not foolproof and CAN miss out on
            // collisions due to projectile moving past the side and
            // INTO the asteroid within a single frame
            const proj_collision = rl.checkCollisionCircleLine(
                self.position,
                Projectile.RADIUS,
                p1,
                p2,
            );

            // End projectile collision check if collision found
            if (proj_collision) {
                return true;
            }
        }

        // Check if projectile is within polygon
        const proj_within = rl.checkCollisionPointPoly(
            self.position,
            poly_points,
        );

        return proj_within;
    }
};

fn get_drawn_points(origin: Vector2, scale: f32, rotation: f32, points: []const Vector2) std.BoundedArray(Vector2, 32) {
    var drawn_points = std.BoundedArray(Vector2, 32).init(0) catch |err| {
        std.log.err("get_drawn_points: failed to init drawn_points bounded array {any}", .{err});
        return .{};
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
            std.log.err("get_drawn_points: failed to add drawing point to bounded array due to overflow {any}", .{err});
            continue;
        };
    }

    return drawn_points;
}

/// Draws a slice of points in relation to the provided `origin` and `scale
fn draw_lines(origin: Vector2, scale: f32, rotation: f32, points: []const Vector2, connect: bool, mirror: bool) void {
    var clone_x: i32 = 0;
    var clone_y: i32 = 0;

    var drawn_points = std.BoundedArray(Vector2, 32).init(0) catch |err| {
        std.log.err("draw_lines: failed to init drawn_points bounded array {any}", .{err});
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
            std.log.err("draw_lines: failed to add drawing point to bounded array due to overflow {any}", .{err});
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
        // Stop drawing if not connecting the final point to the first point
        if (!connect and i == (points.len - 1)) {
            break;
        }
        var currDrawn = drawn_points.get(i);
        const next_idx = (i + 1) % points.len;
        var nextDrawn = drawn_points.get(next_idx);
        rl.drawLineEx(
            currDrawn,
            nextDrawn,
            Line.THICKNESS,
            .white,
        );

        // Skip drawing mirrored clone if not specified
        if (!mirror) {
            continue;
        }

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

fn update() void {
    // Quit game
    if (rl.isKeyDown(.q)) {
        state.quit = true;
        return;
    }

    state.delta_time = rl.getFrameTime();
    state.now += state.delta_time;

    // Update ship position state
    if (!state.ship.is_dead(state.now)) {
        state.ship.update(state.delta_time, State.DRAG);

        // Handle ship vs alien projectile collision
        outer: for (state.aliens.slice()) |*alien| {
            for (alien.projectiles.slice()) |*proj| {
                // Ignore destroyed projectiles
                if (proj.remove) {
                    continue;
                }
                const proj_ship_collided = proj.check_collision_poly(state.ship.drawn_points().slice());
                if (proj_ship_collided) {
                    std.debug.print("proj_ship_collided, projectile_pos: {any}, ship_pos: {any}\n", .{ proj.position, state.ship.position });
                    state.ship.die(state.now);
                    proj.remove = true;
                    state.particles.appendSlice(&state.ship.debris(state.rand)) catch unreachable;
                    break :outer;
                }
            }
        }
    }

    // Handle shooting
    if (!state.ship.is_dead(state.now) and rl.isKeyPressed(.space)) {
        state.ship.shoot();
    }

    // Handle aliens state
    {
        var i: usize = 0;
        while (i < state.aliens.len) {
            var alien: *Alien = &state.aliens.slice()[i];
            const alien_drawn_points = alien.drawn_points();

            // Handle alien vs ship collision
            if (!state.ship.is_dead(state.now)) {
                const collided = state.ship.check_collision_poly(alien_drawn_points.slice());
                if (collided) {
                    alien.remove = true;
                    std.debug.print("alien_ship_collided\n", .{});
                    state.ship.die(state.now);
                    break;
                }
            }

            // Handle alien vs projectile collision
            if (!alien.remove) {
                for (state.ship.projectiles.slice()) |*proj| {
                    // Ignore destroyed projectiles
                    if (proj.remove) {
                        continue;
                    }
                    const proj_alien_collided = proj.check_collision_poly(alien_drawn_points.slice());
                    if (proj_alien_collided) {
                        alien.remove = true;
                        proj.remove = true;
                        break;
                    }
                }
            }

            // Generate alien debris
            if (alien.remove) {
                state.particles.appendSlice(&alien.debris(state.rand)) catch unreachable;
                _ = state.aliens.swapRemove(i);
                continue;
            }

            // Update alien position if no collisions found
            alien.update(state.now, state.delta_time, state.ship.position);
            i += 1;
        }
    }

    // Handle asteroids state
    {
        var i: usize = 0;
        while (i < state.asteroids.len) {
            var asteroid: *Asteroid = &state.asteroids.slice()[i];
            const asteroid_drawn_points = asteroid.drawn_points();

            // Handle asteroid vs ship collision
            if (!state.ship.is_dead(state.now)) {
                const ship_collided = state.ship.check_collision_poly(asteroid_drawn_points.slice());
                if (ship_collided) {
                    state.ship.die(state.now);
                    state.particles.appendSlice(&state.ship.debris(state.rand)) catch unreachable;
                }
            }

            // Handle asteroid vs aliens collision
            for (state.aliens.slice()) |*alien| {
                // Ignore destroyed aliens
                if (alien.remove) {
                    continue;
                }
                const alien_collided = alien.check_collision_poly(asteroid_drawn_points.slice());
                if (alien_collided) {
                    alien.remove = true;
                }
            }

            // Handle asteroid vs ship projectile collision
            for (state.ship.projectiles.slice()) |*proj| {
                // Ignore destroyed projectiles
                if (proj.remove) {
                    continue;
                }

                const proj_asteroid_collided = proj.check_collision_poly(asteroid_drawn_points.slice());
                if (proj_asteroid_collided) {
                    // Handle destroying asteroid
                    const impact = rlm.vector2Scale(
                        rlm.vector2Normalize(proj.velocity),
                        0.5,
                    );
                    handleAsteroidCollision(asteroid, impact);
                    asteroid.remove = true;
                    proj.remove = true;
                    break;
                }
            }

            // Handle asteroid vs alien projectile collision
            outer: for (state.aliens.slice()) |*alien| {
                for (alien.projectiles.slice()) |*proj| {
                    if (proj.remove) {
                        continue;
                    }
                    const proj_asteroid_collided = proj.check_collision_poly(asteroid_drawn_points.slice());
                    if (proj_asteroid_collided) {
                        // Handle destroying asteroid
                        const impact = rlm.vector2Scale(
                            rlm.vector2Normalize(proj.velocity),
                            0.5,
                        );
                        handleAsteroidCollision(asteroid, impact);
                        asteroid.remove = true;
                        proj.remove = true;
                        break :outer;
                    }
                }
            }

            // Remove destroyed asteroid
            if (asteroid.remove) {
                // Update score
                state.add_score(asteroid.size.score());

                // Play asteroid destroyed sound if available
                const asteroid_sound = asteroid.size.play_sound();
                if (asteroid_sound != null) {
                    rl.playSound(asteroid_sound.?);
                }

                // Remove asteroid
                _ = state.asteroids.swapRemove(i);
                continue;
            }

            // Update asteroid position if no collisions found
            asteroid.position = rlm.vector2Add(asteroid.position, asteroid.velocity);
            asteroid.position = Vector2.init(
                @mod(asteroid.position.x, Window.WIDTH),
                @mod(asteroid.position.y, Window.HEIGHT),
            );
            i += 1;
        }
    }

    // Handle particles state
    {
        var i: usize = 0;
        while (i < state.particles.len) {
            var particle: *Particle = &state.particles.slice()[i];

            // Remove expired particles
            particle.ttl -= state.delta_time;
            if (particle.ttl < state.delta_time) {
                _ = state.particles.swapRemove(i);
                continue;
            }

            // Update positions of live particles
            particle.position = rlm.vector2Add(
                particle.position,
                particle.velocity,
            );
            particle.position = Vector2.init(
                @mod(particle.position.x, Window.WIDTH),
                @mod(particle.position.y, Window.HEIGHT),
            );

            i += 1;
        }
    }

    // Handle ship projectile state
    {
        var i: usize = 0;
        while (i < state.ship.projectiles.len) {
            var projectile: *Projectile = &state.ship.projectiles.slice()[i];

            // Remove expired projectiles
            projectile.ttl -= state.delta_time;
            if (projectile.remove or projectile.ttl < state.delta_time) {
                _ = state.ship.projectiles.swapRemove(i);
                continue;
            }

            // Update positions of live projectiles
            projectile.position = rlm.vector2Add(
                projectile.position,
                projectile.velocity,
            );
            projectile.position = Vector2.init(
                @mod(projectile.position.x, Window.WIDTH),
                @mod(projectile.position.y, Window.HEIGHT),
            );

            i += 1;
        }
    }

    // Handle aliens projectile state
    {
        for (state.aliens.slice()) |*alien| {
            var i: usize = 0;
            while (i < alien.projectiles.len) {
                var projectile: *Projectile = &alien.projectiles.slice()[i];

                // Remove expired projectiles
                projectile.ttl -= state.delta_time;
                if (projectile.remove or projectile.ttl < state.delta_time) {
                    _ = alien.projectiles.swapRemove(i);
                    continue;
                }

                // Update positions of live projectiles
                projectile.position = rlm.vector2Add(
                    projectile.position,
                    projectile.velocity,
                );
                projectile.position = Vector2.init(
                    @mod(projectile.position.x, Window.WIDTH),
                    @mod(projectile.position.y, Window.HEIGHT),
                );

                i += 1;
            }
        }
    }

    // Handle ship death
    if (state.ship.is_dead(state.now) and (state.now - state.ship.death_time) >= 3.0) {
        // Reset stage if no more lives
        if (state.ship.lives == 0) {
            state.reset(.{});
        } else {
            state.ship.respawn();
        }
    }

    // Level up if all asteroids destroyed
    if (state.asteroids.len == 0) {
        state.level_up();
    }

    // Play background beat
    // Current method is incrementally halving the initial interval based on progress
    // Incremental rate is calculated via a sigmoid curve on the progress level
    // NOTE: an alternative would be to map interval of beats to progress percentage
    if (!state.ship.is_dead(state.now) and sound != null) {
        const max_interval_ms: u32 = 3000;

        // Max. number of times we can halve the interval is `log2(largest interval)`
        // Cap to 6, since any less will be ignored (interval will be too short)
        const max_interval_log: f32 = @min(math.log2(@as(f32, @floatFromInt(max_interval_ms))), 6.0);

        // Calculate increment rate via sigmoid scale
        const current_progress: f32 = (@as(f32, @floatFromInt(state.level.score)) / @as(f32, @floatFromInt(state.level.max_score)));
        const value = sigmoid_scale(current_progress, 0, @as(u32, @intFromFloat(max_interval_log)), 10);

        // Repeatedly half the interval the closer the progress is to completion
        const interval_ms: f32 = @floatFromInt(@max(50, max_interval_ms >> @intCast(value)));
        const interval_sec: f32 = interval_ms / 1000;
        const last_played_interval: f32 = state.now - state.last_beat_time;

        // Only play beat every `ms_interval` frames
        // NOTE: we track beat time instead of remain fps-agnostic
        if (last_played_interval > interval_sec) {
            const beat = if (state.prev_beat_idx == 0) sound.?.beat.first else sound.?.beat.second;
            state.prev_beat_idx = @mod(state.prev_beat_idx + 1, 2);
            rl.playSound(beat);
            state.last_beat_time = state.now;
        }
    }
}

fn sigmoid_scale(ratio: f32, min: u32, max: u32, steepness: ?u32) u32 {
    // Move input x from [0, 1] to the range of [-0.5, 0.5] since sigmoid
    // returns 0.5 ONLY when input = 0.
    const rescaled: f32 = ratio - 0.5;

    // Scale output result. `steepness` value determines how close
    // the ouputs are to 0 and 1. See examples below.
    // steepness = 2, input: [-1, 1], output: [0.26, 0.73]
    // steepness = 10, input: [-5, 5], output: [0.0067, 0.9933]
    const x: f32 = rescaled * @as(f32, @floatFromInt(if (steepness != null) steepness.? else 10));

    // Calculate approx. sigmoid value
    // S_approx(x) = 0.5 * (x / (1 + |x|) + 1)
    const sig_val: f32 = 0.5 * (x / (1 + @abs(x)) + 1);
    const value: f32 = @as(f32, @floatFromInt(min)) + sig_val * @as(f32, @floatFromInt(max - min));
    return @as(u32, @intFromFloat(value));
}

fn handleAsteroidCollision(asteroid: *Asteroid, impact: Vector2) void {
    // Generate debris
    state.particles.appendSlice(&asteroid.debris(state.rand)) catch unreachable;

    // Generate smaller asteroids
    const nextSize: ?Asteroid.Size = switch (asteroid.size) {
        .Big => .Medium,
        .Medium => .Small,
        .Small => null,
    };
    if (nextSize != null) {
        for (0..2) |_| {
            const dir = rlm.vector2Normalize(asteroid.velocity);
            const smallerAsteroid = Asteroid.init(
                Vector2.init(
                    (state.rand.float(f32) * asteroid.size.size()) + (asteroid.position.x - (asteroid.size.size() / 2)),
                    (state.rand.float(f32) * asteroid.size.size()) + (asteroid.position.y - (asteroid.size.size() / 2)),
                ),
                rlm.vector2Add(
                    rlm.vector2Scale(
                        dir,
                        nextSize.?.velocity(),
                    ),
                    impact,
                ),
                nextSize.?,
                state.rand.int(u64),
            ) catch unreachable;
            state.asteroids.append(smallerAsteroid) catch unreachable;
        }
        // const offset = asteroid.size.size() / 2;
        // const firstAsteroid = Asteroid.init(
        //     asteroid.position.subtractValue(offset),
        //     asteroid.velocity,
        //     nextSize.?,
        //     state.rand.int(u64),
        // ) catch unreachable;
        // const secondAsteroid = Asteroid.init(
        //     asteroid.position.addValue(offset),
        //     asteroid.velocity,
        //     nextSize.?,
        //     state.rand.int(u64),
        // ) catch unreachable;
        // state.asteroids.appendSlice(
        //     &.{ firstAsteroid, secondAsteroid },
        // ) catch unreachable;
    }
}

const Score = struct {
    value: u32,

    const Self = @This();
    fn init(value: u32) Self {
        return Self{
            .value = value,
        };
    }

    fn reset(self: *Self) void {
        self.value = 0;
    }

    fn draw(self: *Self) void {
        Digits.draw(
            self.value,
            Vector2.init(Window.WIDTH, 20),
        );
    }

    const Digits = struct {
        const DigitPoints = []const [2]f32;
        const ZERO: DigitPoints = &.{ .{ 0, 0 }, .{ 1, 0 }, .{ 1, 1 }, .{ 0, 1 }, .{ 0, 0 } };
        const ONE: DigitPoints = &.{ .{ 0.5, 0 }, .{ 0.5, 1 } };
        const TWO: DigitPoints = &.{ .{ 0, 0 }, .{ 1, 0 }, .{ 1, 0.5 }, .{ 0, 0.5 }, .{ 0, 1 }, .{ 1, 1 } };
        const THREE: DigitPoints = &.{ .{ 0, 0 }, .{ 1, 0 }, .{ 1, 0.5 }, .{ 0, 0.5 }, .{ 1, 0.5 }, .{ 1, 1 }, .{ 0, 1 } };
        const FOUR: DigitPoints = &.{ .{ 0, 0 }, .{ 0, 0.5 }, .{ 1, 0.5 }, .{ 1, 0 }, .{ 1, 1 } };
        const FIVE: DigitPoints = &.{ .{ 1, 0 }, .{ 0, 0 }, .{ 0, 0.5 }, .{ 1, 0.5 }, .{ 1, 1 }, .{ 0, 1 } };
        const SIX: DigitPoints = &.{ .{ 1, 0 }, .{ 0, 0 }, .{ 0, 1 }, .{ 1, 1 }, .{ 1, 0.5 }, .{ 0, 0.5 } };
        const SEVEN: DigitPoints = &.{ .{ 0, 0 }, .{ 1, 0 }, .{ 1, 1 } };
        const EIGHT: DigitPoints = &.{ .{ 0, 0 }, .{ 1, 0 }, .{ 1, 1 }, .{ 0, 1 }, .{ 0, 0 }, .{ 0, 0.5 }, .{ 1, 0.5 } };
        const NINE: DigitPoints = &.{ .{ 0, 1 }, .{ 1, 1 }, .{ 1, 0 }, .{ 0, 0 }, .{ 0, 0.5 }, .{ 1, 0.5 } };
        const ALL: []const DigitPoints = &.{
            Digits.ZERO, // 0
            Digits.ONE, // 1
            Digits.TWO, // 2
            Digits.THREE, // 3
            Digits.FOUR, // 4
            Digits.FIVE, // 5
            Digits.SIX, // 6
            Digits.SEVEN, // 7
            Digits.EIGHT, // 8
            Digits.NINE, // 9
        };

        fn draw(num: u32, origin: Vector2) void {
            // Copied over values we'll be mutating within the loop
            var remainder = num;
            var digit_origin = origin;

            var i: usize = 0;
            while (true) : ({
                remainder /= 10;
                i += 1;
            }) {
                // Ensure score is drawn at least once
                if (remainder == 0 and i > 0) {
                    break;
                }

                const digit = remainder % 10;
                const digit_point_values = ALL[digit];
                var points = std.BoundedArray(Vector2, 16).init(0) catch unreachable;
                for (digit_point_values) |point_value| {
                    points.append(
                        Vector2.init(
                            point_value[0],
                            point_value[1],
                        ),
                    ) catch unreachable;
                }

                digit_origin.x -= 1.2 * Line.SCALE;
                draw_lines(
                    digit_origin,
                    Line.SCALE * 0.8,
                    0,
                    points.slice(),
                    false,
                    false,
                );
            }
        }
    };
};

fn render() void {
    // Draw ship lives statistic in top left of screen
    for (0..state.ship.lives) |i| {
        draw_lines(
            Vector2.init(20 + Line.SCALE * @as(f32, @floatFromInt(i)), 20),
            Line.SCALE,
            0,
            &Ship.POINTS,
            true,
            true,
        );
    }

    // Draw score
    state.score.draw();

    // Draw ship (if alive)
    if (!state.ship.is_dead(state.now)) {
        const moving = rl.isKeyDown(.w);
        const booster_tick = @mod(@as(i32, @intFromFloat(state.now * Ship.BOOSTER_TICK_RATE)), 2) == 0;
        const booster = moving and booster_tick;
        state.ship.draw(booster);
    }

    // Draw ship projectiles
    for (state.ship.projectiles.slice()) |*proj| {
        if (proj.is_drawable()) {
            proj.draw();
        }
    }

    // Draw asteroids
    for (state.asteroids.slice()) |*asteroid| {
        asteroid.draw();
    }

    // Draw particles
    for (state.particles.slice()) |*particle| {
        if (particle.is_drawable()) {
            particle.draw();
        }
    }

    // Draw alien projectiles
    for (state.aliens.slice()) |*alien| {
        alien.draw();
        for (alien.projectiles.slice()) |*proj| {
            if (proj.is_drawable()) {
                proj.draw();
            }
        }
    }
}

pub fn main() !void {
    // Window setup
    rl.initWindow(
        Window.WIDTH,
        Window.HEIGHT,
        "Aztewoidz",
    );
    // Close window and OpenGL context
    defer rl.closeWindow();

    // Audio setup
    rl.initAudioDevice();
    rl.setAudioStreamBufferSizeDefault(4096);
    defer rl.closeAudioDevice();

    sound = Sound.init(.{
        .ship = .{
            .thrust = "thrust.wav",
            .fire = "fire.wav",
        },
        .asteroid = .{
            .small = "bangSmall.wav",
            .medium = "bangMedium.wav",
            .large = "bangLarge.wav",
        },
        .saucer = .{
            .small = "saucerSmall.wav",
            .large = "saucerBig.wav",
        },
        .beat = .{
            .first = "beat1.wav",
            .second = "beat2.wav",
        },
    }) catch null;
    if (sound != null) {
        rl.setMasterVolume(Sound.VOLUME);
    }
    defer {
        if (sound != null) {
            sound.?.deinit();
        }
    }

    // FPS setup
    rl.setTargetFPS(Window.FPS);

    // Game state setup
    var rng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
    const rand = rng.random();
    state = try State.init(&rand);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        if (state.quit) {
            break;
        }

        // Update
        update();

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(.black);
        render();
    }
}
