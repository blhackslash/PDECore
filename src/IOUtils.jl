const _ENABLE_CONV_CACHE = Ref{Bool}(false)

"""
    enable_cache!(val::Bool)

Toggles whether on-the-fly Eulerian and Lagrangian conversions are cached to disk.

# Arguments
- `val::Bool`: Set to `true` to enable caching, or `false` to disable it.
"""
enable_cache!(val::Bool) = (_ENABLE_CONV_CACHE[] = val)

"""
    SimFileNotFoundError <: Exception

A custom exception thrown when a specific simulation data file matching the requested 
cryptographic parameter hash cannot be found in the current save directory.

# Fields
- `message::String`: A descriptive error message detailing why the lookup failed.
"""
struct SimFileNotFoundError <: Exception
    message::String
end

# Normalize scalar Ints or Tuples into a standard spatial Tuple
function _normalize_spatial_res(N_grid::Union{Int, Tuple}, DS::Int)
    if N_grid isa Int
        return ntuple(_ -> N_grid, Val(DS))
    elseif N_grid isa Tuple
        length(N_grid) == DS || error("Spatial grid tuple length $(length(N_grid)) does not match DS = $DS")
        return N_grid
    else
        error("Unsupported grid resolution type: $(typeof(N_grid))")
    end
end

# Generate standard string key from a spacetime resolution tuple
function get_conv_key(res::Tuple)
    return "conv_E_" * join(res, "x")
end

# ==============================================================================
# --- UNIFIED SERIALIZATION & PARSING ---
# ==============================================================================

"""
    val2str(v; top_level::Bool=true)

Recursively converts Julia objects into valid, evaluatable Julia code strings.

Uses `top_level` to keep CSV formatting clean for standalone strings, while 
applying strict `repr()` quoting to elements inside containers to maintain type stability 
during deserialization.

# Arguments
- `v`: The Julia object (number, string, array, dictionary, or custom struct) to serialize.

# Keyword Arguments
- `top_level::Bool`: If `true`, outermost strings are not wrapped in explicit quotes. Default is `true`.

# Returns
- `String`: A strictly formatted string representation of the object.
"""
function val2str(v; top_level::Bool=true)
    if v == ""
        return "<empty>"
    elseif isa(v, Function)
        return "Closure"
    elseif isa(v, Val)
        return string(v)
    elseif isa(v, Symbol) 
        return repr(v)
    elseif isa(v, AbstractString)
        return top_level ? String(v) : repr(v)
    elseif isa(v, Number) || isa(v, Type)
        return string(v)
    elseif isa(v, AbstractArray)
        T = eltype(v)
        prefix = T === Any ? "Any" : string(T)
        elements = join([val2str(x; top_level=false) for x in v], ", ")
        return "$(prefix)[$elements]"
    elseif isa(v, Tuple)
        elements = join([val2str(x; top_level=false) for x in v], ", ")
        return length(v) == 1 ? "($elements,)" : "($elements)"
    elseif isa(v, Dict)
        K, V = keytype(v), valtype(v)
        sorted_keys = sort(collect(keys(v)), by=string)
        elements = join(["$(val2str(k; top_level=false)) => $(val2str(v[k]; top_level=false))" for k in sorted_keys], ", ")
        return "Dict{$K, $V}($elements)"
    else
        T = typeof(v)
        type_name = string(T.name.name) 
        fields = propertynames(v)
        if isempty(fields)
            return type_name
        else
            field_strs = ["$f=$(val2str(getproperty(v, f); top_level=false))" for f in fields]
            return "$type_name(" * join(field_strs, ", ") * ")"
        end
    end
end

"""
    str2val(val_str::AbstractString)

Attempts to evaluate a string back into its native Julia type.

This function acts as the inverse of `val2str`. It safely parses standard Julia 
collections and primitives. If it encounters a custom struct or raw UI input that 
cannot be natively parsed, it falls back to returning a cleaned string.

# Arguments
- `val_str::AbstractString`: The stringified representation of a Julia object.

# Returns
- `Any`: The evaluated Julia object, or a cleaned string upon failure.
"""
function str2val(val_str::AbstractString)
    val_str = strip(val_str)
    if val_str == "<empty>" || isempty(val_str)
        return ""
    end
    
    try
        return eval(Meta.parse(val_str))
    catch e
        # Fallback for custom structs or raw unquoted UI strings
        return replace(val_str, r"^\"|\"$" => "")
    end
end

"""
    set_save_path!(path::String)

Sets the root directory for saving simulation plots, HDF5/JLD2 data, and statistics.
Automatically creates `figures` and `data` subdirectories within the specified path 
if they do not currently exist. 

*Note: On Windows, ensure you pass a raw string (e.g., `raw"C:\\Path"`) to correctly process backslashes.*

# Arguments
- `path::String`: The absolute or relative path to the desired root save directory.

# Returns
- `Bool`: `true` if the path was successfully set and subdirectories were created, `false` otherwise.

# Examples
```julia-repl
julia> set_save_path!(joinpath(@__DIR__, "results"))
[ Info: Module save root path set to: /home/user/project/results
true
```
"""
function set_save_path!(path::String)
    abs_path = abspath(path) # Ensure absolute path
    path_ok = false

    if !isdir(abs_path)
        @warn "Save path does not exist: $abs_path. Attempting to create..."
        try
            mkpath(abs_path)
            @info "Created save directory: $abs_path"
            path_ok = true
        catch e
            @error "Failed to create save directory: $abs_path. Error: $e"
            return false 
        end
    else
        path_ok = true
    end

    if path_ok
        _SAVE_ROOT_PATH[] = abs_path
        @info "Module save root path set to: $(_SAVE_ROOT_PATH[])"

        # Create standard subdirectories
        for subdir in ["figures", "data"]
            subdir_path = joinpath(_SAVE_ROOT_PATH[], subdir)
            if !isdir(subdir_path)
                try
                    mkpath(subdir_path)
                    @info "Created subdirectory: $subdir_path"
                catch e
                    @error "Failed to create subdirectory: $subdir_path. Error: $e"
                end
            end
        end
        return true 
    else
        return false 
    end
end

"""
    get_save_path()

Retrieves the currently configured root directory for saving files.

# Returns
- `String`: The absolute path to the active save directory.
"""
function get_save_path()::String
    return _SAVE_ROOT_PATH[]
end

"""
    calculate_hash(params::ParamDict)

Computes a deterministic, cryptographic SHA-256 hash of the simulation parameters.
This ensures that any structural changes to the parameters result in a strictly unique identifier.

# Arguments
- `params::ParamDict`: The dictionary of simulation parameters.

# Returns
- `String`: A hexadecimal string representing the SHA-256 hash.
"""
function calculate_hash(params::ParamDict)
    sorted_keys = sort(collect(keys(params)), by=string)
    stringToHash = join(["$k => $(val2str(params[k]))" for k in sorted_keys], ", ")
    return bytes2hex(sha256(stringToHash))
end

# ==============================================================================
# --- IOUtils.jl Updates ---
# ==============================================================================

"""
    get_file_name(params::ParamDict)

Searches the configured save directory for the most recent `.jld2` file matching 
the cryptographic hash of the provided parameters.

# Arguments
- `params::ParamDict`: The parameter dictionary defining the target simulation file.

# Returns
- `String`: The absolute path to the matched `.jld2` file.

# Throws
- `SimFileNotFoundError`: If the save directory is missing or no file matches the hash.
"""
function get_file_name(params::ParamDict)
    hash_val = calculate_hash(params)
    save_data = joinpath(get_save_path(), "data")
    
    if !isdir(save_data)
        throw(SimFileNotFoundError("Data directory does not exist."))
    end

    all_files = readdir(save_data)
    candidate_files = filter(f -> (endswith(f, "_$(hash_val).jld2") || startswith(f, "$(hash_val)_")) && endswith(f, ".jld2"), all_files)

    if isempty(candidate_files)
        throw(SimFileNotFoundError("File with matching parameters not found."))
    end

    # Return the most recent file matching the exact cryptographic hash
    sort!(candidate_files, by = f -> mtime(joinpath(save_data, f)), rev=true)
    
    return joinpath(save_data, candidate_files[1])
end

"""
    save_sim_data(sim_data::AbstractSimData; overwrite::Bool = false)

Serializes the simulation data to disk in JLD2 format. 

Automatically condenses and cleans the parameter dictionary to strip out heavy closures 
or raw strings, saving them as fast metadata. If a file with the identical parameter hash 
already exists, it will only overwrite it if explicitly instructed.

# Arguments
- `sim_data::AbstractSimData`: The Eulerian or Lagrangian simulation data object to save.

# Keyword Arguments
- `overwrite::Bool`: If `true`, deletes the existing raw data and outdated conversion caches before saving. Default is `false`.
"""
function save_sim_data(sim_data::AbstractSimData; overwrite::Bool = false)
    condensed_params = Dict{Symbol, Any}()
    for (k, v) in sim_data.params
        condensed_params[k] = str2val(val2str(v))
    end
    
    empty!(sim_data.params)
    merge!(sim_data.params, condensed_params)

    file_name = ""
    try
        file_name = get_file_name(sim_data.params)
    catch e
        if !isa(e, SimFileNotFoundError); rethrow(e); end
    end

    if isempty(file_name)
        hash_val = calculate_hash(sim_data.params)
        timestamp = Dates.format(now(), "yyyy-mm-dd_HH-MM-SS_sss")
        save_data = joinpath(get_save_path(), "data")
        if !isdir(save_data); mkpath(save_data); end
        
        file_name = joinpath(save_data, "$(timestamp)_$(hash_val).jld2")
        
        jldopen(file_name, "w") do file
            file["raw"] = sim_data
            
            # --- WRITE FAST METADATA ---
            file["native"] = sim_data isa ESimData ? :eulerian : :lagrangian
            file["params"] = sim_data.params
            file["stat_keys"] = collect(keys(sim_data.stats))
        end
        @info "Saved 'raw' to $(basename(file_name))"
    else
        jldopen(file_name, "a+") do file
            if haskey(file, "raw")
                if overwrite
                    delete!(file, "raw")
                    file["raw"] = sim_data
                    
                    # --- OVERWRITE FAST METADATA ---
                    if haskey(file, "params"); delete!(file, "params"); end
                    file["params"] = sim_data.params
                    
                    if haskey(file, "stat_keys"); delete!(file, "stat_keys"); end
                    file["stat_keys"] = collect(keys(sim_data.stats))
                    
                    if haskey(file, "native"); delete!(file, "native"); end
                    file["native"] = sim_data isa ESimData ? :eulerian : :lagrangian
                    
                    # Clear all stale conversion caches
                    for k in keys(file)
                        if startswith(k, "conv_")
                            delete!(file, k)
                            @debug "Cleared outdated conversion cache: '$k'"
                        end
                    end
                    
                    @info "Overwrote existing 'raw' in $(basename(file_name)) and cleared all caches."
                else
                    @debug "'raw' already exists. Skipping save."
                end
            else
                file["raw"] = sim_data
                file["native"] = sim_data isa ESimData ? :eulerian : :lagrangian
                file["params"] = sim_data.params
                file["stat_keys"] = collect(keys(sim_data.stats))
                @info "Saved 'raw' to $(basename(file_name))"
            end
        end
    end
end

# Default fallback routes to :raw
"""
    load_sim_data(params::ParamDict)
    load_sim_data(params::ParamDict, ::Val{:raw})

Loads the primary, native simulation data from disk that perfectly matches the provided parameter dictionary.

# Arguments
- `params::ParamDict`: The parameter dictionary to match against the disk hash.

# Returns
- `AbstractSimData`: The loaded simulation object (`ESimData` or `LSimData`).
"""
load_sim_data(params::ParamDict) = load_sim_data(params, Val(:raw))
function load_sim_data(params::ParamDict, ::Val{:raw})
    file_name = get_file_name(params)
    return jldopen(file_name, "r") do file
        haskey(file, "raw") ? file["raw"] : throw(SimFileNotFoundError("Key 'raw' not found."))
    end
end

# --- Fast Metadata Reader ---
function _get_native_type(file_name::String)
    return jldopen(file_name, "r") do file
        return file["native"]
    end
end

# ==============================================================================
# --- LOAD ROUTERS ---
# ==============================================================================

"""
    list_available_conversions(params::ParamDict)

Scans the target JLD2 simulation file and returns a list of all conversion keys 
currently cached on disk.

# Arguments
- `params::ParamDict`: The parameter dictionary defining the target simulation file.

# Returns
- `Vector{String}`: A list of keys starting with "conv_" (e.g., `["conv_E_100x100"]`).
"""
function list_available_conversions(params::ParamDict)
    file_name = get_file_name(params)
    return jldopen(file_name, "r") do file
        return filter(k -> startswith(k, "conv_"), keys(file))
    end
end

"""
    load_sim_data(params::ParamDict, ::Val{:eulerian}, res::Tuple)

Retrieves an Eulerian grid representation of the simulation data at the requested resolution. 
If the native data on disk is Lagrangian, or Eulerian at a different resolution, it will 
automatically compute the conversion on the fly. If `_ENABLE_CONV_CACHE` is toggled on, 
it saves this new conversion to the JLD2 file for future fast-loading.

# Arguments
- `params::ParamDict`: The parameters of the simulation.
- `::Val{:eulerian}`: A strict type token requesting Eulerian data.
- `res::Tuple`: The target spatial grid resolution (e.g., `(100, 100)`).

# Returns
- `ESimData`: The successfully loaded or converted Eulerian dataset.
"""
function load_sim_data(params::ParamDict, ::Val{:eulerian}, res::Tuple)
    file_name = get_file_name(params)
    
    # 1. Check if the raw data is of required resolution
    is_perfect_match = jldopen(file_name, "r") do file
        raw = file["raw"]
        return raw isa ESimData && size(raw.u) == res
    end
    
    if is_perfect_match
        return load_sim_data(params, Val(:raw))
    end
    
    # 2. Check for an existing cached conversion matching this exact resolution
    key = get_conv_key(res)
    has_conv = jldopen(file_name, "r") do file; haskey(file, key); end
    
    if has_conv
        return jldopen(file_name, "r") do file; file[key]; end
    end
    
    # 3. Generate it on the fly
    @info "Target Eulerian resolution $key not found. Generating on the fly..."
    raw_data = load_sim_data(params, Val(:raw))
    
    conv_data = if raw_data isa LSimData
        convert_to_eulerian(raw_data, res)
    else
        resample_eulerian(raw_data, res)
    end
    
    # 4. Cache resolution if enabled
    if _ENABLE_CONV_CACHE[]
        jldopen(file_name, "a+") do file
            if !haskey(file, key)
                file[key] = conv_data
            end
        end
    end
    
    return conv_data
end

"""
    load_sim_data(params::ParamDict, ::Val{:lagrangian})

Retrieves a Lagrangian particle representation of the simulation data. 
Automatically generates and optionally caches the conversion if the native data on disk is Eulerian.

# Arguments
- `params::ParamDict`: The parameters of the simulation.
- `::Val{:lagrangian}`: A strict type token requesting Lagrangian data.

# Returns
- `LSimData`: The successfully loaded or converted Lagrangian dataset.
"""
function load_sim_data(params::ParamDict, ::Val{:lagrangian})
    file_name = get_file_name(params)
    native = _get_native_type(file_name)
    
    if native == :lagrangian
        return load_sim_data(params, Val(:raw))
    else
        # Directly load the L-conversion or generate it
        has_conv = jldopen(file_name, "r") do file; haskey(file, "conv_L"); end
        
        if has_conv
            return jldopen(file_name, "r") do file; file["conv_L"]; end
        else
            @info "Lagrangian conversion not found. Generating on the fly..."
            raw_data = load_sim_data(params, Val(:raw))
            conv_data = convert_to_lagrangian(raw_data)
            
            # Cache conversion if enabled
            if _ENABLE_CONV_CACHE[]
                jldopen(file_name, "a+") do file
                    if !haskey(file, "conv_L")
                        file["conv_L"] = conv_data
                    end
                end
            end
            
            return conv_data
        end
    end
end

"""
    load_sim_data(hash_prefix::String; index::Int=1)

Manually loads simulation data by directly matching a cryptographic hash prefix rather than a parameter dictionary.
Useful for manual inspection or debugging specific files in the REPL.

# Arguments
- `hash_prefix::String`: A partial or full SHA-256 hash string (e.g., `"a1b2c3d4"`).

# Keyword Arguments
- `index::Int`: If multiple files match the hash prefix, specifies which one to load (sorted by newest first). Default is `1`.
"""
function load_sim_data(hash_prefix::String; index::Int=1)
    clean_prefix = replace(hash_prefix, ".jld2" => "")
    save_data = joinpath(get_save_path(), "data")
    
    if !isdir(save_data)
        throw(SimFileNotFoundError("Data directory does not exist."))
    end

    all_files = readdir(save_data)
    candidates = filter(f -> occursin(clean_prefix, f) && endswith(f, ".jld2"), all_files)
    
    if isempty(candidates)
         throw(SimFileNotFoundError("No files found matching the hash prefix: $clean_prefix"))
    end

    sort!(candidates, by = f -> mtime(joinpath(save_data, f)), rev=true)
    
    if index > length(candidates) || index < 1
        error("Requested index $index, but only $(length(candidates)) files match the hash '$clean_prefix'.")
    end

    file_name = joinpath(save_data, candidates[index])
    @info "Manual Load: Found $(length(candidates)) matching files. Loading index $index: $(candidates[index])"
    
    # Pure passthrough load to the primary raw data
    return JLD2.load(file_name)
end

# ==============================================================================
# --- EXISTENCE CHECKERS ---
# ==============================================================================

"""
    does_sim_data_exist(params::ParamDict)
    does_sim_data_exist(params::ParamDict, ::Val{:raw})
    does_sim_data_exist(params::ParamDict, ::Val{:eulerian}, res::Tuple)
    does_sim_data_exist(params::ParamDict, ::Val{:lagrangian})

Checks if a simulation matching the given parameters exists on disk without loading the heavy datasets into memory.
When passing the `:eulerian` or `:lagrangian` type tokens, it specifically checks if that pre-computed conversion 
is cached in the file.

# Arguments
- `params::ParamDict`: The parameters of the simulation.

# Returns
- `Bool`: `true` if the requested raw data or specific conversion cache exists; `false` otherwise.
"""
does_sim_data_exist(params::ParamDict) = does_sim_data_exist(params, Val(:raw))

function does_sim_data_exist(params::ParamDict, ::Val{:raw})
    try
        return jldopen(get_file_name(params), "r") do file; haskey(file, "raw"); end
    catch e
        return isa(e, SimFileNotFoundError) ? false : rethrow(e)
    end
end

function does_sim_data_exist(params::ParamDict, ::Val{:eulerian}, res::Tuple)
    try
        file_name = get_file_name(params)
        native = _get_native_type(file_name)
        
        if native == :eulerian
            # If native is Eulerian, check if the raw data perfectly matches the requested resolution
            is_perfect_match = jldopen(file_name, "r") do file
                raw = file["raw"]
                return size(raw.u) == res
            end
            
            if is_perfect_match
                return true
            end
        end
        
        # If not a perfect raw match check for the explicit cached key
        target_key = get_conv_key(res)
        return jldopen(file_name, "r") do file; haskey(file, target_key); end
        
    catch e
        return isa(e, SimFileNotFoundError) ? false : rethrow(e)
    end
end

function does_sim_data_exist(params::ParamDict, ::Val{:lagrangian})
    try
        file_name = get_file_name(params)
        native = _get_native_type(file_name)
        
        if native == :lagrangian
            # If native is Lagrangian, we just need the raw data
            return jldopen(file_name, "r") do file; haskey(file, "raw"); end
        else
            # If native is Eulerian, check for the specific L-conversion key
            return jldopen(file_name, "r") do file; haskey(file, "conv_L"); end
        end
        
    catch e
        return isa(e, SimFileNotFoundError) ? false : rethrow(e)
    end
end

# ==============================================================================
# --- DATA HEALTH CHECKING ---
# ==============================================================================

function _aggregate_component(iterator)
    min_v, max_v = Inf, -Inf
    sum_v = 0.0
    valid_count, nan_count = 0, 0
    
    for val in iterator
        if isnan(val)
            nan_count += 1
        else
            min_v = min(min_v, val)
            max_v = max(max_v, val)
            sum_v += val
            valid_count += 1
        end
    end
    
    mean_v = valid_count > 0 ? sum_v / valid_count : NaN
    min_v = valid_count > 0 ? min_v : NaN
    max_v = valid_count > 0 ? max_v : NaN
    
    return min_v, max_v, mean_v, Float64(nan_count)
end

"""
    check_data(data::ESimData)

Generates a fast, allocation-free `DataFrame` summarizing the numerical health 
of the Eulerian dataset. Aggregates the entire spacetime grid into a single row, 
reporting the Min, Max, Mean, and NaN count for every field component.

# Arguments
- `data::ESimData`: The Eulerian simulation object to analyze.

# Returns
- `DataFrame`: A single-row tabular summary for all components.
"""
function check_data(data::ESimData)
    M = length(data.u) > 0 ? length(first(data.u)) : 1
    
    df_dict = Dict{Symbol, Vector{Float64}}()
    df_dict[:Time] = [NaN] # Indicates time was aggregated across the full tensor
    
    for c in 1:M
        iterator = (v[c] for v in data.u)
        min_v, max_v, mean_v, nan_count = _aggregate_component(iterator)
        
        df_dict[Symbol("C$(c)_Min")]  = [min_v]
        df_dict[Symbol("C$(c)_Max")]  = [max_v]
        df_dict[Symbol("C$(c)_Mean")] = [mean_v]
        df_dict[Symbol("C$(c)_NaNs")] = [nan_count]
    end
    
    df = DataFrame(df_dict)
    select!(df, :Time, Not(:Time))
    
    return df
end

"""
    check_data(data::LSimData)

Generates a fast, allocation-free `DataFrame` summarizing the numerical health 
of the Lagrangian dataset step-by-step. Calculates the Min, Max, Mean, and NaN 
count for every field component at every recorded timestep.

# Arguments
- `data::LSimData`: The Lagrangian simulation object to analyze.

# Returns
- `DataFrame`: A tabular summary with the first column as `:Time`, generating one row per timestep.
"""
function check_data(data::LSimData)
    T_len = length(data.t)
    M = length(data.u) > 0 && length(data.u[1]) > 0 ? length(data.u[1][1]) : 1
    
    df_dict = Dict{Symbol, Vector{Float64}}()
    df_dict[:Time] = data.t
    
    for c in 1:M
        df_dict[Symbol("C$(c)_Min")]  = zeros(T_len)
        df_dict[Symbol("C$(c)_Max")]  = zeros(T_len)
        df_dict[Symbol("C$(c)_Mean")] = zeros(T_len)
        df_dict[Symbol("C$(c)_NaNs")] = zeros(T_len)
    end
    
    for m in 1:T_len
        for c in 1:M
            iterator = (p[c] for p in data.u[m])
            min_v, max_v, mean_v, nan_count = _aggregate_component(iterator)
            
            df_dict[Symbol("C$(c)_Min")][m]  = min_v
            df_dict[Symbol("C$(c)_Max")][m]  = max_v
            df_dict[Symbol("C$(c)_Mean")][m] = mean_v
            df_dict[Symbol("C$(c)_NaNs")][m] = nan_count
        end
    end
    
    df = DataFrame(df_dict)
    select!(df, :Time, Not(:Time))
    
    return df
end

"""
    delete_sim_data(keys::Vector{Symbol}, vals::Vector)

Scans the active save directory and permanently deletes any `.jld2` simulation file 
whose internal parameter dictionary contains exact matches for all provided key-value pairs.

# Arguments
- `keys::Vector{Symbol}`: A list of parameter keys to match.
- `vals::Vector`: A list of corresponding values that must perfectly match the keys.

# Examples
```julia-repl
julia> delete_sim_data([:N, :solver], [100, "upwind"])
[ Warning: Deleting file matching criteria: 2026-09-15_14-30-00_a1b2c3d4.jld2
```
"""
function delete_sim_data(keys::Vector{Symbol}, vals::Vector)
    save_data = get_save_path() * "/data/"
    if !isdir(save_data); return; end
    
    files = readdir(save_data)
    for file in files
        if !endswith(file, ".jld2"); continue; end
        
        full_path = joinpath(save_data, file)
        try
            sim_data = load(full_path, "raw")
            deletion = true
            for (i,key) in enumerate(keys)
                if !haskey(sim_data.params, key) || !(sim_data.params[key] == vals[i])
                    deletion = false
                    break
                end
            end
            
            if deletion
                @warn "Deleting file matching criteria: $file"
                rm(full_path)
            end
        catch e
            @warn "Could not load file $file for deletion check" exception=e
        end
    end
end

"""
    rehash_sim_data(target_path::String; kwargs...)

Recursively scans a directory (or processes a single file) for `.jld2` simulation files,
cleans the parameter dictionaries using the normalization pipeline, recalculates the cryptographic 
hash, and saves the file under its new signature.

# Arguments
- `target_path::String`: The path to a single `.jld2` file or a directory to recursively scan.

# Keyword Arguments
- `delete_old::Bool`: Removes the old file after a successful rehash. Default is `true`.
- `filter_pairs::Union{Dict{Symbol, Any}, Nothing}`: Only processes files containing these exact parameter matches (e.g., `Dict(:N => 100)`).
- `remove_keys::Vector{Symbol}`: Deletes these obsolete keys from the parameter dictionary before rehashing.
- `prompt_keys::Vector{Symbol}`: Pauses on each matched file, prints current parameters, and prompts the user in the REPL to input overriding values for these specific keys.
"""
function rehash_sim_data(
    target_path::String; 
    delete_old::Bool=true,
    filter_pairs::Union{Dict{Symbol, <:Any}, Nothing}=nothing,
    remove_keys::Vector{Symbol}=Symbol[],
    prompt_keys::Vector{Symbol}=Symbol[]
)
    if isfile(target_path) && endswith(target_path, ".jld2")
        _rehash_single_file(target_path, delete_old, filter_pairs, remove_keys, prompt_keys)
    elseif isdir(target_path)
        for (root, dirs, files) in walkdir(target_path)
            for file in files
                if endswith(file, ".jld2")
                    _rehash_single_file(joinpath(root, file), delete_old, filter_pairs, remove_keys, prompt_keys)
                end
            end
        end
    else
        @warn "Path is neither a .jld2 file nor a directory: $target_path"
    end
end

function _rehash_single_file(file_path::String, delete_old::Bool, filter_pairs, remove_keys, prompt_keys)
    local raw_data
    try
        jldopen(file_path, "r") do file
            if !haskey(file, "raw")
                return nothing
            end
            raw_data = file["raw"]
        end
    catch e
        @warn "Failed to open $(basename(file_path))" exception=e
        return
    end

    isnothing(raw_data) && return

    # --- FILTERING ---
    if !isnothing(filter_pairs)
        skip = false
        for (k, v) in filter_pairs
            if !haskey(raw_data.params, k) || raw_data.params[k] != v
                skip = true
                break
            end
        end
        skip && return
    end
    
    @info "Processing matched file: $(basename(file_path))"

    # --- REMOVAL ---
    for k in remove_keys
        if haskey(raw_data.params, k)
            delete!(raw_data.params, k)
            @info "  Removed obsolete key: $k"
        end
    end

    # --- INTERACTIVE PROMPTING ---
    if !isempty(prompt_keys)
        println("\n--- Current Parameters for $(basename(file_path)) ---")
        for (k, v) in raw_data.params
            println("  $k => $(val2str(v))")
        end
        println("---------------------------------------------------")
        
        for pk in prompt_keys
            print("Enter value for '$pk' (valid Julia expression, leave blank to skip): ")
            val_str = strip(readline())
            if !isempty(val_str)
                try
                    val = eval(Meta.parse(val_str))
                    raw_data.params[pk] = val
                    @info "  Injected: $pk = $val"
                catch e
                    @warn "  Failed to parse '$val_str'. Skipping '$pk'."
                end
            else
                @info "  Skipped '$pk'."
            end
        end
    end

    # --- NORMALIZATION & HASHING ---
    condensed_params = Dict{Symbol, Any}()
    for (k, v) in raw_data.params
        condensed_params[k] = str2val(val2str(v))
    end
    
    empty!(raw_data.params)
    merge!(raw_data.params, condensed_params)

    new_hash = calculate_hash(raw_data.params)
    
    bname = basename(file_path)
    m = match(r"^(.+)_([a-f0-9a-fA-F]+)\.jld2$", bname)
    timestamp = !isnothing(m) ? m.captures[1] : Dates.format(Dates.now(), "yyyy-mm-dd_HH-MM-SS_sss")
    
    new_file_name = "$(timestamp)_$(new_hash).jld2"
    new_file_path = joinpath(dirname(file_path), new_file_name)
    
    # --- SAFE FILE SWAP ---
    temp_file = new_file_path * ".tmp"
    try
        jldopen(temp_file, "w") do file
            file["raw"] = raw_data
            file["native"] = raw_data isa ESimData ? :eulerian : :lagrangian
            file["params"] = raw_data.params
            file["stat_keys"] = collect(keys(raw_data.stats))
        end
        
        is_same_file = abspath(file_path) == abspath(new_file_path)
        
        if delete_old && !is_same_file
            rm(file_path, force=true)
            @info "Rehashed and renamed: $bname -> $new_file_name\n"
        elseif is_same_file
            @info "Rehashed in-place (hash unchanged): $bname\n"
        else
            @info "Rehashed and copied (old file kept): $bname -> $new_file_name\n"
        end
        
        mv(temp_file, new_file_path, force=true)
        
    catch e
        @error "Failed to write $new_file_name" exception=e
        rm(temp_file, force=true)
    end
end

"""
    get_clean_params(params::Dict)
    get_clean_params(sim_data::AbstractSimData)

Generates a deep copy of the parameter dictionary where all values have been safely scrubbed 
and normalized. This function is invaluable for debugging serialization signatures, as it mirrors 
the exact dictionary state used to generate the cryptographic hash.

# Arguments
- `params::Dict`: A raw parameter dictionary.
- `sim_data::AbstractSimData`: A simulation object whose `.params` field will be extracted.

# Returns
- `Dict{Symbol, Any}`: The normalized parameter dictionary.
"""
function get_clean_params(params::Dict)
    clean_dict = Dict{Symbol, Any}()
    for (k, v) in params
        clean_dict[k] = str2val(val2str(v))
    end
    return clean_dict
end

get_clean_params(sim_data) = get_clean_params(sim_data.params)

"""
    print_clean_params(data)

Neatly prints the scrubbed parameter dictionary to the REPL in alphabetical order. 

# Arguments
- `data`: Accepts either a `ParamDict` directly or an `AbstractSimData` object.

# Returns
- `Dict{Symbol, Any}`: The newly cleaned dictionary that was just printed.
"""
function print_clean_params(data)
    clean_dict = get_clean_params(data)
    println("\n--- Cleaned Parameters ---")
    for (k, v) in sort(collect(clean_dict), by=x->string(x[1]))
        println("  $k => $v")
    end
    println("--------------------------\n")
    return clean_dict
end