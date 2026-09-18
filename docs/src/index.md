# PDEStudioCore.jl

**PDEStudioCore.jl** is a robust, headless-safe Julia backend engineered for the execution, management, and statistical analysis of Partial Differential Equation (PDE) simulations. 

Designed with reproducible academic research in mind, it provides a unified framework for generating strictly typed, precision-agnostic Eulerian and Lagrangian datasets. It features deterministic cryptographic hashing for simulation parameters, automated disk caching, and a highly optimized multithreaded statistical integration pipeline. 

---

## 🏗️ Core Data Structures

All simulation outputs are wrapped in strongly typed structures that strictly map the mathematical domains of your data.

| Type | Description | Dimensions |
| :--- | :--- | :--- |
| `ESimData{D, DS, M, T}` | Represents Eulerian grid data (fields on a static mesh). | `D` = Total Spacetime, `DS` = Spatial |
| `LSimData{D, DS, M, T}` | Represents Lagrangian particle data (scattered points moving). | `M` = Field Components, `T` = Precision |

*Example: An Eulerian simulation in 2D space over time with 4 state variables in Float64 precision is typed as `ESimData{3, 2, 4, Float64}`.*

---

## 🧩 The Simulation Configuration (`SimulationConfig`)

The `SimulationConfig` is the central orchestration structure of the package—the definitive blueprint for your simulation runs. 

It acts as the binding layer that connects your custom numerical solver to your parameter space. By encapsulating the core simulation function alongside the baseline parameters, method-specific overrides, and multi-dimensional parameter sweeps, the `SimulationConfig` ensures that every pipeline execution is strictly defined, fully reproducible, and structurally ready for automated parallel evaluation.

---

## 📖 The Configuration Dictionaries

To cleanly manage complex multi-dimensional parameter sweeps without memory allocations within the `SimulationConfig`, the package uses three distinct strictly-typed dictionary formats:

*   **`ParamDict` (`Dict{Symbol, Any}`):** The fundamental parameter dictionary passed into your custom simulation function. It holds the flat, resolved list of parameters for a single run (e.g., `:N => 100`, `:CFL => 0.2`).
*   **`MethodDict` (`Dict{Symbol, ParamDict}`):** Contains method-specific overrides. It allows you to define a shared baseline `ParamDict`, and dynamically swap parameters for different numerical methods (e.g., overriding `:solver_type` for an `:implicit` vs. an `:explicit` scheme). 
*   **`VariedDict` (`Dict{Symbol, Vector}`):** Defines the parameter grid. The backend automatically computes the Cartesian product of all vectors defined here and executes the pipeline across every combination.

---

## ⚙️ Main API Functions

*   **`run_all_simulations(config::SimulationConfig; kwargs...)`:** The main workhorse. It unpacks the `VariedDict`, applies `MethodDict` overrides, and handles secure cryptographic disk-caching. If a simulation with the exact structural parameters already exists on disk, it is safely bypassed to conserve compute hours.
*   **`calculate_all_stats!(sim_data, ref_func)`:** Evaluates registered statistics (Mass, L1/L2 errors, etc.) dynamically. It uses the `ref_func` to generate a perfect pointwise analytical cache, evaluating exact error metrics across both uniform Eulerian grids and scattered Lagrangian fields.

---

## 📊 Custom Statistics

The package allows you to easily inject and evaluate custom metrics across massive datasets.

### 1. Integrated-Out Statistics (via `calc_stat` overload)
To have the backend automatically integrate a custom metric across specific dimensions (e.g., evaluating a spatial error profile at every time step), overload the `calc_stat` function:

```julia
# Overload for your custom metric
function PDEStudioCore.calc_stat(::Val{:my_custom_error}, fixed_coords, u, ana, domain::DomainInfo)
    measure = PDEStudioCore.get_integration_measure(:my_custom_error, domain)
    return sum(abs.(u .- ana) .* measure)
end

# Register the statistic and declare which dimensions to retain
PDEStudioCore.register_stat!(:my_custom_error, :time)
```
You can explicitly define a vector of dimension symbols to keep (e.g., `[:x, :y]`), or use the built-in aliases: `:all` (full tensor), `:space` (integrates out time), or `:time` (integrates out space).

### 2. Complete Custom Statistics
If your statistic bypasses standard integration and you want to append a pre-calculated array directly to the dataset, use `add_stat!`:

```julia
# Bypasses calc_stat and directly inserts the stat into the dictionary and registry
PDEStudioCore.add_stat!(sim_data, :custom_metric, my_value_array, :time)
```

---

## 🛠️ Technical Details & Dimension Keys (`dim_keys`)

A core part of the architecture is the `dim_keys` field inside `DomainInfo`. 
*   **Identification:** The `dim_keys` tuple acts as the *sole identifier* for your axes. The value (e.g., `:x`, `:t`) and the order matter strictly for interpolation, statistical slicing, and plotting.
*   **Consistency:** While you can set these keys freely to match your physical model (e.g., `(:r, :theta, :t)`), you should **never** change the layout of a tuple for a specific model paradigm once data has been serialized to disk, as this breaks backwards compatibility.

---

## 🚀 Examples

To help you get started with the `PDEStudioCore` pipeline, we provide complete, runnable examples in the `examples/` directory.

*   **`examples/dummy.jl`**: A minimal, self-contained quick-start script. It demonstrates how to set up a shared parameter pool, define numerical methods, sweep over time-step sizes, and run a mock 1D wave simulation.