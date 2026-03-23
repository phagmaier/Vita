const std = @import("std");
const Config = @import("config.zig").Config;
const Grid = @import("grid.zig").Grid;
const Cell = @import("grid.zig").Cell;

/// Double-buffered resource diffusion. Reads from grid.cells, writes to buffer, then swaps.
pub fn diffuse(grid: *Grid, buffer: []Cell, config: Config) void {
    const size = config.gridSize();

    // Initialize buffer with zero resources, copy occupants
    for (0..size) |i| {
        buffer[i].resources = .{ 0, 0, 0, 0 };
        buffer[i].occupant = grid.cells[i].occupant;
    }

    for (0..size) |i| {
        const neighbors = grid.neighborIndices(@intCast(i));
        for (0..4) |r| {
            const amount = grid.cells[i].resources[r];
            const donate_each: u16 = amount / config.diffusion_denom;
            const total_donated = donate_each * 4;
            const remainder = amount - total_donated;

            buffer[i].resources[r] += remainder;
            for (neighbors) |n| {
                buffer[n].resources[r] += donate_each;
            }
        }
    }

    // Swap: copy buffer back to grid
    @memcpy(grid.cells, buffer);
}

/// Add injection_amount of each resource to every cell.
pub fn inject(grid: *Grid, config: Config) void {
    for (grid.cells) |*cell| {
        for (0..4) |r| {
            cell.resources[r] +|= config.injection_amount;
        }
    }
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
