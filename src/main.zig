const std = @import("std");
const builtin = @import("builtin");

pub const config_mod = @import("config.zig");
pub const organism_mod = @import("organism.zig");
pub const grid_mod = @import("grid.zig");
pub const pool_mod = @import("pool.zig");
pub const metabolism_mod = @import("metabolism.zig");
pub const interaction_mod = @import("interaction.zig");
pub const reproduction_mod = @import("reproduction.zig");
pub const death_mod = @import("death.zig");
pub const diffusion_mod = @import("diffusion.zig");
pub const logger_mod = @import("logger.zig");

const Config = config_mod.Config;
const Grid = grid_mod.Grid;
const Cell = grid_mod.Cell;
const OrganismPool = pool_mod.OrganismPool;
const EMPTY = organism_mod.EMPTY;
const metabolism = metabolism_mod;
const interaction = interaction_mod;
const reproduction = reproduction_mod;
const death = death_mod;
const diffusion = diffusion_mod;
const Logger = logger_mod.Logger;

pub fn main() !void {
    var da = std.heap.DebugAllocator(.{}){};
    const allocator = if (builtin.mode == .Debug)
        da.allocator()
    else
        std.heap.smp_allocator;

    const config = Config{};

    // Init grid
    var grid = try Grid.init(allocator, config);
    defer grid.deinit();

    // Init diffusion buffer
    const diff_buffer = try allocator.alloc(Cell, config.gridSize());
    defer allocator.free(diff_buffer);

    // Init organism pool
    var pool = try OrganismPool.init(allocator, config);
    defer pool.deinit();

    // Init RNG
    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        std.posix.getrandom(std.mem.asBytes(&seed)) catch {
            seed = 12345;
        };
        break :blk seed;
    });
    const rng = prng.random();

    // Init logger
    var logger = try Logger.init("vita_log.csv");
    defer logger.deinit();

    // Place starting organisms
    var placed: u32 = 0;
    const grid_size = config.gridSize();
    while (placed < config.starting_organisms) {
        const pos = rng.intRangeLessThan(u32, 0, grid_size);
        if (grid.cells[pos].occupant == EMPTY) {
            _ = pool.spawn(&grid, pos, rng, config);
            placed += 1;
        }
    }

    std.debug.print("Vita: placed {} organisms. Starting simulation...\n", .{placed});

    // Main tick loop
    //const max_ticks: u64 = 20_000;
    const max_ticks: u64 = 100_000;
    var tick: u64 = 0;
    while (tick < max_ticks) : (tick += 1) {
        // 1. Shuffle alive list (every 5 ticks to save performance)
        if (tick % 5 == 0) {
            pool.shuffleAliveList(rng);
        }

        // 2. Snapshot loop count
        var loop_count = pool.alive_count;

        // 3. Process each organism
        var i: u32 = 0;
        while (i < loop_count) {
            const pool_idx = pool.alive_list[i];
            var org = &pool.organisms[pool_idx];
            var died = false;

            // a. Metabolism
            const met_result = metabolism.processMetabolism(org, &grid.cells[org.grid_index], config);
            if (met_result == .dead) {
                died = true;
            }

            // b. Interaction
            if (!died) {
                const pick = rng.intRangeAtMost(u32, 0, 3);
                const neighbor_cell_idx = grid.neighbors[@as(usize, org.grid_index) * 4 + pick];
                const neighbor_occupant = grid.cells[neighbor_cell_idx].occupant;
                if (neighbor_occupant != EMPTY) {
                    const neighbor = &pool.organisms[neighbor_occupant];
                    switch (interaction.processInteraction(org, neighbor, config)) {
                        .parasitism => logger.recordParasitism(),
                        .mutualism => logger.recordMutualism(),
                        else => {},
                    }
                }
            }

            // c. Reproduction
            if (!died) {
                if (reproduction.tryReproduce(pool_idx, &pool, &grid, rng, config)) {
                    logger.recordBirth();
                }
            }

            // d. Death check
            if (!died) {
                org.age +|= 1;
                if (death.checkDeath(org, rng, config)) {
                    died = true;
                }
            }

            // Handle death
            if (died) {
                pool.killInLoop(&grid, i, loop_count);
                loop_count -= 1;
                logger.recordDeath();
                // Don't advance i — swap-remove put a new organism at this index
            } else {
                i += 1;
            }
        }

        // 4. Resource diffusion
        diffusion.diffuse(&grid, diff_buffer, config);

        // 5. Resource injection
        if (tick % config.injection_interval == 0) {
            diffusion.inject(&grid, config);
        }

        // 6. Log every 100 ticks
        if (tick % 100 == 0) {
            try logger.logTick(tick, &pool, &grid);
            std.debug.print("Tick {}: alive={}\n", .{ tick, pool.alive_count });
        }

        // Early exit if everything died
        if (pool.alive_count == 0) {
            std.debug.print("All organisms dead at tick {}.\n", .{tick});
            break;
        }
    }

    std.debug.print("Simulation complete. {} ticks, {} alive.\n", .{ tick, pool.alive_count });
    if (builtin.mode == .Debug) {
        _ = da.deinit();
    }
}

test {
    std.testing.refAllDeclsRecursive(@This());
}
