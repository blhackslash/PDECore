# Statistics and Analytics

**PDEStudioCore.jl** features a powerful, multithreaded statistical integration pipeline. Instead of forcing you to write complex loops to average data over space or time, the backend automatically slices your multidimensional Eulerian tensors or Lagrangian particle series, executes your custom math, and saves the reduced data to disk.

By default, the global statistics registry starts completely empty, ensuring the backend makes no assumptions about your physical model.

## 1. Loading Presets

If you are working with standard physical models, you can load a predefined suite of statistics. For example, to load standard metrics for hyperbolic PDEs (like mass, L1/L2 errors, and wave heights):

```julia
using PDEStudioCore
PDEStudioCore.set_stat_preset!("hyperbolic")
```

## 2. Automated Integration (via `calc_stat`)

If you want to compute a metric that integrates out specific dimensions (e.g., calculating the spatial L2 error at *every* time step), you should use the automated `calc_stat` pipeline. 

### Step A: Register the Statistic
First, register your statistic's name and define which dimensions you want to **retain**. The backend will automatically integrate out the dimensions you *do not* list here. 

You can use the built-in aliases (`:all`, `:space`, `:time`) or an explicit vector of dimension symbols (e.g., `[:x, :y]`).

```julia
# We want a time series, so we tell the registry to retain the :time dimension
PDEStudioCore.register_stat!(:custom_energy, :time)
```

### Step B: Overload `calc_stat`
Next, write a method extending `PDEStudioCore.calc_stat` for your specific metric. The backend will automatically multithread this function across your data slices.

```julia
function PDEStudioCore.calc_stat(::Val{:custom_energy}, fixed_coords, u, ana, domain::DomainInfo)
    # 1. Fetch the combined scalar measure (e.g., dx * dy) for the dimensions being integrated
    measure = PDEStudioCore.get_integration_measure(:custom_energy, domain)
    
    # 2. Perform your math (u and ana are pre-sliced 1D iterators)
    return sum(abs2.(u) .* measure)
end
```

**Understanding the Inputs:**
*   `::Val{:name}`: The strict dispatch token matching your registered statistic.
*   `fixed_coords`: The exact spatial or temporal coordinates of the slice currently being evaluated.
*   `u`: A flat iterator containing the numerical simulation data for this specific slice.
*   `ana`: A flat iterator containing the exact analytical reference data (or `NaN`s if no reference function was provided).
*   `domain`: The `DomainInfo` metadata object, providing access to grid spacing and bounding boxes.

## 3. Direct Injection (via `add_stat!`)

Sometimes, a statistic does not fit the standard integration pipeline. For example, tracking the physical execution time of your solver, memory allocations, or a complex global scalar that requires access to the entire dataset at once.

For these cases, use `add_stat!`. This function attaches a raw array or scalar directly to the simulation object. 

### Using `add_stat!` in Post-Processing
The most elegant place to inject custom metrics is inside the `post_process_func` of your `SimulationConfig`. The backend runs this function immediately after standard stats are calculated.

```julia
function my_post_process(sim_data)
    # 1. Calculate a totally custom global metric
    max_val = maximum(sim_data.u)
    
    # 2. Inject it into the dataset, explicitly declaring it has no dimensions (Symbol[])
    PDEStudioCore.add_stat!(sim_data, :global_maximum, max_val, Symbol[])
    
    # 3. Return true to instruct the backend to overwrite the file on disk!
    return true
end

# Attach it to your config
config = SimulationConfig(
    :my_wave_solver, shared, methods, [:upwind];
    post_process_name = :my_post_process
)
```

> **Note:** Whenever you use `add_stat!`, you must provide the `kept_dims` argument (like `:time`, `:space`, or `Symbol[]`). This ensures the UI frontend (**PDEStudio.jl**) knows exactly how to slice and visualize your custom array later!