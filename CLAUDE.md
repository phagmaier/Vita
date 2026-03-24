# Red Queen Bitstring Ecosystem — Implementation Spec (Zig)


## Files
- `src/config.zig` — Has the constants and the configuration and starting point for the agents and the world
- `src/death.zig` — Checks if an should die and has some tests
- `src/grid.zig` — The actual grid of the world
- `src/interaction.zig` — deals with agent interaction logic
- `src/logger.zig` — logs data 
- `src/logger.zig` — logs data 
- `src/main.zig` - What runs the code
- `src/metabolism.zig` - Metabolism logic
- `src/organism.zig` - The organism struct
- `src/pool.zig` - the organism pool the container of the agents
- `src/reproduction.zig` - Reproduction engine and logic
- `visualize.py` - Helps us visualize the logged data in order to help tune the params of the mode


## What We Are Building

An artificial life simulation where organisms are bitstring genomes living on a 2D toroidal grid. Organisms consume resources, interact with neighbors via lock-and-key bitstring matching (parasitism or mutualism), reproduce with mutation, and die. The goal is to produce sustained co-evolutionary arms races.

Language: Zig. Use the standard library wherever possible.

---

## The Organism

### Genome

an array (bitset) of bits that represent a string or genome that have four Regions corresponding to how the agent interacts acts

### Region Layout

The genome is divided into 4 contiguous regions, always in this order:

```
[attack][defense][metabolism][signal]
```

When a region grows via duplication mutation, its entry in `region_sizes` increases. If a mutation would push total length past 512, reject it.

---

## The Grid

512 × 512 toroidal grid stored as a flat array of cells.


### Toroidal Neighbor Lookup

Extract x/y from flat index: `x = index % 512`, `y = index / 512`.

4 cardinal neighbors with wrapping:
- North: `((y + 511) % 512) * 512 + x`
- South: `((y + 1) % 512) * 512 + x`
- East:  `y * 512 + ((x + 1) % 512)`
- West:  `y * 512 + ((x + 511) % 512)`

---

## Organism Pool


Birth: pop index from free_list, init organism, append to alive_list, set cell occupant.
Death: push index to free_list, swap-remove from alive_list, set cell occupant to 0xFFFFFFFF.

---

## Tick Loop

Each tick, in this exact order:

1. **Shuffle alive_list** using Fisher-Yates to prevent positional advantage.
2. **Snapshot `loop_count = alive_count`** before iteration begins.
3. **For each living organism** (iterate `alive_list[0..loop_count]`):
   a. Metabolism
   b. Interaction
   c. Reproduction check
   d. Death check
4. **Resource diffusion** (separate pass, double-buffered).
5. **Resource injection** (every 10 ticks).

### Alive List Iteration Safety

**Deaths during iteration:** When an organism at index `i` dies, swap-remove replaces it with the last element of alive_list and decrements `alive_count`. Do NOT advance `i` after a death — the swapped-in organism at index `i` has not been processed yet. Also decrement `loop_count` so we don't read past the end.

**Births during iteration:** Newborns are appended to the end of alive_list (at positions >= original `loop_count`). Because we iterate only up to the snapshotted `loop_count`, newborns do NOT act on their birth tick. They begin acting next tick.

---

## Metabolism

Read the organism's metabolism region as four 4-bit values (bits 0-3, 4-7, 8-11, 12-15 of the metabolism region). Each 4-bit value (0-15) is the affinity for that resource type.

Per tick:
- For each resource type i (0-3): consume `min(affinity_i, cell.resources[i])` from the cell.
- Gain energy: `total_consumed * 5`.
- Produce waste into the cell:

| Consumed Resource | Produces Resource |
|-------------------|-------------------|
| 0                 | 1                 |
| 1                 | 0                 |
| 2                 | 3                 |
| 3                 | 2                 |

- Waste amount per type: `consumed_i / 2` (integer division).
- Subtract maintenance cost: `10 + (genome_byte_len / 8)` where genome_byte_len = `(sum of region_sizes + 7) / 8`.
- If energy would drop to 0 or below from maintenance, organism dies immediately.

---

## Interaction

1. Pick a random cardinal neighbor cell.
2. If empty, skip.
3. If occupied, run the **signal check** first, then the **attack/defense comparison**.

### Step 1: Signal Check (Species Recognition)

XOR the signal regions of both organisms, truncated to `min(actor_signal_len, neighbor_signal_len)` bits. Popcount the result.

Signal similarity = `(compare_len - differing_bits) * 100 / compare_len`

If signal similarity >= 70%, the organisms recognize each other as kin. **Skip the interaction entirely.**

This creates selective pressure for:
- Signal divergence between lineages (enables parasitism arms races)
- Signal convergence within a lineage (kin protection)

### Step 2: Attack vs Defense Comparison

Compare the attacker's attack region against the defender's defense region only (signal is no longer part of defense).

Truncate to `compare_len = min(attacker_attack_len, defender_defense_len)` bits. XOR those bits, popcount to get `differing_bits`.

Match score = `differing_bits * 100 / compare_len`

The score is capped at 100 by construction since `differing_bits` cannot exceed `compare_len`.

### Outcomes

| Match %   | Result |
|-----------|--------|
| >= 70     | Parasitism. Attacker steals `victim.energy / 4` from victim. |
| 40 to 69  | Mutualism. Both gain 30 energy. |
| < 40      | Nothing. |

Interaction is one-directional per processing. The neighbor gets their own turn when they are processed from the alive_list.

---

## Reproduction

Conditions: `energy > 1000` AND at least one empty cardinal neighbor.

Procedure:
1. Pick a random empty adjacent cell.
2. Copy genome and region_sizes to child.
3. Apply mutations to child genome (see Mutation section).
4. Energy split from pre-reproduction energy:
   - Parent gets: `energy * 4 / 10`
   - Child gets: `energy * 4 / 10`
   - 20% lost.
5. Child age = 0.
6. Place child in the empty cell.
7. Add child to organism pool.

---

## Mutation

All mutations are applied to the child's genome during reproduction.

### Point Mutation
For each bit in the genome (up to total genome length): flip with 0.5% probability.
`if (rng.random() % 10000 < 50) toggle(bit)`

### Region Duplication
Roll once per reproduction: 0.5% chance.
Pick a random region (0-3). Copy all bits of that region and insert right after the original. Shift all subsequent region bits right. Double that region's `region_sizes` entry. Reject if total genome length would exceed 512.

### Region Shrink
Roll once per reproduction: 0.5% chance.
Pick a random region (0-3). If region size > 8 bits, remove the last half of its bits. Shift subsequent region bits left. Halve that region's `region_sizes` entry. Don't let any region go below 8 bits.

### Insertion
Roll once per reproduction: 0.3% chance.
Insert 4-16 random bits at a random position within a random region. Shift subsequent bits right. Update that region's `region_sizes`. Reject if total > 512.

### Deletion
Roll once per reproduction: 0.3% chance.
Remove 4-16 bits from a random position within a random region. Shift subsequent bits left. Update that region's `region_sizes`. Don't let any region go below 8 bits.

---

## Death

### Starvation
If energy hits 0 (or would go below 0 from maintenance), die immediately.

### Age-Based
Each tick after processing, roll `rng.random() % 10000`. Die if result < `2 + (genome_byte_len / 4)`.
For a 12-byte starting genome: ~4/10000 per tick, average lifespan ~2500 ticks.

---

## Resource Diffusion

Separate pass after all organisms have acted. Double-buffered: read from current resource grid, write to second buffer, swap after.

For each cell, for each resource type:
- Donate `amount / 8` to each of 4 cardinal neighbors.
- Remainder stays in the cell.

### Resource Injection
Every 10 ticks: add 2 units of each resource type to every cell.

---

## Starting Conditions

| Parameter                        | Value     |
|----------------------------------|-----------|
| Grid size                        | 512 × 512 |
| Starting organism count          | 60,000    |
| Max population                   | 300,000   |
| Starting energy per organism     | 500       |
| Starting resources per cell      | 100 each  |
| Starting genome length           | 96 bits   |
| Starting region sizes            | [32, 32, 16, 16] |
| Max genome length                | 512 bits  |

Place starting organisms at random grid positions. Skip if position already occupied.
Initialize each genome to random bits.

---

## Config Struct

**NOTE:** All rates are out of 10000 (so 50 = 0.5%, 30 = 0.3%).

---

## Tuning Guide

| Problem                          | Fix                                         |
|----------------------------------|---------------------------------------------|
| Population explodes              | Lower starting_resources to 50, raise reproduction_threshold to 1500 |
| World empties out                | Lower maintenance_base to 5, raise energy_per_resource to 8 |
| No interactions happening        | Lower parasitism_threshold to 60, lower mutualism_low to 30 |
| Everything converges fast        | Raise mutation rates, verify interaction matching works |
| Genomes bloating out of control  | Raise region_shrink_rate, increase maintenance penalties |
| Genomes staying tiny forever     | Lower region_shrink_rate, raise region_duplication_rate |
| No arms races / everything cooperates | Lower signal_similarity_threshold to 60, raise parasitism_steal_pct |
| Kin never cooperate              | Raise signal_similarity_threshold to 80 |

---

## Logging (CSV, one row per sample)

Log every 100 ticks:

```
tick, alive_count, births, deaths, mean_energy, mean_genome_len, unique_phenotypes, metabolic_diversity, signal_clusters, total_resources
```

- unique_phenotypes: hash each organism's attack + defense bits, count distinct hashes among living organisms.
- metabolic_diversity: count distinct metabolism region bit patterns among living organisms.
- signal_clusters: count distinct signal region bit-pattern hashes among living organisms (measures species divergence).
- total_resources: sum of all resources across all cells.
