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
file-API pull took 0.21 seconds; visual inspection showed the Windows desktop
and Start menu. This demonstrates the transport mechanism on the unsealed
golden source. It does not yet establish the production `desktop.screenshot`
latency or fresh-clone promotion gate.

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

## Windows execution references

Incus requires the agent CD (`source=agent:config`) at every boot to refresh
credentials. Windows guest commands use `cmd.exe /c`; PowerShell is an explicit
command chosen by the caller. The Driver CLI proxies through
`\\.\pipe\cua-driver` to a daemon in an interactive session, not the Incus
agent's service session. Guest screenshot bytes must travel through the file
API rather than text exec output.

Native Incus exec preserved `cmd.exe /c exit /b 37` as exit code 37 and
PowerShell `exit 23` as exit code 23. Windows PowerShell 5.1 used output code
page 437 by default: `Write-Output ([char]0x03a9)` emitted byte `EA`, which is
not UTF-8. Explicitly setting
`[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding`
emitted `CE A9` for the same character. Text callers must select UTF-8 when
returning non-ASCII output; the transport must not assume the default Windows
code page is UTF-8. Raw measurements are in
`/tmp/phase7-windows-exec-semantics.json`.

Sources:

- [Incus VM installation and agent CD](https://linuxcontainers.org/incus/docs/main/howto/instances_create/)
- [Incus software TPM](https://linuxcontainers.org/incus/docs/main/reference/devices_tpm/)
- [Cua Windows session guide](https://cua.ai/docs/how-to-guides/driver/windows-ssh.md)
- [Microsoft FirstLogonCommands concurrency](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-firstlogoncommands)
- [Microsoft Sysprep options](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/sysprep-command-line-options?view=windows-11)
