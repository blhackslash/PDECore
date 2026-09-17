using Documenter
using PDECore

makedocs(
    sitename = "PDECore.jl",
    modules = [PDECore],
    checkdocs = :exports,
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", "false") == "true",
        canonical = "https://blhackslash.github.io/PDECore.jl/",
        assets = String[],
    ),
    pages = [
        "Home" => "index.md",
        "Simulation Config" => "simulation_config.md",
        "Advanced Config" => "advanced_config.md",
        "Statistics" => "statistics.md",
        "API Reference" => "api.md",
    ],
)

deploydocs(
    repo = "github.com/blhackslash/PDECore.jl.git",
    devbranch = "main",
    push_preview = true,
)
