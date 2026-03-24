const std = @import("std");
const Config = @import("config.zig").Config;
const Organism = @import("organism.zig").Organism;
const GENOME_BITS = @import("organism.zig").GENOME_BITS;

pub const InteractionResult = enum {
    skipped,
    nothing,
    mutualism,
    parasitism,
};

// StaticBitSet(512) uses ArrayBitSet(usize, 512) internally: 8 x u64 words.
const MASK_BITS: u16 = @bitSizeOf(usize); // 64 on 64-bit
const NUM_MASKS: u16 = GENOME_BITS / MASK_BITS; // 8

/// Extract up to MASK_BITS bits from a genome starting at bit `start` (LSB-first).
pub inline fn extractWord(genome: *const std.StaticBitSet(GENOME_BITS), start: u16) usize {
    const word_idx = start / MASK_BITS;
    const bit_off: std.math.Log2Int(usize) = @intCast(start % MASK_BITS);
    const lo = genome.masks[word_idx] >> bit_off;
    if (bit_off == 0) return lo;
    const hi_shift: std.math.Log2Int(usize) = @intCast(MASK_BITS - @as(u32, bit_off));
    const hi: usize = if (word_idx + 1 < NUM_MASKS) genome.masks[word_idx + 1] << hi_shift else 0;
    return lo | hi;
}

/// Count differing bits between two genome ranges using word-level XOR + popcount.
/// ~32-64x faster than bit-by-bit for large regions.
fn countDifferingBits(
    a: *const std.StaticBitSet(GENOME_BITS),
    a_start: u16,
    b: *const std.StaticBitSet(GENOME_BITS),
    b_start: u16,
    len: u16,
) u32 {
    var differing: u32 = 0;
    var offset: u16 = 0;
    while (offset + MASK_BITS <= len) {
        differing += @popCount(extractWord(a, a_start + offset) ^ extractWord(b, b_start + offset));
        offset += MASK_BITS;
    }
    if (offset < len) {
        const remaining: std.math.Log2Int(usize) = @intCast(len - offset);
        const mask: usize = (@as(usize, 1) << remaining) - 1;
        differing += @popCount((extractWord(a, a_start + offset) ^ extractWord(b, b_start + offset)) & mask);
    }
    return differing;
}

/// Compare signal regions of two organisms. Returns similarity percentage (0-100).
fn signalSimilarity(a: *const Organism, b: *const Organism) u32 {
    const a_len = a.region_sizes[3]; // signal
    const b_len = b.region_sizes[3];
    const compare_len = @min(a_len, b_len);
    if (compare_len == 0) return 100; // both empty = identical

    const a_start = a.regionStart(.signal);
    const b_start = b.regionStart(.signal);

    const differing = countDifferingBits(&a.genome, a_start, &b.genome, b_start, compare_len);
    return (compare_len - differing) * 100 / compare_len;
}

/// Compare attacker's attack region vs defender's defense region. Returns match percentage (0-100).
fn attackDefenseMatch(attacker: *const Organism, defender: *const Organism) u32 {
    const atk_len = attacker.region_sizes[0]; // attack
    const def_len = defender.region_sizes[1]; // defense
    const compare_len = @min(atk_len, def_len);
    if (compare_len == 0) return 0;

    const atk_start = attacker.regionStart(.attack);
    const def_start = defender.regionStart(.defense);

    const differing = countDifferingBits(&attacker.genome, atk_start, &defender.genome, def_start, compare_len);
    return differing * 100 / compare_len;
}

/// Process interaction between actor and neighbor. Modifies energy directly.
pub fn processInteraction(actor: *Organism, neighbor: *Organism, config: Config) InteractionResult {
    // Step 1: Signal check
    const similarity = signalSimilarity(actor, neighbor);
    if (similarity >= config.signal_similarity_threshold) {
        return .skipped; // Kin recognition — skip
    }

    // Step 2: Attack vs Defense
    const match_pct = attackDefenseMatch(actor, neighbor);

    if (match_pct >= config.parasitism_threshold) {
        // Parasitism: attacker steals energy
        const steal = (neighbor.energy * @as(u32, config.parasitism_steal_pct)) / 100;
        neighbor.energy -|= steal;
        actor.energy += steal;
        return .parasitism;
    } else if (match_pct >= config.mutualism_low) {
        // Mutualism: both gain energy
        actor.energy += config.mutualism_bonus;
        neighbor.energy += config.mutualism_bonus;
        return .mutualism;
    }

    return .nothing;
}

// --- Tests ---

test "identical signal regions are recognized as kin" {
    var a = Organism.initTest(.{ 32, 32, 16, 16 }, 500);
    var b = a; // Identical

    const config = Config{};
    const result = processInteraction(&a, &b, config);
    try std.testing.expectEqual(InteractionResult.skipped, result);
}

test "completely different signals allow interaction" {
    var a = Organism.initTest(.{ 32, 32, 16, 16 }, 500);
    var b = a;

    // Make all of b's signal bits 1 (a's are all 0)
    const sig_start = b.regionStart(.signal);
    for (0..16) |i| {
        b.genome.set(sig_start + i);
    }

    const config = Config{};
    const result = processInteraction(&a, &b, config);
    // Signal similarity = 0%, so interaction proceeds
    // Attack/defense match depends on bits — both all zeros = 0 differing = 0% match
    try std.testing.expectEqual(InteractionResult.nothing, result);
}

test "parasitism steals energy" {
    var attacker = Organism.initTest(.{ 32, 32, 16, 16 }, 500);
    var defender = attacker;

    // Make signals different so interaction proceeds
    const sig_start = defender.regionStart(.signal);
    for (0..16) |i| {
        defender.genome.set(sig_start + i);
    }

    // Make attack all 1s, defense all 0s -> 100% differing = 100% match
    for (0..32) |i| {
        attacker.genome.set(i); // attack region starts at 0
    }
    // defender's defense region is all 0s (already)

    const config = Config{};
    const result = processInteraction(&attacker, &defender, config);
    try std.testing.expectEqual(InteractionResult.parasitism, result);

    // Attacker should have gained energy, defender lost
    const stolen = @as(u32, 500) * config.parasitism_steal_pct / 100;
    try std.testing.expectEqual(@as(u32, 500 + stolen), attacker.energy);
    try std.testing.expectEqual(@as(u32, 500 - stolen), defender.energy);
}

test "mutualism gives both energy" {
    var a = Organism.initTest(.{ 32, 32, 16, 16 }, 500);
    var b = a;

    // Make signals different
    const sig_start = b.regionStart(.signal);
    for (0..16) |i| {
        b.genome.set(sig_start + i);
    }

    // Set attack to have ~50% match with defense (mutualism range)
    // Attack: first 16 bits set, last 16 unset
    // Defense: all unset
    // -> 16 differing out of 32 = 50% match
    for (0..16) |i| {
        a.genome.set(i);
    }

    const config = Config{};
    const result = processInteraction(&a, &b, config);
    try std.testing.expectEqual(InteractionResult.mutualism, result);
    try std.testing.expectEqual(@as(u32, 500 + config.mutualism_bonus), a.energy);
    try std.testing.expectEqual(@as(u32, 500 + config.mutualism_bonus), b.energy);
}
