# Phase 3 (resume) — OVN spike after the uplink stop

You paused the OVN spike at two problems and asked for a decision. The
decision is the **pause** option, followed by resuming the *spike* — not
the cleanup. Read this in full; the original prompt
(`prompts/03-ovn-spike.md`) still applies except where overridden here.

## Decisions

1. **Do not restore the pre-spike baseline.** The lab wants OVN; Phase 5
   makes it durable. The spike's end state is: chassis enabled on all
   four members, `network.ovn.northbound_connection` pointing at the
   temporary central on `sandbox01`, and the uplink ranges set. Leave
   central running on `sandbox01` until Phase 5 replaces it. Do not
   attempt to unset the northbound key or disable the chassis again.
2. **Chassis stay enabled as long as the northbound key is set.** Your
   hang reproduced the failure mode: with the key set and chassis
   disabled, cluster notifications block on OVN. Record this as a rule in
   the report and in `spikes/ovn/README.md`; Phase 5 must sequence any
   chassis change after repointing the key.
3. **The uplink is the existing `fast40-macvlan` network.** Incus accepts
   `physical`, `bridge`, and `macvlan` managed networks as OVN uplinks
   (the standalone example in "How to set up OVN with Incus" configures
   `ipv4.ovn.ranges` on an existing managed network and creates the OVN
   network with `network=<parent>`). Do not create a second managed
   network on `fast40`. Set on `fast40-macvlan`:
   `ipv4.ovn.ranges=10.10.40.64-10.10.40.79`, `ipv4.gateway=10.10.40.1/24`,
   `dns.nameservers=10.10.40.1` (confirm the DNS address from the address
   plan), through the fleet `cluster/` deploy that owns that network.
   `.64–.79` is outside gw01's dynamic pool (`.200–.250`) and clear of
   `sandbox01` (`.10`); record the reservation for the address-plan
   amendment. If `macvlan` as an uplink fails for a reason you can quote,
   the fallback is to replace `fast40-macvlan` with a `physical` network
   on `fast40` and repoint the `image-build` profile to it — that is a
   fleet change and a report item, not a silent swap.
4. File the unset quirk upstream: `network.ovn.northbound_connection`
   cannot be unset on a server without a local NB socket because the
   default is validated by connection. Include the exact error text you
   captured. Link the issue in the report.

## Resume from step 5 of the original prompt

- OVN network in a disposable project (`features.networks=true`,
  restricted like Phase 2's projects), `network=fast40-macvlan`,
  `ipv4.nat=true`, DHCP on. Two containers on different members with
  `--target`. Cross-member ping; egress (`wget -qO- https://1.1.1.1` or
  ping `10.10.40.1`), noting the source address on the VLAN 40 side
  (`tcpdump` on `sandbox01` or a gw01 counter); one `incus network
  forward` reachable from the operator workstation over Tailscale.
- Central stop/start behavior (step 6), teardown and repeat (step 7).
- Measure: instance MTU Incus chose and whether a 100 MB transfer
  between the two members completes; external addresses consumed per
  OVN network and per forward; time to create a network and to bring a
  cross-member ping up.
- Reboot check (step 8) only if a member reboot is still warranted: the
  question is whether a node with chassis enabled and central reachable
  boots cleanly. The earlier `lab03` reboot with central *unreachable*
  returned to ONLINE in ~116 s; compare its `initrd-cleanup-root.service`
  failure against a member that never ran OVN before attributing it.

## Deliverables

As in the original prompt: fleet PR (chassis deploy, Incus OVN config,
uplink settings on `fast40-macvlan`, all enabled), `spikes/ovn/README.md`
+ probe, no `networking` changes unless a gw01 rule is needed for the
forward. Plus the rule from decision 2 and the upstream issue link.

## Acceptance evidence

The original list, with the verdict SMOOTH / NOT SMOOTH stated on the
basis of steps 5–7 only. The cleanup difficulty you hit is not a
NOT SMOOTH criterion; it is a Phase 5 sequencing constraint.
