const std = @import("std");
const Config = @import("config.zig").Config;
const Organism = @import("organism.zig").Organism;
const EMPTY = @import("organism.zig").EMPTY;
const Grid = @import("grid.zig").Grid;

pub const OrganismPool = struct {
    organisms: []Organism,
    alive_list: []u32,
    alive_count: u32,
    free_list: []u32,
    free_count: u32,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, config: Config) !OrganismPool {
        const max = config.max_population;
        const organisms = try allocator.alloc(Organism, max);
        const alive_list = try allocator.alloc(u32, max);
        const free_list = try allocator.alloc(u32, max);

        // Fill free list with all indices (reversed so we pop from the end starting at 0)
        for (0..max) |i| {
            free_list[i] = @intCast(max - 1 - i);
        }

        return OrganismPool{
            .organisms = organisms,
            .alive_list = alive_list,
            .alive_count = 0,
            .free_list = free_list,
            .free_count = @intCast(max),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *OrganismPool) void {
        self.allocator.free(self.organisms);
        self.allocator.free(self.alive_list);
        self.allocator.free(self.free_list);
    }

    /// Spawn a new organism at the given grid cell. Returns the organism pool index, or null if pool is full.
    pub fn spawn(self: *OrganismPool, grid: *Grid, grid_index: u32, rng: std.Random, config: Config) ?u32 {
        if (self.free_count == 0) return null;

        self.free_count -= 1;
        const pool_index = self.free_list[self.free_count];

        var org = Organism.initRandom(rng, config);
        org.grid_index = grid_index;
        self.organisms[pool_index] = org;

        self.alive_list[self.alive_count] = pool_index;
        self.alive_count += 1;

        grid.cells[grid_index].occupant = pool_index;

        return pool_index;
    }

    /// Spawn a child organism with a pre-built organism struct. Returns pool index or null.
    pub fn spawnChild(self: *OrganismPool, grid: *Grid, child: Organism) ?u32 {
        if (self.free_count == 0) return null;

        self.free_count -= 1;
        const pool_index = self.free_list[self.free_count];

        self.organisms[pool_index] = child;

        self.alive_list[self.alive_count] = pool_index;
        self.alive_count += 1;

        grid.cells[child.grid_index].occupant = pool_index;

        return pool_index;
    }

    /// Kill the organism at the given alive_list index. Uses swap-remove.
    /// Returns true if swap-remove replaced the current index (caller should not advance).
    pub fn kill(self: *OrganismPool, grid: *Grid, alive_index: u32) void {
        const pool_index = self.alive_list[alive_index];
        const org = &self.organisms[pool_index];

        // Clear grid cell
        grid.cells[org.grid_index].occupant = EMPTY;

        // Push to free list
        self.free_list[self.free_count] = pool_index;
        self.free_count += 1;

        // Swap-remove from alive list
        self.alive_count -= 1;
        if (alive_index < self.alive_count) {
            self.alive_list[alive_index] = self.alive_list[self.alive_count];
        }
    }

    /// Kill the organism during a processing loop, preserving the split between
    /// current tick actors and newborns.
    pub fn killInLoop(self: *OrganismPool, grid: *Grid, alive_index: u32, loop_count: u32) void {
        const pool_index = self.alive_list[alive_index];
        const org = &self.organisms[pool_index];

        grid.cells[org.grid_index].occupant = EMPTY;
        self.free_list[self.free_count] = pool_index;
        self.free_count += 1;

        self.alive_count -= 1;

        const last_in_loop = loop_count - 1;
        const last_overall = self.alive_count;

        if (alive_index < last_in_loop) {
            // Swap current with the last in the loop snapshot
            self.alive_list[alive_index] = self.alive_list[last_in_loop];
            // Swap vacated loop position with the last overall (a newborn)
            if (last_in_loop < last_overall) {
                self.alive_list[last_in_loop] = self.alive_list[last_overall];
            }
        } else if (alive_index < last_overall) {
            // Just swap with the last overall
            self.alive_list[alive_index] = self.alive_list[last_overall];
        }
    }

    /// Shuffle alive_list using Fisher-Yates.
    pub fn shuffleAliveList(self: *OrganismPool, rng: std.Random) void {
        if (self.alive_count <= 1) return;
        var i: u32 = self.alive_count - 1;
        while (i > 0) : (i -= 1) {
            const j = rng.intRangeAtMost(u32, 0, i);
            const tmp = self.alive_list[i];
            self.alive_list[i] = self.alive_list[j];
            self.alive_list[j] = tmp;
        }
    }
};

// --- Tests ---

test "spawn and kill cycle" {
    const allocator = std.testing.allocator;
    const config = Config{ .grid_width = 4, .grid_height = 4, .max_population = 10 };
    var grid = try @import("grid.zig").Grid.init(allocator, config);
    defer grid.deinit();
    var pool = try OrganismPool.init(allocator, config);
    defer pool.deinit();

    var prng = std.Random.DefaultPrng.init(42);
    const rng = prng.random();

    // Spawn 3 organisms
    const idx0 = pool.spawn(&grid, 0, rng, config).?;
    const idx1 = pool.spawn(&grid, 1, rng, config).?;
    _ = pool.spawn(&grid, 2, rng, config).?;

    try std.testing.expectEqual(@as(u32, 3), pool.alive_count);
    try std.testing.expectEqual(@as(u32, 7), pool.free_count);
    try std.testing.expectEqual(idx0, grid.cells[0].occupant);
    try std.testing.expectEqual(idx1, grid.cells[1].occupant);

    // Kill organism at alive_list index 0
    pool.kill(&grid, 0);
    try std.testing.expectEqual(@as(u32, 2), pool.alive_count);
    try std.testing.expectEqual(@as(u32, 8), pool.free_count);
    try std.testing.expectEqual(EMPTY, grid.cells[0].occupant);

    // Spawn another — should reuse freed slot
    const idx3 = pool.spawn(&grid, 3, rng, config).?;
    _ = idx3;
    try std.testing.expectEqual(@as(u32, 3), pool.alive_count);
    try std.testing.expectEqual(@as(u32, 7), pool.free_count);
}

test "killInLoop correctly swaps for snapshot safety" {
    const allocator = std.testing.allocator;
    const config = Config{ .grid_width = 4, .grid_height = 4, .max_population = 10 };
    var grid = try Grid.init(allocator, config);
    defer grid.deinit();
    var pool = try OrganismPool.init(allocator, config);
    defer pool.deinit();

    var prng = std.Random.DefaultPrng.init(42);
    const rng = prng.random();

    // 1. Initial population: [A, B, C]
    const idxA = pool.spawn(&grid, 0, rng, config).?;
    _ = pool.spawn(&grid, 1, rng, config).?; // idxB
    const idxC = pool.spawn(&grid, 2, rng, config).?;

    const loop_count: u32 = 3;

    // 2. Births: [A, B, C, D, E]
    const idxD = pool.spawn(&grid, 3, rng, config).?;
    const idxE = pool.spawn(&grid, 4, rng, config).?;

    try std.testing.expectEqual(@as(u32, 5), pool.alive_count);
    try std.testing.expectEqual(idxE, pool.alive_list[4]);

    // 3. B dies at index 1.
    // loop_count=3, so A, B, C are in scope.
    // killInLoop(1, 3) should:
    // - Swap B with C (index 1 < loop_count-1)
    // - Swap C's old position (2) with E (index 4)
    pool.killInLoop(&grid, 1, loop_count);

    // Expected: [A, C, E, D]
    try std.testing.expectEqual(idxA, pool.alive_list[0]);
    try std.testing.expectEqual(idxC, pool.alive_list[1]);
    try std.testing.expectEqual(idxE, pool.alive_list[2]);
    try std.testing.expectEqual(idxD, pool.alive_list[3]);
    try std.testing.expectEqual(@as(u32, 4), pool.alive_count);
}

test "pool full returns null" {
    const allocator = std.testing.allocator;
    const config = Config{ .grid_width = 4, .grid_height = 4, .max_population = 2 };
    var grid = try @import("grid.zig").Grid.init(allocator, config);
    defer grid.deinit();
    var pool = try OrganismPool.init(allocator, config);
    defer pool.deinit();

    var prng = std.Random.DefaultPrng.init(42);
    const rng = prng.random();

    _ = pool.spawn(&grid, 0, rng, config);
    _ = pool.spawn(&grid, 1, rng, config);
    try std.testing.expectEqual(@as(?u32, null), pool.spawn(&grid, 2, rng, config));
}
