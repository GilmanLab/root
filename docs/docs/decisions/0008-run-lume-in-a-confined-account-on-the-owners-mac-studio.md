---
status: proposed
date: 2026-09-15
decision-makers:
  - Josh Gilman
---

# ADR-0008: Run Lume in a Confined Account on the Owner's Mac Studio

## Context and Problem Statement

Mac guests require Apple hardware and Apple's Virtualization framework, so they
cannot run on the Incus cluster. The original agentcompute design assumed a
dedicated Mac mini, but the owner already operates an always-on Mac Studio that
can host the required private seed. Where should Lume run, and which boundary
should separate the backend from the owner's workstation account?

## Decision Drivers

- Run macOS guests on owner-controlled Apple Silicon.
- Keep the consented seed host-local and never redistribute it.
- Prevent the backend identity from administering the Mac or traversing the
  owner's home directory.
- Expose the loopback Lume lifecycle API only through an authenticated,
  source-restricted connection from `agentcompute01`.
- Make clone identity, guest-count enforcement, and cleanup explicit in the
  service instead of relying on silent Lume behavior.

## Considered Options

- Lume under a confined account on the owner's always-on Mac Studio
- A dedicated Mac mini running Lume
- Tart or a custom Virtualization.framework backend on the Mac Studio
- Hosted macOS workers

## Decision Outcome

Proposed choice: **Lume under a confined account on the owner's always-on Mac
Studio**. The host is `studio-1`, a Mac Studio with an M2 Max and 64 GB of
memory. This record remains `proposed` until the owner accepts it.

Lume and its VM store run as the hidden, standard `agentcompute` account. The
account is not an administrator, has no sudo access, and cannot traverse the
owner's home directory. Its VM store is `/Users/agentcompute/.lume`. Studio
remains a user-owned tailnet device rather than receiving a backend device tag.

`lume serve` binds only to `127.0.0.1:7777`. Agentcompute reaches that lifecycle
API through the source-restricted Studio SSH account and local TCP forwarding.
Guest exec does not use `lume ssh`: the backend invokes system SSH directly to
the guest's Lume NAT lease with Studio as a `ProxyJump`, a separate per-image
guest key, and pinned host keys for both hops. File transfer uses SFTP over the
same direct guest path.

The stopped, consented seed stays in the confined account's Lume store and is
not published. Lume assigns a new `machineIdentifier` when it clones a VM, but
a fresh clone with that identifier can enter Setup Assistant. Before the
clone's first boot, agentcompute copies the seed's `machineIdentifier` into the
stopped clone while retaining the clone's generated MAC address. Snapshot and
restore clones follow the same pre-boot identity rule.

Apple permits at most two additional running macOS guests on a host.
Agentcompute serializes starts and counts every running macOS VM visible in
the confined account, regardless of name. It refuses a third before the Lume
run mutation; cloning and configuring a stopped VM do not consume a running slot.
This check is required because Lume
0.5.3 accepts the third run request but leaves the VM stopped and reports the
limit only in its service log. A separate account can still consume a host-wide
slot, so a run that remains stopped is diagnosed against new Lume log output.

Lume 0.5.3 starts a wildcard VNC listener even for `--display none`. The owner
rejected a blanket high-port PF rule because it could disrupt LAN Continuity
and `rapportd`. Upstream [cua#3209](https://github.com/trycua/cua/pull/3209)
merged an explicit disabled-VNC policy, but it was not in release 0.5.3 at
rollout. The approved temporary exception is an exact source commit pinned in
`pins/lume.yaml`, with `source_build: true` and the built binary's SHA-256.
It installs only for `agentcompute`; the system-wide Lume remains unchanged.

Every backend run requests disabled VNC and no display. Startup fails closed
if either the account-local CLI or the running daemon lacks that policy.
The backend polls Lume until Running and stops any guest reporting a VNC URL.
No PF rule is installed, so this change does not alter Internet Sharing or the
owner's Continuity services. Once a release includes the feature, replace the
source pin with that release. The 0.5.3 release pin is retained as a rollback
reference, **not** an automatic fallback that may serve backend guests with VNC.

### Consequences

- Good, because the lab can use an already available, always-on Apple Silicon
  host without buying and operating a second Mac now.
- Good, because the backend's normal shell, Lume store, and loopback API are
  confined to a non-administrator account separate from the owner's files.
- Good, because lifecycle calls, guest calls, and file transfer use distinct
  keys and verify both SSH hops.
- Bad, because a personal host is now a backend availability and capacity
  dependency. Owner use, restart, sleep, or maintenance can interrupt Mac
  sandboxes.
- Bad, because the two-running-guest host limit is small and shared with any
  macOS VM running under another account.
- Bad, because the seed contains an operator's one-time Accessibility and Screen
  Recording consent and must remain private, stopped, and recoverable on this
  host.
- Bad, because a temporary source build adds build/signing provenance and an
  account-local deployment step until upstream publishes disabled VNC in a
  release. Both CLI and daemon must be upgraded together.
- Bad, because moving the backend later requires moving the confined account's
  Lume store, reissuing the host key, and re-establishing host policy.

### Confirmation

Compliance is observable when all of the following remain true:

- `agentcompute` is a hidden standard account with no administrator or sudo
  access, the owner home denies traversal, and `lume serve` listens only on
  `127.0.0.1:7777`.
- The durable service configuration enables Lume only after source-pinned SSH,
  separate host and guest keys, known-host pins, and disabled-VNC enforcement
  are verified. No account-owned per-VM VNC listener appears during startup.
- Live qualification separately samples account-owned TCP listeners from the
  create request through Running; only the daemon's loopback listener may exist.
- Generated guest SSH configuration uses Studio as `ProxyJump`; guest exec and
  SFTP do not invoke `lume ssh` and do not use an SSH agent.
- A fresh clone receives the seed's `machineIdentifier` while stopped and
  before first boot, retains a distinct generated MAC address, and reaches the
  desktop rather than Setup Assistant.
- A third running macOS guest is refused before a Lume run mutation. A
  host-wide slot held by another account produces an explicit capacity error
  rather than a false Running state.
- The owner has explicitly changed this record's status to `accepted`; a
  qualification run or durable rollout does not accept the decision by itself.

## Pros and Cons of the Options

### Confined Account on the Owner's Mac Studio

- Good, because it uses known hardware and keeps the backend separate from the
  owner's login account.
- Bad, because the host is shared with owner activity and was not purchased as
  dedicated service infrastructure.

### Dedicated Mac Mini

- Good, because service availability, packet filtering, and capacity would be
  isolated from the owner's workstation.
- Bad, because it adds hardware and migration work before the two-guest backend
  needs more capacity. It remains the migration option if sharing Studio stops
  being acceptable.

### Tart or a Custom Virtualization.framework Backend

- Good, because another backend could offer different lifecycle or networking
  behavior.
- Bad, because agentcompute would need to replace Lume's seed, clone, run,
  snapshot, and VNC lifecycle instead of using the implemented backend.

### Hosted macOS Workers

- Good, because host maintenance and hardware ownership move to a provider.
- Bad, because the private consented seed, low-latency desktop control, and
  sandbox lifecycle would cross a new trust and cost boundary.

## More Information

- [Agentcompute design](../designs/agentcompute.md)
- [Deploy and operate agentcompute](../runbooks/agentcompute.md)
- [ADR-0007: Use Cua Driver over Guest Execution for Desktop Automation](0007-use-cua-driver-over-guest-execution.md)
