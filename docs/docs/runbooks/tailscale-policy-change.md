---
title: Change the Tailscale policy
description: Change, verify, roll back, or emergency-edit the tailnet policy file.
---

# Change the Tailscale policy

Use this runbook to change the tailnet policy file: tags, auto-approved routes,
access rules, or Tailscale SSH access. Field-level facts live in the
[Tailscale policy reference](../reference/networking/tailscale-policy.md).

## Preconditions

- Write access to `GilmanLab/networking`.
- Owner, Admin, or Network admin on the tailnet, for verification in the admin
  console.
- The repository variables `TS_TAILNET`, `TS_POLICY_CLIENT_ID`, and
  `TS_POLICY_AUDIENCE` are set, and the trust credential behind them is valid.

## Safety impact

An applied policy takes effect on the tailnet immediately and can remove access
from devices and users, including your own Tailscale SSH access. It cannot lock
you out of the admin console, so recovery is always possible. Tailscale
validates the policy before applying it, so a malformed or self-inconsistent
policy fails in CI rather than on the tailnet.

## Procedure

1. Create a branch and worktree in `GilmanLab/networking` from the fetched
   default branch:

   ```bash
   git fetch origin --prune
   wt switch --create --base origin/master --no-cd --format=json <branch>
   ```

2. Edit `tailscale/policy.hujson` in the returned worktree path. Keep comments
   describing intent next to the rules they explain.

3. Commit and push, then open a pull request:

   ```bash
   git push -u origin HEAD
   gh pr create --fill
   ```

4. Wait for the **Tailscale ACL** check and read its result:

   ```bash
   gh pr checks --watch
   ```

   The `Validate policy` step sends the whole file to Tailscale. Failures are
   annotated on the offending line of the policy file. Fix and push again until
   the check passes.

5. Squash-merge the pull request:

   ```bash
   gh pr merge --squash
   ```

6. Watch the apply run on `master`:

   ```bash
   gh run watch "$(gh run list --workflow=tailscale-acl.yml --branch=master --limit=1 --json databaseId --jq '.[0].databaseId')"
   ```

   The `Apply policy` step logs the tailnet checksum, the local checksum, and
   either `no update needed, doing nothing` or a successful write.

7. Remove the worktree:

   ```bash
   wt remove <branch>
   ```

## Verification

- The apply run concluded successfully.
- The [Access controls](https://login.tailscale.com/admin/acls) page shows the
  merged policy.
- The behavior you changed works as intended: for a route change, confirm the
  advertised route on the [Machines](https://login.tailscale.com/admin/machines)
  page; for an access rule, connect from an affected device.

## Rollback

Revert the merged pull request and let the pipeline apply the previous policy:

```bash
gh pr create --title 'revert: <original title>' --fill  # from a revert branch
```

Reverting through GitHub keeps git and the tailnet consistent. Do not undo a
change by editing the admin console.

## Emergency change

If the pipeline is unavailable and access must be restored now:

1. Open [Access controls](https://login.tailscale.com/admin/acls) and select
   **Edit anyway** to bypass the console lock.
2. Make the smallest change that restores access.
3. Carry the same change into `tailscale/policy.hujson` through a pull request
   as soon as possible.

The next apply overwrites the tailnet's copy with the file in git, so an
emergency edit that is not carried back into git is silently lost.

## Escalation

- Validation fails with an error you cannot interpret: check the
  [policy file syntax reference](https://tailscale.com/docs/reference/syntax/policy-file).
- The step fails with `token exchange failed with status 403`: the OIDC token's
  claims do not match the trust credential. Inspect the credential on the
  [Trust credentials](https://login.tailscale.com/admin/settings/trust-credentials)
  page, which records the most recent token exchange error, and compare its
  subject against the
  [expected subject](../reference/networking/tailscale-policy.md#credentials).
  Confirm the repository variables still match the credential.
- The apply step fails on a checksum mismatch: someone edited the policy in the
  console. Reconcile that edit into git, then re-run the workflow.
