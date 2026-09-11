# agentcompute: Go software architecture

Session 019, 2026-09-11. Synthesized from a software-architect proposal
(`agent://GoArchitect`) and a complexity review (`agent://GoComplexity`);
this document is the middle ground and the one to build from. It covers
only the Go program that serves the vocabulary in
`docs/docs/designs/drafts/agentcompute.md` through CodeMode. No OVN
deployment, image recipes, networking prerequisites, or deployment form.

## Summary

Generate the repository from `template-mcp-codemode` and keep everything
it already decides: Cobra/Viper CLI, stdio and HTTP transports (HTTP is
the deployment; stdio is development-only and exits with its client), one
immutable CodeMode build, `codemode.ServeWorkerAndExit()` as the first
statement of `main` and every `TestMain`, stderr-only `slog`. The three
MCP tools stay the whole MCP surface; the vocabulary is CodeMode
capabilities behind them.

Shape: **handlers → `compute` service → concrete `incus` adapter**. There
is no cross-hypervisor interface in slices 1 and 2 because only Incus
exists; handlers see `compute` types only, never Incus API types, so when
Lume arrives the consumer-sized interfaces are extracted from real call
sites rather than guessed. State lives in Incus (project and instance
metadata), not in memory. One re-scanning TTL reaper, one small keyed
mutation gate, fixed I/O bounds, and a transient disk screenshot store.
Nothing configurable that has not yet needed tuning.

## Decisions carried out of the review

| Item | Decision |
| --- | --- |
| Cross-backend `compute.Backend` (24 methods) | Not yet. Concrete `*incus.Client` behind a `compute.Service`. Extract interfaces at Lume time. |
| Stringly `ChangeState`/`ChangeSnapshot` | Cut; explicit methods per verb, added with their slice. |
| `Sandbox.Generation`, deleting marker | Cut. Explicit delete sets `expires_at = now` first; the reaper's re-scan is the retry mechanism. |
| `Sandbox.Owner` | Keep as a write-only metadata key (`user.agentcompute.subject`). Zero behavior today; costs one string. |
| Backend-operation semaphore | Cut; CodeMode's `MaxConcurrentExecutions` already bounds live work. |
| Per-sandbox gate on every operation | Narrowed to control-plane mutations (create/delete/extend/attach). Exec, reads, waits, and desktop calls run under their deadline-bounded contexts only. |
| Combined 64 KiB exec cap | Two independent capped, draining writers with per-stream `truncated` flags. |
| Five-kind error taxonomy | Two sentinels that change control flow: `compute.ErrNotFound`, `compute.ErrUnavailable`. Everything else is a wrapped error for logs. |
| Durable screenshot index + 256-bit tokens | In-memory index, 128-bit random filenames, scratch dir wiped at startup. |
| Configurable intervals/caps/limits | Constants in code until the lab proves a need. |
| Least-loaded placement | Slice 1 uses the single configured member. `host?` accepted and honored; no scheduler. |
| Lume adapter, sidecar, `net.*` rejection paths | Deferred to the macOS slice; their shape follows a Lume spike. |
| `mockery` mock of the big seam | Cut with the seam. Mocks target the small interfaces `mcpserver` handlers consume (see Testing). |

## Package layout

```text
cmd/agentcompute/main.go        ServeWorkerAndExit first; then cli.Execute.
internal/cli/                   Template as-is, plus:
  runtime.go                    Build deps once (incus client, catalog, store, reaper); own shutdown order.
  stdio.go, http.go             Mount the screenshot handler; stdio starts its own listener for it.
internal/mcpserver/
  server.go                     Options.Deps, registrations, Build. Template file, extended.
  sandbox.go image.go           One file per root: flat input/output DTOs + handlers.
  instance.go net.go desktop.go
  convert.go                    compute → DTO conversion (RFC3339, {items}, empty collections).
internal/compute/
  types.go                      Sandbox, Instance, NIC, Network, ExecRequest/ExecResult, CatalogImage.
  service.go                    Orchestration: name rules, expiry checks, gate, defaults, catalog lookup.
  catalog.go                    Immutable image catalog loaded from config.
  reaper.go                     Startup + periodic scan; deletes expired sandboxes.
  gate.go                       Keyed, context-aware mutex by sandbox name.
  errors.go                     ErrNotFound, ErrUnavailable.
internal/incus/
  client.go                     Wraps lxc/incus/client; request-scoped project clients.
  sandbox.go                    Project create/list/get/delete; metadata keys.
  instance.go                   Create/start/stop/delete/wait, exec streaming, file pull/push.
  network.go                    Bridge (slice 1) then OVN networks, NIC attach/detach, ACLs, forwards, peers (later slices).
internal/desktop/               Slice 2.
  driver.go                     Build argv, run via compute exec, parse Driver JSON, fetch screenshot file.
  store.go                      Transient disk store + http.Handler.
```

Later capabilities are more files and methods in these packages. They do
not introduce mechanisms.

## Core types

`compute` types are plain Go: they may hold `time.Time` and maps. DTOs in
`mcpserver` are separate structs following CodeMode's rules (flat scalar
inputs with pointers for optionals, struct roots, `json` tags).

```go
package compute

type Ref struct{ Sandbox, Name string }

type Sandbox struct {
    Name      string
    Platform  string // "incus" | "mac"
    Subject   string
    CreatedAt time.Time
    ExpiresAt time.Time
}

type Instance struct {
    Ref            Ref
    Image, Kind    string // kind: "container" | "vm"
    Host, Status   string
    CPUs, MemoryMB int64
    DiskGB         int64
    Desktop        bool
    NICs           []NIC
}

type NIC struct {
    Name, Network, MAC string
    Addresses          []string
}

type Network struct {
    Name, Kind, CIDR, Gateway, Host string // kind: "bridge" | "ovn"
    DHCP, NAT, DNS                  bool
}

type CatalogImage struct {
    Name, OS, Version, Platform string
    Kind                        string // default kind
    Kinds                       []string
    Desktop                     bool
    Reference                   string // Incus "remote:alias" or Lume OCI ref
    CPUs, MemoryMB, DiskGB      int64  // defaults
}

type CreateInstance struct {
    Ref            Ref
    Image          CatalogImage
    Kind, Network  string // network "" = sandbox default, "none" = no NIC
    Host           string
    CPUs, MemoryMB int64
    DiskGB         int64
    Start          bool
}

type ExecRequest struct {
    Ref       Ref
    Argv      []string // fixed per guest OS: {"sh","-c",cmd}; later cmd.exe / zsh
    User, Cwd string
    Env       map[string]string
    Stdin     string
    Timeout   time.Duration
}

type ExecResult struct {
    ExitCode                   int64
    Stdout, Stderr             string
    StdoutTruncated            bool
    StderrTruncated            bool
    TimedOut                   bool
}

var (
    ErrNotFound    = errors.New("not found")
    ErrUnavailable = errors.New("backend unavailable")
)
```

The service is the only thing handlers call:

```go
type Service struct {
    incus   *incus.Client
    catalog *Catalog
    gate    *gate
    log     *slog.Logger
}

func (s *Service) CreateSandbox(ctx context.Context, name string, ttl time.Duration, subject string) (Sandbox, error)
func (s *Service) ListSandboxes(ctx context.Context) ([]Sandbox, error)
func (s *Service) GetSandbox(ctx context.Context, name string) (Sandbox, []Instance, []Network, error)
func (s *Service) ExtendSandbox(ctx context.Context, name string, ttl time.Duration) (Sandbox, error)
func (s *Service) DeleteSandbox(ctx context.Context, name string) error

func (s *Service) CreateInstance(ctx context.Context, req CreateInstance) (Instance, error)
func (s *Service) ListInstances(ctx context.Context, sandbox string) ([]Instance, error)
func (s *Service) GetInstance(ctx context.Context, ref Ref) (Instance, error)
func (s *Service) DeleteInstance(ctx context.Context, ref Ref) error
func (s *Service) Exec(ctx context.Context, req ExecRequest) (ExecResult, error)

func (s *Service) CreateNetwork(ctx context.Context, sandbox string, n Network) (Network, error)
func (s *Service) AttachNIC(ctx context.Context, ref Ref, network, nic, ip, mac string) (NIC, error)
```

That is the slice-1 surface. `Start/Stop/Restart`, `Wait`, `ReadFile`,
`WriteFile`, snapshots, `Publish`, `DetachNIC`, `Peer`, `ACL*`, `Forward`,
and `Impair` are added to the same struct in later slices. `Exec` is the
seam desktop rides on in slice 2; `ReadFile` joins it then.

### Capability registration

Exactly the template pattern (`internal/mcpserver/randomint.go`,
`docs/docs/how-to/add-a-capability.md`): one `codemode.Register` per
capability, typed input/output structs, `ID == Name`, handler closes over
`Dependencies{Compute *compute.Service, Desktop *desktop.Service}`.

```go
type instanceCreateIn struct {
    Sandbox  string  `json:"sandbox"`
    Name     string  `json:"name"`
    Image    string  `json:"image"`
    Kind     *string `json:"kind,omitempty"`
    CPUs     *int64  `json:"cpus,omitempty"`
    MemoryMB *int64  `json:"memory_mb,omitempty"`
    DiskGB   *int64  `json:"disk_gb,omitempty"`
    Network  *string `json:"network,omitempty"`
    Host     *string `json:"host,omitempty"`
    Start    *bool   `json:"start,omitempty"`
}
```

Boundary translations forced by flat inputs: `env` is `KEY=VALUE` lines
split at the first `=`; `desktop.call.args` must parse as exactly one JSON
object; `desktop.call.result` is a JSON string (Starlark `json.decode`).
Root lists are `{items: [...]}`; timestamps are RFC3339 strings; empty
collections are initialized so they never become `None`.

### Error contract

CodeMode hides ordinary handler errors: they reach the agent as the bare
text `capability failed`, and since Starlark has no try/except the
program aborts. That was unusable for named-resource capabilities, so
[meigma/codemode#58](https://github.com/meigma/codemode/issues/58) was
filed and shipped in [PR #59](https://github.com/meigma/codemode/pull/59),
released as [codemode v0.2.1](https://github.com/meigma/codemode/releases/tag/v0.2.1)
(2026-09-11). Pin `github.com/meigma/codemode v0.2.1` or later.

`codemode.AgentError{Message}` is the opt-in. Return it directly or
wrapped (`fmt.Errorf("lookup: %w", err)`); CodeMode finds it with
`errors.As`, attaches only `Message` (non-printables → spaces, invalid
UTF-8 repaired, ≤256 bytes with `...`), and the MCP error becomes
`capability failed: instance "web" not found in sandbox "demo"`. The
program still aborts; `errors.Is(err, ErrCapabilityFailure)` still holds.
Everything not wrapped in `AgentError` stays hidden.

Rule for this codebase: the `compute` service returns `*codemode.AgentError`
for every failure the agent can act on — unknown sandbox/instance/network/
image, expired sandbox, unsupported kind or platform, instance not
running, exec timed out before readiness, name rule violations that
survive binding. Backend and transport failures (Incus unreachable,
operation error, decode failure) are ordinary wrapped errors: logged with
detail via `slog`, surfaced as bare `capability failed`. `compute.ErrNotFound`
and `compute.ErrUnavailable` remain the internal control-flow sentinels;
the handler layer maps `ErrNotFound` to an `AgentError` naming the
resource. Messages name the resource and the sandbox, never hosts,
paths, or credentials.

Mapping otherwise: binding failures → `ErrInvalidArguments` (already
carries the argument name); request deadline → `ErrResourceLimit`;
cancellation → `context.Canceled`.

## Request flow

### `instance.create` (slice 1)

1. CodeMode binds and authorizes; handler validates names and ranges,
   resolves defaults from the catalog entry, builds `CreateInstance`.
2. `Service.CreateInstance` acquires the sandbox gate, re-reads the
   project, rejects an expired sandbox, releases the gate after the Incus
   create request is accepted (the instance name now exists; concurrent
   deletes will see it).
3. `incus.Client.CreateInstance` uses a project-scoped client with
   `--target` = the sandbox's member, image source from
   `CatalogImage.Reference`, config `limits.cpu`/`limits.memory`, root
   disk size on the project's default pool, one `nic` device on the
   default network unless `network == "none"`, and metadata
   `user.agentcompute.image`, `user.agentcompute.desktop`. Waits for the
   operation, then starts and waits for `Running` (bounded by the
   request context and a 5-minute create timeout).
4. Returns the observed `Instance`. A failed or canceled wait does not
   delete the instance; `instance.get`/`delete` and the reaper recover it.

### `desktop.call` (slice 2)

1. Handler parses `args` as one JSON object, checks the instance has
   `user.agentcompute.desktop=true`.
2. `desktop.Service.Call` chooses a guest temp path, builds argv
   `cua-driver call <tool> <json> --screenshot-out-file <path>` (the
   documented CLI spelling; the draft's shorthand is wrong and should be
   corrected), runs it through `compute.Service.Exec` with a bounded
   JSON buffer that fails rather than truncates.
3. Parses the Driver's structured content, strips embedded image blocks,
   pulls the screenshot with `compute.Service.ReadFile`, publishes it to
   the store, removes the guest file best-effort.
4. Returns `{ok, summary, result, screenshot_url?}`. `desktop.screenshot`
   is the same path with `get_desktop_state` /
   `get_window_state(include_accessibility_tree=false)`.

## State and concurrency

**Registry is Incus.** A sandbox is a project `ac-<name>` with
`features.images=true`, `features.profiles=true`,
`features.networks=false` in slice 1 (Incus: "This feature requires the
server to be configured for OVN"; flips to `true` with the OVN slice),
restricted settings (`restricted=true`,
`restricted.containers.nesting=block`, `restricted.devices.*` per the
draft's security section, `restricted.networks.access` listing the
sandbox's own bridges), and metadata:

| Key | Value |
| --- | --- |
| `user.agentcompute.version` | `1` — presence marks ownership; the reaper never touches a project without it |
| `user.agentcompute.created_at` | RFC3339 |
| `user.agentcompute.expires_at` | RFC3339 |
| `user.agentcompute.subject` | authz subject ID |
| `user.agentcompute.host` | member name (slice 1: the configured member) |

Names: `[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?`, lowercase only, no
normalization; `default` and `none` reserved. Omitted `sandbox.create.name`
generates `<adjective>-<noun>` from a small word list, retrying on
collision. Instance and network names follow the same rule; Incus sees
them unprefixed inside the project.

**Default network, slice 1.** Bridge networks cannot live inside a
project without OVN, so the per-sandbox default bridge is created in the
Incus `default` project as `ac-<sandbox>-default` (`ipv4.address=auto`,
`ipv4.nat=true`, `ipv4.dhcp=true`, on the sandbox's member) and carries
`user.agentcompute.sandbox=<name>` so the reaper can find it. Instances in
the sandbox project reference it by that name; the agent sees it as
`default` (the `ac-<sandbox>-` prefix is stripped at the DTO boundary).
Created at `sandbox.create`, deleted last at `sandbox.delete`. Additional
`kind="bridge"` networks follow the same placement and prefix. When the
OVN slice lands, sandbox projects switch to `features.networks=true`,
OVN networks live inside the project under their plain names, and the
switch is a config flag (`default_network_kind`), never an implicit
rewrite of an explicit request. Existing bridge sandboxes are drained,
not converted.

**Gate.** `gate.Lock(ctx, sandbox)` is a keyed mutex honoring context
cancellation. Held for sandbox create/delete/extend, instance create/
delete, network create, NIC attach. Not held for exec, reads, waits, or
desktop calls. Handlers re-read `expires_at` after acquiring it.

**Reaper.** Runs at startup and every 30 s under the runtime's lifecycle
context, in whichever process is running; the deployed HTTP service is
what makes it continuous. Lists projects, filters on the ownership key,
and for each expired project acquires the gate, re-reads expiry, then
deletes in dependency order: forwards, NICs, instances, sandbox images
and snapshots, OVN networks, the sandbox's bridges in the `default`
project, then the project. Failure leaves the expired project in place;
the next scan retries. `sandbox.delete` is the same routine after setting
`expires_at = now`. `sandbox.extend` writes `now + ttl`.

**Exec.** Two capped writers (64 KiB each) that keep draining after the
cap, so the Incus websocket completes; per-stream truncation flags. Exec
timeout is the earliest of the request deadline and `Timeout`; an
exec-only timeout returns `TimedOut=true` with captured output. The Incus
client is scoped per request (`UseProject`, `UseTarget`); a shared client
is never mutated.

**CodeMode limits.** `MaxExecutionTime = 15m`, `MaxNativeCalls = 1000`,
default value/aggregate byte limits. No goroutine-per-wait; all waits are
synchronous under the request context.

**Screenshot store (slice 2).** Scratch directory wiped at startup;
in-memory map `id → {path, sandbox, expires}`; ids are 128-bit
`crypto/rand` hex used as the filename; atomic rename on publish; 5-minute
retention capped by sandbox expiry; purge by sandbox on delete; 16 MiB per
image, 128 MiB total live bytes (reject on overflow after expiring stale
entries); `image.DecodeConfig` for dimensions with a pixel cap. Handler
serves GET/HEAD only, fixed `image/png`, `nosniff`, `no-store`. Configured
public base URL; never derived from `Host`. Mounted beside MCP in HTTP
mode; a separate listener in stdio mode. No base64 fallback.

## Configuration

One strict TOML/YAML file (`--config`, `AGENTCOMPUTE_CONFIG`), loaded after
flag parsing, unknown keys rejected. Flags/env keep only what the template
already has (transport address, log level) plus the config path.

```yaml
incus:
  remote: nas01            # existing incus remote name, or:
  url: https://10.10.10.14:8443
  client_cert: /path/cert.pem
  client_key: /path/key.pem
  host: lab01              # slice-1 member for all sandboxes
  pool: data
sandbox:
  default_ttl_minutes: 240
  max_ttl_minutes: 1440
  default_network_kind: bridge   # ovn later
screenshots:
  dir: /var/lib/agentcompute/shots
  base_url: http://agentcompute.lab:8081
images:
  - name: ubuntu/24.04
    os: ubuntu
    version: "24.04"
    kinds: [container, vm]
    kind: container
    reference: images:ubuntu/24.04
    cpus: 2
    memory_mb: 2048
    disk_gb: 10
```

Everything else (reaper interval, exec caps, screenshot bounds, create
timeout) is a constant.

## Testing

- `mcpserver`: one table-driven contract test that runs `search_api` /
  `describe_api` over the registered catalog and asserts names,
  signatures, and output shapes for the current slice — this is what
  keeps agents' saved programs working. One in-memory MCP
  search → describe → execute round trip using the template's transport
  from `server_test.go`. Handlers are tested against small interfaces
  declared in `mcpserver` (`sandboxService`, `instanceService`, …)
  covering exactly the methods the handlers call; mockery generates
  those. `TestMain` calls `ServeWorkerAndExit` first.
- `compute`: Testify tests for the behaviors that can plausibly break:
  name validation, expiry re-read after gate acquisition, extend
  semantics, reaper retry after a partial delete, capped-writer draining,
  timeout vs cancellation in exec. The Incus client is behind a small
  interface here too (the methods `Service` uses), mocked with mockery.
- `desktop` (slice 2): `httptest` + scratch dir for the store; parser
  tests on captured Driver output from the pinned version.
- Opt-in integration lane (`-tags integration`, `AGENTCOMPUTE_TEST_REMOTE`)
  against the real cluster: create sandbox → instance → exec → restart
  server → discover → TTL delete with no residue. This is the only proof
  of exec streaming, project scoping, and cleanup; keep it.

## Risks

- **CodeMode version.** `AgentError` requires codemode ≥ v0.2.1. The
  template pins by tag; bump it when generating the repository.
- **Driver CLI contract.** Output schema, `--screenshot-out-file`
  behavior, and element-token continuity across one-shot CLI invocations
  must be verified against the pinned Driver in slice 2. If tokens do
  not survive across invocations, `desktop.call` needs a long-lived
  `cua-driver serve` session per instance, which changes the exec model.
- **Screenshot URL reachability.** Agents must be able to fetch the store
  URL; MCP authentication does not cover it. Verify with the first real
  agent host.
- **Cancellation is not rollback.** Incus operations may commit after the
  request is canceled. Named resources plus the reaper make this
  recoverable, not exactly-once.
- **Long blocking programs** hold worker slots. 8 concurrent executions
  is the ceiling for concurrent agents; raise `MaxConcurrentExecutions`
  if it binds.

## Draft corrections to carry back

1. `desktop.call` invocation is `cua-driver call <tool> <json>
   --screenshot-out-file <path>`, not `cua-driver <tool> '<json>'`.
2. The "short, actionable Starlark error" promise now stands on
   `codemode.AgentError` (#59); record the CodeMode version as a
   prerequisite.
3. Record the name rules and the slice-1 default-bridge shape.

## Deliberately excluded

OVN deployment and chassis/uplink setup, image recipes, VLAN and fleet
work, deployment form and CI, authorization policy beyond `AllowAll`,
async operation IDs, a Lume adapter and its sidecar (macOS slice),
SPICE/VNC clients, and a typed re-modeling of the Driver tool catalog.
