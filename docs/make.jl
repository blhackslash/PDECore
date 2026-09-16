# docs/make.jl
using Documenter
using PDECore

makedocs(
    sitename = "PDECore.jl",
    modules = [PDECore],
    remotes = nothing,
    checkdocs = :exports, # Tell Documenter to ignore unlisted private functions
    format = Documenter.HTML(
        # Set this if you link between pages without '.html'
        prettyurls = true,
        # Informs Documenter that the site lives under /PDECore/
        canonical = "https://docs.blackslash.win/PDECore/"
    ),
    pages = [
        "Home" => "index.md",
        "Simulation Config" => "simulation_config.md",
        "Advanced Config" => "advanced_config.md",
        "Statistics" => "statistics.md",
        "API Reference" => "api.md",
    ]
)