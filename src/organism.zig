const std = @import("std");
const Config = @import("config.zig").Config;

pub const EMPTY: u32 = 0xFFFFFFFF;
pub const GENOME_BITS: u16 = 512;
pub const NUM_REGIONS: usize = 4;

pub const Region = enum(u2) {
    attack = 0,
    defense = 1,
    metabolism = 2,
    signal = 3,
};

pub const Organism = struct {
    genome: std.StaticBitSet(GENOME_BITS),
    region_sizes: [NUM_REGIONS]u16,
    region_starts: [NUM_REGIONS]u16,
    energy: u32,
    age: u16,
    grid_index: u32,

    pub fn regionStart(self: *const Organism, region: Region) u16 {
        return self.region_starts[@intFromEnum(region)];
    }

    /// Recompute cached region_starts from region_sizes. Call after any mutation that changes region_sizes.
    pub fn updateRegionStarts(self: *Organism) void {
        self.region_starts[0] = 0;
        self.region_starts[1] = self.region_sizes[0];
        self.region_starts[2] = self.region_starts[1] + self.region_sizes[1];
        self.region_starts[3] = self.region_starts[2] + self.region_sizes[2];
    }

    pub fn totalGenomeLen(self: *const Organism) u16 {
        return self.region_starts[3] + self.region_sizes[3];
    }

    pub fn genomeByteLen(self: *const Organism) u16 {
        return (self.totalGenomeLen() + 7) / 8;
    }

    pub fn getRegionBit(self: *const Organism, region: Region, bit_offset: u16) bool {
        const abs = self.regionStart(region) + bit_offset;
        return self.genome.isSet(abs);
    }

    pub fn setRegionBit(self: *Organism, region: Region, bit_offset: u16, val: bool) void {
        const abs = self.regionStart(region) + bit_offset;
        if (val) {
            self.genome.set(abs);
        } else {
            self.genome.unset(abs);
        }
    }

    /// Create a test organism with region_starts computed automatically.
    pub fn initTest(region_sizes: [NUM_REGIONS]u16, energy: u32) Organism {
        var org = Organism{
            .genome = std.StaticBitSet(GENOME_BITS).initEmpty(),
            .region_sizes = region_sizes,
            .region_starts = undefined,
            .energy = energy,
            .age = 0,
            .grid_index = 0,
        };
        org.updateRegionStarts();
        return org;
    }

    pub fn read4BitValue(self: *const Organism, region: Region, nibble_index: u16) u4 {
        var val: u4 = 0;
        const base = nibble_index * 4;
        for (0..4) |i| {
            const bit_pos: u16 = base + @as(u16, @intCast(i));
            if (bit_pos < self.region_sizes[@intFromEnum(region)]) {
                if (self.getRegionBit(region, bit_pos)) {
                    val |= @as(u4, 1) << @intCast(i);
                }
            }
        }
        return val;
    }

    pub fn initRandom(rng: std.Random, config: Config) Organism {
        var org = Organism{
            .genome = std.StaticBitSet(GENOME_BITS).initEmpty(),
            .region_sizes = config.starting_region_sizes,
            .region_starts = undefined,
            .energy = config.starting_energy,
            .age = 0,
            .grid_index = EMPTY,
        };
        org.updateRegionStarts();
        const total = org.totalGenomeLen();
        for (0..total) |i| {
            if (rng.boolean()) {
                org.genome.set(i);
            }
        }
        return org;
    }
};

// --- Tests ---

test "region starts are correct" {
    var org = Organism{
        .genome = std.StaticBitSet(GENOME_BITS).initEmpty(),
        .region_sizes = .{ 32, 32, 16, 16 },
        .region_starts = undefined,
        .energy = 500,
        .age = 0,
        .grid_index = 0,
    };
    org.updateRegionStarts();
    try std.testing.expectEqual(@as(u16, 0), org.regionStart(.attack));
    try std.testing.expectEqual(@as(u16, 32), org.regionStart(.defense));
    try std.testing.expectEqual(@as(u16, 64), org.regionStart(.metabolism));
    try std.testing.expectEqual(@as(u16, 80), org.regionStart(.signal));
}

test "total genome len" {
    var org = Organism{
        .genome = std.StaticBitSet(GENOME_BITS).initEmpty(),
        .region_sizes = .{ 32, 32, 16, 16 },
        .region_starts = undefined,
        .energy = 500,
        .age = 0,
        .grid_index = 0,
    };
    org.updateRegionStarts();
    try std.testing.expectEqual(@as(u16, 96), org.totalGenomeLen());
    try std.testing.expectEqual(@as(u16, 12), org.genomeByteLen());
}

test "initRandom produces valid organism" {
    var prng = std.Random.DefaultPrng.init(42);
    const rng = prng.random();
    const config = Config{};
    const org = Organism.initRandom(rng, config);
    try std.testing.expectEqual(@as(u16, 96), org.totalGenomeLen());
    try std.testing.expectEqual(@as(u32, 500), org.energy);
    try std.testing.expectEqual(@as(u16, 0), org.age);
}

test "read4BitValue" {
    var org = Organism{
        .genome = std.StaticBitSet(GENOME_BITS).initEmpty(),
        .region_sizes = .{ 32, 32, 16, 16 },
        .region_starts = undefined,
        .energy = 500,
        .age = 0,
        .grid_index = 0,
    };
    org.updateRegionStarts();
    // Set metabolism region bits 0-3 to 0b1010 = 5
    org.setRegionBit(.metabolism, 0, true);
    org.setRegionBit(.metabolism, 1, false);
    org.setRegionBit(.metabolism, 2, true);
    org.setRegionBit(.metabolism, 3, false);
    try std.testing.expectEqual(@as(u4, 5), org.read4BitValue(.metabolism, 0));
}
