using Documenter
using DocumenterLandingPage
using Giac
# Note: Giac.Commands is not imported here because it has ~2000 auto-generated
# command functions. Their usage is documented in commands_submodule.md.

DocMeta.setdocmeta!(Giac, :DocTestSetup, :(using Giac); recursive=true)

_pages = [
    "Home" => "index.md",
    "Installation" => "install.md",
    "Quick Start" => "quickstart.md",
    "Variable Declaration" => "variables.md",
    "Constants" => "constants.md",
    "Command discovery and help" => "command_discovery_help.md",
    "Variable Substitution" => "substitute.md",
    "Creating Julia Functions" => "julia_functions.md",
    "Using with Pluto reactive notebooks" => "pluto.md",
    "Using icas (Giac C++ REPL)" => "icas.md",
    "Mathematics" => [
        "Algebra" => "mathematics/algebra.md",
        "Calculus" => "mathematics/calculus.md",
        "Linear Algebra" => "mathematics/linear_algebra.md",
        "Differential Equations" => "mathematics/differential_equations.md",
        "Trigonometry" => "mathematics/trigonometry.md",
    ],
    "Physics" => [
        "Mechanics" => "physics/mechanics.md",
        "Electromagnetism" => "physics/electromagnetism.md",
    ],
    "Signal Processing" => [
        "Discrete-Time Transforms" => "domains/signal/discrete_transforms.md",
        "Continuous-Time Transforms" => "domains/signal/continuous_transforms.md",
    ],
    "API Reference" => [
        "Core API" => "api/core.md",
        "GIAC Commands" => "api/giac_commands.md",
        "Commands submodule" => "api/commands_submodule.md",
    ],
    "Held Commands" => "held_commands.md",
    "Tables.jl Compatibility" => "tables.md",
    "Migration" => [
        "D → Differential" => "migration/d_to_differential.md",
    ],
    "Extensions" => [
         "Symbolics.jl" => "extensions/symbolics.md",
         "SymPy.jl" => "extensions/sympy.md",
         "MathJSON.jl" => "extensions/mathjson.md",
         "MCP Server" => "extensions/mcp.md",
         "TermInterface.jl" => "extensions/terminterface.md",
         "LibPARI.jl" => "extensions/libpari.md",
         "Nemo.jl" => "extensions/nemo.md",
    ],
    "Developer Guide" => [
        "Overview" => "developer/index.md",
        "Package Architecture" => "developer/architecture.md",
        "Performance Tiers" => "developer/tier-system.md",
        "invoke_cmd Fast Path" => "developer/invoke_cmd_fastpath.md",
        "Adding Functions" => "developer/contributing.md",
        "Memory Management" => "developer/memory.md",
        "Troubleshooting" => "developer/troubleshooting.md",
    ],
]

function flatten_pages(pages, prefix="")
    flat = Pair{String, String}[]
    for item in pages
        if item isa Pair
            name, file_or_list = item[1], item[2]
            if file_or_list isa String
                push!(flat, name => file_or_list)
            elseif file_or_list isa AbstractVector
                append!(flat, flatten_pages(file_or_list, name * " > "))
            end
        elseif item isa String
            push!(flat, item => item)
        end
    end
    return flat
end

flat_pages = flatten_pages(_pages)

# Generate llms.txt and llms-full.txt before Documenter builds the site
open(joinpath(@__DIR__, "src", "llms.txt"), "w") do io
    println(io, "# Giac.jl")
    println(io, "> Giac.jl is a Julia interface to the Giac computer algebra system.")
    println(io, "")
    println(io, "## Documentation Sections")
    for (name, path) in flat_pages
        url_path = replace(path, ".md" => ".html")
        println(io, "- [$name]($url_path)")
    end
end

open(joinpath(@__DIR__, "src", "llms-full.txt"), "w") do io
    println(io, "# Giac.jl Full Documentation")
    println(io, "> This file contains the complete documentation for Giac.jl.")
    println(io, "")
    for (name, path) in flat_pages
        src_path = joinpath(@__DIR__, "src", path)
        if isfile(src_path)
            println(io, "## Section: $name")
            println(io, "<!-- Source: $path -->")
            println(io, "")
            println(io, read(src_path, String))
            println(io, "\n---\n")
        end
    end
end

makedocs(
    sitename = "Giac.jl",
    doctest = true,
    repo = Documenter.Remotes.GitHub("JuliaGiac", "Giac.jl"),
    # Note: Giac.Commands is excluded from modules because it has ~2000 auto-generated
    # command functions that aren't individually documented (usage is documented in
    # commands_submodule.md instead)
    modules = [Giac],
    plugins = [LandingPage()],
    format = Documenter.HTML(
        # Landing-page actions use directory-style URLs (for example
        # `/quickstart/`), so keep the same URL layout locally and in CI.
        prettyurls = true,
        canonical = "https://JuliaGiac.github.io/Giac.jl",
        # api/core.md legitimately exceeds the 100 KiB soft threshold: it carries
        # the full core-API docstring set plus worked examples. Ignoring it here
        # is Documenter's own recommended alternative to raising the general limit.
        size_threshold_ignore = ["api/core.md"],
        assets = ["assets/custom-mermaid.js"],
    ),
    pages = _pages,
    checkdocs = :exports,
    # Allow missing_docs warning for auto-generated Commands (1800+ functions)
    warnonly = [:missing_docs],
)

deploydocs(
    repo = "github.com/JuliaGiac/Giac.jl.git",
    devbranch = "main",
)
