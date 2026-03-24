const std = @import("std");
const Config = @import("config.zig").Config;
const Organism = @import("organism.zig").Organism;
const OrganismPool = @import("pool.zig").OrganismPool;
const Grid = @import("grid.zig").Grid;

pub const Logger = struct {
    file: std.fs.File,
    births_this_interval: u32,
    deaths_this_interval: u32,
    parasitism_this_interval: u32,
    mutualism_this_interval: u32,

    pub fn init(path: []const u8) !Logger {
        const file = try std.fs.cwd().createFile(path, .{});
        try file.writeAll("tick,alive_count,births,deaths,mean_energy,mean_genome_len,unique_phenotypes,metabolic_diversity,signal_clusters,total_resources,parasitism_events,mutualism_events\n");
        return Logger{
            .file = file,
            .births_this_interval = 0,
            .deaths_this_interval = 0,
            .parasitism_this_interval = 0,
            .mutualism_this_interval = 0,
        };
    }

    pub fn deinit(self: *Logger) void {
        self.file.close();
    }

    pub fn recordBirth(self: *Logger) void {
        self.births_this_interval += 1;
    }

    pub fn recordDeath(self: *Logger) void {
        self.deaths_this_interval += 1;
    }

    pub fn recordParasitism(self: *Logger) void {
        self.parasitism_this_interval += 1;
    }

    pub fn recordMutualism(self: *Logger) void {
        self.mutualism_this_interval += 1;
    }

    pub fn logTick(self: *Logger, tick: u64, pool: *const OrganismPool, grid: *const Grid) !void {
        var total_energy: u64 = 0;
        var total_genome_len: u64 = 0;

        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const aa = arena.allocator();

        // Pre-allocate maps to avoid frequent resizing
        const map_capacity = @min(pool.alive_count, 10000);
        var phenotype_set = std.AutoHashMap(u64, void).init(aa);
        try phenotype_set.ensureTotalCapacity(map_capacity);
        var metabolism_set = std.AutoHashMap(u64, void).init(aa);
        try metabolism_set.ensureTotalCapacity(map_capacity);
        var signal_set = std.AutoHashMap(u64, void).init(aa);
        try signal_set.ensureTotalCapacity(map_capacity);

        for (0..pool.alive_count) |i| {
            const org = &pool.organisms[pool.alive_list[i]];
            total_energy += org.energy;
            total_genome_len += org.totalGenomeLen();

            const pheno_hash = hashRegions(org, 0, 2);
            _ = phenotype_set.getOrPutValue(pheno_hash, {}) catch {};

            const meta_hash = hashRegion(org, 2);
            _ = metabolism_set.getOrPutValue(meta_hash, {}) catch {};

            const sig_hash = hashRegion(org, 3);
            _ = signal_set.getOrPutValue(sig_hash, {}) catch {};
        }

        var total_resources: u64 = 0;
        for (grid.cells) |cell| {
            for (cell.resources) |r| total_resources += r;
        }

        const alive = pool.alive_count;
        const mean_energy: u64 = if (alive > 0) total_energy / alive else 0;
        const mean_genome_len: u64 = if (alive > 0) total_genome_len / alive else 0;

        // Format line into a stack buffer then write
        var fmt_buf: [512]u8 = undefined;
        const line = std.fmt.bufPrint(&fmt_buf, "{},{},{},{},{},{},{},{},{},{},{},{}\n", .{
            tick,
            alive,
            self.births_this_interval,
            self.deaths_this_interval,
            mean_energy,
            mean_genome_len,
            phenotype_set.count(),
            metabolism_set.count(),
            signal_set.count(),
            total_resources,
            self.parasitism_this_interval,
            self.mutualism_this_interval,
        }) catch return;

        _ = self.file.writeAll(line) catch {};

        self.births_this_interval = 0;
        self.deaths_this_interval = 0;
        self.parasitism_this_interval = 0;
        self.mutualism_this_interval = 0;
    }
};

fn hashRegion(org: *const Organism, region_idx: usize) u64 {
    const start = blk: {
        var s: u16 = 0;
        for (0..region_idx) |i| s += org.region_sizes[i];
        break :blk s;
    };
    const len = org.region_sizes[region_idx];
    return hashBitRange(org, start, len);
}

fn hashRegions(org: *const Organism, start_region: usize, count: usize) u64 {
    const start = blk: {
        var s: u16 = 0;
        for (0..start_region) |i| s += org.region_sizes[i];
        break :blk s;
    };
    var total_len: u16 = 0;
    for (start_region..start_region + count) |i| {
        total_len += org.region_sizes[i];
    }
    return hashBitRange(org, start, total_len);
}

fn hashBitRange(org: *const Organism, start: u16, len: u16) u64 {
    var h: u64 = 0xcbf29ce484222325;
    const MASK_BITS = @bitSizeOf(usize);
    var offset: u16 = 0;
    while (offset + MASK_BITS <= len) {
        const word = @import("interaction.zig").extractWord(&org.genome, start + offset);
        h ^= word;
        h *%= 0x100000001b3;
        offset += MASK_BITS;
    }
    if (offset < len) {
        const remaining: std.math.Log2Int(usize) = @intCast(len - offset);
        const mask: usize = (@as(usize, 1) << remaining) - 1;
        const word = @import("interaction.zig").extractWord(&org.genome, start + offset) & mask;
        h ^= word;
        h *%= 0x100000001b3;
    }
    h ^= len;
    h *%= 0x100000001b3;
    return h;
}
