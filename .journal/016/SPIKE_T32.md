# T32 spike: CAPI self-managed pivot on Incus (kind + CAPN)

Executed 2026-08-25 on `sandbox01` (Ubuntu 26.04, Incus 7.3, vanilla Zabbly
stable, 12 cores / 28GB / 50GiB loop ZFS pool). Verdict: **the pivot is
smooth — option (b) CAPI self-managed wins per the pre-registered decision
rule** in VISION "VM orchestration (T32)".

## Stack (all latest-at-time, pin these for the real bootstrap)

| Component | Version |
| --- | --- |
| kind | v0.33.0-alpha |
| clusterctl / CAPI | v1.13.3 / v1.14.0 |
| CAPN (infrastructure-incus) | v0.9.0 (v1beta2 contract, Incus 7.x) |
| CABPT / CACPPT (talos bootstrap / control-plane) | v0.6.12 / v0.5.13 |
| Talos | v1.12.2 nocloud (factory.talos.dev, SecureBoot off) |
| Kubernetes | v1.34.0 |

## What was proven

1. **Create**: kind on the host → `clusterctl init -i incus -c talos -b talos`
   → Talos-flavor template, 3 control planes / 0 workers, haproxy `lxc` dev
   LB. All 3 Talos VMs Ready ~3.5 min after apply; taints removed via
   `allowSchedulingOnControlPlanes` strategic patch; 14/14 pods Running.
2. **Forward pivot**: providers + `lxc-secret` installed into the workload
   cluster, `clusterctl move` completed in **2.3 s**, zero errors.
3. **Self-management**: post-pivot, scaled `mgmt-md-0` 0→1 from the cluster
   itself; CAPN (in-cluster) created the worker VM, node joined Ready in
   ~2 min. Scaled back 1→0 cleanly.
4. **Reverse pivot (recovery path)**: `clusterctl move` back to kind worked
   first try (~30 s incl. quiesce). Recovery = laptop kind + `clusterctl
   init` + recreate `lxc-secret` + move. Confirmed, not theoretical.
5. **Teardown**: `kubectl delete cluster` from kind removed all VMs + LB;
   no orphans.

## Gotchas (feed into T08 template + bootstrap design)

- **CABPT rejects JSON6902 `configPatches` for multi-doc Talos configs** —
  error surfaces as `DataSecretGenerationFailed` on Machine conditions and
  machines sit in Pending with no VMs. Use `strategicPatches` (plain YAML
  merge). This was the only failure of the whole spike.
- CAPN is not in clusterctl's default registry: needs
  `~/.cluster-api/clusterctl.yaml` from
  `https://capn.linuxcontainers.org/static/v0.1/clusterctl.yaml`.
- Quick-start Incus prep: `core.https_address` + `incus cluster enable` +
  trusted client cert; the cert/key land verbatim in the `lxc-secret`
  Kubernetes secret (custody consideration for the real cluster: this is a
  full-trust Incus client credential living in etcd).
- Talos nocloud image import is manual (factory raw.xz → qcow2 + metadata
  tar → `incus image import`). Fine one-off; the self-hosted image factory
  (T31) + a small script subsume it later.
- Talos default PodSecurity (warn=restricted) spams warnings installing the
  providers; pods admit fine (enforce=baseline). Cosmetic.
- The book's "UEFI boot seems to not work correctly" caveat did **not**
  manifest: v1.12.2 nocloud image with `security.secureboot=false` booted
  fine on Incus 7.3 defaults.
- The `lxc` haproxy LB container is a control-plane SPOF (dev-only by
  design). Production template must use **kube-vip** (CAPN-supported, L2
  VIP, no BGP — fits gw01's no-BGP ruling) or OVN. → T08/T10.
- `cluster.x-k8s.io/v1beta1` deprecation warnings on the template's
  Cluster/MachineDeployment: CAPN v0.9 templates still emit v1beta1 tops;
  watch for template updates before the real bootstrap.

## Residue on sandbox01 (reset-button covers all of it)

- `/usr/local/bin/{kind,clusterctl,kubectl,talosctl}`, `qemu-utils` pkg
- Incus: now a single-member cluster (`sandbox01`), `core.https_address
  10.10.40.10:8443`, trusted client cert `client.crt` (840e88091799),
  `talos-v1.12.2` image cached
- `~/t32/` working dir (image files, cluster.yaml, stale kubeconfigs)
- Pre-existing `spike` VM untouched

## Artifacts

- `T32_CLUSTER_MANIFEST.yaml` (this folder): the exact 7-doc manifest that
  worked (Talos flavor + strategicPatches). Starting point for the real
  mgmt-cluster template.
