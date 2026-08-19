# AWS Migration Plan — glab `infra` → `GilmanLab/aws`

Status: ready for implementation. Drafted 2026-08-18 in session 002 (vision /
sounding-board session). Implementing session: report progress and deviations
back so session 002's tracker (VISION.md, T35) stays current.

Sources: repo evidence in `~/code/glab` and the GlabAwsMigrationAudit brief
(transcript at `history://GlabAwsMigrationAudit`; key facts are inlined below —
this plan is self-contained).

## Goal

Move all six OpenTofu roots that constitute the lab's AWS substrate out of the
deprecated glab-generation `GilmanLab/infra` repo into a new dedicated
`GilmanLab/aws` repo, **preserving all Terraform state and all live resource
identities**. Acceptance for every migrated root: `tofu plan` from the new
repo shows **zero creates, zero changes, zero destroys**.

## Non-goals

- Destroying Keycloak (happens later, only after Zitadel serves — separate task).
- Restructuring `GilmanLab/secrets` (T33, separate task).
- Any resource rename/refactor (`moved` blocks). Pure relocation only.
- Migrating non-AWS glab content (T37, separate audit).

## Facts

| Fact | Value |
| --- | --- |
| AWS account (lab) | `186067932323` |
| Profile | `lab-admin` (SSO; role LabAccountAdmin) |
| Region | `us-west-2` |
| Lab state bucket | `glab-lab-tfstate-186067932323` (manually bootstrapped, versioned, SSE-S3; intentionally outside Terraform) |
| Old account | `340752822076`, profile `jmgilman-prod` (aws-vault), bucket `gilmanlab-tfstate` |
| Source repo | `~/code/glab/infra` → github.com/GilmanLab/infra |
| Destination repo | `GilmanLab/aws` (to be created; wire into lab2 meta `init.sh` like `networking/`) |
| SOPS KMS key (identity-critical) | `arn:aws:kms:us-west-2:186067932323:key/2aba1d94-6eaf-4d80-8d26-2077f32fd7c5`, alias `alias/glab-sops` |
| Root-CA KMS key (identity-critical) | key `5b585512-8604-43ce-b416-90fbd3cffcfa`, alias `alias/glab-pki-root-ca` |

## Root inventory and treatment

| # | Source root | State object | Status | Treatment |
| --- | --- | --- | --- | --- |
| 1 | `infra/aws/lab-foundation` | `s3://glab-lab-tfstate-…/aws/lab-foundation.tfstate` | LIVE (VPC 172.16.0.0/16, IGW/subnet/routes, private zone `glab.lol` `Z009084217D5KKVQERJY3`, public zone `acme.glab.lol`, SOPS KMS key) | Pure move |
| 2 | `infra/security/pki/root-ca` | `s3://glab-lab-tfstate-…/security/pki/root-ca.tfstate` | LIVE (KMS ECC_NIST_P384 SIGN_VERIFY key + alias; committed `root_ca.crt` bound to it) | Pure move |
| 3 | `infra/network/tailscale` | `s3://gilmanlab-tfstate/network/tailscale.tfstate` (**old account**) | LIVE (MagicDNS, split DNS → 10.10.10.1, federated identity for subnet router, VPC route approval) | Move + **backend migration** to lab bucket key `network/tailscale.tfstate` |
| 4 | `infra/aws/subnet-router` | `s3://glab-lab-tfstate-…/aws/subnet-router.tfstate` | LIVE (EC2 `i-07878bb4aa9896dd4`, EIP `44.235.183.135`, IAM role `glab-aws-subnet-router`, dns-mirror via SSM) | Pure move |
| 5 | `infra/aws/keycloak` | `s3://glab-lab-tfstate-…/aws/keycloak.tfstate` | LIVE (Flatcar EC2 `i-01b23894c8a16971a`, EBS `vol-09baa3d716d956887`, `id.glab.lol`, current `glab-github-token-broker` Lambda via module `github.com/meigma/github-token-broker//terraform?ref=v2.0.0`) | Pure move |
| 6 | `infra/aws/github-token-broker` | `s3://glab-lab-tfstate-…/aws/github-token-broker.tfstate` | **TOMBSTONE** — glab session 044 targeted-destroyed everything except (per journal evidence) the GitHub Actions OIDC provider `arn:aws:iam::186067932323:oidc-provider/token.actions.githubusercontent.com` | **NEVER apply.** Carve OIDC provider into a new `aws/github-oidc` root (state mv/import), then retire legacy state |

Migration order: 1 → 2 → 3 → 4 → 5, with the tombstone (6) resolved after the
repo bootstrap and before or alongside root 1 (it has no dependents on the
others). Order rationale: foundation is discovered by name/tag from
subnet-router and keycloak; tailscale identity precedes subnet-router
operationally; keycloak spans the most dependencies so it moves last.

## Invariants (violating any one is a rollback)

1. KMS key ARNs must not change: `alias/glab-sops` (every SOPS file in
   `GilmanLab/secrets` embeds it) and `alias/glab-pki-root-ca` (committed
   `root_ca.crt` is bound to it).
2. IAM names must not change: role `glab-aws-subnet-router` (Tailscale
   federated-identity subject), Lambda `glab-github-token-broker` (labctl and
   Keycloak systemd units invoke by name).
3. Hosted zones must not be recreated: private `glab.lol`
   (`Z009084217D5KKVQERJY3` is hard-coded in subnet-router IAM), public
   `acme.glab.lol` (Cloudflare delegation pins its NS set).
4. The subnet-router EC2/device identity must not be replaced: VyOS CoreDNS
   pulls the mirrored `glab.lol` zone from Tailscale IP `100.80.89.100`.
5. `id.glab.lol` and the Keycloak EBS volume are identity/data-critical
   until the post-Zitadel teardown.
6. Never ordinary-apply the tombstone root — its source still declares the
   destroyed legacy Lambda/roles.
7. Never read or copy `s3://gilmanlab-tfstate/security/pki/root-ca.tfstate`
   (old account) — it points at the destroyed old root-CA key and shares its
   key name with the live lab object.
8. Single writer: once a root is initialized from `GilmanLab/aws`, the glab
   copy must never be applied again (remove/disable it in the same cutover).
9. Pulled state files are secrets. Keep them out of git, store under a
   0700 scratch dir, shred after the rollback window.

## Phase 0 — Freeze and capture (read-only)

1. Fresh SSO: `aws sso login --profile lab-admin`; verify
   `aws sts get-caller-identity --profile lab-admin` → account `186067932323`.
2. Confirm no in-flight applies; confirm no `*.tflock` objects in either bucket.
3. For each of the five lab-bucket objects: record S3 version-id + ETag
   (`aws s3api list-object-versions --bucket glab-lab-tfstate-186067932323 --prefix <key>`).
4. Per root in the glab checkout: `just init` (needs
   `GLAB_AWS_STATE_BUCKET=glab-lab-tfstate-186067932323`), then capture
   `tofu state pull > <scratch>/<root>.tfstate.backup`, `tofu state list`,
   and lineage/serial from the pulled file.
5. Old account (aws-vault `jmgilman-prod`): capture the same for
   `gilmanlab-tfstate/network/tailscale.tfstate` ONLY.
6. Tombstone: `tofu state list` on root 6 — confirm the exact remaining
   resources (expected: `aws_iam_openid_connect_provider.github_actions[0]`,
   possibly nothing else). If anything unexpected remains, stop and report.
7. Inventory external OIDC-provider consumers: search GilmanLab org workflows
   for `role-to-assume` / the provider ARN. Known stale consumer: glab
   `platform/.github/workflows/publish-github-token-broker.yml` references
   publisher role that was destroyed — mark for cleanup, not recreation.

## Phase 1 — Bootstrap `GilmanLab/aws`

1. Create the private repo (org conventions per existing GilmanLab repos;
   squash-merge only). Wire into lab2 meta `init.sh`.
2. Copy per root: `*.tf`, `*.tftest.hcl`/`tests/`, templates, `terraform.tfvars`,
   `.terraform.lock.hcl` (exact pins: AWS provider 5.100.0, tailscale 0.28.0,
   archive 2.7.1, null 3.2.4), Justfile + `scripts/check.sh`, README.
   Do NOT copy `.terraform/`, `tfplan`, local state, lock objects.
3. Keep the glab Justfile contract: offline `check`, partial-backend `init`
   requiring `GLAB_AWS_STATE_BUCKET`, saved `plan`, `apply`, `output`.
   Replace the tailscale root's `aws-vault exec jmgilman-prod` wrapper with
   the `lab-admin` convention and make the SOPS credentials path explicit
   (`GLAB_SECRETS_DIR`; the old default assumed glab sibling layout).
4. Suggested layout (directory names are free — state keys are not):
   `aws/lab-foundation`, `aws/subnet-router`, `aws/keycloak`,
   `aws/github-oidc` (new), `network/tailscale`, `security/pki/root-ca`.
5. CI: backendless `init -backend=false` + validate + fmt-check + `tofu test`
   for ALL roots (glab Moon CI omitted root-ca and tailscale — fix that).
   No AWS credentials in CI for this phase.
6. Docs note in repo README: state bucket, profile, region, the invariants
   list above, and a pointer to the meta-repo docs site for architecture.

## Phase 2 — Tombstone → `aws/github-oidc`

1. Author the new minimal root `aws/github-oidc` declaring ONLY the retained
   `aws_iam_openid_connect_provider` (source it from the legacy root's
   declaration), backend key `aws/github-oidc.tfstate`.
2. Move the resource across states (both states backed up in Phase 0):
   either `tofu state mv -state=<legacy pulled> -state-out=<new>` followed by
   pushes, or `tofu state rm` in legacy + `tofu import` in the new root.
   Prefer import (simpler to reason about, provider ARN is known).
3. Acceptance: new root plans 0/0/0; legacy state is empty
   (`tofu state list` → nothing).
4. Retire the legacy root: do not copy its source into `GilmanLab/aws` except
   as the `github-oidc` extraction; delete the empty legacy state object only
   after the full migration verifies.
5. Cleanup item: remove/replace glab `platform` publisher workflow that
   assumes the destroyed publisher role.

## Phase 3 — Per-root pure moves (roots 1, 2, 4, 5)

For each root, in order (foundation → root-ca → subnet-router → keycloak;
tailscale between root-ca and subnet-router, see Phase 4):

1. In the `GilmanLab/aws` checkout:
   `GLAB_AWS_STATE_BUCKET=glab-lab-tfstate-186067932323 just init`
   (i.e. `tofu init -reconfigure -backend-config="bucket=…"` with the SAME
   state key as before).
2. Verify `tofu state list` and lineage/serial match Phase 0 capture exactly.
3. `tofu plan -refresh-only` — review; then `tofu plan -detailed-exitcode`.
   Acceptance: exit code 0 (no changes). Any diff → stop, diagnose against
   the Phase 0 backup, do not apply.
4. Mark the glab copy dead: remove the root from `GilmanLab/infra` (or at
   minimum its Justfile entrypoints) in a PR that lands before any future
   apply from the new repo.

## Phase 4 — `network/tailscale` backend migration

1. In `GilmanLab/aws`, update the root's `backend.tf` from the hard-coded
   `gilmanlab-tfstate` to the lab bucket (keep key `network/tailscale.tfstate`;
   partial-config like the other roots is fine).
2. Credentials: Tailscale provider inputs come from
   `secrets/network/tailscale/terraform.sops.yaml` (KMS decrypt via
   `lab-admin`).
3. Backend-aware migration, preferred: with a shell that can read the old
   object (aws-vault `jmgilman-prod`) and write the new bucket (`lab-admin`),
   run `tofu init -migrate-state`. If no single principal spans both
   accounts: `tofu state pull` under the old profile → verify
   lineage/serial/resource list → `tofu state push` into the freshly
   configured lab backend → verify `state list`.
4. Acceptance: plan 0/0/0 from the new repo/backend. The federated identity,
   split-DNS entries, and device route must all show unchanged.
5. Do not delete the old-bucket object until the rollback window closes; then
   delete it explicitly (avoid future confusion with the dead root-ca object
   sitting in the same bucket — which is never to be touched).

## Phase 5 — Cutover

1. `GilmanLab/infra`: remove the six migrated roots (PR), leaving a README
   tombstone pointing at `GilmanLab/aws`.
2. Meta-repo docs (`docs/` in lab2): the glab-generation architecture pages
   that reference `infra/aws/...` paths are v1 docs — do NOT port wholesale;
   record in T37's scope that path references changed. Any v2 doc that names
   the root-CA cert path or AWS layout gets updated when written.
3. Report back to session 002: per-root verification table (state serial,
   plan result), deviations from this plan, and the final `GilmanLab/aws`
   layout — tracker items T35 (close), T33 (unblocked), plus a new teardown
   task for Keycloak-after-Zitadel.

## Risks (watch actively)

- Plan diffs caused by provider drift rather than state loss — diagnose with
  the refresh-only plan first; never "fix" a diff by applying during
  migration.
- Broker resurrection via the tombstone (Invariant 6).
- Wrong root-ca state object (Invariant 7).
- Dual writers during the window between first new-repo init and glab root
  removal (Invariant 8).
- `terraform.tfvars` in subnet-router/tailscale contain copied identifiers
  (trust-credential client id, issuer, role ARN) — carry them verbatim.
- SOPS 3.11 metadata quirk: encrypted files carry empty `aws_profile: ""`
  fields; do not strip them (breaks MAC).

## Open items deliberately left to the implementing session

- Exact `GilmanLab/aws` repo settings/CI wiring (follow org template norms).
- Whether to rename directories (allowed) — state keys stay fixed either way.
- Scheduling of the old-bucket tailscale object deletion.
