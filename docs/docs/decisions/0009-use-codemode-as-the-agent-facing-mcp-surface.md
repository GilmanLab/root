---
status: proposed
date: 2026-09-15
decision-makers:
  - Josh Gilman
---

# ADR-0009: Use CodeMode as the Agent-Facing MCP Surface

## Context and Problem Statement

Agentcompute has many lifecycle, network, file, and desktop operations. Exposing
each operation as a separate MCP tool would enlarge the public tool list and
force intermediate results through the model between dependent calls. How
should agents discover and compose the service's capabilities while keeping the
outer MCP contract small and stable?

## Decision Drivers

- Keep the public MCP tool list small as compute capabilities are added.
- Let an agent discover exact capability names and shapes at runtime.
- Compose dependent operations without returning every intermediate value to
  the model.
- Validate typed inputs and expose an authorization point for every native call.
- Bound program execution time, native calls, and values.

## Considered Options

- CodeMode with three MCP tools and bounded Starlark programs
- One direct MCP tool for every agentcompute operation
- One custom dispatcher tool accepting arrays of JSON operations
- Expose the underlying Incus, Lume, and Driver APIs directly

## Decision Outcome

Proposed choice: **CodeMode with three MCP tools and bounded Starlark
programs**. Agentcompute's outer MCP surface is exactly `search_api`,
`describe_api`, and `execute`. This record remains `proposed` until the owner
accepts it.

`search_api` discovers registered capabilities by name and search metadata.
`describe_api` returns the generated input and output shape for one capability.
`execute` evaluates a bounded Starlark program and returns the converted value
of its zero-argument `main()` function. Capabilities use stable dotted names
under `sandbox`, `image`, `instance`, `net`, and `desktop`.

Each capability is registered as a typed Go handler. Inputs are flat structs
whose direct exported fields are scalar `string`, `int64`, `bool`, or `float64`
values, with pointers for optional scalars. Input lists and nested objects are
not part of this contract. An agent repeats a capability call inside its
program for multi-value operations. Where the underlying native API itself
requires a free-form object, such as a Cua Driver call, agentcompute accepts an
explicit JSON object string and the handler validates it. Outputs may contain
bounded nested structs and lists.

CodeMode creates a fresh Starlark worker for each `execute` request and permits
native calls only from `main()`. The worker is a language and execution
boundary, not an operating-system isolation boundary: capability handlers run
in the privileged parent service, and the worker runs as the same operating
system user as the service. Authentication and authorization therefore remain
host responsibilities outside program-controlled arguments.

### Consequences

- Good, because adding a capability does not add another outer MCP tool or
  require clients to load a growing tool schema list.
- Good, because one program can create resources, wait, inspect results, and
  clean up while returning only its final bounded value.
- Good, because generated descriptions and argument binding come from the same
  Go types used by handlers.
- Good, because CodeMode passes canonical typed arguments to the authorizer for
  every native call. The deployed policy is `authz.AllowAll`: bearer
  authentication is the current gate, and subject identity is attribution.
- Bad, because clients must discover CodeMode and write Starlark instead of
  calling an operation-specific MCP tool directly.
- Bad, because flat scalar inputs require repeated calls or an explicitly
  validated string encoding when an operation naturally takes a collection or
  nested object.
- Bad, because changing a capability's typed shape can invalidate saved
  programs even though the outer three-tool list is unchanged.
- Bad, because CodeMode does not isolate handler side effects, filesystem,
  credentials, CPU, or memory at the operating-system level.

### Confirmation

Compliance is observable when all of the following remain true:

- MCP tool discovery returns exactly `search_api`, `describe_api`, and
  `execute`.
- `search_api` finds an agentcompute capability, `describe_api` reports its
  flat typed input, and `execute` can call it from `main()` and return its
  result.
- A wrongly typed argument is rejected before handler dispatch.
- New operations are registered through `codemode.Register`; they do not call
  `mcp.AddTool` or add another public dispatcher.
- Runtime limits remain configured for execution and native calls, and the
  deployment continues to establish trusted subject identity outside program
  source and capability arguments.
- The owner has explicitly changed this record's status to `accepted`; passing
  discovery or execution checks does not accept the decision.

## Pros and Cons of the Options

### CodeMode

- Good, because it supplies discovery, generated descriptions, typed binding,
  per-call authorization, bounded composition, and a fixed MCP surface.
- Bad, because it introduces a worker protocol and Starlark execution model that
  operators and contributors must understand.

### Direct MCP Tool per Operation

- Good, because ordinary MCP clients can call each operation without writing a
  program.
- Bad, because the tool list and schema payload grow with every capability, and
  dependent calls repeatedly move intermediate data through the model.

### Custom JSON Operation Dispatcher

- Good, because it could keep one public tool and batch several operations.
- Bad, because agentcompute would have to invent discovery, type checking,
  references between results, control flow, limits, authorization points, and
  error projection already supplied by CodeMode.

### Direct Infrastructure APIs

- Good, because it avoids an application-level capability layer.
- Bad, because it exposes provider-specific credentials and mutable
  infrastructure primitives instead of the sandbox ownership, TTL, cleanup,
  and policy boundaries agentcompute enforces.

## More Information

- [Agentcompute design](../designs/agentcompute.md)
- [Deploy and operate agentcompute](../runbooks/agentcompute.md)
- [CodeMode documentation](https://meigma.github.io/codemode/)
