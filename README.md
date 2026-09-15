# Giac.jl

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/JuliaGiac/Giac.jl)
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.18685533.svg)](https://doi.org/10.5281/zenodo.18685533)
[![Documentation](https://img.shields.io/badge/docs-stable-blue.svg)](https://JuliaGiac.github.io/Giac.jl/stable)
[![Documentation](https://img.shields.io/badge/docs-dev-blue.svg)](https://JuliaGiac.github.io/Giac.jl/dev)
[![CI](https://github.com/JuliaGiac/Giac.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/JuliaGiac/Giac.jl/actions/workflows/CI.yml)
[![codecov](https://codecov.io/github/JuliaGiac/Giac.jl/graph/badge.svg)](https://codecov.io/github/JuliaGiac/Giac.jl)

A Julia wrapper for the [Giac](https://www-fourier.univ-grenoble-alpes.fr/~parisse/giac.html) computer algebra system.

For LLM integration via the Model Context Protocol, see
[`docs/src/extensions/mcp.md`](https://juliagiac.github.io/Giac.jl/dev/extensions/mcp/).

For a KaimonSlate integration, see [GiacSlate.jl](https://github.com/JuliaGiac/GiacSlate.jl).

## Security

`giac_eval` hands a string to Giac's evaluation engine, and Giac is a
programming language with file access, not an expression calculator. Its
`secure_run` mode blocks the file-*writing* side by default, but the `read*`
family is not guarded and reaches any file the process can read.

**Never pass untrusted input to `giac_eval` without OS-level sandboxing.** See
[SECURITY.md](SECURITY.md).

## Contributors

See [CONTRIBUTORS.md](CONTRIBUTORS.md) for the people who built, reviewed,
and inspired this package.
