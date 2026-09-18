# Orchestrating with SimulationConfig

The `SimulationConfig` is the central orchestration structure in **PDEStudioCore.jl**. Instead of writing nested `for` loops to iterate over parameters, numerical methods, and grid resolutions, you define a single blueprint. The backend automatically parses this to generate, hash, and execute the exact Cartesian product of your parameter space.

> **Note:** This guide breaks down the configuration step by step. If you prefer to see the complete, runnable script all at once, you can find it in your repository at `examples/dummy.jl`.

---

## Step 1: Setting the Target Module

Because `PDEStudioCore.jl` is designed to be a heavily serialized, headless backend, it does not require you to pass compiled function closures directly. Instead, you pass the **names** of your functions as Strings or Symbols. 

First, we must tell the backend which module to search when looking up these function names. This is usually `Main` or your custom package module.

```julia
using PDEStudioCore

# Register the namespace so PDEStudioCore can dynamically find our solver later
PDEStudioCore.set_target_module!(@__MODULE__)
```

## Step 2: Defining the Simulation Function

Next, we define the actual numerical solver. You can define this centrally or in another file, as long as it is loaded into the module we just registered. 

The function must accept a single argument (a strictly typed `ParamDict`) and return an `AbstractSimData` object (like `ESimData` or `NoSimData`).

```julia
function my_wave_solver(params::ParamDict)
    # 1. Extract parameters from the dictionary
    N = params[:N]
    scheme = params[:scheme]
    cfl = params[:cfl]
    
    println("Running $scheme with N=$N and CFL=$cfl")
    
    # 2. ... allocate arrays and run your numerical solver here ...
    
    # 3. Return the packaged simulation data
    return NoSimData() # (Use create_sim_data in a real script)
end
```

## Step 3: The Shared Parameters

Now we start building the parameter hierarchy. The first layer is the shared baseline. These are global values—like physical constants or domain sizes—that remain identical across every single simulation run in the batch.

```julia
shared_params = Dict(
    :L => 1.0,  # Domain length
    :T => 5.0   # Total simulation time
)
```

## Step 4: Method Overrides

The second layer defines the numerical methods. This dictionary maps specific method identifiers (like `:upwind` or `:lax_wendroff`) to their localized parameter overrides. When the backend runs a specific method, these parameters will overwrite any matching keys in the shared baseline.

*Tip: You can explicitly exclude shared parameters from a method by passing an `:ignore => [:key1, :key2]` array inside its dictionary.*

```julia
method_overrides = Dict(
    :upwind => Dict(
        :scheme => "Upwind", 
        :cfl => 0.5
    ),
    :lax_wendroff => Dict(
        :scheme => "Lax-Wendroff", 
        :cfl => 0.8
    )
)
```

## Step 5: Assembly and Execution

Finally, we bind all these components together into the `SimulationConfig` and hand it off to the execution engine. We explicitly declare which methods from our `method_overrides` dictionary we want to activate for this specific run.

```julia
# Assemble the blueprint
config = SimulationConfig(
    :my_wave_solver,          # The name of our solver function
    shared_params,            # The baseline parameters
    method_overrides,         # The localized method overrides
    [:upwind, :lax_wendroff]; # The specific methods to activate right now
)

# Execute the Sweep (Runs 6 simulations total: 2 methods × 3 resolutions)
run_all_simulations(config)
```
