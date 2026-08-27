# SPIRE B-shape spike: nested topology on Incus with componere plugins

Executed 2026-08-26/27 on `sandbox01` (Ubuntu 26.04, Incus 7.3, standalone),
stacked on the T32 rig recipe (`.journal/016/SPIKE_T32.md`). Verdict: **the
B (nested) diagram works in reality, end to end, including both componere
v0.1.0 releases in their first real-world integration.** Phase 1 (flat chain)
attested on the first apply; phase 2 (nested) proved all three registered
claims. Total subagent wall time ~48 min across four agents.

## Stack

| Component | Version |
| --- | --- |
| SPIRE server/agent | 1.15.3 |
| incus-spire-attestor (incus-server + incus-agent plugins) | v0.1.0 |
| incus-guest-agent (Talos static pod) | 0.1.0 @ sha256:c938c2c6… |
| kind / CAPI / CAPN / CABPT / CACPPT | (T32 pins) v1.14.0 / v0.9.0 / v0.6.12 / v0.5.13 |
| Talos / Kubernetes | v1.12.2 / v1.34.0 |
| Trust domain (throwaway) | spike.gilman.io |

## What was proven

1. **Guest-agent on CAPN-created Talos VM**: `agent:config` device +
   digest-pinned no-reboot machineconfig patch. Correctly skipped `/dev/sr0`
   (the CAPN cloud-init disk) and staged from `/dev/sr1` — the multi-optical
   media-skip logic works with a coexisting cloud-init disk. `/dev/incus/sock`
   live on the node; `incus info` returns agent data.
2. **Incus node attestation from a k8s pod**: SPIRE agent DaemonSet (alpine,
   HTTP-fetched sha256-verified static binaries, hostPaths `/dev/incus` +
   `/sys/class/dmi/id`, hostNetwork, privileged ns). First apply attested:
   agent ID `spiffe://spike.gilman.io/spire/agent/incus/652e5051-…4beb`,
   selectors project/name/location/uuid/profile all matching the live Incus
   record. **Standalone `location: none` → `sandbox01` server_name
   substitution verified live.** Restricted client cert (restricted: true,
   projects: [default]) completed the whole flow.
3. **Nested bootstrap (claim i)**: hand-rolled downstream `spire-server-0` in
   ns `spire-mgmt`, `UpstreamAuthority "spire"` over the root agent's
   hostPath'd Workload API socket, `-downstream` entry on the root with
   k8s selectors (`k8s:ns:spire-mgmt`, `k8s:sa:spire-server`). Downstream log:
   `X509 CA activated self_signed=false upstream_authority_id=60bdf7d7…`;
   root and downstream bundles equal.
4. **Chain to root (claim ii)**: test pod (local k8s_psat agent path) fetched
   `spiffe://spike.gilman.io/workload/test`; openssl verified leaf →
   DOWNSTREAM-1 intermediate → root bundle. OK.
5. **Root-outage issuance (claim iii)**: root killed 04:33:46Z → FRESH SVID
   serial F38B6EF6… issued 04:33:48Z with root down (openssl verify OK) →
   root restarted 04:33:57Z, healthcheck passed, incus agent re-attested
   (can_reattest=true exercised for real).

## Gotchas (feed into the production design)

- **Incus server-cert SANs**: sandbox01's cert names only 127.0.0.1/::1. Both
  CAPN's lxc-secret (needed insecure-skip-verify) and the attestor server
  plugin (strict verification against `tls_ca_path`) hit this; plugin fixed
  by loopback endpoint since the root server ran on the Incus host itself.
  **Before the real deploy: check what cert the nas01/IncusOS cluster
  listener presents; the plugin needs a verifiable SAN.**
- **helm-charts-hardened 0.30.1 does not fit this nested shape**: it
  hardcodes a CSI-driver volume and its own upstream socket path
  (`/run/spire/upstream_agent/spire-agent.sock`), and the cluster had no
  StorageClass. Hand-rolled manifests were straightforward. For production
  either adopt the chart's whole nested layout (its own upstream agent
  shape, CSI driver, PVCs) or keep hand-rolled manifests in the cluster
  template. **spire-controller-manager / ClusterSPIFFEID was consequently
  NOT exercised** — downstream entries were created manually. B's entry-
  ergonomics claim rests on upstream tooling, not spike-proven.
- **Root agent needs the k8s WorkloadAttestor** (skip_kubelet_verification +
  `nodes/proxy` RBAC + SA token) so the downstream entry can use k8s
  selectors instead of uid matching. Rollout did not disturb the incus node
  attestation.
- Downstream datastore was sqlite on emptyDir (spike-grade); production
  needs a PVC → the mgmt/cattle clusters need a StorageClass decision
  before nested SPIRE lands (interacts with T16 storage design).
- 10s SVID notBefore backdate is normal SPIRE clock-skew tolerance; don't
  misread it in timelines.

## Residue on sandbox01 (reset-button covers all)

- `~/spike-spire/` (binaries, tls incl. restricted-cert keypair, server.conf,
  server-data, manifests, logs, serve/)
- Running host processes: spire-server (root), python3 http.server :8000
- Incus: `capn-client` (unrestricted, d953525a9bcd) and `spike-spire`
  (restricted, b7827d16…) trust entries; `mgmt-control-plane-lq6vw` VM +
  `mgmt-37a8e-lb` container; kind cluster with CAPI/CAPN providers
- Workload cluster: ns `spire` (root agent DS), `spire-mgmt` (downstream
  server + local agent), `workload-test` (test pod)

## Artifacts

- `local://rig.md`, `local://artifacts.md`, `local://phase1.md`,
  `local://phase2.md` (subagent reports, session-local)
- sandbox01: `~/spike-spire/{server.conf,spire-agent-ds.yaml,spire-mgmt.yaml,incus-guest-agent.yaml,cluster.yaml}`
- `.journal/017/NOTES.md` (running log with timelines and steering)
