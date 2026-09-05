import pyperf

# Load benchmark JSON files
bench_base = pyperf.Benchmark.load("baseline.json")
bench_opt = pyperf.Benchmark.load("optimized_refactor.json")

# Extract raw values
base_vals = bench_base.get_values()
opt_vals = bench_opt.get_values()

print(f"Baseline  - Min: {min(base_vals):.4f}s, Max: {max(base_vals):.4f}s, StDev: {bench_base.stdev():.4f}s")
print(f"Optimized - Min: {min(opt_vals):.4f}s, Max: {max(opt_vals):.4f}s, StDev: {bench_opt.stdev():.4f}s")
