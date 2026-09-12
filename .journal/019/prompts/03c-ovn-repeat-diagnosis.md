# Phase 3 (follow-up) — Diagnose the OVN recreate failure before deciding the fallback

The Phase 3 spike reported NOT SMOOTH (agentcompute#15, `spikes/ovn/README.md`).
The first pass proved every datapath property; the verdict rests on two
failures that were run in a confounding order. This is a bounded
diagnosis with a decision rule, not a redesign. Read the spike report in
full first, then `prompts/03-ovn-spike.md` and `03b` for the rules that
still apply (chassis stay enabled while the NB key is set; no networking
changes; disposable project only; everything cluster-side through fleet).

Precondition: fleet#14, agentcompute#15, and root#30 are merged (the
cluster is already in the state they describe). If they are not, say so
and stop.

## Hypotheses to separate

- **H1 — uplink plumbing is torn down with the last consumer.** When the
  last OVN network using `fast40-uplink` is deleted, Incus removes the
  provider-bridge mapping on the chassis; the next create rebuilds it
  incompletely on the gateway chassis, so the router's gateway port never
  reaches `fast40` (matches: no ARP/ICMP from `.64` seen at the gateway,
  neighbor `FAILED`, east-west fine).
- **H2 — the step-6 `Errored` networks contaminated chassis state** before
  step 7 ran.
- **H3 — stale ARP at gw01/sandbox01 for `.64`** (less likely: the capture
  saw no ARP *requests answered*, but rule it out cheaply).

## Procedure

Run each cycle as: create project + OVN network (`network=fast40-uplink`,
NAT) + two guests on different members + forward → verify cross-member
ping, gateway ping, DNS, HTTPS, forward → full teardown. Record per cycle:
NB router + gateway chassis binding, the external IP and router MAC,
gw01/sandbox01 neighbor state for that IP, `incus monitor --type=logging
--pretty` output around create/delete (look for uplink/OVS mapping
messages), and a `tcpdump` on `sandbox01` for ARP involving the router
IP during the gateway ping.

1. **Clean repeat, no step-6 contamination**: three consecutive cycles
   from a clean state (delete any leftover `Errored` network first). If
   all three pass, H2 was the cause; record it and go to the decision.
2. **If a cycle fails**: test H3 by clearing the gw01 neighbor entry for
   the router IP (via the VyOS operational command, read-only otherwise)
   and re-pinging; then test H1 by creating a permanent `keeper` OVN
   network in the `default` project on `fast40-uplink` (no instances) and
   running three more cycles with it present. Also try a cycle that uses
   a *different* external address (set `ipv4.address`/router IP if Incus
   allows, or leave `.64` occupied by the keeper so the sandbox network
   takes `.65`) to see whether reuse of the same IP matters.
3. **Then reproduce step 6 once** (create with central stopped) and
   confirm the `Errored` network is deletable and, after deletion, a
   cycle still passes — this establishes that step-6 residue is
   recoverable by deletion alone, which is what the reaper will do.

Do not restart OVS/chassis, recreate the uplink, or change the network
architecture to make a cycle pass. Fixes are limited to the keeper
network and the neighbor clear, each of which is a legitimate mitigation
agentcompute can own.

## Decision rule

- **PROCEED** if three consecutive cycles pass with the keeper network
  present (or without it, if step 1 passes). Report which; Phase 5 then
  makes the keeper a fleet-owned permanent network if it was needed, and
  the reaper handles `Errored` networks.
- **FALLBACK** if cycles still fail with the keeper and after the
  neighbor clear. Report the exact failing observation; the design's
  documented bridge fallback is then the owner's decision.

Either way, file an Incus issue for the step-6 behavior (create with NB
unreachable hangs 60 s and leaves an `Errored` network holding an
address) and, if H1 is confirmed, a second one with the reproduction.

## Deliverables

Append the results to `spikes/ovn/README.md` (new section, dated), update
the probe to run a full cycle from one command, and record the
per-sandbox external-address number again if the keeper changes it.
Report the verdict with the cycle table.
