---
id: 017
title: Session opened, goal pending
started: 2026-08-26
---

## 2026-08-26 20:11 — Kickoff
Goal for the session: not yet stated; the user asked only to start a new session.
Current state of the world: four-node Incus cluster live (nas01 + lab01–03); storage converged via fleet pyinfra; T48 (VLAN 30 lab datapath) still blocked waiting on the IncusOS stable release carrying lxc/incus-os#1306 (nodes run 202608201218, manual reboot needed once published). Open threads from 013: sw-core01 `just plan` verification after `aws sso login`, svc-tofu RouterOS credential rotation, T44–T47.
Plan: await the user's actual request.

## 2026-08-26 20:16 — Context: two Componere repos reviewed
Read `~/code/componere/incus-spire-attestor` and `~/code/componere/incus-guest-agent` (READMEs, docs trees, security model, runtime reference, changelogs).

- **incus-spire-attestor** (v0.1.0, released today): two SPIRE NodeAttestor plugins sharing logical name `incus` — `incus-agent` (guest, beside SPIRE Agent) + `incus-server` (beside SPIRE Server). Proof = server writes single-use 128-bit nonce into `user.spire.attestor.nonce.<hex>` on the instance via the Incus API; guest reads it back through `/dev/incus/sock`. Guest claims (name, DMI UUID, location, cloud-init ID) only locate; identity + selectors come from the Incus API record. VMs only; project allowlist; restricted TLS cert bounds the Incus 7.3 `can_edit` blast radius. Agent ID = `spiffe://<td>/spire/agent/incus/<volatile.uuid>`. Go, hexagonal (internal/{attest,incus,spire,wire,config,agent,server}), moon+mise, goreleaser + melange/apko carrier image on GHCR.
- **incus-guest-agent** (v0.1.0, released today): privileged Talos `machine.pods` static pod that stands in for the loader Talos can't run — finds the Incus `agent:config` ISO under `/dev/sr*`, stages the 5 agent files into a private tmpfs, supervises the host-supplied `incus-agent` (subreaper, process-group shutdown). Restores `incus info`/`incus exec` AND node-local `/dev/incus/sock` on immutable Talos guests. Digest-pinned deploy patch in `deploy/talos/`.

Synergy: the guest-agent provides exactly the `/dev/incus/sock` channel the attestor's guest plugin needs, making SPIRE node attestation possible for Talos VMs on the Incus cluster. Fits the T32-resolved mgmt-cluster plan (CAPI self-managed pivot; Talos VMs on nas01) — SPIFFE/SPIRE identity for the mgmt cluster's services. Awaiting the user's actual request.
