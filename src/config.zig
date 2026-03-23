pub const Config = struct {
    grid_width: u32 = 512,
    grid_height: u32 = 512,
    starting_organisms: u32 = 60000,
    max_population: u32 = 300000,
    starting_energy: u32 = 500,
    starting_resources: u16 = 100,
    starting_region_sizes: [4]u16 = .{ 32, 32, 16, 16 },
    max_genome_bits: u16 = 512,
    energy_per_resource: u16 = 5,
    waste_ratio_denom: u8 = 2,
    maintenance_base: u16 = 10,
    maintenance_byte_denom: u16 = 8,
    reproduction_threshold: u32 = 1000,
    parent_energy_pct: u8 = 40,
    child_energy_pct: u8 = 40,
    signal_similarity_threshold: u8 = 70,
    parasitism_threshold: u8 = 70,
    mutualism_low: u8 = 40,
    parasitism_steal_pct: u8 = 25,
    mutualism_bonus: u16 = 30,
    point_mutation_rate: u16 = 50,
    region_duplication_rate: u16 = 50,
    region_shrink_rate: u16 = 50,
    insertion_rate: u16 = 30,
    deletion_rate: u16 = 30,
    diffusion_denom: u8 = 8,
    injection_amount: u16 = 2,
    injection_interval: u16 = 10,
    age_death_base: u16 = 2,
    age_death_byte_denom: u16 = 4,

    pub fn gridSize(self: Config) u32 {
        return self.grid_width * self.grid_height;
    }

    pub fn startingGenomeLen(self: Config) u16 {
        var total: u16 = 0;
        for (self.starting_region_sizes) |s| total += s;
        return total;
    }
};
