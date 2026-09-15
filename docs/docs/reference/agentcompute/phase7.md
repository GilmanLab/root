# agentcompute Phase 7 qualification

This report records the Windows image and router experiments started on
2026-09-14. It is an execution report, not an amendment to the design draft.

## Media and distribution decisions

The owner authorized official evaluation media for Windows 11 Enterprise and
Windows Server 2025, then explicitly authorized unattended acceptance of both
evaluation license agreements. These are expiring test images, not production
entitlements. Windows media and captured disks remain outside Git. Windows
images must never be published to a registry, including a private registry.

Windows 11 Enterprise evaluation build 26200.6584 matched Microsoft's published
SHA-256:

```text
a61adeab895ef5a4db436e0a7011c92a2ff17bb0357f58b13bbc4062e535e7b9
```

No Microsoft-published SHA-256 was found for the selected Server 2025 evaluation
build 26100.32230. The owner approved pinning the measured digest of the exact
ISO from Microsoft's official HTTPS download endpoint:

```text
7b052573ba7894c9924e3e87ba732ccd354d18cb75a883efa9b900ea125bfd51
```

That Server digest is **measured, not Microsoft-published**. The exception applies
to this build and these bytes, not to future media. Input URLs, versions, hashes,
and provenance belong in `agentcompute/images/windows/pins.lock.yaml`.

## Cluster-local catalog namespace

The existing reconciler imports qualified Linux images into the `image-build`
project. Windows aliases use that same namespace; no new shared image project is
needed. An `alias:` entry resolves to a fingerprint there, then the existing
private-image copy path creates the sandbox-local association before launch.
An alias is not a sandbox-local published image merely because it has no
registry reference.

The first live alias-only smoke used the existing `image-build/router` alias.
Through the production stdio MCP server it created `p7-alias-smoke`, launched a
router, executed `printf alias-clone-ok`, and deleted the sandbox. The program
completed in 7.454 seconds with exit code 0 and stdout `alias-clone-ok`. This
proves the alias resolution and cross-project copy path; it is not Windows
clone qualification. Local evidence:
`/tmp/agentcompute-phase7-alias-evidence/08.json`.

## Representative topology prerequisite

The draft's representative program is retained unchanged. Its `wan` network is
attached as guest NIC `eth1`; `wan` is not the guest NIC name. The NAT invocation
is `/opt/router/nat --mode port-restricted --inside eth0 --outside eth1`.

OVN DHCP on the isolated `lan` supplies the logical router at `.1` as the default
gateway. The program does not replace the client's route with a route through
`rtr`. NAT and impairment measurements therefore require an explicit subsequent
`instance.exec` setting `ip route replace default via <rtr-LAN-address>` on the
client. The helper must not seize `.1` or silently modify another instance.

The router also retained the LAN DHCP default ahead of its WAN DHCP default.
The explicit follow-up selected its WAN egress with
`/opt/router/route --to default --via 10.99.0.1 --dev eth1`. The Ubuntu desktop
image did not contain `ping`; the disposable client received `iputils-ping`
and a reachable DNS server before measurement.

## Router qualification

The unchanged representative program completed in **37.782 seconds**, returning
both router NICs, 190 application/process entries, and a fetchable 1280 × 800
PNG. No shared `router` alias was moved.

The final local router build produced an 11,683,284-byte unified image, with
44,479,971 decoded bytes. Download/verification took 7.972 seconds, pinned
distrobuilder compilation 31.766 seconds, and assembly 1.170 seconds. Its
fingerprint is:

```text
d10fff199809da10f04565f1a6a932ef77e0252efec48fb6fe68ae6e5f26d111
```

It was imported under the cluster-local qualification alias
`image-build/router-phase7-qualified` and booted as a fresh router. This is
qualification evidence, not a registry release or a change to the production
Linux catalog digest.

### Packet and impairment results

The client was `192.168.50.3`, router WAN `10.99.0.2`, and observer `10.99.0.3`.
WAN `tcpdump` showed `10.99.0.2 > 10.99.0.3` ICMP requests, not the client's
LAN source. Production MCP `net.impair` supplied the following measurements:

| State | Packets sent/received | Observed loss | Mean RTT |
| --- | ---: | ---: | ---: |
| Baseline | 100/100 | 0% | 0.444 ms |
| 100 ms delay, 5% configured loss | 200/192 | 4% | 100.725 ms |
| Cleared | 100/100 | 0% | 0.626 ms |

`tc` reported `delay 100ms loss 5%` and eight dropped packets. Clearing restored
the router's `noqueue` root; clearing again succeeded. The Starlark binding
requires a float for loss, for example `loss_percent=5.0`, not integer `5`.
Negative loss and an unknown NIC returned agent-visible errors.

The UDP probe rejected replies from an uncontacted remote port and an
uncontacted remote address, then accepted each after the client contacted it.
An initial implementation still let unsolicited packets addressed to the
router itself occupy conntrack tuples: one client source port mapped to
40000, then 61583. The corrected helper drops unsolicited WAN INPUT packets
before confirmation, while permitting DHCP replies. On the final baked image,
all three contacted endpoints used translated port 40020.

The first probe after replacing the router timed out while the observer's
neighbor entry was `FAILED`. A router-to-observer reachability probe succeeded;
the subsequent complete UDP probe passed. The report does not treat that first
attempt as a pass.

### Privilege and helper boundaries

The production sandbox had `restricted=true`, low-level container configuration
blocked, nesting blocked, and privilege restricted to `unprivileged`. The
router's UID map was `0 1000000 1000000000`; nftables, `tc`, and WireGuard worked
without relaxing the project.
These network changes require `CAP_NET_ADMIN` inside the container's network
namespace. Successful execution under those restrictions establishes that the
router does not require `security.privileged=true` or host-namespace privileges.

NAT and route reruns succeeded. DHCP reruns on an isolated dummy interface
replaced only the helper-owned daemon. A planted PID belonging to `sleep` was
rejected and the unrelated process remained alive. The DHCP helper was not
left competing with OVN DHCP.

Raw evidence is in `agentcompute/spikes/phase7-router/integration-evidence.json`.
The `nat-repro` sandbox was deleted after qualification.

## Guest NIC and Linux capture findings

The Ubuntu VM named its configured `eth0` device `enp5s0`. Matching only names
lost its IP address. The backend now matches observed interfaces by MAC while
preserving the configured NIC identity. Live `instance.get` returned
`192.168.50.3`; `net.impair(nic="eth0")` installed netem on `enp5s0`, and clearing
restored `mq`/`fq_codel`. The regression suite also covers a Windows-style
`Ethernet 2` name alongside an unrelated interface named `eth0`.

Full-desktop PNGs were all black both before and after launching Text Editor.
They prove transport and dimensions, not a usable visual desktop. A separate
822 × 642 window capture visibly showed the editor and its New Document tab,
but took 6.128 seconds. These Linux observations do not establish the Windows
capture acceptance gate.

## Windows installation findings

The repack injects VirtIO drivers into both `boot.wim` images and the selected
`install.wim` image. The installer uses Microsoft's `efisys_noprompt.bin`;
distrobuilder's original prompting boot image stopped unattended firmware boot.
The installed root disk has boot priority 10 and the installer has priority 1.
Reversing those priorities restarted Setup from the CD after image application
and produced the interrupted-upgrade dialog.

The implementation uses one installer ISO containing `Autounattend.xml` and
the provisioning payload, rather than a separate payload ISO. The agent CD
remains a separate `agent:config` device.

Two answer-file errors stopped Windows before first logon:

- `Microsoft-Windows-Deployment/Reseal` was placed in `specialize`, where it is
  not valid. It was removed; this bake does not enter audit mode.
- `HideWirelessSetupInHDS` is not a Windows Shell Setup setting. The guest's
  `Panther/UnattendGC/setuperr.log` named that exact setting and reported
  `Setting is not defined in this component`. All installation and deployment
  answer files now use `HideWirelessSetupInOOBE`.

The failed-installation diagnostic shell ran Windows `10.0.26200.6584`.
Starting the Incus agent directly allowed `cmd.exe /c ver` and a file-API pull
of the setup error log. The four staged PowerShell scripts parsed without
errors in Windows PowerShell 5.1. These are diagnostic results, not proof of
unattended bootstrap, Sysprep, or fresh-clone qualification.

The corrected Win11 restage took 65.725 seconds, including 31.560 seconds to
compile distrobuilder and 13.131 seconds for driver injection and ISO
generation. The resulting installer was 7,169,525,760 bytes; import into the
cluster took 178.830 seconds. These are installer measurements, not captured
image size or install-to-capture time.

The corrected answer file reached the Win11 automation desktop without console
input. Bootstrap then failed before agent installation: `New-Item -Force`
attempted to replace the existing BitLocker registry subtree. Policy setup now
creates missing keys without replacing existing ones.

Native Windows PowerShell 5.1 checks exposed two further bootstrap failures:
strict-mode access to a missing `AutoLogonCount` property, and rejection of the
empty pinned-servicing array by a mandatory parameter. The corrected property
lookup returned `null`; the `[AllowEmptyCollection()]` parameter accepted zero
packages. These checks validate the boundary fixes, not the complete bake.

The next unattended bootstrap passed: Incus agent, Cua Driver 0.28.1,
persistent console auto-logon, and UltraVNC installation completed in 34.745
seconds. Controller recovery exposed two transport issues: `--project` placed
after the guest `--` separator became a guest argument, and files copied from
the ISO retained their read-only attribute. The controller now places project
flags before the subcommand; copied scripts are made writable. The SYSTEM
environment also lacked `COMPUTERNAME`, so identity checks use
`[Environment]::MachineName`.

Before sealing, `manage-bde -status C:` reported:

```text
Conversion Status:    Fully Decrypted
Percentage Encrypted: 0.0%
Encryption Method:    None
Protection Status:    Protection Off
Lock Status:          Unlocked
Key Protectors:       None Found
```

The WMI encryption query independently reported conversion status 0 and
encryption percentage 0. Manual event-log clearing failed on an analytic
channel and was removed: Sysprep `/generalize` already clears event logs.
The successful verification report is
`/tmp/phase7-windows-finalize-verified.json`; it is pre-seal evidence, not
fresh-clone qualification.

### Native bake qualification

Installation, native qualification, and production promotion are separate
stages. Both native bakes completed installation, sealing, capture, and
fresh-clone qualification:

| Image | Bake measurements | Qualified image |
| --- | --- | --- |
| Windows 11 desktop | Install-to-agent: 514.8 seconds; agent-to-bootstrap: 31.2 seconds; install-to-bootstrap: 546.0 seconds. Finalize/verify: 93.1 seconds; Sysprep-to-stopped: 92.6 seconds; total seal: 99.4 seconds. | `c437bd3d36d64c2d1682af0543d1c230e5e9be409c1b57a280c38678e6c317d8`, 12,401,757,277 bytes |
| Windows Server 2025 Core | Install-to-bootstrap: 276.2 seconds. Total bake: 662.2 seconds, including 191.7 seconds for capture. | `e60d305082ae461c6111985a009c0971b2da59391449dabf44ec915b5b28d379`, 6,215,643,757 bytes |

The sealing path changed after native testing showed that Sysprep launched as
`SYSTEM` skipped XAML registration. Sysprep now runs from an elevated task
owned by the logged-on administrator, as required by Microsoft's documented
administrator execution context. The controller removes the task after
dispatch. It never boots the generalized source again. Both clone smoke
reports passed `source-sealed-as-interactive-administrator`; each source was
deleted after capture without another boot.

The qualified Win11 clone reached the Incus agent in 6.0 seconds and completed
the smoke script in 11.0 seconds. Its hostname and machine SID both differed
from the source. The source disk was fully decrypted before sealing. On the
clone, the Cua Driver first-logon autostart registration did not survive
Sysprep: it was registered but not running. The deployment bootstrap repaired
the registration idempotently and started the daemon in the interactive
session.

The Win11 clone passed Driver `list_windows`, application enumeration, and a
non-black 1280 × 800 desktop capture. With no console user signed in, an
UltraVNC probe returned `RFB 003.008` in 0.8 seconds. After a reboot, the Driver
recovered in 6.7 seconds. The Win11 bake and native qualification records are:

- `/tmp/phase7-windows-user-final-evidence/windows-11-desktop-bake.json`
- `/tmp/phase7-windows-user-final-evidence/windows-11-desktop-bake-qualified.json`

The Server Core clone reached the Incus agent in 63.0 seconds and completed
its smoke script in 8.2 seconds. Its hostname and machine SID both differed
from the source. The clone identified itself as Server Core, had no
`explorer.exe`, and had neither the Cua Driver nor its proxy. Server Core did
not expose BitLocker capability; the qualification treated the absent
namespace as a determined, unencrypted state rather than desktop decryption
evidence. Its bake record is
`/tmp/phase7-windows-core-user-final-evidence/windows-server-2025-bake.json`.

The fingerprint-bound qualification records passed the promotion gate.
`images/windows/bake.py promote` moved both stable aliases:

| Stable alias | Fingerprint | Size |
| --- | --- | ---: |
| `windows/11/desktop-26200.6584` | `c437bd3d36d64c2d1682af0543d1c230e5e9be409c1b57a280c38678e6c317d8` | 12,401,757,277 bytes |
| `windows/server-2025-26100.32230` | `e60d305082ae461c6111985a009c0971b2da59391449dabf44ec915b5b28d379` | 6,215,643,757 bytes |

Both images are in the shared `image-build` project. `images/catalog.yaml`
contains alias-only rows for both, with no registry digest. Through the
production MCP server, `image.list` returned both with platform `incus`;
`desktop` was `true` for `windows/11/desktop` and `false` for
`windows/server-2025`. Promotion summaries are
`/tmp/phase7-windows-11-promotion-gate.json` and
`/tmp/phase7-core-promotion-gate.json`.

### Windows Driver transport experiment

Incus exec runs as `NT AUTHORITY\SYSTEM` (SID `S-1-5-18`). The Cua daemon ran
as the automation user in Session 2. Direct SYSTEM calls could read status
metadata but failed to open `\\.\pipe\cua-driver` with access denied.

A native launcher obtained the logged-on console user's token and started
the Cua client under that account in Session 0. Keeping the client in
Session 0 preserves standard-handle inheritance; the daemon remains in the
interactive session. No pipe ACL or Cua authorization checks were changed.
`list_windows` returned the automation user's Explorer window and Cua overlay.

Three one-shot Incus calls took 5.891, 6.048, and 3.887 seconds. A persistent
Cua MCP connection through the same launcher initialized in 5.971 seconds,
then `get_desktop_state` wrote a 1280 × 800 PNG in 0.287 seconds. An Incus
file-API pull took 0.21 seconds; visual inspection showed the Windows desktop.
This demonstrates the transport mechanism on the unsealed golden source.
Production transport and latency results are recorded below.

### Capture storage recovery

Sysprep shut down the Win11 source in 20.7 seconds. The first publication
attempt exposed a CLI destination issue: remote publication must name both
the source instance and destination remote when the client has no default
remote. The bake now supplies both explicitly.

The next attempt failed while converting the stopped disk to QCOW2:
`No space left on device` at byte 21,502,094,336. `lab01` had no
`storage.images_volume` setting, so capture scratch used the small IncusOS
system filesystem rather than the VM's `data` pool.

The owner first approved `data/images` on `lab01`. The two-operation deployment
succeeded in 24.84 seconds, and a second run reported no changes. The owner
then explicitly approved the same member-local setting on the other three
members. Capture scratch now uses `data/images` on all four members. The
change preserved three image replicas and the existing OS and VM storage
layout. The generalized source remained stopped throughout recovery.

A later transfer failure included a source IP that was initially read as the
destination. Read-only SQL against the cluster replica records corrected that
interpretation. A successful cross-project copy then confirmed the corrected
source and destination roles.

The deployment is
`fleet/cluster/src/fleet_cluster/deploys/image_cache.py`; the normal storage
runner invokes it after base storage convergence. Its standalone invocation
is `uv run --locked pyinfra inventory.py src/fleet_cluster/deploys/image_cache.py --yes`
from `fleet/cluster`. The full base-storage dry run had previously failed on
its existing OS-pool check (`storage pool data does not exist`); this recovery
did not change OS pools or bypass that check.

## Windows workflow boundary

The public `agentcompute/.github/workflows/windows-images.yml` validates the
source and dispatches its commit to the private
`agentcompute-images/.github/workflows/windows.yml`. The private worker
rejects commits outside public `master` before executing source code. It uses
the existing restricted `image-build` certificate, project, and network; no
permissions are widened.

The private worker shares the existing Linux `image-bake` concurrency group.
Selection `all` bakes Win11 and Server Core serially. Each installer volume must
already exist on the selected member as `<image>-installer`; the publisher
does not download or repack Windows media. It only calls the Incus API.
Neither workflow uploads Windows artifacts or publishes to a registry.

The existing project permits two virtual machines, including stopped ones.
Successful qualification deletes the bake's own golden source before the next
image starts. Candidate images remain cluster-local; a fingerprint-bound
qualification file gates promotion. The workflow definitions passed
actionlint 1.7.12; a GitHub-hosted dispatch has not yet been exercised.

## Production Windows qualification gates

Fresh clones of both promoted aliases passed the production gates.

### Windows 11 desktop acceptance

The Windows 11 gate used a fresh clone of the promoted alias. `instance.create`
took 227.602 seconds. `desktop.info` took 0.890 seconds and reported Cua Driver
0.28.1 ready with VNC at `10.19.37.2:5900`. The first
`desktop.screenshot` took 0.225 seconds and returned a fetchable 1280 × 800 PNG
URL. Visual inspection showed a real desktop without an expired-license
watermark. `desktop.call` with `list_windows` took 0.179 seconds and returned
Explorer, the Cua overlay, and the elevated PowerShell window.

`instance.exec` returned `Microsoft Windows [Version 10.0.26200.6584]`. The
fresh identity was hostname `AGENTCO-PVCDLHE` and machine SID
`S-1-5-21-843443935-4175633203-2814764488`. The guest IPv4 MTU was 1442. From
a disposable Alpine `router` container in the same sandbox, `instance.exec`
read `RFB 003.008` from the clone's port 5900.

The fresh clone reported `Windows(R), EnterpriseEval edition`, license status
1, and 129,596 minutes remaining. Automatic startup activation completed
without an operator command. The gate summary is
`/tmp/phase7-windows-11-promotion-gate.json`; raw MCP records and VNC evidence
are in `/tmp/phase7-prod-gate-evidence` and `/tmp/phase7-vnc-evidence`.

### Screenshot response latency

Before the response-path correction, the first production screenshot took
2.575 seconds, followed by a 2.291-second result. Stage profiling measured
0.067–0.083 seconds for capture, approximately 0.15 seconds for the guest file
pull, and 1.07–1.09 seconds for guest PNG deletion on the response path.

Deletion now runs on a bounded queue that drains when the Driver closes. If
the queue is full or the Driver is closed, deletion falls back to the
synchronous path. The implementation does not cache screenshots or take a
warm-up capture. The first screenshot on the final fresh clone took 0.225
seconds, within the two-second requirement. Earlier transport records are in
`/tmp/phase7-windows-transport-evidence`; the final measurement is in
`/tmp/phase7-prod-gate-evidence`.

### Windows Server 2025 Core acceptance

Creating the Server Core clone in the stopped state took 5.070 seconds.
`instance.start` took 68.779 seconds, including Incus agent readiness and guest
MTU configuration. The clone reported Windows version `10.0.26100.32230` and
installation type `Server Core`. Its fresh identity was hostname
`AGENTCO-F3SL6G6` and machine SID
`S-1-5-21-2702624203-1327223776-16106274`.

The clone had no Cua Driver process. `desktop.info` returned `ready=false` with
no tools. Its guest IPv4 MTU was 1442. The
`Windows(R), ServerStandardEval edition` license reported status 1 and 259,196
minutes remaining. An explicitly authorized operator command activated this
clone before automatic activation was implemented; the Windows 11 gate above
proves automatic activation. The Core summary is
`/tmp/phase7-core-promotion-gate.json`; raw evidence is in
`/tmp/phase7-core-final-evidence` and
`/tmp/phase7-core-confirmation-evidence`.

### Corrections required by production runs

1. **Windows exec quoting.** The Incus guest agent applies Windows CRT quoting
   to argv. As a result, `cmd.exe /c <quoted PowerShell>` executed the command
   as a literal string, returned exit code 0, and echoed the command text. An
   environment-variable carrier preserved quotes but broke CMD percent
   expansion: `echo %SystemRoot%` printed `%SystemRoot%`. The shipped
   `internal/windowsexec` adapter carries a base64 UTF-16LE
   `powershell.exe -EncodedCommand` launcher. Through `ProcessStartInfo`, the
   launcher starts `cmd.exe /d /s /c "<raw command>"` without placing a quote
   or space in any argv element. Native probes returned `Client` from a quoted
   PowerShell registry query, `C:\WINDOWS` from `echo %SystemRoot%`, both lines
   from `echo a & echo b`, `input-through-mcp` from stdin through `findstr`,
   and exit code 7 from `exit 7`. Working-directory selection and separate
   stderr also passed. Evidence is in
   `/tmp/phase7-windows-cmd-launcher-probe.json` and
   `/tmp/phase7-windows-carrier-probe.json`.
2. **OVN MTU.** OVN set `bridge.mtu` to 1442 while Windows kept its NIC at
   1500. Incus 7.3 did not pass `host_mtu` to the guest NIC, so TLS connections
   to Microsoft hung. A controlled request to the same endpoint and IP timed
   out at MTU 1500 and returned HTTP/1.1 403, proving reachability, at MTU
   1442. The reproduction is
   `/tmp/phase7-windows-mtu-reproduction.json`. The backend now reads the
   owned network's actual `bridge.mtu`, matches the guest adapter by MAC, and
   sets IPv4 `NlMtuBytes` after a started create, start, restart, or hot NIC
   attach. After a second network was attached, both `Ethernet` and
   `Ethernet 2` reported 1442; after detach, only `Ethernet` remained. The
   lifecycle proof is in `/tmp/phase7-windows-lifecycle-evidence`.
3. **Evaluation activation.** A fresh clone's first-boot activation ran before
   MTU correction and left the guest unlicensed. The OVN clone reported
   license status 5 with zero grace, unlike the earlier bridge-based native
   clone. The owner explicitly authorized normal Microsoft evaluation
   activation. Windows startup now activates an unlicensed evaluation edition
   after setting the NIC MTU, only on networks with egress through `ipv4.nat`.
   Startup reports activation failures instead of returning a misleadingly
   ready clone. The path uses no rearm, product-key change, clock change, or
   activation bypass. The failed state and authorized recovery are recorded
   in `/tmp/phase7-production-license.json` and
   `/tmp/phase7-production-activation-result.txt`; automatic activation is
   recorded in `/tmp/phase7-prod-gate-evidence`.
4. **Timeouts and transient VM state.** The shared instance-creation budget
   was five minutes, and a cold Windows create failed after 303.9 seconds. The
   budget is now ten minutes; subsequent creates took 224.7 and 227.6 seconds.
   During a guest reboot, Incus reports the VM as `Error` while QMP reconnects.
   This transient state aborted a readiness wait during first logon. The wait
   no longer treats transient VM `Error` as terminal, and regression coverage
   exercises the condition. The completed create is recorded in
   `/tmp/phase7-prod-gate-evidence`; the earlier run is in
   `/tmp/phase7-windows-transport-evidence`.

## Windows execution references

Incus requires the agent CD (`source=agent:config`) at every boot to refresh
credentials. The public Windows `instance.exec` contract accepts a raw command
string. Windows detection applies to OS values whose lowercase form begins
with `windows`.

`internal/windowsexec` launches the raw command as described in the production
correction above. Its observable Windows semantics are:

- Output uses CRLF line endings.
- PowerShell writes its progress stream to stderr as CLIXML even when the
  command succeeds. Callers must use the exit code, not non-empty stderr, to
  determine success.
- Exit codes propagate. CMD operators, percent expansion, stdin, environment
  variables, working-directory selection, and separate stderr work through
  the launcher.

Native Incus exec preserved `cmd.exe /c exit /b 37` as exit code 37 and
PowerShell `exit 23` as exit code 23. Windows PowerShell 5.1 used output code
page 437 by default: `Write-Output ([char]0x03a9)` emitted byte `EA`, which is
not UTF-8. Explicitly setting
`[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding`
emitted `CE A9` for the same character. Text callers must select UTF-8 when
returning non-ASCII output; the transport must not assume the default Windows
code page is UTF-8. Raw measurements are in
`/tmp/phase7-windows-exec-semantics.json`.

The Driver CLI proxies through `\\.\pipe\cua-driver` to a daemon in an
interactive session, not the Incus agent's service session. Guest screenshot
bytes travel through the file API rather than text exec output.

### CodeMode result shape

The CodeMode Starlark validator rejects a program that reads a field absent
from a capability's declared output. It reports only `invalid program`, not
the field name. `instance.get` returns `nics`, with addresses nested under
each NIC; it does not return the top-level `addresses` map exposed by
`instance.create`. The failed field access and the returned shape are recorded
in `/tmp/phase7-starlark-evidence`, `/tmp/phase7-starlark-evidence2`, and
`/tmp/phase7-starlark-evidence3`.

Sources:

- [Incus VM installation and agent CD](https://linuxcontainers.org/incus/docs/main/howto/instances_create/)
- [Incus software TPM](https://linuxcontainers.org/incus/docs/main/reference/devices_tpm/)
- [Cua Windows session guide](https://cua.ai/docs/how-to-guides/driver/windows-ssh.md)
- [Microsoft FirstLogonCommands concurrency](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-firstlogoncommands)
- [Microsoft Sysprep options](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/sysprep-command-line-options?view=windows-11)
