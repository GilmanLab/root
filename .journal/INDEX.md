# Session Journal

| ID  | Date       | Title | Status | Summary |
|-----|------------|-------|--------|---------|
| 001 | 2026-08-14 | Design Lab v2 core networking | complete | Created the networking repository and documented the authoritative Lab v2 device boundaries, switch topology, and physical cabling. |
| 002 | 2026-08-14 | Lab v2 vision, tracker, and first-node bootstrap | complete | Captured the Lab v2 vision and running tracker into `.journal/VISION.md`, drove the naming/AWS/secrets/sandbox work through handoff sessions, and bootstrapped `nas01` live as the Incus cluster's first member. |
| 003 | 2026-08-18 | Manage the Tailscale policy with GitOps | complete | Put the tailnet policy file under version control in the networking repository and made GitHub Actions validate it on pull requests and apply it on merge. |
| 004 | 2026-08-18 | Migrate AWS infrastructure into GilmanLab/aws | complete | Moved all six OpenTofu roots into the private AWS repository with preserved identities and zero-change plans, then retired the legacy writers. |
| 005 | 2026-08-18 | Restructure the secrets root of trust | complete | Added YubiKey-backed recovery to every SOPS file, defined the lab v2 secret hierarchy, removed stale policy artifacts, and documented the scoped KMS model. |
| 006 | 2026-08-18 | Automate and deploy the VyOS gateway | complete | Finalized the core-network design, replaced legacy VyOS automation, and deployed the accepted saved configuration to `gw01`. |
| 007 | 2026-08-19 | Build and deploy sandbox01 base automation | complete | Created and live-tested reset-button automation for `sandbox01`, repaired physical routing, and made direct Tailscale SSH the routine transport. |
| 008 | 2026-08-20 | New Lab v2 work session | in-progress | Session opened; goal to be stated by the user. |
