#!/usr/bin/env python3
"""Vita simulation dashboard — reads vita_log.csv and produces a multi-panel plot."""

import csv
import sys
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker

def load_csv(path):
    data = {}
    with open(path) as f:
        reader = csv.DictReader(f)
        for key in reader.fieldnames:
            data[key] = []
        for row in reader:
            for key in reader.fieldnames:
                data[key].append(int(row[key]))
    return data

def plot_dashboard(data, save_path=None):
    ticks = data["tick"]
    if not ticks:
        print("No data to plot.")
        return

    fig, axes = plt.subplots(3, 2, figsize=(14, 10), sharex=True)
    fig.suptitle("Vita — Red Queen Ecosystem Dashboard", fontsize=14, fontweight="bold")

    # --- Panel 1: Population ---
    ax = axes[0][0]
    ax.plot(ticks, data["alive_count"], color="#2196F3", linewidth=1.5)
    ax.set_ylabel("Population")
    ax.set_title("Population Over Time")
    ax.yaxis.set_major_formatter(ticker.FuncFormatter(lambda x, _: f"{x/1000:.0f}k" if x >= 1000 else f"{x:.0f}"))
    ax.grid(True, alpha=0.3)

    # --- Panel 2: Births & Deaths ---
    ax = axes[0][1]
    ax.plot(ticks, data["births"], color="#4CAF50", linewidth=1, alpha=0.8, label="Births")
    ax.plot(ticks, data["deaths"], color="#F44336", linewidth=1, alpha=0.8, label="Deaths")
    ax.set_ylabel("Count (per 100 ticks)")
    ax.set_title("Births & Deaths")
    ax.legend(loc="upper right", fontsize=8)
    ax.yaxis.set_major_formatter(ticker.FuncFormatter(lambda x, _: f"{x/1000:.0f}k" if x >= 1000 else f"{x:.0f}"))
    ax.grid(True, alpha=0.3)

    # --- Panel 3: Energy ---
    ax = axes[1][0]
    ax.plot(ticks, data["mean_energy"], color="#FF9800", linewidth=1.5)
    ax.set_ylabel("Mean Energy")
    ax.set_title("Mean Organism Energy")
    ax.grid(True, alpha=0.3)

    # --- Panel 4: Genome Length ---
    ax = axes[1][1]
    ax.plot(ticks, data["mean_genome_len"], color="#9C27B0", linewidth=1.5)
    ax.set_ylabel("Mean Genome Length (bits)")
    ax.set_title("Mean Genome Length")
    ax.grid(True, alpha=0.3)

    # --- Panel 5: Diversity ---
    ax = axes[2][0]
    ax.plot(ticks, data["unique_phenotypes"], color="#E91E63", linewidth=1, alpha=0.8, label="Phenotypes")
    ax.plot(ticks, data["metabolic_diversity"], color="#00BCD4", linewidth=1, alpha=0.8, label="Metabolic")
    ax.plot(ticks, data["signal_clusters"], color="#8BC34A", linewidth=1, alpha=0.8, label="Signal")
    ax.set_ylabel("Unique Count")
    ax.set_xlabel("Tick")
    ax.set_title("Diversity Metrics")
    ax.legend(loc="upper right", fontsize=8)
    ax.yaxis.set_major_formatter(ticker.FuncFormatter(lambda x, _: f"{x/1000:.0f}k" if x >= 1000 else f"{x:.0f}"))
    ax.grid(True, alpha=0.3)

    # --- Panel 6: Total Resources ---
    ax = axes[2][1]
    ax.plot(ticks, data["total_resources"], color="#795548", linewidth=1.5)
    ax.set_ylabel("Total Resources")
    ax.set_xlabel("Tick")
    ax.set_title("Total Resources in World")
    ax.yaxis.set_major_formatter(ticker.FuncFormatter(lambda x, _: f"{x/1e6:.1f}M" if x >= 1e6 else f"{x/1000:.0f}k"))
    ax.grid(True, alpha=0.3)

    plt.tight_layout()

    if save_path:
        plt.savefig(save_path, dpi=150, bbox_inches="tight")
        print(f"Saved to {save_path}")
    else:
        plt.show()

def main():
    csv_path = sys.argv[1] if len(sys.argv) > 1 else "vita_log.csv"
    save_path = sys.argv[2] if len(sys.argv) > 2 else None

    data = load_csv(csv_path)
    print(f"Loaded {len(data['tick'])} data points from {csv_path}")
    print(f"Ticks: {data['tick'][0]} to {data['tick'][-1]}")
    print(f"Population: {data['alive_count'][0]} -> {data['alive_count'][-1]}")

    plot_dashboard(data, save_path)

if __name__ == "__main__":
    main()
