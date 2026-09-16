---
status: proposed
date: 2026-09-15
decision-makers:
  - Josh Gilman
---

# ADR-0007: Use Cua Driver over Guest Execution for Desktop Automation

## Context and Problem Statement

Agentcompute must expose the same desktop automation vocabulary for Linux,
Windows, and macOS guests without making a guest desktop service reachable from
every sandbox network. The chosen mechanism must support semantic accessibility
actions and screenshots, preserve isolated guest topologies, and keep binary
images out of CodeMode values. How should agentcompute reach and operate a
guest desktop?

## Decision Drivers

- Use one native desktop capability set across Linux, Windows, and macOS.
- Keep desktop control available when an Incus guest has no operator-reachable
  network path.
- Avoid adding a Driver listener to sandbox network policy.
- Return structured Driver results while moving screenshots through a bounded
  binary path.
- Retain a human-accessible fallback for setup, login, and recovery screens.

## Considered Options

- Cua Driver in the graphical session, reached through guest execution
- A network-exposed Cua MCP endpoint in every desktop guest
- Hypervisor console automation through SPICE or VNC
- Separate platform-specific automation implementations

## Decision Outcome

Proposed choice: **Cua Driver in the graphical session, reached through guest
execution**. This record remains `proposed` until the owner accepts it.

Curated desktop images install the pinned Cua Driver and start its daemon in the
logged-in graphical session. Agentcompute exposes `desktop.info`,
`desktop.call`, and `desktop.screenshot` capabilities. `desktop.call` forwards a
native Driver tool name and JSON object without defining a second typed API for
each upstream tool.

Linux and macOS use bounded one-shot Driver CLI calls. Linux calls travel
through Incus exec to the user-session socket. macOS calls travel through the
Lume backend's direct guest SSH path as user `lume`. There is no persistent Mac
Driver bridge. Windows is the exception: agentcompute keeps a Cua MCP session
over one guest exec stream through the in-guest session proxy, because the
Incus agent service identity cannot access the interactive user's named pipe
directly. A lost Windows response closes that session for the next call but
never replays an action whose effect is unknown.

The Driver writes screenshots to a temporary guest file. Agentcompute pulls the
file through the backend's binary file path—Incus file access or SFTP for
macOS—validates and optionally resizes the PNG, and publishes a short-lived URL.
Screenshot bytes do not cross the CodeMode value boundary. In-guest VNC or
Lume's VM console remains a fallback for a human; it is not the agent automation
API.

### Consequences

- Good, because semantic actions, accessibility trees, application discovery,
  and screenshots use the Driver's native cross-platform vocabulary.
- Good, because Incus desktop control does not depend on a guest network route
  or an exposed Driver port. An isolated `nat=false`, `network=none` guest
  remains controllable through the Incus agent.
- Good, because screenshot data uses a bounded binary transfer instead of
  base64 or another large value inside a Starlark result.
- Bad, because each desktop image must maintain a logged-in graphical session,
  a compatible Driver daemon, and platform-specific startup behavior.
- Bad, because Linux and macOS pay one-shot CLI startup cost for each operation,
  while Windows adds persistent-session lifecycle and reconnect handling.
- Bad, because macOS Accessibility and Screen Recording consent must be granted
  to the signed Driver app on the private seed; the service cannot grant it
  unattended.
- Bad, because pre-login screens and a broken graphical session still require a
  separately protected VNC or console path.

### Confirmation

Compliance is observable when all of the following remain true:

- `search_api` finds the stable `desktop.*` capabilities, `describe_api`
  reports their typed shapes, and `desktop.info` discovers the installed Driver
  version and native tool names.
- A native read such as `list_apps` returns structured Driver content, and a
  screenshot capability returns a fetchable PNG URL rather than image bytes.
- Linux and macOS Driver operations execute one-shot guest commands. Windows
  reuses a Driver MCP session carried by a guest exec stream and does not replay
  a call after a lost response.
- No desktop image exposes a Driver control listener as part of its sandbox
  network contract.
- The owner has explicitly changed this record's status to `accepted`; technical
  evidence alone does not accept the decision.

## Pros and Cons of the Options

### Cua Driver over Guest Execution

- Good, because it combines a cross-platform semantic API with the existing
  authenticated backend control paths.
- Bad, because guest images and graphical-session startup become part of the
  automation contract.

### Network-Exposed Cua MCP Endpoint

- Good, because every platform could use a long-lived MCP connection.
- Bad, because each guest would need a listener, authentication, address
  discovery, and policy exceptions that conflict with arbitrary or isolated
  network topologies.

### Hypervisor Console Automation

- Good, because a console can cover boot and login screens before the guest
  desktop service starts.
- Bad, because console pixels do not provide the Driver's native application,
  window, and accessibility semantics. Incus exposes graphical VM consoles
  through SPICE, for which this service has no supported client path.

### Platform-Specific Automation

- Good, because each platform could use its native automation framework
  directly.
- Bad, because agentcompute would own three incompatible vocabularies, image
  contracts, permission models, and result formats.

## More Information

- [Agentcompute design draft](../designs/drafts/agentcompute.md)
- [Deploy and operate agentcompute](../runbooks/agentcompute-service.md)
- [ADR-0009: Use CodeMode as the Agent-Facing MCP Surface](0009-use-codemode-as-the-agent-facing-mcp-surface.md)
