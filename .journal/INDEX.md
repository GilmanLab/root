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
| 008 | 2026-08-20 | Bring the lab switches under management | complete | Converged `sw-core01` to v2 under a new OpenTofu root, readdressed and escrowed `sw-mgmt01`, and fixed gw01's missing NTP firewall rules at source. |
| 009 | 2026-08-21 | Bring the lab compute nodes online | complete | Provisioned AMT and installed IncusOS on all three MS-02s, joining them to form the four-node cluster with recovery keys escrowed and the procedure runbooked. |
| 010 | 2026-08-21 | Configure storage and networking across the cluster | complete | Brought cluster storage fully live under new fleet pyinfra automation (data pools, cluster pool, 17.4TB hdd raidz1) and converged the VLAN 30 storage network, with the lab datapath pending 10G DACs and the merged upstream IncusOS ice-firmware fix. |
| 011 | 2026-08-21 | Session opened, goal pending | in-progress | New session primed; awaiting the user's actual request. |
| 012 | 2026-08-22 | Make the MacBook and Mac Studio interchangeable | in-progress | Working toward interchangeable MacBook/Mac Studio environments, with the lab as a possible supporting utility. |
| 013 | 2026-08-23 | Review the 25G DAC issues on the lab nodes | in-progress | Recovering prior-session detail on the 25G DAC/FEC failures between the three MS-02 lab nodes and sw-core01. |
