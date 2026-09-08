---
id: 018
title: Session opened, goal pending
started: 2026-09-08
---

## 2026-09-08 15:42 — Kickoff
Goal for the session: Start a new session; the substantive goal is not yet specified.
Current state of the world: Personal journal resolved to `journal/jmgilman`. Required skills, technical notes, and the latest three closed-session summaries (013, 010, 009) are loaded.
Plan: Commit and push the new session's journal files, bind session 018 to this task, then await the user's actual request.

## 2026-09-08 16:05 — Disposable desktop assessment
User goal: Give any agent on this Mac a repeatable way to acquire a temporary
x86 desktop for GUI testing: Ubuntu Desktop, Fedora Desktop, Arch with KDE,
Windows, and macOS if practical. User proposed golden templates, common test
credentials, and a dedicated Incus project; these guests will never host lab
services. No implementation or provisioning was requested.

User-reported proof: Another development session exercised retained Ubuntu
24.04 GNOME/Wayland and gateway VMs through Incus machine control plus private
CDP to gateway Chromium, Guacamole, and RDP. The agent performed GUI testing
and cleanup; humans approved sensitive actions. Treat this as demonstrated,
not a requirement to reproduce before assessing the extension.

Assessment recommendations, not adopted decisions:
- Use versioned golden images and a fresh VM per job in one desktop-testing
  project. Keep common guest credentials; regenerate machine-specific identity
  on image instantiation. Capture a working image before building a large
  image-factory design.
- Keep Incus for commands/files/lifecycle and the proven Guacamole path for
  graphical interaction. Add a small local lifecycle helper and shared agent
  skill, with a separate connection/browser context per job.
- Ownership metadata, bounded resource use, expiry with an independent
  cleanup process, external evidence collection, and explicit release are the
  useful operational minimum. Do not confuse disposable with Incus
  `ephemeral`: that property deletes an instance when stopped.
- Ubuntu is the existing baseline. Fedora GNOME is a strong candidate.
  Arch Plasma needs an active/autologged-in session for KRdp; prove its
  NLA and GFX/H.264 negotiation through the actual Guacamole build.
- Windows 11 Pro/Enterprise is practical, with VirtIO, TPM/Secure Boot,
  generalized images, appropriate licensing, and a tested UAC interaction
  path. Current Incus documents a Windows guest-agent service; do not assume
  commands/files require a separate Windows control plane.
- macOS on the non-Apple x86 cluster is not the recommended route. Apple's
  Tahoe license restricts it to Apple hardware. A separate Apple-silicon VM
  backend would be ARM coverage, not fulfillment of the x86 requirement.
- Readiness must prove a usable graphical session and input. GUI launches
  must enter the ordinary user's actual session. RDP results do not establish
  physical-console, GPU, or low-level input fidelity.

Research used official Incus, Ubuntu, GNOME, KDE, Guacamole, Microsoft, and
Apple documentation. Context7 lookup was unavailable (quota); direct official
sources were used instead. Local Incus client is 7.3; its default server
reported unreachable, so no live cluster version or VM state was established.
No infrastructure was changed.

Key sources:
- https://linuxcontainers.org/incus/docs/main/howto/images_create/
- https://linuxcontainers.org/incus/docs/main/explanation/projects/
- https://linuxcontainers.org/incus/docs/main/reference/instance_properties/
- https://linuxcontainers.org/incus/docs/main/howto/instances_create/
- https://documentation.ubuntu.com/desktop/en/24.04/how-to/share-your-desktop-remotely/
- https://invent.kde.org/plasma/krdp/-/raw/master/README.md
- https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/sysprep--generalize--a-windows-installation?view=windows-11
- https://www.apple.com/legal/sla/docs/macOSTahoe.pdf

Suggested first experiment: turn the proven Ubuntu desktop into a clean image,
create two independent jobs, exercise the real application and reconnect/reboot
paths, collect evidence, and prove explicit and abandoned-job cleanup. Then
add Windows, Fedora, and Arch, reusing the lifecycle while proving each
desktop-specific readiness adapter. macOS remains a separate scope decision.
