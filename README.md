# PDEStudioCore.jl

[![Stable Docs](https://img.shields.io/badge/docs-stable-blue.svg)](https://blhackslash.github.io/PDEStudioCore.jl/)
[![Build Status](https://github.com/blhackslash/PDEStudioCore.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/blhackslash/PDEStudioCore.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/blhackslash/PDEStudioCore.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/blhackslash/PDEStudioCore.jl)

**PDEStudioCore.jl** is a robust, headless-safe Julia backend engineered for the execution, management, and statistical analysis of Partial Differential Equation (PDE) simulations. 

Designed with reproducible academic research in mind, it provides a unified framework for generating strictly typed, precision-agnostic Eulerian and Lagrangian datasets. It features deterministic cryptographic hashing for simulation parameters, automated disk caching, and a highly optimized multithreaded statistical integration pipeline. 

## Installation

From the Julia REPL, type `]` to enter the Pkg prompt and run:

```julia
pkg> add PDEStudioCore
```

## Documentation

For a detailed overview of Core Data Structures, the `SimulationConfig`, custom statistical integration, and the full API reference, please visit the [Stable Documentation](https://blhackslash.github.io/PDEStudioCore.jl/).

## Examples

To help you get started, we provide a complete, runnable example in this repository:

*   **`examples/dummy.jl`**: A minimal, self-contained quick-start script. It demonstrates how to set up a shared parameter pool, define numerical methods, sweep over time-step sizes, and run a mock 1D wave simulation.