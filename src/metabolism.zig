const std = @import("std");
const Config = @import("config.zig").Config;
const Organism = @import("organism.zig").Organism;
const Region = @import("organism.zig").Region;
const Cell = @import("grid.zig").Cell;

pub const MetabolismResult = enum {
    alive,
    dead,
};

const WASTE_MAP = [4]usize{ 1, 0, 3, 2 };

pub fn processMetabolism(org: *Organism, cell: *Cell, config: Config) MetabolismResult {
    var total_consumed: u32 = 0;

    // Compute region start once — avoids 16 redundant regionStart() calls
    const met_start = org.regionStart(.metabolism);
    const met_size = org.region_sizes[2];

    // Read 4-bit affinities and consume resources
    for (0..4) |i| {
        const base: u16 = @as(u16, @intCast(i)) * 4;
        var affinity: u16 = 0;
        inline for (0..4) |bit| {
            const bit_pos: u16 = base + @as(u16, @intCast(bit));
            if (bit_pos < met_size and org.genome.isSet(met_start + bit_pos)) {
                affinity |= @as(u16, 1) << @intCast(bit);
            }
        }
        const available = cell.resources[i];
        const consumed: u16 = @intCast(@min(affinity, available));
        cell.resources[i] -= consumed;
        total_consumed += consumed;

        // Produce waste
        const waste: u16 = consumed / config.waste_ratio_denom;
        const waste_target = WASTE_MAP[i];
        cell.resources[waste_target] +|= waste; // saturating add to prevent overflow
    }

    // Gain energy
    org.energy += total_consumed * config.energy_per_resource;

    // Maintenance cost
    const genome_byte_len: u32 = org.genomeByteLen();
    const maintenance: u32 = config.maintenance_base + (genome_byte_len / config.maintenance_byte_denom);

    if (org.energy <= maintenance) {
        org.energy = 0;
        return .dead;
    }
    org.energy -= maintenance;
    return .alive;
}

// --- Tests ---

test "metabolism consumes resources and produces waste" {
    const config = Config{};
    var org = Organism{
        .genome = std.StaticBitSet(512).initEmpty(),
        .region_sizes = .{ 32, 32, 16, 16 },
        .energy = 500,
        .age = 0,
        .grid_index = 0,
    };
    // Set metabolism nibble 0 = 0b1111 = 15 (max affinity for resource 0)
    for (0..4) |bit| {
        org.setRegionBit(.metabolism, @intCast(bit), true);
    }
    // Set metabolism nibble 1 = 0b0000 = 0 (no affinity for resource 1)
    // (already zero)

    var cell = Cell{
        .resources = .{ 10, 20, 0, 0 },
        .occupant = 0,
    };

    const result = processMetabolism(&org, &cell, config);
    try std.testing.expectEqual(MetabolismResult.alive, result);

    // Should have consumed 10 of resource 0 (min(15, 10)), 0 of resource 1 (min(0, 20))
    try std.testing.expectEqual(@as(u16, 0), cell.resources[0]);

    // Waste: consumed 10 of resource 0 -> produces 5 into resource 1
    // cell.resources[1] was 20 (nothing consumed from it), + 5 waste = 25
    try std.testing.expectEqual(@as(u16, 25), cell.resources[1]);

    // Energy: 500 + (10 * 5) - (10 + 12/8) = 500 + 50 - 11 = 539
    try std.testing.expectEqual(@as(u32, 539), org.energy);
}

test "metabolism kills organism when energy too low" {
    const config = Config{};
    var org = Organism{
        .genome = std.StaticBitSet(512).initEmpty(),
        .region_sizes = .{ 32, 32, 16, 16 },
        .energy = 5, // Very low
        .age = 0,
        .grid_index = 0,
    };

    var cell = Cell{
        .resources = .{ 0, 0, 0, 0 }, // No resources to consume
        .occupant = 0,
    };

    const result = processMetabolism(&org, &cell, config);
    try std.testing.expectEqual(MetabolismResult.dead, result);
    try std.testing.expectEqual(@as(u32, 0), org.energy);
}
