---
title: Deploy and operate agentcompute
description: Deploy, verify, maintain, and recover the agentcompute HTTP service.
---

# Deploy and operate agentcompute

Use this runbook to deploy and operate the durable `agentcompute` Streamable
HTTP service. The deployed endpoint is
`https://agentcompute01.tailda715.ts.net`. Tailscale Serve terminates HTTPS on
port `443` and proxies to the service on `127.0.0.1:8080`.

The verified tailnet IPv4 is **`100.65.152.20`**. Studio's SSH policy pins this
address; re-enrollment requires checking both the MagicDNS name and source pin.

The service runs in the `agentcompute01` Ubuntu 24.04 VM in the Incus `default`
project on `lab01`. OpenTofu in `GilmanLab/fleet/incus/agentcompute` owns the VM,
the `ac-svc-vlan40` OVN network, and the private `agentcompute01.glab.lol` A
record. The service process owns runtime sandbox resources.

For an initial deployment or replacement, keep this order: apply the
infrastructure, install the verified release, deliver the credentials and start
the service, then enroll the node and publish Tailscale Serve. Publishing last
prevents an unauthenticated or credential-incomplete listener from reaching the
tailnet.

## Preconditions

- Administrative access to the Incus cluster, the Tailscale tailnet, the
  `glab.lol` private Route 53 zone, and the lab S3 state bucket.
- Current checkouts of `GilmanLab/fleet`, `GilmanLab/agentcompute`, and the
  private `GilmanLab/secrets` repository.
- An authenticated `lab-admin` AWS profile and `GLAB_AWS_STATE_BUCKET` set to
  the existing fleet state bucket.
- SOPS decryption access to
  `services/agentcompute/credentials.sops.yaml`. The file uses the
  `agentcompute` encryption scope and follows
  [ADR-0003](../decisions/0003-use-kms-with-pgp-recovery-for-secrets.md).
- An Incus administration remote named `nas01` with its existing pinned server
  certificate. Do not enable automatic certificate acceptance.
- The `tag:agentcompute` tailnet policy is applied. Its only tag owner is
  `autogroup:admin`; tailnet members can reach the tag on TCP `443`, and the tag
  can reach the user-owned `studio-1` host only on TCP `22`.
- After enrollment, follow
  [Authorize agentcompute SSH to Studio](agentcompute-studio-ssh.md) to pin
  Studio access to the service's verified tailnet IPv4.
- On macOS, point the OpenTofu provider at the administration client's actual
  configuration: `export INCUS_CONF="$HOME/Library/Application Support/incus"`.
  Incus 7.3 uses that directory, while provider 1.2.0 defaults to
  `$HOME/.config/incus`. A missing pin caused by that mismatch is not a reason
  to enable certificate acceptance.

## Configure an agent client

Use a Streamable HTTP MCP connection, not an SSE-only URL or local stdio
server:

| Setting | Value |
| --- | --- |
| Server name | `agentcompute` |
| Transport | Streamable HTTP |
| URL | `https://agentcompute01.tailda715.ts.net/` |
| HTTP header | `Authorization: Bearer <omp token>` |
| Token source | SOPS `auth_tokens.omp` in `services/agentcompute/credentials.sops.yaml` |
| TLS | Default public trust; never disable verification |

Resolve the token through the client's secret or environment support. Do not
commit its value to client configuration, pass it in a command argument, or
paste it into an agent prompt. The authenticated initialization recipe below
keeps it on curl's standard input.

The client discovers exactly three MCP tools: `search_api`, `describe_api`,
and `execute`. Start with a resource query such as `{"query":"sandbox"}`;
describe exact returned names before using them in `def main():`. Search is
not free-form planning: if a multi-resource sentence returns no matches, use
one resource or exact capability name. A minimal discovery-driven health
check describes `sandbox.list` and executes:

```python
def main():
    return sandbox.list()
```

Use `sandbox.get` or `instance.list` for inventory details. Creating resources
is not necessary for every client health check.

## Safety boundary

> project creation is root-equivalent in Incus 7.4 (OpenFGA model warning; scriptlet cannot see the project name at create time), so this credential is cluster root; the server's only exposure is the tailnet MCP endpoint behind bearer tokens, and agent code never reaches the Incus client.

The Incus trust entry is the dedicated, unrestricted `agentcompute01` client.
Never substitute `bootstrap-admin`, broaden an image-build or CI certificate, or
reuse one of those identities. The MCP service accepts the static named bearer
identity `omp`; possession of its token grants every currently registered
capability.

The Phase 2 live restricted-certificate check is the evidence for this
exception: the `image-build` certificate saw an empty filtered list for
`default` instances, received HTTP `403` when updating default-project
configuration, and received HTTP `403` when creating an `ac-` project. It cannot
perform the deployed project's create path. A future design can replace the
root identity with a fleet-managed pool of pre-restricted `ac-NN` projects and
a restricted claim-and-release certificate. That design also needs marker or
profile metadata because a restricted certificate cannot edit project
configuration. Do not implement that deferred pool as an ad hoc deployment
change.

Do not change the IncusOS bond or disable `strict_hwaddr`. The management NIC is
a routed Incus NIC on the host's `_vmgmt` Layer 3 interface; the `mgmt` bridge
is only Layer 2. The deployed paths are:

| Purpose | Configuration |
| --- | --- |
| Management and default route | `10.10.10.16/32` through `169.254.0.1` on `mgmt0` |
| Pinned Incus API | `https://10.10.10.14:8443` through `mgmt0` |
| Guest reach | `ac-svc-vlan40`, gateway `10.158.86.1/24`, service guest address `10.158.86.2` |
| Sandbox VLAN route | `10.10.40.0/24` through `10.158.86.1` on `guest0` |
| MCP listener | `127.0.0.1:8080` only |
| Published endpoint | `https://agentcompute01.tailda715.ts.net:443` through Tailscale Serve |

One service process owns one runtime and one in-process reaper. All HTTP
sessions share it. The reaper scans once at startup and every 30 seconds. Do not
run a second durable service or a long-lived STDIO process against the same
sandbox set.

## Materialize deployment inputs

Keep plaintext in one owner-only temporary directory. The trap removes local
material at shell exit; the one-time Tailscale key is unusable after successful
enrollment.

```bash
export GLAB_SECRETS_DIR="$HOME/code/glab/secrets"
export FLEET_DIR="$HOME/code/lab2/fleet"
export AGENTCOMPUTE_DIR="$HOME/code/lab2/agentcompute"
export AWS_PROFILE=lab-admin

umask 077
AGENTCOMPUTE_CREDENTIALS="$(mktemp -d)"
trap 'rm -rf "$AGENTCOMPUTE_CREDENTIALS"; unset TS_OAUTH_CLIENT_ID TS_OAUTH_CLIENT_SECRET TS_OAUTH_SCOPE TS_OAUTH_TAGS_JSON OMP_TOKEN' EXIT
SECRETS_FILE="$GLAB_SECRETS_DIR/services/agentcompute/credentials.sops.yaml"

sops --decrypt --extract '["incus"]["client_certificate"]' \
  "$SECRETS_FILE" >"$AGENTCOMPUTE_CREDENTIALS/incus-client.crt"
sops --decrypt --extract '["incus"]["client_key"]' \
  "$SECRETS_FILE" >"$AGENTCOMPUTE_CREDENTIALS/incus-client.key"
sops --decrypt --extract '["studio"]["private_key"]' \
  "$SECRETS_FILE" >"$AGENTCOMPUTE_CREDENTIALS/mac-ssh.key"
sops --decrypt --extract '["auth_tokens"]' --output-type json \
  "$SECRETS_FILE" >"$AGENTCOMPUTE_CREDENTIALS/auth-tokens.json"
pin_version="$(
  awk -F'"' '
    $1 ~ /^service_version[[:space:]]*=/ { print $2 }
  ' "$FLEET_DIR/incus/agentcompute/release.auto.tfvars"
)"
test -n "$pin_version"
curl -fsSL \
  "https://raw.githubusercontent.com/GilmanLab/agentcompute/v$pin_version/images/catalog.yaml" \
  -o "$AGENTCOMPUTE_CREDENTIALS/catalog.yaml"
chmod 0600 "$AGENTCOMPUTE_CREDENTIALS"/*

export TF_VAR_images_catalog_file="$AGENTCOMPUTE_CREDENTIALS/catalog.yaml"
export TF_VAR_incus_client_certificate_file="$AGENTCOMPUTE_CREDENTIALS/incus-client.crt"
```

The encrypted document also records `incus.url`, `incus.trust_name`, and
`incus.restricted`. Require the reviewed values before using the material:

```bash
test "$(sops --decrypt --extract '["incus"]["url"]' "$SECRETS_FILE")" = \
  'https://10.10.10.14:8443'
test "$(sops --decrypt --extract '["incus"]["trust_name"]' "$SECRETS_FILE")" = \
  'agentcompute01'
test "$(sops --decrypt --extract '["incus"]["restricted"]' "$SECRETS_FILE")" = \
  'false'
jq -e 'keys == ["omp"] and (.omp | type == "string" and length > 0)' \
  "$AGENTCOMPUTE_CREDENTIALS/auth-tokens.json" >/dev/null
```

Nothing private enters cloud-init, OpenTofu input, or OpenTofu state. Public
certificates, image catalog, SSH host-key pins, and runtime configuration do.
The three base private inputs are delivered after provisioning as `root:root`
mode `0600` files in a mode `0700` directory. Enabling Lume adds a fourth
private input, `mac-guest.key`, delivered separately from the qualified
Studio account by `just deliver-lume-key`. With `lume_host` set, deliver it
**before** `just deliver-credentials` on a first deployment or VM replacement;
the unit is gated on that file too. The unit loads the Incus client
certificate/key, bearer-token file, Studio SSH key, and enabled Mac guest key
with `LoadCredential=`.
Treat the runtime credential mount as unit-private; do not infer its access from
ownership or mode observed outside the service namespace.

## Enroll the Incus identity

Calculate the certificate fingerprint and compare it with any existing entry.
Stop if the name exists with a different fingerprint or is restricted.

```bash
expected_fingerprint="$(
  openssl x509 -in "$AGENTCOMPUTE_CREDENTIALS/incus-client.crt" \
    -noout -fingerprint -sha256 |
    cut -d= -f2 | tr -d ':' | tr 'A-F' 'a-f'
)"
existing="$(
  incus config trust list nas01: --format=json |
    jq -r '.[] | select(.name == "agentcompute01") | [.fingerprint, .restricted] | @tsv'
)"

if test -z "$existing"; then
  incus config trust add-certificate nas01: \
    "$AGENTCOMPUTE_CREDENTIALS/incus-client.crt" \
    --name agentcompute01 \
    --description 'agentcompute01 service runtime'
else
  test "$existing" = "$expected_fingerprint"$'\t'false
fi
```

Do not modify the existing image-build CI trust while enrolling this identity.

## Deploy the VM and network

Run the OpenTofu root from `GilmanLab/fleet`. Review the saved plan before
applying it. It must create or update only this root's VM, OVN network, private
DNS record, and associated state; it must not change host bonds, IncusOS
`strict_hwaddr`, the shared `fast40-uplink`, or other trust entries.

```bash
cd "$FLEET_DIR/incus/agentcompute"
just init
just check
just plan
tofu show tfplan
just apply
```

Wait for the one-time bootstrap. A successful bootstrap installs and holds the
pinned Tailscale package, creates the non-login `agentcompute` service account,
and enables—but does not yet start—the credential-gated service.

```bash
incus exec --project default nas01:agentcompute01 -- cloud-init status --wait
incus exec --project default nas01:agentcompute01 -- \
  cloud-init status --format json |
  jq -e '.status == "done" and .errors == []' >/dev/null
```

Cloud-init is not a convergence mechanism. After a reviewed plan is applied,
`just install-release` converges the public runtime bundle—configuration,
catalog, unit, and SSH host pins—alongside the verified release. Bootstrap,
network, and certificate changes still require deliberate VM replacement,
release installation, credential delivery, and tailnet enrollment. Do not
rerun the old bootstrap on an existing VM.

## Verify and install the pinned release

Read the applied release pin instead of choosing a version at the command line.
Download on the administration workstation, verify the GitHub attestation and
immutable release, and compare the exact SHA-256. Check the Linux binary's
embedded commit on the service VM, not on the Mac workstation.

```bash
pin="$(tofu output -json release_pin)"
version="$(jq -r .version <<<"$pin")"
digest="$(jq -r .sha256 <<<"$pin")"
test "$version" = "$pin_version"
asset="$(jq -r .asset <<<"$pin")"
tag="v$version"
release_dir="$(mktemp -d)"

cleanup_release() { rm -rf "$release_dir"; }
trap 'cleanup_release; rm -rf "$AGENTCOMPUTE_CREDENTIALS"; unset TS_OAUTH_CLIENT_ID TS_OAUTH_CLIENT_SECRET TS_OAUTH_SCOPE TS_OAUTH_TAGS_JSON OMP_TOKEN' EXIT

release_state="$(gh release view "$tag" --repo GilmanLab/agentcompute --json isDraft,tagName)"
test "$(jq -r .isDraft <<<"$release_state")" = 'false'
test "$(jq -r .tagName <<<"$release_state")" = "$tag"
gh release download "$tag" --repo GilmanLab/agentcompute \
  --dir "$release_dir" --pattern "$asset" --pattern checksums.txt
tag_commit="$(gh api "repos/GilmanLab/agentcompute/commits/$tag" --jq .sha)"

gh attestation verify "$release_dir/$asset" \
  --repo GilmanLab/agentcompute \
  --signer-workflow GilmanLab/agentcompute/.github/workflows/attest.yml \
  --source-ref "refs/tags/$tag" \
  --source-digest "$tag_commit" \
  --deny-self-hosted-runners
test "$(shasum -a 256 "$release_dir/$asset" | awk '{print $1}')" = "$digest"
awk -v digest="$digest" -v asset="$asset" '
  $1 == digest && $2 == asset { found = 1 }
  END { exit !found }
' "$release_dir/checksums.txt"
gh release verify "$tag" --repo GilmanLab/agentcompute
gh release verify-asset "$tag" "$release_dir/$asset" --repo GilmanLab/agentcompute
just install-release "$release_dir/$asset"
banner="$(incus exec --project default nas01:agentcompute01 -- /usr/local/bin/agentcompute --version)"
case "$banner" in
  "agentcompute $version ($tag_commit) built "*) ;;
  *) printf 'unexpected release banner: %s\n' "$banner" >&2; exit 1 ;;
esac
```

The workstation installer first refreshes the VM-side installer from the
`release_installer` output in applied state. It resolves its module directory
and requires initialized state-backend access. The VM-side installer repeats
the pinned digest and version checks, converges the public runtime bundle,
installs a versioned file under `/usr/local/lib/agentcompute`, atomically
changes `/usr/local/bin/agentcompute`, and restarts the service only if it is
already running. It does not overwrite private credentials. A rejected asset
does not replace the current binary or runtime bundle.

A changed image catalog is reconciled before the MCP listener opens. During
that work, systemd can report `active` while Tailscale Serve returns `502`.
Wait for the service's `listening` log entry, then perform the HTTPS checks
below; `systemctl is-active` alone is not a readiness check.

GitHub artifact and OCI attestations and the OCI Cosign signature are release
evidence, not deployed-service acceptance. Do not claim SLSA Build Level 3:
the artifact build occurs outside the reusable attester, so signer isolation
does not establish that level for the build.

## Deliver credentials and start the service

Delivery validates that the bearer file is a non-empty JSON identity-to-token
object with unique names and tokens and no whitespace or control characters.
It pushes all three private files as root-owned mode `0600`, then restarts the
unit. Install the release first so the initial service start cannot select an
unverified binary.
With `lume_host` enabled, first follow
[the Mac guest-key delivery procedure](#deliver-permanent-runtime-configuration).
That delivery does not start the service; the base delivery below does.


```bash
just deliver-credentials \
  "$AGENTCOMPUTE_CREDENTIALS/incus-client.key" \
  "$AGENTCOMPUTE_CREDENTIALS/auth-tokens.json" \
  "$AGENTCOMPUTE_CREDENTIALS/mac-ssh.key"
```

The runtime loads bearer tokens once at process start. Credential delivery uses
`systemctl restart`, so a successful delivery activates all three private
inputs immediately and disconnects existing MCP sessions.

## Enroll the tailnet node and publish HTTPS

Mint one non-reusable, non-ephemeral, pre-authorized key from the scoped OAuth
client. The Python process keeps the OAuth secret and access token out of its
arguments; only the one-time auth key is written to the temporary directory.

```bash
export TS_OAUTH_CLIENT_ID="$(sops --decrypt --extract '["tailscale"]["oauth_client_id"]' "$SECRETS_FILE")"
export TS_OAUTH_CLIENT_SECRET="$(sops --decrypt --extract '["tailscale"]["oauth_client_secret"]' "$SECRETS_FILE")"
export TS_OAUTH_SCOPE="$(sops --decrypt --extract '["tailscale"]["scope"]' "$SECRETS_FILE")"
export TS_OAUTH_TAGS_JSON="$(sops --decrypt --extract '["tailscale"]["tags"]' --output-type json "$SECRETS_FILE")"

python3 - "$AGENTCOMPUTE_CREDENTIALS/tailscale-auth.key" <<'PY'
import json
import os
import sys
import urllib.parse
import urllib.request

output = sys.argv[1]
tags = json.loads(os.environ["TS_OAUTH_TAGS_JSON"])
if os.environ["TS_OAUTH_SCOPE"] != "auth_keys" or tags != ["tag:agentcompute"]:
    raise SystemExit("refusing OAuth scope or tags outside the reviewed deployment")

form = urllib.parse.urlencode({
    "client_id": os.environ["TS_OAUTH_CLIENT_ID"],
    "client_secret": os.environ["TS_OAUTH_CLIENT_SECRET"],
    "grant_type": "client_credentials",
}).encode()
with urllib.request.urlopen(
    urllib.request.Request(
        "https://api.tailscale.com/api/v2/oauth/token",
        data=form,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    ),
    timeout=30,
) as response:
    access_token = json.load(response)["access_token"]

body = json.dumps({
    "keyType": "auth",
    "capabilities": {
        "devices": {
            "create": {
                "reusable": False,
                "ephemeral": False,
                "preauthorized": True,
                "tags": tags,
            }
        }
    },
    "expirySeconds": 600,
    "description": "agentcompute01 one-time enrollment",
}).encode()
with urllib.request.urlopen(
    urllib.request.Request(
        "https://api.tailscale.com/api/v2/tailnet/-/keys",
        data=body,
        headers={
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json",
        },
    ),
    timeout=30,
) as response:
    key = json.load(response)["key"]

with open(output, "x", encoding="utf-8") as handle:
    handle.write(key + "\n")
os.chmod(output, 0o600)
PY

unset TS_OAUTH_CLIENT_ID TS_OAUTH_CLIENT_SECRET TS_OAUTH_SCOPE TS_OAUTH_TAGS_JSON
just enroll-tailscale "$AGENTCOMPUTE_CREDENTIALS/tailscale-auth.key"
rm -f "$AGENTCOMPUTE_CREDENTIALS/tailscale-auth.key"
```

The enrollment script moves the key through VM tmpfs, shreds the VM copy on
success or failure, joins as `tag:agentcompute`, does not accept subnet routes, and
requires the exact `agentcompute01.tailda715.ts.net` MagicDNS name before it
publishes HTTPS `443` to `http://127.0.0.1:8080`. It refuses a collision suffix
such as `agentcompute01-1` instead of publishing an endpoint that disagrees
with screenshot URLs. It does not enable Tailscale SSH. On an already enrolled
and correctly tagged node, the VM-side operation reasserts Tailscale Serve only
after the same name check.

## Verify the deployment

First verify process, route, listener, node identity, and Serve state from the
administration workstation:

```bash
incus exec --project default nas01:agentcompute01 -- \
  systemctl is-active agentcompute.service tailscaled.service
incus exec --project default nas01:agentcompute01 -- \
  ss -H -lnt 'sport = :8080'
incus exec --project default nas01:agentcompute01 -- \
  ip route get 10.10.10.14
incus exec --project default nas01:agentcompute01 -- \
  ip route get 10.10.40.65
incus exec --project default nas01:agentcompute01 -- \
  tailscale serve status
incus exec --project default nas01:agentcompute01 -- \
  tailscale status --json |
  jq -e '
    .BackendState == "Running" and
    .Self.DNSName == "agentcompute01.tailda715.ts.net." and
    (.Self.TailscaleIPs | index("100.65.152.20") != null) and
    (.Self.Tags | index("tag:agentcompute") != null)
  ' >/dev/null
```

The listener output must name only `127.0.0.1:8080`. The API route must use
`mgmt0` through `169.254.0.1` with source `10.10.10.16`; the VLAN 40 route must
use `guest0` through `10.158.86.1` with source `10.158.86.2`.

Check private DNS and public HTTPS identity from a tailnet member:

```bash
set -o pipefail
test "$(dig +short agentcompute01.glab.lol A)" = '10.10.10.16'
openssl s_client \
  -connect agentcompute01.tailda715.ts.net:443 \
  -servername agentcompute01.tailda715.ts.net \
  -verify_return_error </dev/null 2>/dev/null |
  openssl x509 -noout -issuer -subject -dates -ext subjectAltName

test "$(curl -sS -o /dev/null -w '%{http_code}' \
  https://agentcompute01.tailda715.ts.net/)" = '401'
```

The certificate must validate through the workstation's default public trust
and contain `agentcompute01.tailda715.ts.net` in its subject alternative names.
Do not pin the automatically renewed Tailscale Serve leaf.

Finally, make an authenticated MCP initialization request without putting the
bearer token in the process arguments:

```bash
OMP_TOKEN="$(sops --decrypt --extract '["auth_tokens"]["omp"]' "$SECRETS_FILE")"
cat >"$AGENTCOMPUTE_CREDENTIALS/initialize.json" <<'JSON'
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"deployment-check","version":"1"}}}
JSON

printf 'header = "Authorization: Bearer %s"\n' "$OMP_TOKEN" |
  curl --config - --fail-with-body --silent --show-error \
    -H 'Accept: application/json, text/event-stream' \
    -H 'Content-Type: application/json' \
    --data-binary @"$AGENTCOMPUTE_CREDENTIALS/initialize.json" \
    https://agentcompute01.tailda715.ts.net/
unset OMP_TOKEN
```

Require a successful `initialize` result naming `agentcompute` before declaring
the MCP endpoint accepted. A healthy systemd unit, valid TLS, and an HTTP `401`
without a token do not prove authenticated MCP handling.

### Phase 9b qualification — 2026-09-16

Live qualification used the deployed HTTPS endpoint, normal certificate validation,
and the SOPS-managed `omp` identity from fresh workstation processes. The
initial network, TTL, snapshot, and Windows checks ran on v0.1.2; Mac rollout
and the later restart/concurrency checks ran on
[`v0.1.3`](https://github.com/GilmanLab/agentcompute/releases/tag/v0.1.3),
commit `d85426b72257998a339b91f854c8928ca9d3e361`. Its Linux amd64 SHA-256 is
`d7e8e5229e7299612f858ba6d39718d402fc3b80017cbe3da0c7c0e2a6859c63`;
the checksum and exact-tag/commit GitHub attestation passed before installation.

The final deployed release is
[`v0.1.4`](https://github.com/GilmanLab/agentcompute/releases/tag/v0.1.4),
commit `18c881ae6c854030bfed8115ac50d51c221b0151`, Linux amd64 SHA-256
`fc9394427e573132a2461f7764c23bc0448bbceecd2bbfdd1f901f5b636dc8be`.
Its exact-tag/commit attestation, checksum manifest, immutable release, and
release-asset verification passed. The applied upgrade changed only the
service's public cloud-init metadata and release outputs; the installer
converged the public runtime bundle without replacing the VM or credentials.

| Contract | Observed result |
| --- | --- |
| One-minute TTL with a running VM | `p9b-ttl` expired at `02:04:44Z`; absent at `02:05:07.499Z`, 23.499 seconds later. `ac-p9b-ttl` was also absent from Incus project listing. |
| LAN-only client through guest NAT | Client `192.168.50.3` had only its LAN NIC and used router `192.168.50.2`. Verified HTTPS returned `200`; WAN capture showed source `10.99.0.2`, the router's WAN address. |
| Cross-member OVN and workstation forward | `lab01` and `lab02` containers exchanged three of three pings in each direction. Workstation HTTP to `10.10.40.67:8080` returned `p9b-final-forward`. |
| Isolated networks | `network=none`, `ipv4.nat=false`, and no external allocation. Direct lab/internet pings failed; intentional `net.peer` traffic succeeded both ways. A forward on an isolated network returned `AgentError`. |
| External-address budget | The representative sandbox held `.69` for default NAT, `.70` for WAN NAT, and `.71` for its forward; LAN held none. The service network separately held `.65`. Eight such sandboxes use 24 addresses, leaving 39 after the service's one address. |
| Snapshot semantics | Restore recovered the original file contents and returned `Running` with the same name but a different UUID, MAC, and DHCP address; all original snapshots were consumed. Separate create/list/delete checks retained only the named snapshot until its deletion. |
| Windows ready screenshot | Three initial captures took 1.146, 1.150, and 1.148 seconds. After a later service restart, readiness took 6.182 seconds and the subsequent real desktop capture took 1.379 seconds. |
| Restart rediscovery | `systemctl restart agentcompute.service` preserved discovery of all four then-existing sandboxes: three Incus and one Mac, with the same ten-instance total and expiry metadata. |
| Eight blocking executions | Eight simultaneous `sleep 5` programs returned their distinct results successfully. Tool times were 5.671–6.015 seconds; total workstation wall time, including client setup, was 7.381 seconds. |
| Mac lifecycle | HTTPS create returned Running in 44.992 seconds; `sw_vers` reported macOS 26.6.2 / 25G83; Driver 0.28.1 was ready; the 1920×1200 screenshot showed the desktop. Instance and sandbox deletion left only the stopped seed in Lume. |
| No-VNC boundary | Sampling began before the Mac create request and continued through Running. The first 1,000 listener observations contained only account-owned `127.0.0.1:7777`, no guest VNC listener. PF filter/NAT rules, the global Lume digest, and owner `rapportd` listeners were unchanged. |
| Fresh-shell operation | The runbook's service, routing, Serve, DNS, public TLS, unauthenticated `401`, and SOPS-authenticated initialization commands passed under `bash --noprofile --norc` with a minimal environment. |
| Fresh discovery-only workflow | On v0.1.4, an independent agent starting with `search_api` created `p9b-final`: NAT WAN `10.77.9.0/24`, isolated LAN `10.77.10.0/24`, dual-NIC router, and LAN-only Ubuntu desktop at `10.77.10.3`. It configured guest routing/DNS, verified HTTPS to `example.com`, listed applications, and captured the desktop without patching the image. The returned 1280×800 full-desktop image was visually verified over HTTPS. |
| Final fleet drift | OpenTofu reported `No changes. Your infrastructure matches the configuration.` with detailed exit code `0` after the v0.1.4 installation. |

A separate isolated HTTP fault fixture exercised the actual Incus SDK and
restore adapter without faulting the deployed cluster. Stop failure retained
the running original and snapshot; copy failure retained them with the original
stopped; delete failure retained the stopped original plus staged copy;
rename failure retained the staged copy; start failure retained the stopped
replacement under the original name. The success control returned that
replacement Running. All six cases passed; the temporary harness was removed.

Windows's persistent guest MCP session has a cold-start cost. A direct first
screenshot after restart, without a new readiness probe, took 5.275 seconds.
The sub-two-second result is measured **after readiness**, not a cold-call
latency guarantee.

### Phase 9a qualification — 2026-09-15

- Deployed [`v0.1.1`](https://github.com/GilmanLab/agentcompute/releases/tag/v0.1.1),
  commit `e1a13b7d9e95c287be3f35c797b1511732d1b0b6`. The Linux amd64
  SHA-256 is `1a3c63ee3fc3edf4a3b65c9198c47aa343ff1361f1f6de91fa0b9b6f027cda60`;
  checksum, exact-tag/commit GitHub attestation, and immutable release-asset
  verification passed before use.
- OpenTofu reported no changes. The Ubuntu VM runs on `lab01`; routed
  management reaches the pinned API without changing host `strict_hwaddr` or
  the bond. A sandbox forward at `10.10.40.68:5900` returned
  `RFB 003.008` to the service over `guest0`.
- HTTPS validated through the default public trust store with a Let's Encrypt
  certificate for the service hostname. Missing and invalid tokens returned
  `401`; an authenticated cross-origin request returned `403`.
- Authenticated MCP initialization, `search_api`, `describe_api`, and `execute`
  passed. A Linux desktop VM reached readiness, listed applications, launched
  Text Editor, and returned a window screenshot through the HTTPS base URL.
  Its project recorded `user.agentcompute.subject=omp`.
- Credential redelivery restarted the service. A fresh MCP session rediscovered
  the running desktop and a five-minute sandbox. That short-lived sandbox,
  created at `23:02:52Z` with expiry `23:07:52Z`, disappeared automatically;
  direct Incus lookup then returned `Project not found`.
- Explicit desktop sandbox deletion removed its resources and revoked a fresh
  screenshot URL (`404`). No qualification sandboxes remained.
- Studio accepted the dedicated key from `100.65.152.20`, with normal shell
  access as `agentcompute`, and rejected the same key from Studio's own source
  with `Permission denied (publickey)`.

Two findings informed the later qualification:

1. `v0.1.0` rejected Tailscale Serve's preserved public `Host` header on the
   loopback listener. `v0.1.1` permits that path only with configured bearer
   authentication, while retaining cross-origin protection and the host guard
   for unauthenticated loopback servers.
2. Whole-desktop capture returned a black `1280×800` image even after Text
   Editor launched. Explicit window capture rendered the editor correctly
   (`822×642`), and accessibility state was available. Phase 9a did not qualify
   whole-desktop capture. Phase 9b traced this to the Driver's cosmetic cursor
   overlay freezing X root reads, including VNC; see the
   [implementation outcome](../designs/agentcompute.md#runtime-and-image-contract-details).

## Operate the Mac backend

The host is the owner's `studio-1` Mac Studio, not a dedicated appliance.
Use only the hidden standard `agentcompute` account, its Lume store, and its
loopback daemon. Do not grant it administrator access or access to the owner's
home. The stopped seed is `ac-seed-macos-tahoe-desktop`; it is private and must
not be published. Two running macOS guests is the host-wide limit.

### Install and activate the no-VNC build

Lume 0.5.3 has no VNC-disable option. The temporary source build is pinned in
[`agentcompute/pins/lume.yaml`](https://github.com/GilmanLab/agentcompute/blob/master/pins/lume.yaml).
It records upstream commit `ab957bdb7566f7e137b00654cc01167d9e42af38`,
the actual signed Mach-O SHA-256, toolchain, dependency lock, and release
fallback. `--version` still prints `0.5.3`; that is **not** artifact verification.
The measured clean build is not bitwise reproducible. A checksum mismatch
requires a reviewed re-pin, not skipping the installer check.

From the owner account, stage only the public build inputs outside the
protected home, then build as `agentcompute`:

```bash
LUME_STAGE="$(mktemp -d /tmp/lume-build.XXXXXX)"
mkdir -p "$LUME_STAGE/images/macos" "$LUME_STAGE/pins"
cp "$AGENTCOMPUTE_DIR/images/macos/build-lume.sh" \
  "$AGENTCOMPUTE_DIR/images/macos/lib.sh" "$LUME_STAGE/images/macos/"
cp "$AGENTCOMPUTE_DIR/pins/lume.yaml" "$LUME_STAGE/pins/"
chmod -R a+rX "$LUME_STAGE"
sudo -u agentcompute -H "$LUME_STAGE/images/macos/build-lume.sh"
rm -rf "$LUME_STAGE"
```

The installer refuses root and writes only beneath `/Users/agentcompute`.
The launcher is `/Users/agentcompute/bin/lume`; the signed executable is
`/Users/agentcompute/.local/share/lume/lume.app/Contents/MacOS/lume`.
Leave `/usr/local/bin/lume` and its global app bundle untouched.

With every backend worker stopped and the seed stopped, repoint only the
existing account daemon. Preserve its `UserName`, `HOME`, log paths, and
KeepAlive settings. Back up the plist first. Replace the whole argument array;
do not insert another executable as an extra argument:

```bash
plist=/Library/LaunchDaemons/io.gilman.agentcompute.lume-serve.plist
sudo plutil -replace ProgramArguments -json \
  '["/Users/agentcompute/bin/lume","serve","--port","7777"]' "$plist"
sudo launchctl bootout system/io.gilman.agentcompute.lume-serve
sudo launchctl bootstrap system "$plist"
sudo lsof -nP -a -u agentcompute -iTCP -sTCP:LISTEN
```

Require only `127.0.0.1:7777` for the lifecycle API. Probe a unique,
nonexistent, colon-free name with a deliberately conflicting policy:

```bash
curl --silent --show-error --write-out '\nHTTP %{http_code}\n' \
  --json '{"noDisplay":false,"vnc":"disabled"}' \
  "http://127.0.0.1:7777/lume/vms/ac-vnc-policy-probe-$(uuidgen)/run"
```

Require HTTP `400` and `VNC is disabled for this run`. The pinned daemon
validates this before any VM operation. Old 0.5.3 ignores the policy and returns
`202`; that is a failed gate, not permission to run a worker.

No PF configuration is installed. A blanket high-port block was rejected
because it could disrupt LAN Continuity and `rapportd`; dynamic port watching
would leave a pre-discovery exposure window. Preserve Internet Sharing and
Apple's live PF anchors. Sample `lsof` continuously from a real backend run
request through Running: no account-owned per-VM VNC listener may appear, and
Lume inventory must report `vncUrl: null`.

### Deliver permanent runtime configuration

Fleet's `lume_host` is Studio's verified tailnet IPv4, `100.122.142.76`.
The fleet module supplies `studio_known_hosts` and `mac_guest_known_hosts`;
the latter pins the qualified seed's SSH key by seed-name `HostKeyAlias`,
not a reusable DHCP address. Verify pins through the already trusted host/seed,
never accept a fresh key merely because `ssh-keyscan` returned it.

Stage the qualified seed's guest key from Studio in the owner-only credential
directory. It is separate from the service-to-Studio SSH key:

```bash
sudo cat /Users/agentcompute/.ssh/guest_ed25519 \
  >"$AGENTCOMPUTE_CREDENTIALS/mac-guest.key"
chmod 0600 "$AGENTCOMPUTE_CREDENTIALS/mac-guest.key"
cd "$FLEET_DIR/incus/agentcompute"
just deliver-lume-key "$AGENTCOMPUTE_CREDENTIALS/mac-guest.key"
```

Review and apply the fleet plan with `lume_host` enabled and the release's
catalog, including `macos/tahoe/desktop`. Install the verified compatible
release to converge the public runtime bundle and load the new credential.
Require a clean plan, successful authenticated initialization, Mac create,
`sw_vers`, `desktop.screenshot`, and delete through deployed HTTPS. A temporary
systemd override is not permanent backend rollout.

### Manual console and guest re-consent

`desktop.screenshot` is the normal observation path. There is no automatic VNC
fallback. If a human needs a console, stop the exact guest, then **start it by
hand with VNC enabled**, for example as the confined account:

```bash
sudo -u agentcompute -H /Users/agentcompute/bin/lume run \
  <exact-stopped-guest-name> --no-display --vnc enabled
```

This deliberately opens Lume's wildcard VNC listener for the maintenance
session. Treat its URL/password as a secret; do not leave it running unattended
or expose it on an untrusted LAN. Stop it afterward and return normal workers
to the backend's disabled-VNC start path.

For lost desktop permissions, have the operator open the **guest's** System
Settings → Privacy & Security. Re-enable CuaDriver under Accessibility and
Screen Recording; add `/Applications/CuaDriver.app` to Screen Recording if
absent. Let the operator authenticate and approve each permission. Do not
modify TCC databases, grant owner-host permissions, or automate consent.
Restart the guest's `com.trycua.cua_driver_daemon` LaunchAgent, then recheck
Driver readiness and a real screenshot. Qualify a disposable clone through the
deployed MCP endpoint: `desktop.info` must report readiness, `sw_vers` must
identify the expected release, and `desktop.screenshot` must show the desktop.
Then delete the clone and retain the stopped seed. The legacy
`images/macos/provision.sh` and `verify.sh --clone` scripts still assume
`lume ssh`; they are not a qualified rebuild or recovery path.

Return to an account-local release pin once an upstream Lume release includes
[cua#3209](https://github.com/trycua/cua/pull/3209). Retire the source-build
procedure then, while retaining disabled-VNC enforcement. Falling back to the
old global 0.5.3 binary requires disabling the Mac backend; it is not an
equivalent console-safe release.

## Routine operations

### Inspect and restart

```bash
incus exec --project default nas01:agentcompute01 -- \
  systemctl status agentcompute.service --no-pager
incus exec --project default nas01:agentcompute01 -- \
  journalctl -u agentcompute.service -n 100 --no-pager
incus exec --project default nas01:agentcompute01 -- \
  systemctl restart agentcompute.service
incus exec --project default nas01:agentcompute01 -- \
  systemctl is-active agentcompute.service
```

A restart disconnects active MCP sessions. The new process reconnects to Incus,
reconciles the pinned image catalog, rediscovers persisted sandboxes, and runs
an immediate reaper scan before the next 30-second interval. Do not start a
second process to preserve sessions during the restart.

### Check TTL cleanup

Discover `sandbox.create`, `sandbox.get`, `instance.create`, and
`sandbox.list`; create a uniquely named one-minute sandbox with a small
running guest. Record the returned `expires_at`. Poll from fresh MCP sessions
until it disappears, then check the backend:

```bash
incus project list nas01: --format=json
```

The corresponding `ac-<name>` project must be absent within two minutes after
expiry, not merely hidden from the MCP list. For Mac sandboxes, also inspect
the confined account's Lume inventory and sandbox metadata. A restart must
still rediscover unexpired sandboxes and reap expired ones. Do not infer
cleanup from a successful HTTP response alone.

### Recover a stuck sandbox

1. Describe and call `sandbox.get` and `instance.list`. Capture the sandbox
   name, expiry, guest state, and operation error, without bearer tokens or
   screenshot URLs.
2. Check `journalctl -u agentcompute.service` and the matching Incus operation
   or account-local Lume log. A slow clone/boot is not itself a stuck delete.
3. Use `sandbox.delete` first; it owns ordered resource cleanup. If it fails,
   retry after resolving the reported backend problem. Do not create a second
   project with the same name or delete shared OVN resources.
4. Before direct backend cleanup, verify the exact `ac-` project and
   `user.agentcompute.*` ownership/expiry metadata. Stop or delete only its
   instances, forwards, and networks, then its project. On Studio, operate
   only on the named backend clone and metadata; never the stopped seed or
   another user's VM.
5. Recheck both MCP and backend inventory. A transient not-found error during
   concurrent expiry is different from residual backend resources.

### Upgrade the release

Update `service_version` and `service_sha256` together in
`release.auto.tfvars`. Verify the new release with the procedure above, review
and apply the saved OpenTofu plan, then run `just install-release` with the
verified asset. A release-pin plan must not replace the VM. The script reads
`release_installer` from applied state, replaces the VM-side installer, and
stages the asset. After digest and embedded-version verification, it installs
the public runtime bundle (config, catalog, SSH pins, and unit) and binary,
then restarts an already-running service. It never overwrites credentials,
network configuration, certificates, or Tailscale state. It needs initialized
state and `lab-admin` AWS access, but no reboot or VM replacement. Network and
bootstrap changes still require a deliberate replacement; changing cloud-init
metadata alone does not converge the live VM. Keep the previous versioned
binary until the new endpoint passes full verification.

### Rotate credentials

Update and merge the SOPS file before changing the running service.

- **Bearer token:** materialize the new `auth_tokens` object, update the MCP
  client for the same maintenance window, then redeliver all three private
  inputs. Delivery restarts the unit. The identity name remains `omp`; token
  values never belong in logs or documentation.
- **Studio SSH key:** first authorize the new public key with the exact service
  source in the [Studio SSH runbook](agentcompute-studio-ssh.md). Redeliver all
  three inputs; delivery restarts the unit. Verify the Studio connection, then
  remove the old public key.
- **Incus client certificate and key:** enroll the new dedicated certificate
  before stopping the old identity. Update the public-certificate OpenTofu
  input and perform a deliberate VM replacement so cloud-init installs the new
  public half; then install, deliver, enroll, and verify in the documented
  order. Remove the old trust entry only after full acceptance.
- **Tailscale OAuth client:** rotate the encrypted OAuth fields. It affects only
  future one-time enrollment keys and does not require a service restart.

## Rollback and recovery

For a release regression, return `release.auto.tfvars` to the last accepted
version and digest, review and apply the plan, then install that verified asset
through `just install-release`. Confirm the embedded tag commit and repeat the
full verification procedure. Do not point the symlink at an unverified file.
With `lume_host` enabled, retain agentcompute **v0.1.3 or newer**: older releases
do not enforce disabled VNC. Disable the Mac backend before deliberately
rolling back below that boundary; never silently substitute the global Lume
0.5.3 binary or enable VNC to make a rollback start.


For a VM replacement, use a saved plan with an explicit replacement and expect
to lose the VM's tailnet node identity and delivered files:

```bash
tofu plan -replace=incus_instance.service -out=tfplan
tofu show tfplan
tofu apply tfplan
```

After cloud-init completes, install the release, deliver the Mac guest key if
Lume is enabled, then deliver the three base credentials to start the unit.
Before enrollment, remove the old, offline `agentcompute01` device from the tailnet so
the replacement can receive the exact MagicDNS name. Then enroll and run the
full verification. Never accept a collision name such as `agentcompute01-1`;
the enrollment script refuses to publish Serve under that name.

If exposure must stop immediately, remove Serve without changing the loopback
service or deleting state:

```bash
incus exec --project default nas01:agentcompute01 -- tailscale serve reset
```

After resolving the incident, re-publish the existing loopback service with:

```bash
incus exec --project default nas01:agentcompute01 -- \
  tailscale serve --bg --https=443 http://127.0.0.1:8080
```

Stop and escalate if the saved plan changes shared OVN or host networking, the
Incus certificate does not match `agentcompute01`, the VM cannot reach the
pinned API, a non-loopback port `8080` listener appears, the node has an
unexpected tag, an unauthenticated request is not `401`, the authenticated MCP
initialization fails, or expired sandboxes survive a service restart and reaper
interval.
