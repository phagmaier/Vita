const std = @import("std");
const Config = @import("config.zig").Config;
const Organism = @import("organism.zig").Organism;
const GENOME_BITS = @import("organism.zig").GENOME_BITS;
const NUM_REGIONS = @import("organism.zig").NUM_REGIONS;
const Region = @import("organism.zig").Region;
const EMPTY = @import("organism.zig").EMPTY;
const Grid = @import("grid.zig").Grid;
const OrganismPool = @import("pool.zig").OrganismPool;

/// Shift bits right by `count` positions starting from `start` up to `end` (exclusive).
/// Bits at positions >= end are untouched. Bits at [start, start+count) become 0.
fn shiftBitsRight(genome: *std.StaticBitSet(GENOME_BITS), start: u16, end: u16, count: u16) void {
    if (count == 0 or start >= end) return;
    const new_end = @min(end + count, GENOME_BITS);
    // Work backwards to avoid overwriting
    var i: u16 = new_end;
    while (i > start + count) {
        i -= 1;
        const src = i - count;
        if (src < end) {
            if (genome.isSet(src)) {
                genome.set(i);
            } else {
                genome.unset(i);
            }
        }
    }
    // Clear the gap [start, start+count)
    const clear_end = @min(start + count, new_end);
    for (start..clear_end) |j| {
        genome.unset(j);
    }
}

/// Shift bits left by `count` positions starting from `start+count` down to `start`.
/// Bits at [end-count, end) become 0.
fn shiftBitsLeft(genome: *std.StaticBitSet(GENOME_BITS), start: u16, end: u16, count: u16) void {
    if (count == 0 or start >= end or count >= end - start) return;
    // Work forwards
    for (start..end - count) |i| {
        const src = i + count;
        if (genome.isSet(src)) {
            genome.set(i);
        } else {
            genome.unset(i);
        }
    }
    // Clear tail
    for (end - count..end) |j| {
        genome.unset(j);
    }
}

/// Sample from geometric distribution: number of failures before first success.
/// P(X = k) = (1-p)^k * p.  Pass log(1-p) precomputed to avoid recomputing each call.
inline fn geometricSample(rng: std.Random, log_1_minus_p: f32) u32 {
    // Inverse transform: floor(log(U) / log(1-p)) for U ~ Uniform(0,1)
    const u = rng.float(f32);
    const safe_u: f32 = if (u > 0.0) u else 1e-7;
    return @intFromFloat(@floor(@log(safe_u) / log_1_minus_p));
}

/// Apply point mutations using geometric distribution to jump to each mutated bit.
/// Reduces RNG calls from O(genome_len) to O(expected_mutations) — ~96x fewer calls at 0.5% rate.
fn pointMutation(child: *Organism, rng: std.Random, config: Config) void {
    if (config.point_mutation_rate == 0) return;
    const total_len: u32 = child.totalGenomeLen();
    if (total_len == 0) return;

    const p: f32 = @as(f32, @floatFromInt(config.point_mutation_rate)) / 10000.0;
    const log_1_minus_p = @log(1.0 - p);

    var pos: u32 = geometricSample(rng, log_1_minus_p);
    while (pos < total_len) {
        child.genome.toggle(pos);
        pos += 1 + geometricSample(rng, log_1_minus_p);
    }
}

/// Region duplication: copy all bits of a random region and insert after it.
fn regionDuplication(child: *Organism, rng: std.Random, config: Config) void {
    if (rng.intRangeAtMost(u16, 0, 9999) >= config.region_duplication_rate) return;

    const region_idx = rng.intRangeAtMost(u2, 0, 3);
    const region_size = child.region_sizes[region_idx];
    const total = child.totalGenomeLen();

    if (total + region_size > config.max_genome_bits) return; // Reject

    const region_start = child.regionStart(@enumFromInt(region_idx));
    const region_end = region_start + region_size;

    // Shift everything after this region right by region_size
    shiftBitsRight(&child.genome, region_end, total, region_size);

    // Copy region bits into the gap (they're already there from the shift, but let's be explicit)
    for (0..region_size) |i| {
        const src_pos = region_start + i;
        const dst_pos = region_end + i;
        if (child.genome.isSet(src_pos)) {
            child.genome.set(dst_pos);
        } else {
            child.genome.unset(dst_pos);
        }
    }

    child.region_sizes[region_idx] += region_size;
}

/// Region shrink: remove last half of a random region's bits.
fn regionShrink(child: *Organism, rng: std.Random, config: Config) void {
    if (rng.intRangeAtMost(u16, 0, 9999) >= config.region_shrink_rate) return;

    const region_idx = rng.intRangeAtMost(u2, 0, 3);
    const region_size = child.region_sizes[region_idx];

    if (region_size <= 8) return; // Don't shrink below 8

    const half = region_size / 2;
    const new_size = region_size - half;
    if (new_size < 8) return; // Safety check

    const total = child.totalGenomeLen();
    const region_start = child.regionStart(@enumFromInt(region_idx));
    const remove_start = region_start + new_size;

    // Shift everything after the removed portion left
    shiftBitsLeft(&child.genome, remove_start, total, half);

    child.region_sizes[region_idx] = new_size;
}

/// Insertion: insert 4-16 random bits at a random position within a random region.
fn insertion(child: *Organism, rng: std.Random, config: Config) void {
    if (rng.intRangeAtMost(u16, 0, 9999) >= config.insertion_rate) return;

    const insert_len = rng.intRangeAtMost(u16, 4, 16);
    const total = child.totalGenomeLen();

    if (total + insert_len > config.max_genome_bits) return; // Reject

    const region_idx = rng.intRangeAtMost(u2, 0, 3);
    const region_size = child.region_sizes[region_idx];
    const region_start = child.regionStart(@enumFromInt(region_idx));
    const insert_offset = rng.intRangeAtMost(u16, 0, region_size);
    const insert_pos = region_start + insert_offset;

    // Shift right
    shiftBitsRight(&child.genome, insert_pos, total, insert_len);

    // Fill inserted bits with random values
    for (0..insert_len) |i| {
        const pos = insert_pos + i;
        if (rng.boolean()) {
            child.genome.set(pos);
        } else {
            child.genome.unset(pos);
        }
    }

    child.region_sizes[region_idx] += insert_len;
}

/// Deletion: remove 4-16 bits from a random position within a random region.
fn deletion(child: *Organism, rng: std.Random, config: Config) void {
    if (rng.intRangeAtMost(u16, 0, 9999) >= config.deletion_rate) return;

    const region_idx = rng.intRangeAtMost(u2, 0, 3);
    const region_size = child.region_sizes[region_idx];

    if (region_size <= 8) return;

    const max_delete = @min(@as(u16, 16), region_size - 8);
    if (max_delete < 4) return;
    const delete_len = rng.intRangeAtMost(u16, 4, max_delete);

    const region_start = child.regionStart(@enumFromInt(region_idx));
    const max_offset = region_size - delete_len;
    const delete_offset = rng.intRangeAtMost(u16, 0, max_offset);
    const delete_pos = region_start + delete_offset;

    const total = child.totalGenomeLen();
    shiftBitsLeft(&child.genome, delete_pos, total, delete_len);

    child.region_sizes[region_idx] -= delete_len;
}

/// Apply all mutations to child genome.
pub fn mutateChild(child: *Organism, rng: std.Random, config: Config) void {
    pointMutation(child, rng, config);
    regionDuplication(child, rng, config);
    regionShrink(child, rng, config);
    insertion(child, rng, config);
    deletion(child, rng, config);
    child.updateRegionStarts();
}

/// Try to reproduce. Returns true if reproduction occurred.
pub fn tryReproduce(
    parent_pool_idx: u32,
    pool: *OrganismPool,
    grid: *Grid,
    rng: std.Random,
    config: Config,
) bool {
    const parent = &pool.organisms[parent_pool_idx];
    if (parent.energy <= config.reproduction_threshold) return false;

    // Find an empty neighbor
    const neighbors = grid.neighborIndices(parent.grid_index);
    var empty_neighbors: [4]u32 = undefined;
    var empty_count: u32 = 0;
    for (neighbors) |n| {
        if (grid.cells[n].occupant == EMPTY) {
            empty_neighbors[empty_count] = n;
            empty_count += 1;
        }
    }
    if (empty_count == 0) return false;

    const target_cell = empty_neighbors[rng.intRangeAtMost(u32, 0, empty_count - 1)];

    // Create child as copy of parent
    var child = parent.*;
    child.age = 0;
    child.grid_index = target_cell;

    // Apply mutations
    mutateChild(&child, rng, config);

    // Energy split
    const pre_energy = parent.energy;
    parent.energy = pre_energy * config.parent_energy_pct / 100;
    child.energy = pre_energy * config.child_energy_pct / 100;

    // Place child
    _ = pool.spawnChild(grid, child);

    return true;
}

// --- Tests ---

test "shiftBitsRight works correctly" {
    var bs = std.StaticBitSet(GENOME_BITS).initEmpty();
    // Set bits 4,5,6,7
    bs.set(4);
    bs.set(5);
    bs.set(6);
    bs.set(7);

    shiftBitsRight(&bs, 4, 8, 4);

    // Bits 4-7 should be cleared, bits 8-11 should be set
    try std.testing.expect(!bs.isSet(4));
    try std.testing.expect(!bs.isSet(5));
    try std.testing.expect(!bs.isSet(6));
    try std.testing.expect(!bs.isSet(7));
    try std.testing.expect(bs.isSet(8));
    try std.testing.expect(bs.isSet(9));
    try std.testing.expect(bs.isSet(10));
    try std.testing.expect(bs.isSet(11));
}

test "shiftBitsLeft works correctly" {
    var bs = std.StaticBitSet(GENOME_BITS).initEmpty();
    // Set bits 8,9,10,11
    bs.set(8);
    bs.set(9);
    bs.set(10);
    bs.set(11);

    shiftBitsLeft(&bs, 4, 12, 4);

    // Bits 4-7 should now be set, 8-11 cleared
    try std.testing.expect(bs.isSet(4));
    try std.testing.expect(bs.isSet(5));
    try std.testing.expect(bs.isSet(6));
    try std.testing.expect(bs.isSet(7));
    try std.testing.expect(!bs.isSet(8));
    try std.testing.expect(!bs.isSet(9));
    try std.testing.expect(!bs.isSet(10));
    try std.testing.expect(!bs.isSet(11));
}

test "point mutation flips some bits" {
    const config = Config{ .point_mutation_rate = 5000 }; // 50% rate for test
    var org = Organism.initTest(.{ 32, 32, 16, 16 }, 500);
    var prng = std.Random.DefaultPrng.init(42);
    pointMutation(&org, prng.random(), config);

    // With 50% rate on 96 bits, some should be flipped
    var set_count: u32 = 0;
    for (0..96) |i| {
        if (org.genome.isSet(i)) set_count += 1;
    }
    try std.testing.expect(set_count > 0);
    try std.testing.expect(set_count < 96);
}

test "region duplication doubles region size" {
    const config = Config{ .region_duplication_rate = 10000 }; // 100% rate for test
    var org = Organism.initTest(.{ 32, 32, 16, 16 }, 500);
    // Set some attack bits
    for (0..32) |i| {
        org.genome.set(i);
    }

    // Force region 0 (attack) by using a seed that gives 0 for the region roll
    var prng = std.Random.DefaultPrng.init(0);
    regionDuplication(&org, prng.random(), config);

    // One region should have doubled
    const total = org.totalGenomeLen();
    try std.testing.expect(total > 96);
    try std.testing.expect(total <= 128); // one region doubled at most
}

test "mutations preserve region boundary invariants" {
    const config = Config{
        .point_mutation_rate = 100,
        .region_duplication_rate = 500,
        .region_shrink_rate = 500,
        .insertion_rate = 500,
        .deletion_rate = 500,
    };
    var prng = std.Random.DefaultPrng.init(99);
    const rng = prng.random();

    var org = Organism.initRandom(rng, config);

    // Apply mutations many times
    for (0..100) |_| {
        mutateChild(&org, rng, config);
        // Invariants: total <= 512, each region >= 8 (except if started < 8)
        const total = org.totalGenomeLen();
        try std.testing.expect(total <= 512);
        for (org.region_sizes) |s| {
            try std.testing.expect(s >= 8);
        }
    }
}
