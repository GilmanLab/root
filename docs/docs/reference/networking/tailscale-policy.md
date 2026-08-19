---
title: Tailscale policy
description: Tailnet identity, policy file location, tags, and the credentials that sync the policy.
---

# Tailscale policy

The tailnet policy file is the canonical definition of tag ownership,
auto-approved subnet routes, network access rules, and Tailscale SSH access. It
is applied by CI, not by hand;
[ADR-0002](../../decisions/0002-manage-tailscale-policy-with-gitops.md) records
why. To change it, follow the
[policy change runbook](../../runbooks/tailscale-policy-change.md).

## Tailnet

| Field | Value |
| --- | --- |
| Tailnet ID | `THZctfF8wr11CNTRL` |
| Admin console | <https://login.tailscale.com/admin> |
| Console editing | Disabled through **Prevent edits in the admin console** |

## Source of truth

| Artifact | Location |
| --- | --- |
| Policy file | [`tailscale/policy.hujson`](https://github.com/GilmanLab/networking/blob/master/tailscale/policy.hujson) in `GilmanLab/networking` |
| Sync workflow | [`.github/workflows/tailscale-acl.yml`](https://github.com/GilmanLab/networking/blob/master/.github/workflows/tailscale-acl.yml) |
| Action | [`tailscale/gitops-acl-action`](https://github.com/tailscale/gitops-acl-action), pinned by commit |

The workflow runs the action with `action: test` on pull requests, which sends
the policy to Tailscale for validation, and with `action: apply` on pushes to
`master` and on manual dispatch, which validates and then writes the policy to
the tailnet.

The file is [HuJSON](https://github.com/tailscale/hujson): JSON with comments
and trailing commas. Section syntax is documented in Tailscale's
[policy file reference](https://tailscale.com/docs/reference/syntax/policy-file).

## Tags

| Tag | Purpose | Owner |
| --- | --- | --- |
| `tag:subnet-router` | Devices that advertise lab and home subnet routes into the tailnet | `autogroup:admin` |

A tagged device is owned by its tag, not by the user who registered it. Removing
a tag from the policy while a device still carries it leaves that device without
the access the tag granted.

## Auto-approved routes

The policy auto-approves the following advertised routes for
`tag:subnet-router`, so a replaced or re-registered subnet router needs no
manual approval:

| Range | Scope |
| --- | --- |
| `10.10.0.0/16` | Lab |
| `172.16.0.0/16` | Lab |
| `192.168.1.0/24` | Home |
| `192.168.2.0/24` | Home |

The [network address and VLAN plan](address-plan.md) is canonical for lab
prefixes. Reconcile this list whenever that plan changes.

## Credentials

CI authenticates with a Tailscale
[workload identity federation](https://tailscale.com/docs/features/workload-identity-federation)
credential. GitHub Actions presents an OIDC token, Tailscale exchanges it for a
short-lived API token, and no long-lived credential is stored.

| Field | Value |
| --- | --- |
| Credential type | OpenID Connect trust credential |
| Issuer | GitHub Actions |
| Subject | `repo:GilmanLab@66194346/networking@1334494603:*` |
| Scopes | `policy_file`, with `devices:posture_attributes` and `devices:core:read` |
| Audience | `api.tailscale.com/<client id>` |

The `GilmanLab` organization issues OIDC subjects in GitHub's immutable form,
with numeric organization and repository IDs rather than
`repo:GilmanLab/networking:...`. A subject pattern written with plain names
never matches, and Tailscale rejects the token exchange with HTTP 403 before it
evaluates scopes. The trailing `*` covers both subject shapes CI produces:
`:ref:refs/heads/master` for an apply run and `:pull_request` for a validation
run.

Trust credentials are managed on the
[Trust credentials](https://login.tailscale.com/admin/settings/trust-credentials)
page. The node-registration credential used elsewhere in the lab is a separate
credential with auth key scopes and must not be reused here.

The workflow reads three GitHub Actions **variables** in `GilmanLab/networking`.
None is secret; the client ID and audience are published by the admin console.

| Variable | Value |
| --- | --- |
| `TS_TAILNET` | Tailnet ID |
| `TS_POLICY_CLIENT_ID` | Trust credential client ID |
| `TS_POLICY_AUDIENCE` | `api.tailscale.com/<client id>` |

## Drift

`gitops-pusher`, which the action runs, detects console edits by comparing the
tailnet's policy checksum against a cache file. CI runners are ephemeral and the
action does not persist that cache, so drift detection reports nothing in this
setup. Console editing is disabled instead, and an apply always overwrites the
tailnet's copy with the file in git.
