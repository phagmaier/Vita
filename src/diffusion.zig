const std = @import("std");
const Config = @import("config.zig").Config;
const Grid = @import("grid.zig").Grid;
const Cell = @import("grid.zig").Cell;

/// Double-buffered resource diffusion. Reads from grid.cells, writes to buffer.
pub fn diffuse(grid: *Grid, buffer: []Cell, config: Config) void {
    const size = config.gridSize();
    const denom = config.diffusion_denom;

    // Zero out resources in buffer but keep occupants
    for (0..size) |i| {
        buffer[i].occupant = grid.cells[i].occupant;
        buffer[i].resources = .{ 0, 0, 0, 0 };
    }

    const neighbor_table = grid.neighbors;
    const cells = grid.cells;

    for (0..size) |i| {
        const base = i * 4;
        const n0 = neighbor_table[base];
        const n1 = neighbor_table[base + 1];
        const n2 = neighbor_table[base + 2];
        const n3 = neighbor_table[base + 3];

        inline for (0..4) |r| {
            const amount = cells[i].resources[r];
            const give = amount / denom;
            const keep = amount - (give * 4);

            buffer[i].resources[r] +|= keep;
            buffer[n0].resources[r] +|= give;
            buffer[n1].resources[r] +|= give;
            buffer[n2].resources[r] +|= give;
            buffer[n3].resources[r] +|= give;
        }
    }

    @memcpy(grid.cells, buffer);
}

// --- Tests ---

test "diffusion conserves total resources" {
    const allocator = std.testing.allocator;
    const config = Config{ .grid_width = 4, .grid_height = 4, .starting_resources = 100 };
    var grid = try Grid.init(allocator, config);
    defer grid.deinit();

    const buffer = try allocator.alloc(Cell, config.gridSize());
    defer allocator.free(buffer);

    // Compute total before
    var total_before: u64 = 0;
    for (grid.cells) |cell| {
        for (cell.resources) |r| total_before += r;
    }

    diffuse(&grid, buffer, config);

    // Compute total after
    var total_after: u64 = 0;
    for (grid.cells) |cell| {
        for (cell.resources) |r| total_after += r;
    }

    try std.testing.expectEqual(total_before, total_after);
}

test "injection adds resources" {
    const allocator = std.testing.allocator;
    const config = Config{ .grid_width = 4, .grid_height = 4, .starting_resources = 10, .injection_amount = 5 };
    var grid = try Grid.init(allocator, config);
    defer grid.deinit();

    inject(&grid, config);

    // Each cell should now have 15
    try std.testing.expectEqual(@as(u16, 15), grid.cells[0].resources[0]);
    try std.testing.expectEqual(@as(u16, 15), grid.cells[0].resources[3]);
}

test "diffusion spreads resources from a spike" {
    const allocator = std.testing.allocator;
    const config = Config{ .grid_width = 4, .grid_height = 4, .starting_resources = 0 };
    var grid = try Grid.init(allocator, config);
    defer grid.deinit();

    const buffer = try allocator.alloc(Cell, config.gridSize());
    defer allocator.free(buffer);

    // Put 80 resource 0 in cell 5
    grid.cells[5].resources[0] = 80;

    diffuse(&grid, buffer, config);

    // Cell 5 should have remainder: 80 - 4*(80/8) = 80 - 40 = 40
    try std.testing.expectEqual(@as(u16, 40), grid.cells[5].resources[0]);

    // Each neighbor should have received 80/8 = 10
    const neighbors = grid.neighborIndices(5);
    for (neighbors) |n| {
        try std.testing.expectEqual(@as(u16, 10), grid.cells[n].resources[0]);
    }
}

/// Add injection_amount of each resource to every cell.
pub fn inject(grid: *Grid, config: Config) void {
    const amount = config.injection_amount;
    for (grid.cells) |*cell| {
        cell.resources[0] +|= amount;
        cell.resources[1] +|= amount;
        cell.resources[2] +|= amount;
        cell.resources[3] +|= amount;
    }
}
