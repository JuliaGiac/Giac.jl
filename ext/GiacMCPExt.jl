# Extension module for ModelContextProtocol.jl integration.
# Exposes Giac's CAS engine to MCP-aware LLM clients (Claude Desktop, Claude Code, ...).
# Activated automatically when both `Giac` and `ModelContextProtocol` are loaded.

module GiacMCPExt

using Giac
using Giac: giac_eval, search_commands, GiacContext
using ModelContextProtocol

# ============================================================================
# Tool and server descriptions
# ============================================================================

const _SERVER_DESCRIPTION = """
Computer Algebra System server powered by Giac/Xcas. Provides exact symbolic \
computation through ~2200 commands: algebra, calculus, differential equations, \
Laplace/Z-transforms, linear algebra, number theory, and more.
"""

const _EVAL_DESCRIPTION = """
Evaluate any expression using the Giac/Xcas computer algebra system (~2200 functions).
Syntax follows Xcas conventions.

Domains and example expressions:
- Algebra: factor(x^4-1), expand((x+1)^3), simplify((x^2-1)/(x-1))
- Equations: solve(x^2-3*x+2=0, x), linsolve([x+y=1, x-y=3], [x,y])
- Calculus: diff(sin(x^2), x), integrate(x*exp(x), x), limit(sin(x)/x, x, 0), series(exp(x), x, 0, 5)
- Differential equations: desolve(y'+y=sin(x), y)
- Laplace/Z: laplace(sin(t), t, s), ilaplace(1/(s^2+1), s, t), ztrans(1, n, z), invztrans(z/(z-1), z, n)
- Linear algebra: det([[1,2],[3,4]]), inv([[a,b],[c,d]]), eigenvalues([[1,2],[3,4]]), jordan([[2,1],[0,2]])
- Number theory: ifactor(2310), isprime(17), nextprime(100)
- Polynomials: partfrac(1/(x^3-1), x), gcd(x^4-1, x^2-1), roots(x^3-6*x^2+11*x-6), resultant(x^2-1, x^2-4, x)
- Trigonometry: trigexpand(sin(2*x)), tlin(sin(x)^2)
- Combinatorics: comb(10,3), perm(5,2), factorial(10)
- Statistics: mean([1,2,3,4]), stddev([1,2,3,4])

Multiple statements can be separated by semicolons; the result is the value of the last one.
Variables are symbolic by default.
Each call is independent — variable bindings (a := 5) do NOT persist across calls.
"""

const _SEARCH_DESCRIPTION = """
Search the Giac command catalogue by keyword. Returns matching command names as a \
comma-separated list, or the literal "No commands matched." when nothing matches.

Use this to discover the right Giac function for a given task when you are unsure of \
the exact name.

Examples:
- query="laplace" -> laplace, ilaplace
- query="matrix"  -> det, inv, eigenvalues, ...
"""

# ============================================================================
# Tool factories
# ============================================================================

function _make_eval_tool()
    return MCPTool(
        name = "giac_eval",
        description = _EVAL_DESCRIPTION,
        parameters = [
            ToolParameter(
                name = "expr",
                type = "string",
                description = "Any valid Giac/Xcas expression",
                required = true,
            ),
        ],
        handler = function (params)
            try
                # A fresh context per call, which is what makes the "each call is
        # independent" line above true rather than aspirational: a binding
        # from one call cannot reach the next, and none of them reach the
        # default context the rest of the session uses.
        result = giac_eval(params["expr"], GiacContext())
                return TextContent(text = string(result))
            catch e
                return CallToolResult(
                    isError = true,
                    content = Content[TextContent(text = "Error: " * sprint(showerror, e))],
                )
            end
        end,
    )
end

function _make_search_tool()
    return MCPTool(
        name = "giac_search",
        description = _SEARCH_DESCRIPTION,
        parameters = [
            ToolParameter(
                name = "query",
                type = "string",
                description = "Keyword to search for in Giac command names.",
                required = true,
            ),
        ],
        handler = function (params)
            try
                query = params["query"]
                # Two-tier search: prefix first (canonical Giac.jl semantics),
                # then substring fallback so LLM-style queries like "matrix" or
                # "prime" surface the right commands even when the keyword is
                # not at the start of the name.
                results = search_commands(query)
                if isempty(results)
                    escaped = replace(query, r"([.*+?^${}()|\[\]\\])" => s"\\\1")
                    results = search_commands(Regex(escaped))
                end
                if isempty(results)
                    return TextContent(text = "No commands matched.")
                end
                return TextContent(text = join(string.(results), ", "))
            catch e
                return CallToolResult(
                    isError = true,
                    content = Content[TextContent(text = "Error: " * sprint(showerror, e))],
                )
            end
        end,
    )
end

# ============================================================================
# Public entry point
# ============================================================================

"""
    Giac.giac_mcp_server(; name="giac-cas", kwargs...) -> ModelContextProtocol.Server

Construct an MCP server exposing Giac's CAS engine. Returns a `Server` value that
has not yet been started; call `start!(server)` to enter the STDIO JSON-RPC loop.

`kwargs...` are forwarded to `ModelContextProtocol.mcp_server` — accepted keys
include `version`, `instructions`, `capabilities`, and `auto_register_dir`.

See `docs/src/extensions/mcp.md` and `specs/070-mcp-server-integration/quickstart.md`
for setup with Claude Desktop, Claude Code, and other MCP clients.
"""
function Giac.giac_mcp_server(;
    name::AbstractString = "giac-cas",
    version::AbstractString = string(pkgversion(Giac)),
    kwargs...,
)
    return mcp_server(;
        name = name,
        version = version,
        description = _SERVER_DESCRIPTION,
        tools = [_make_eval_tool(), _make_search_tool()],
        kwargs...,
    )
end

end # module GiacMCPExt
