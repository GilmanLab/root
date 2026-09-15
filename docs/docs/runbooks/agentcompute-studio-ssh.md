---
title: Authorize agentcompute SSH to Studio
description: Restrict the agentcompute service key to Studio SSH connections from the deployed service node.
---

# Authorize agentcompute SSH to Studio

Use this runbook to authorize the dedicated `agentcompute01` service key for
native OpenSSH on `studio-1`. This is a narrowly scoped Phase 8 host-access
procedure. It does not install or operate Lume, build a macOS seed, manage
worker VMs, change VNC filtering, or define a Phase 9b macOS lifecycle.

Studio remains the user-owned tailnet device `studio-1` at `100.122.142.76`.
**Do not assign `tag:macbackend` or any replacement device tag.** The tailnet
policy uses the `studio-1` host alias, allows `tag:agentcompute` to reach only
TCP `22` on that address, and leaves the existing `autogroup:admin` wildcard
rule unchanged. Host OpenSSH provides the source and key restrictions.

## Preconditions

- The Studio owner is present with console or existing administrative access.
  Keep that access open until a new connection passes.
- Remote Login is enabled and `/usr/sbin/sshd` uses the root-owned drop-in
  directory `/etc/ssh/sshd_config.d`.
- The dedicated local `agentcompute` account is hidden, standard rather than
  administrator, unable to use `sudo`, and a member of
  `com.apple.access_ssh`.
- The owner home directory denies traversal by `agentcompute`. On this Studio,
  `/Users/josh` is mode `0700`.
- `lume serve` is already loopback-only on `127.0.0.1:7777` under the
  `agentcompute` account.
- SOPS access to
  `GilmanLab/secrets/services/agentcompute/credentials.sops.yaml`, whose
  `studio.public_key` and `studio.private_key` are the dedicated service SSH
  keypair.
- The current tailnet policy containing the `studio-1` alias and
  `tag:agentcompute` SSH rule has been applied through
  [the policy change procedure](tailscale-policy-change.md).

## Safety impact

A malformed OpenSSH drop-in can disable Remote Login. Keep the owner session
open, validate with `sshd -t`, and restore the saved files before closing that
session if validation fails.

The dedicated account is the containment boundary. Do not make it an
administrator, grant sudo, expose the loopback Lume API directly, copy the
private service key into a guest, or weaken the owner-home permissions.

The approved transport is a normal shell plus local TCP forwarding. Remove the
old forwarding-only restrictions: no `ForceCommand`, no `PermitOpen`, and no
`restrict` authorized-key option. Agent, X11, tunnel, remote-forward, and
gateway forwarding remain disabled.

## Confirm the service source

Read the service node's tailnet IPv4 from the node itself. The approved and
currently deployed source is `100.65.152.20`.

```bash
SERVICE_TAILNET_IP="$(
  incus exec --project default nas01:agentcompute01 -- tailscale ip -4 |
    sed -n '1p'
)"
test "$SERVICE_TAILNET_IP" = '100.65.152.20'

incus exec --project default nas01:agentcompute01 -- tailscale status --json |
  jq -e '
    .BackendState == "Running" and
    .Self.DNSName == "agentcompute01.tailda715.ts.net." and
    (.Self.TailscaleIPs | index("100.65.152.20") != null) and
    (.Self.Tags | index("tag:agentcompute") != null)
  ' >/dev/null
```

If the address changes, stop. Update and re-verify the source pin in both files
below before using the new node. A tag match alone is not an OpenSSH source
pin.

## Materialize the public key

On the trusted administration workstation, write only the public half to a
temporary file:

```bash
export GLAB_SECRETS_DIR="$HOME/code/glab/secrets"
SECRETS_FILE="$GLAB_SECRETS_DIR/services/agentcompute/credentials.sops.yaml"
umask 077
STUDIO_SSH_WORK="$(mktemp -d)"
trap 'rm -rf "$STUDIO_SSH_WORK"' EXIT

sops --decrypt --extract '["studio"]["public_key"]' \
  "$SECRETS_FILE" >"$STUDIO_SSH_WORK/agentcompute01.pub"
ssh-keygen -l -f "$STUDIO_SSH_WORK/agentcompute01.pub"
```

Transfer that public file to the owner session through the existing trusted
administrative path. Do not transfer the private key to Studio for normal
operation.

## Install the source-restricted key

Run this block in the Studio owner session from the directory containing
`agentcompute01.pub`:

```bash
set -euo pipefail
SERVICE_TAILNET_IP=100.65.152.20
SERVICE_PUBLIC_KEY="$(cat agentcompute01.pub)"
KEY_BACKUP="$HOME/agentcompute-authorized_keys.$(date +%Y%m%d%H%M%S).bak"
if sudo test -f /Users/agentcompute/.ssh/authorized_keys; then
  sudo cp -p /Users/agentcompute/.ssh/authorized_keys "$KEY_BACKUP"
  sudo chown "$(id -un):$(id -gn)" "$KEY_BACKUP"
fi

sudo -u agentcompute -H sh -c '
  set -eu
  install -d -m 0700 "$HOME/.ssh"
  tmp="$(mktemp "$HOME/.ssh/.authorized_keys.XXXXXX")"
  trap '\''rm -f "$tmp"'\'' EXIT
  printf '\''from="%s",no-agent-forwarding,no-X11-forwarding %s agentcompute server\n'\'' \
    "$1" "$2" >"$tmp"
  chmod 0600 "$tmp"
  mv -f "$tmp" "$HOME/.ssh/authorized_keys"
  trap - EXIT
' sh "$SERVICE_TAILNET_IP" "$SERVICE_PUBLIC_KEY"
```

This dedicated account has one server key. Do not append the same key without a
`from=` restriction, and do not retain an old forced-command form of the key.

## Install the OpenSSH account policy

Back up the current drop-in and install the reviewed policy atomically:

```bash
set -euo pipefail
SERVICE_TAILNET_IP=100.65.152.20
DROPIN=/etc/ssh/sshd_config.d/110-agentcompute.conf
BACKUP="$HOME/110-agentcompute.conf.$(date +%Y%m%d%H%M%S).bak"

if sudo test -f "$DROPIN"; then
  sudo cp -p "$DROPIN" "$BACKUP"
fi

candidate="$(mktemp)"
trap 'rm -f "$candidate"' EXIT
cat >"$candidate" <<EOF
Match User agentcompute
    AllowUsers agentcompute@$SERVICE_TAILNET_IP
    AuthenticationMethods publickey
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    AllowTcpForwarding local
    PermitTunnel no
    X11Forwarding no
    AllowAgentForwarding no
    GatewayPorts no
Match all
EOF
sudo /usr/sbin/sshd -t -f "$candidate"
sudo install -o root -g wheel -m 0644 "$candidate" "$DROPIN"
sudo /usr/sbin/sshd -t
sudo /usr/sbin/sshd -T \
  -C "user=agentcompute,host=studio-1,addr=$SERVICE_TAILNET_IP" |
  egrep '^(authenticationmethods|passwordauthentication|kbdinteractiveauthentication|allowtcpforwarding|permitopen|permittunnel|x11forwarding|allowagentforwarding|gatewayports|forcecommand) '
```

Require the effective configuration to show public-key authentication, local
TCP forwarding, no agent/X11/tunnel/gateway forwarding, `forcecommand none`, and
`permitopen any`. The last two values confirm that the old `ForceCommand` and
`PermitOpen` directives are absent; they do not make the key usable from an
unapproved source.

OpenSSH reads the policy for each new connection. Leave the existing owner
session open while performing both verification paths below.

## Verify the allowed service connection

Obtain Studio's ED25519 host public key through its console, not through an
unverified `ssh-keyscan` result:

```bash
sudo cat /etc/ssh/ssh_host_ed25519_key.pub
```

On the administration workstation, paste that exact line when `read` prompts,
then build a temporary known-hosts file and copy it to the service VM:

```bash
read -r STUDIO_HOST_KEY
printf 'studio-1,100.122.142.76 %s\n' "$STUDIO_HOST_KEY" \
  >"$STUDIO_SSH_WORK/studio-known-hosts"
incus file push --project default --mode 0600 --uid 0 --gid 0 \
  "$STUDIO_SSH_WORK/studio-known-hosts" \
  nas01:agentcompute01/run/studio-known-hosts
```

Run a normal shell command with the delivered private key. Strict host-key
checking must remain enabled.

```bash
incus exec --project default nas01:agentcompute01 -- \
  ssh -F /dev/null \
    -i /etc/agentcompute/credentials/mac-ssh.key \
    -o BatchMode=yes \
    -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=yes \
    -o UserKnownHostsFile=/run/studio-known-hosts \
    agentcompute@studio-1 \
    'printf "user=%s\n" "$(id -un)"; printf "connection=%s\n" "$SSH_CONNECTION"; uname -s; ! sudo -n true'
```

Require all of these observations:

- `user=agentcompute`;
- `SSH_CONNECTION` starts with `100.65.152.20` and ends with
  `100.122.142.76 22`;
- `uname -s` prints `Darwin`;
- the remote `sudo -n true` check fails, making the final negation succeed.

Exercise local forwarding to the loopback Lume API. This check reads the
qualified stopped seed; it does not start or modify a VM.

```bash
incus exec --project default nas01:agentcompute01 -- sh -eu -c '
  ssh -F /dev/null \
    -i /etc/agentcompute/credentials/mac-ssh.key \
    -o BatchMode=yes \
    -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=yes \
    -o UserKnownHostsFile=/run/studio-known-hosts \
    -N -L 127.0.0.1:17777:127.0.0.1:7777 \
    agentcompute@studio-1 &
  tunnel=$!
  trap "kill $tunnel 2>/dev/null || true; wait $tunnel 2>/dev/null || true" EXIT
  attempts=0
  while test "$attempts" -lt 10; do
    if curl -fsS -o /dev/null \
      http://127.0.0.1:17777/lume/vms/ac-seed-macos-tahoe-desktop; then
      exit 0
    fi
    attempts=$((attempts + 1))
    sleep 1
  done
  exit 1
'
```

Remove the temporary host-key file after the check:

```bash
incus exec --project default nas01:agentcompute01 -- \
  rm -f /run/studio-known-hosts
```

The application must use an independently verified persistent known-hosts file
when this SSH path is wired into runtime configuration. Never replace host-key
verification with `StrictHostKeyChecking=no` or an unverified `ssh-keyscan`.

## Verify refusal of the same key from another source

This negative check is required. A different key proves nothing, and a failure
caused only by the tailnet ACL does not prove the OpenSSH source restriction.
Use an admin-owned tailnet device because the existing admin wildcard permits
it to reach Studio TCP `22`.

In an owner-only temporary directory on that non-service source, materialize the
same private key and confirm its derived public-key fingerprint matches the
installed public key:

```bash
umask 077
sops --decrypt --extract '["studio"]["private_key"]' \
  "$SECRETS_FILE" >"$STUDIO_SSH_WORK/mac-ssh.key"
chmod 0600 "$STUDIO_SSH_WORK/mac-ssh.key"
ssh-keygen -y -f "$STUDIO_SSH_WORK/mac-ssh.key" \
  >"$STUDIO_SSH_WORK/derived-mac-ssh.pub"
test "$(ssh-keygen -l -f "$STUDIO_SSH_WORK/derived-mac-ssh.pub" | awk '{print $2}')" = \
  "$(ssh-keygen -l -f "$STUDIO_SSH_WORK/agentcompute01.pub" | awk '{print $2}')"

set +e
ssh -F /dev/null \
  -i "$STUDIO_SSH_WORK/mac-ssh.key" \
  -o BatchMode=yes \
  -o IdentitiesOnly=yes \
  -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile="$STUDIO_SSH_WORK/studio-known-hosts" \
  agentcompute@100.122.142.76 true
status=$?
set -e
rm -f "$STUDIO_SSH_WORK/mac-ssh.key" \
  "$STUDIO_SSH_WORK/derived-mac-ssh.pub"
test "$status" -eq 255
```

Require `Permission denied (publickey)` and exit `255`. If the connection
succeeds, restore the previous policy immediately and inspect both
`authorized_keys` and the effective `sshd` configuration.

## Rollback and escalation

To roll back before closing the owner session, restore the saved drop-in or
remove the new one when no prior file existed. Restore the previous
`~agentcompute/.ssh/authorized_keys`, then run `sudo /usr/sbin/sshd -t`. Do not
leave a half-applied combination in which the key and account policy have
different source addresses.

Stop and escalate if the service IPv4 differs from `100.65.152.20`, Studio has
become tagged, the owner home is traversable, the dedicated account can use
sudo, effective policy contains a forced command or destination-specific
`PermitOpen`, the allowed service connection cannot open a normal shell, or the
same key succeeds from any other source.
