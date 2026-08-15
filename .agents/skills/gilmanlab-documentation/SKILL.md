---
name: gilmanlab-documentation
description: Standardize repository-local technical documentation across GilmanLab repositories. Use when creating, moving, editing, or reviewing architecture documents, decision records, design documents, reference material, or runbooks.
---

# GilmanLab Documentation

Use this skill for documentation in the meta repository and every cloned
sub-repository.

## Adopted conventions

This contract combines established conventions rather than defining a new
all-purpose documentation format:

- Use [Diátaxis](https://diataxis.fr/) to keep explanation, reference, and
  task-oriented documentation distinct.
- Use [MADR 4.0](https://adr.github.io/madr/) for architectural decision
  records.
- Use the Google-style design document structure described in
  [Design Docs at Google](https://www.industrialempathy.com/posts/design-docs-at-google/)
  and [Software Engineering at Google](https://abseil.io/resources/swe-book/html/ch10.html#design_docs).
- Borrow test, risk, rollout, and rollback prompts from the
  [Kubernetes Enhancement Proposal template](https://github.com/kubernetes/enhancements/tree/master/keps/NNNN-kep-template)
  only when those concerns apply.
- Use [arc42](https://docs.arc42.org/) concepts selectively when describing
  architecture. Do not require a complete arc42 document.

Documentation is code: review it with implementation changes and maintain one
canonical source for each fact.

## Locate the content root

`<docs-root>` is the meta repository's `docs/docs/` content directory, built by
the MkDocs project at `<meta-repo>/docs/`. All GilmanLab documentation lives
there, regardless of which repository owns the implementation.

Never create a documentation tree inside a sub-repository. If one exists, treat
it as a migration candidate into the central site, not as a second content
root.

## Standard structure

Create a directory only when it has real content:

```text
<docs-root>/
├── index.md
├── architecture/
├── decisions/
├── designs/
│   └── drafts/
├── reference/
└── runbooks/
```

`index.md` is a short navigation page, not a duplicate architecture overview.

| Directory | Reader's question | Contract |
| --- | --- | --- |
| `architecture/` | How does the current system fit together? | Current-state explanation |
| `decisions/` | Why was this consequential choice made? | Durable decision record |
| `designs/` | What change will we build, and how? | Accepted or implemented specification |
| `designs/drafts/` | What design is still under discussion? | Unstable working specification |
| `reference/` | What are the exact facts or supported values? | Lookup-oriented technical description |
| `runbooks/` | How do I perform or recover an operation? | Goal-oriented operational procedure |

Keep each document to one primary purpose. Link related documents instead of
merging their content.

## Authoring workflow

1. Search the central `<docs-root>` for an existing canonical document before
   writing; extend or link instead of duplicating.
2. Classify the reader's need using the table above.
3. For a decision or design, copy the corresponding template from
   `references/` beside this skill.
4. Start with the minimum sections needed to test the idea. Omit inapplicable
   optional sections instead of leaving empty headings.
5. Link canonical configuration, issues, experiments, and related documents.
   Do not copy exact values that already have a better source of truth.
6. When implementation changes behavior, update affected architecture,
   reference, and runbook documents as a companion change in the meta
   repository.
7. Build the documentation site with `moon run docs:build` and fix strict-mode
   failures before merging.

## Architecture contract

Architecture documents explain the implemented system at a scope useful to the
owning repository. Planned behavior belongs in a design until it is implemented.

Select only the views needed for the subject:

- Context, scope, and external dependencies
- Building blocks and their responsibilities
- Runtime or traffic flows
- Deployment and physical topology
- Trust, security, and failure boundaries
- Important quality constraints and known risks
- Links to governing decisions and precise reference data

Prefer several scoped documents over a repository-wide architecture monolith.
Use diagrams only when they clarify structure or flow. Do not duplicate live
configuration, inventory tables, or procedural steps.

## Decision contract

Use a decision record when a choice is expensive to reverse, crosses component
or repository boundaries, affects security or availability, constrains future
designs, or has credible alternatives future maintainers may reconsider.

Follow MADR 4.0 and `references/decision-template.md`.

- Store records in `decisions/` from their creation, including `proposed`
  records. Do not put proposed decisions under `designs/drafts/`.
- Name files `NNNN-short-descriptive-title.md` with monotonically increasing,
  zero-padded numbers. Never reuse a number.
- Use MADR statuses: `proposed`, `accepted`, `rejected`, `deprecated`, or
  `superseded by ADR-NNNN`.
- Keep one decision per record.
- After acceptance, do not rewrite the decision or its original rationale.
  Correct trivial errors, append relevant evidence, or supersede it with a new
  record.
- Summarize evidence in the record and link detailed experiments or designs.
- Use the `Confirmation` section to state how compliance can be observed.

A small, local, readily reversible choice can remain in its design document or
implementation review.

## Design contract

Use a design document when implementation requires agreement about interacting
components, interfaces, migration, security, failure behavior, or meaningful
tradeoffs. Do not require one for a simple local change.

Follow the Google-style funnel in `references/design-template.md`: context and
scope, goals and non-goals, overview, details, cross-cutting concerns, then
alternatives. Add production-readiness sections only where the system warrants
them.

- Draft at `designs/drafts/<short-descriptive-title>.md`.
- Promote an accepted draft with `git mv` to
  `designs/<short-descriptive-title>.md` and set its status to `accepted`.
  Draft links are intentionally unstable; accepted links are stable.
- Use statuses `draft`, `accepted`, `implemented`, `abandoned`, or
  `superseded`.
- Prototype uncertain mechanisms before specifying them in detail. Link the
  evidence and revise the draft with what was learned.
- Acceptance means reviewers agree the design is sufficiently clear to
  implement and verify. It does not mean every incidental detail is fixed.
- Mark the document `implemented` only after the delivered system and its
  current architecture documentation agree with it.
- Record consequential choices as decision records and link them. The design
  keeps implementation context; the decision record keeps the durable choice
  and rationale.
- After implementation, use a new design for a major change. Preserve the old
  document as historical context and link its replacement.

## Reference contract

Reference documentation is factual, neutral, and optimized for lookup. It may
cover APIs, commands, configuration fields, address plans, interfaces, ports,
limits, schemas, or supported values.

Mirror the structure and terminology of the system. Prefer generated reference
when a reliable source can produce it. State applicability and version where a
fact is not universal. Put rationale in a decision or architecture document.

## Runbook contract

Runbooks are Diátaxis how-to guides for operators. Each runbook targets one
observable operational outcome and normally includes:

1. Preconditions and required access
2. Safety impact
3. Ordered procedure
4. Verification of the outcome
5. Rollback or recovery
6. Escalation conditions

Use real commands and expected observations. Do not turn a runbook into a
concept tutorial or duplicate command reference.

## Cross-repository ownership

All documentation lives in the meta repository's central site; implementation
lives in the owning repositories. Namespace domain-specific reference material
by domain (for example `reference/networking/`), keep one global decision
sequence, and let design titles scope themselves.

The implementing repository's changes and their documentation updates ship as
companion changes: when a sub-repository change alters documented behavior,
update the central documents in the same unit of work. Keep exact values
(addresses, VLANs, ports, hardware) in one canonical reference document and
link to it from every other document.
