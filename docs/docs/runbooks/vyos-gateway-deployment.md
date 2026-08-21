---
title: Deploy the VyOS gateway configuration
description: Validate, inspect, deploy, verify, and recover the gw01 configuration.
---

# Deploy the VyOS gateway configuration

Use this runbook to deploy the version-controlled `gw01` configuration from
[`GilmanLab/networking`](https://github.com/GilmanLab/networking). The
[Lab v2 core network design](../designs/lab-v2-core-network.md) defines the
accepted behavior. The
[network address and VLAN plan](../reference/networking/address-plan.md) is the
canonical source for addresses, interfaces, and VLANs.

## Preconditions

- Use a reviewed checkout of `GilmanLab/networking`. Run every command below
  from that checkout's root.
- Install the repository's Moon toolchain and dependencies.
- Have SSH access to `gw01` and a verified `known_hosts` entry for the target.
  The deployment always uses strict host-key checking.
- Have a separate checkout of the private `GilmanLab/secrets` repository and
  SOPS decryption access for the `network-vyos` scope. Routine access uses the
  KMS path described in
  [ADR-0003](../decisions/0003-use-kms-with-pgp-recovery-for-secrets.md).
- Confirm that no other operator or controller is deploying `gw01`. The
  fail-fast lock serializes syncs only within the same networking checkout.
- Have PiKVM or local-console access before changing routing, firewall, SSH, or
  transit configuration.
- Run the operator commands from a shell that does not set the `CI`
  environment variable. The `vyos-facts` and `vyos-sync` tasks are
  `runInCI: false`, and Moon excludes them whenever `CI` is truthy, failing
  with "No tasks found". Agent and automation shells often export `CI=true`;
  clear it for the single command when needed:

  ```bash
  CI= moon run network:vyos-facts
  ```

Pull requests run static validation only. Merging a change does not deploy it
to `gw01`; an operator must run `moon run network:vyos-sync`.

## Source and secret inputs

The authoritative gateway source is:

- [`vyos/gw01/config.boot.tmpl`](https://github.com/GilmanLab/networking/blob/master/vyos/gw01/config.boot.tmpl);
- [`vyos/gw01/assets/coredns/Corefile`](https://github.com/GilmanLab/networking/blob/master/vyos/gw01/assets/coredns/Corefile); and
- [`vyos/gw01/assets/scripts/dns-mirror-fetch-glab-lol.sh`](https://github.com/GilmanLab/networking/blob/master/vyos/gw01/assets/scripts/dns-mirror-fetch-glab-lol.sh).

The [`networking_vyos` package](https://github.com/GilmanLab/networking/tree/master/src/networking_vyos)
owns validation, secret handling, locking, staging, and verification. Its
`pyinfra-vyos` 0.1.0 boundary consists of the `Version`, redacted
`ConfigurationCommands`, and `PendingSave` facts plus `config_load()`,
`config()`, and `config_save()`. No decrypted configuration file is written.

If the secrets repository is not already present, clone it outside the public
networking repository. Set `GLAB_SECRETS_DIR` to its absolute path:

```bash
mkdir -p "$HOME/code/glab"
test -d "$HOME/code/glab/secrets/.git" || \
  git clone git@github.com:GilmanLab/secrets.git "$HOME/code/glab/secrets"
export GLAB_SECRETS_DIR="$HOME/code/glab/secrets"
```

`GLAB_SECRETS_DIR` has no default. The checkout must contain this encrypted
input:

| Path relative to `GLAB_SECRETS_DIR` | Required keys |
| --- | --- |
| `network/vyos/ssh.sops.yaml` | `public_key`, `password_hash` |

Do not decrypt the file to disk or print its values. The full configuration
load substitutes only `@@VYOS_PUBLIC_KEY@@`. A separate generic `config()`
operation applies `password_hash` after the load, before verification, so a
full-load failure cannot print the hash with the candidate configuration.

Connection flags take precedence over environment variables, which take
precedence over defaults:

| Flag | Environment variable | Default |
| --- | --- | --- |
| `--host` | `VYOS_HOST` | `10.0.0.2` |
| `--ssh-user` | `VYOS_SSH_USER` | `vyos` |
| `--ssh-key` | `VYOS_SSH_KEY` | `~/.ssh/vyos-gateway` |
| `--known-hosts` | `VYOS_KNOWN_HOSTS` | `~/.ssh/known_hosts` |

Pass flags to the underlying module after Moon's `--`.

`VYOS_SSH_KEY` points to the controller-local private-key file used for the SSH
connection. It is separate from the encrypted `private_key`, which is retained
for key distribution and recovery. Provision the local file with owner-only
permissions before running the commands; the deployment does not write the
decrypted private key to that path.

For a non-default connection, set all changed values explicitly:

```bash
export VYOS_HOST=10.0.0.2
export VYOS_SSH_USER=vyos
export VYOS_SSH_KEY="$HOME/.ssh/vyos-gateway"
export VYOS_KNOWN_HOSTS="$HOME/.ssh/known_hosts"
```

Confirm that the selected host-key file contains the independently verified
`gw01` key:

```bash
ssh-keygen -F "$VYOS_HOST" -f "$VYOS_KNOWN_HOSTS"
```

Do not disable host-key checking to work around a missing or changed entry.
Verify a changed fingerprint through PiKVM or the local console before updating
`known_hosts`.

## Validate and inspect

1. Validate the tracked template, sentinels, and non-secret assets locally:

   ```bash
   moon run network:vyos-validate
   ```

   This static check does not read `GLAB_SECRETS_DIR` or contact `gw01`. Stop if
   validation fails.

2. Read the current router state:

   ```bash
   moon run network:vyos-facts
   ```

   The facts command is read-only and requests redacted VyOS configuration
   output. It must report `pending_save: False`, derived from the
   `PendingSave` fact, before a sync. Stop if the router has an existing unsaved
   change.

   Use JSON when another tool will consume the result:

   ```bash
   moon run network:vyos-facts -- --json
   ```

## Deploy

1. Start the interactive sync:

   ```bash
   moon run network:vyos-sync
   ```

   Review the prompt before approving the change. For an already reviewed,
   noninteractive invocation, use:

   ```bash
   moon run network:vyos-sync -- --yes
   ```

2. Wait for the command to finish. The sync performs this guarded sequence:

   1. repeats local validation and decrypts the expected SSH values;
   2. acquires a fail-fast local lock at `.moon/cache/gw01.lock` for all remote
      stages;
   3. runs a read-only preflight and requires the `PendingSave` fact to be
      `False`;
   4. stages the remaining non-secret CoreDNS assets;
   5. creates the empty nftables compatibility chains required by the installed
      VyOS rolling image, then loads and commits the secret-free candidate with
      `config_load(..., save=False)`;
   6. applies the console password hash with `config(..., save=False)`;
   7. verifies the running candidate in a fresh process;
   8. calls `config_save()` only after verification succeeds; and
   9. performs a fresh final check that requires the `PendingSave` fact to be
      `False`.

   The lock is local to this checkout and controller. It does not exclude a
   sync started from another controller, so operators must coordinate before
   running the command. A failed verification never saves the candidate as the
   boot configuration.

## Verify

Run a new facts process after a successful sync:

```bash
moon run network:vyos-facts -- --json
```

Confirm all of the following:

- the JSON field `pending_save` is `false`;
- the reported configuration remains redacted; and
- the changed routing, DHCP, DNS, Tailscale, CoreDNS, or firewall behavior meets
  the applicable criteria in the
  [core network design](../designs/lab-v2-core-network.md#verification).

## Failure and recovery

If local validation, secret loading, lock acquisition, or the read-only
preflight fails, fix the reported condition and run the procedure again. These
failures occur before the candidate is loaded.

If candidate verification fails after the load, do not save from the VyOS CLI.
The rejected candidate can remain active in the running configuration, but the
previous boot configuration is unchanged. If SSH or routed access is lost, use
PiKVM or the local console to reboot `gw01`. The reboot restores the previous
boot configuration.

If `config_save()` fails or the final check does not report the `PendingSave`
fact as `False`, do not assume which configuration will survive a reboot.
Keep console access, inspect the running and boot configurations locally, and
resolve the save state before another deployment.

Escalate instead of retrying blindly when:

- preflight reports an unsaved change you do not own;
- the host key changes without an explained router reinstall or key rotation;
- verification fails but the previous boot configuration does not recover
  access; or
- the post-save JSON check reports `"pending_save": true`.
