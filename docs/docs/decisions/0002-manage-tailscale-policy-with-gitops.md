---
status: accepted
date: 2026-08-18
---

# ADR-0002: Manage the Tailnet Policy File with GitOps

## Context and Problem Statement

The tailnet policy file controls tag ownership, auto-approved subnet routes,
network access rules, and Tailscale SSH access. Editing it in the Tailscale
admin console leaves no reviewable history, no validation before a change takes
effect, and no relationship to the repository that owns the network
implementation. Where should the policy file live, and how should it reach the
tailnet?

## Decision Drivers

- Keep the policy under review and version control with the rest of the network
  implementation.
- Validate a policy change before it reaches the tailnet.
- Avoid storing a long-lived Tailscale credential in the repository or in CI.
- Keep the operational surface small enough for a single-owner lab.

## Considered Options

- Track the policy file in `GilmanLab/networking` and sync it with Tailscale's
  `gitops-acl-action`.
- Continue editing the policy in the Tailscale admin console.
- Manage the policy with the Tailscale Terraform provider.
- Track the policy in a dedicated private repository.

## Decision Outcome

Track the policy file at `tailscale/policy.hujson` in `GilmanLab/networking` and
sync it with the `tailscale/gitops-acl-action` GitHub Action: validate on pull
requests, apply on merge to `master`. Authenticate with a Tailscale workload
identity federation credential holding the `policy_file` scope, so CI exchanges
a GitHub OIDC token for a short-lived API token and no long-lived secret is
stored.

Git is the source of truth. Admin console editing is disabled through **Prevent
edits in the admin console**, with an external reference pointing at the policy
file. An operator may still use **Edit anyway** for an emergency change, and the
next apply overwrites it.

The policy file carries no user email addresses, so the repository stays public.
Adding a rule, group, or test that names an individual user requires revisiting
that assumption.

### Consequences

- Good, because every policy change is a reviewable diff with history.
- Good, because an invalid policy fails on the pull request instead of on the
  tailnet.
- Good, because CI holds no long-lived Tailscale credential.
- Good, because the policy sits beside the network implementation it governs.
- Bad, because applying a change now depends on GitHub Actions availability.
- Bad, because an emergency console edit is silently discarded by the next
  apply, so it must be carried back into git.
- Bad, because a policy change and its documentation live in two repositories
  and must be merged as companion changes.

### Confirmation

The implementation conforms to this decision when:

- `tailscale/policy.hujson` in `GilmanLab/networking` matches the policy served
  by the tailnet.
- `.github/workflows/tailscale-acl.yml` runs the action with `action: test` on
  pull requests and `action: apply` on `master`.
- The workflow authenticates with `oauth-client-id` and `audience`, and the
  repository holds no Tailscale API key or OAuth secret.
- **Prevent edits in the admin console** is enabled, with an external reference
  to the policy file.
- The policy file contains no user email addresses.

## Pros and Cons of the Options

### GitOps in `GilmanLab/networking`

- Good, because the policy is reviewed and versioned with the network
  implementation.
- Good, because Tailscale validates the whole policy on every pull request.
- Bad, because it adds a CI dependency to a change that used to be a console
  edit.

### Admin Console Only

- Good, because it needs no tooling and applies changes immediately.
- Bad, because it has no diff, no review, and no history beyond the console's
  own audit trail.
- Bad, because there is no validation step separate from applying the change.

### Tailscale Terraform Provider

- Good, because it could manage the policy alongside other Tailscale resources
  such as trust credentials and DNS settings.
- Bad, because it requires state storage and a Terraform toolchain for a single
  file.
- Bad, because it expresses the policy through provider resources rather than
  the policy file Tailscale documents.

### Dedicated Private Repository

- Good, because it matches Tailscale's guidance for policies containing user
  email addresses.
- Bad, because it separates the policy from the network implementation and its
  review flow.
- Bad, because it adds a repository to maintain for one file, while this policy
  contains no personal data.

## More Information

See the [Tailscale policy reference](../reference/networking/tailscale-policy.md)
for the tailnet's tags, routes, and credential inventory, and the
[Tailscale policy change runbook](../runbooks/tailscale-policy-change.md) for
the change, rollback, and emergency procedures. Tailscale documents the
mechanism in [GitOps for Tailscale with GitHub Actions](https://tailscale.com/docs/integrations/github/gitops).
