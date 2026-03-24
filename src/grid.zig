const std = @import("std");
const Config = @import("config.zig").Config;
const EMPTY = @import("organism.zig").EMPTY;

pub const Cell = struct {
    resources: [4]u16,
    occupant: u32,
};

pub const Grid = struct {
    cells: []Cell,
    neighbors: []u32, // Precomputed flat table: [N, S, E, W] per cell, stride 4
    width: u32,
    height: u32,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, config: Config) !Grid {
        const size = config.gridSize();
        const cells = try allocator.alloc(Cell, size);
        for (cells) |*cell| {
            cell.* = .{
                .resources = .{ config.starting_resources, config.starting_resources, config.starting_resources, config.starting_resources },
                .occupant = EMPTY,
            };
        }

        // Precompute neighbor indices once — eliminates division/modulo in the hot path
        const neighbors = try allocator.alloc(u32, size * 4);
        const w = config.grid_width;
        const h = config.grid_height;
        for (0..size) |idx| {
            const i: u32 = @intCast(idx);
            const x = i % w;
            const y = i / w;
            const n = if (y == 0) (h - 1) * w + x else (y - 1) * w + x;
            const s = if (y == h - 1) x else (y + 1) * w + x;
            const e = if (x == w - 1) y * w else y * w + (x + 1);
            const ww = if (x == 0) y * w + (w - 1) else y * w + (x - 1);
            neighbors[idx * 4 + 0] = n;
            neighbors[idx * 4 + 1] = s;
            neighbors[idx * 4 + 2] = e;
            neighbors[idx * 4 + 3] = ww;
        }

        return Grid{
            .cells = cells,
            .neighbors = neighbors,
            .width = w,
            .height = h,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Grid) void {
        self.allocator.free(self.cells);
        self.allocator.free(self.neighbors);
    }

    pub fn neighborIndices(self: *const Grid, index: u32) [4]u32 {
        const base: usize = @as(usize, index) * 4;
        return .{
            self.neighbors[base],
            self.neighbors[base + 1],
            self.neighbors[base + 2],
            self.neighbors[base + 3],
        };
    }
};

// --- Tests ---

test "neighbor wrapping top-left corner" {
    const config = Config{ .grid_width = 4, .grid_height = 4 };
    const allocator = std.testing.allocator;
    var grid = try Grid.init(allocator, config);
    defer grid.deinit();

    // Index 0 = (0,0)
    const neighbors = grid.neighborIndices(0);
    // North: (0, 3) = 12
    try std.testing.expectEqual(@as(u32, 12), neighbors[0]);
    // South: (0, 1) = 4
    try std.testing.expectEqual(@as(u32, 4), neighbors[1]);
    // East: (1, 0) = 1
    try std.testing.expectEqual(@as(u32, 1), neighbors[2]);
    // West: (3, 0) = 3
    try std.testing.expectEqual(@as(u32, 3), neighbors[3]);
}

test "neighbor wrapping bottom-right corner" {
    const config = Config{ .grid_width = 4, .grid_height = 4 };
    const allocator = std.testing.allocator;
    var grid = try Grid.init(allocator, config);
    defer grid.deinit();

    // Index 15 = (3,3)
    const neighbors = grid.neighborIndices(15);
    // North: (3, 2) = 11
    try std.testing.expectEqual(@as(u32, 11), neighbors[0]);
    // South: (3, 0) = 3
    try std.testing.expectEqual(@as(u32, 3), neighbors[1]);
    // East: (0, 3) = 12
    try std.testing.expectEqual(@as(u32, 12), neighbors[2]);
    // West: (2, 3) = 14
    try std.testing.expectEqual(@as(u32, 14), neighbors[3]);
}

test "grid init sets resources and occupant" {
    const config = Config{ .grid_width = 4, .grid_height = 4, .starting_resources = 50 };
    const allocator = std.testing.allocator;
    var grid = try Grid.init(allocator, config);
    defer grid.deinit();

    try std.testing.expectEqual(@as(u16, 50), grid.cells[0].resources[0]);
    try std.testing.expectEqual(EMPTY, grid.cells[0].occupant);
}
