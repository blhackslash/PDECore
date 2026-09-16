# Advanced Simulation Configurations

While the default setup runs your numerical methods perfectly fine, you will often want to sweep across parameter spaces, compare results against a mathematical baseline, or apply custom modifications to your datasets after generation. 

The `SimulationConfig` constructor accepts several optional keyword arguments to orchestrate these advanced workflows seamlessly.

## 1. Varied Parameters (Grid Sweeps)

To run a parameter sweep, you define a `varied_params` dictionary containing vectors of values. The backend automatically computes the Cartesian product of all provided vectors and executes a simulation task for every single combination.

```julia
# Define the parameter sweep
varied = Dict(
    :N   => [50, 100, 200],
    :CFL => [0.1, 0.5, 0.8]
)

config = SimulationConfig(
    :my_wave_solver, shared, methods, [:upwind];
    varied_params = varied
)
```

### Advanced Tuple Sweeps
If your solver expects a tuple (e.g., a 2D spatial resolution like `:Ns => (100, 100)`), you can sweep over individual dimensions independently. Append `__x`, `__y`, or `__1`, `__2` to the base key. The backend intercepts these and safely reconstructs the strictly typed `Tuple` before passing it to your solver.

```julia
varied_tuples = Dict(
    :Ns__x => [50, 100], # Sweeps the first element
    :Ns__y => [50, 100]  # Sweeps the second element
)
```

## 2. Analytical Reference Functions

To automate the calculation of error metrics (like L1/L2 errors), you can provide a continuous analytical reference function. This function takes a spacetime coordinate vector and returns the exact mathematical solution. By passing its registered name to `ref_func_name`, the backend will automatically generate a pointwise perfect exact cache and evaluate your registered statistics against it.

```julia
function exact_wave(st)
    # st is a spacetime coordinate SVector (e.g., [x, y, t])
    return SVector(sin(st[1] - st[end]))
end

config = SimulationConfig(
    :my_wave_solver, shared, methods, [:upwind];
    ref_func_name = :exact_wave
)
```

## 3. Custom Post-Processing

If you need to mutate your data immediately after it is generated (e.g., filtering out noise, computing derived fields, or triggering external plotting scripts), use `post_process_name`. The function must accept an `AbstractSimData` object and return a `Bool`. If it returns `true`, the backend automatically overwrites the dataset on disk to save your modifications.

```julia
function filter_results(sim_data)
    # Mutate data...
    return true # Triggers a disk save
end

config = SimulationConfig(
    :my_wave_solver, shared, methods, [:upwind];
    post_process_name = :filter_results
)
```

## 4. Source Files Tracking

For strict academic reproducibility, you can pass a list of file paths to `source_files`. Notably, every file listed here is automatically loaded into the target module before execution begins. This ensures your solvers and reference functions are always compiled and available, while also keeping a record of the specific scripts used to generate the batch.

```julia
config = SimulationConfig(
    :my_wave_solver, shared, methods, [:upwind];
    source_files = ["src/wave_equations.jl", "src/boundary_conditions.jl"]
)
```