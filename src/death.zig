const std = @import("std");
const Config = @import("config.zig").Config;
const Organism = @import("organism.zig").Organism;

/// Check if organism should die this tick. Returns true if dead.
/// Covers age-based probabilistic death. Starvation is handled in metabolism.
pub fn checkDeath(org: *const Organism, rng: std.Random, config: Config) bool {
    // Starvation (belt-and-suspenders — metabolism already handles this)
    if (org.energy == 0) return true;

    // Age-based death
    const genome_byte_len: u32 = org.genomeByteLen();
    const death_threshold: u32 = config.age_death_base + (genome_byte_len / config.age_death_byte_denom);
    const roll = rng.intRangeAtMost(u32, 0, 9999);
    return roll < death_threshold;
}

// --- Tests ---

test "zero energy means death" {
    const config = Config{};
    const org = Organism{
        .genome = std.StaticBitSet(512).initEmpty(),
        .region_sizes = .{ 32, 32, 16, 16 },
        .energy = 0,
        .age = 0,
        .grid_index = 0,
    };
    var prng = std.Random.DefaultPrng.init(42);
    try std.testing.expect(checkDeath(&org, prng.random(), config));
}

test "larger genome increases death probability" {
    const config = Config{};
    // Small genome: 96 bits = 12 bytes, threshold = 2 + 12/4 = 5
    const small = Organism{
        .genome = std.StaticBitSet(512).initEmpty(),
        .region_sizes = .{ 32, 32, 16, 16 },
        .energy = 1000,
        .age = 100,
        .grid_index = 0,
    };
    // Large genome: 512 bits = 64 bytes, threshold = 2 + 64/4 = 18
    const large = Organism{
        .genome = std.StaticBitSet(512).initEmpty(),
        .region_sizes = .{ 128, 128, 128, 128 },
        .energy = 1000,
        .age = 100,
        .grid_index = 0,
    };

    // Run many trials and compare death rates
    var prng = std.Random.DefaultPrng.init(12345);
    const rng = prng.random();
    var small_deaths: u32 = 0;
    var large_deaths: u32 = 0;
    const trials = 100000;

    for (0..trials) |_| {
        if (checkDeath(&small, rng, config)) small_deaths += 1;
        if (checkDeath(&large, rng, config)) large_deaths += 1;
    }

    // Large genome should have significantly more deaths
    try std.testing.expect(large_deaths > small_deaths);
}
