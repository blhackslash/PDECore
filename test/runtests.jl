using Test
using PDECore
using StaticArrays

# 1. Define Mock Structures for Hashing Tests
struct MockBoundary end
struct MockDomain
    bounds::Vector{Float64}
    bc::MockBoundary
end

# 2. Define a Fast Mock Simulation & Reference
function mock_wave_sim(params::ParamDict)
    N = params[:N]

    # 1D space (0 to 1), 1D time (3 steps)
    x = collect(range(0.0, 1.0, length=N))
    t = [0.0, 0.1, 0.2]

    # Constant field of 1.0
    u = fill(SVector{1, Float64}(1.0), N, length(t))

    return create_sim_data(x, u, t, params; time_dim=:t)
end

# Reference function exactly matching the simulation output
mock_ref_func(st) = SVector{1, Float64}(1.0)

@testset "PDECore.jl Integration Tests" begin
    tmp_dir = mktempdir()
    set_save_path!(tmp_dir)

    @testset "Serialization & Hashing" begin
        domain = MockDomain([0.0, 1.0], MockBoundary())
        params = create_param_dict(:domain => domain, :N => 50)
        hash_1 = calculate_hash(params)

        domain_identical = MockDomain([0.0, 1.0], MockBoundary())
        params_identical = create_param_dict(:domain => domain_identical, :N => 50)
        hash_2 = calculate_hash(params_identical)

        @test hash_1 == hash_2
    end

    @testset "Simulation Pipeline & I/O" begin
        shared = create_param_dict(:N => 10, :wave_speed => 1.0)
        methods = create_method_dict(:upwind => create_param_dict(:solver => "upwind"))

        config = SimulationConfig(
            :mock_wave_sim, shared, methods, [:upwind];
            varied_params = create_varied_dict(:wave_speed => [1.0, 2.0])
            )

        run_all_simulations(config; force_overwrite=true, calculate_stats=false)

        task_1_params = create_param_dict(:N => 10, :wave_speed => 1.0, :solver => "upwind")
        loaded_data = load_sim_data(task_1_params)

        @test loaded_data isa ESimData

        @testset "Statistical Calculations" begin
            # Run Pass 2 manually on the loaded data
            calculate_all_stats!(loaded_data, mock_ref_func)

            # 1. Check Standard Metric (:mass keeps :time by default)
            @test haskey(loaded_data.stats, :mass)
            @test length(loaded_data.stats[:mass]) == 3 # Should match the 3 time steps

            # 2. Check Error Metric Integration
            @test haskey(loaded_data.stats, :l1error)
            # Since simulation and reference are identical (1.0), the error must be 0.0
            @test all(v -> v[1] ≈ 0.0, loaded_data.stats[:l1error])

            # 3. Check Custom Stat Registration
            PDECore.register_stat!(:mock_custom_stat, :time)
            @test get_kept_dims(:mock_custom_stat, loaded_data.domain) == [:t]
        end
    end
end
