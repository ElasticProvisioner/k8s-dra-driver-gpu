---
name: dra-proposal-and-design-review
description: Draft or review maintainer-ready design proposals, architecture decision records, implementation plans, feature-gate plans, and scope analyses for the DRA Driver for NVIDIA GPUs. Use when a user asks for a proposal, design review, ADR, feature gate plan, scope analysis, or maintainer-ready technical writeup.
metadata:
  author: "DRA Driver for NVIDIA GPUs team"
---

# DRA Proposal and Design Review

Produce decision-ready design material grounded in the current repository. Optimize for the questions maintainers must resolve before implementation: user need, correct ownership layer, observable contract, authoritative state, compatibility, failure behavior, rollout, and evidence that the design can be tested.

Draft in the response unless the user explicitly asks to create or edit a repository file. Do not open issues, PRs, or external discussions without separate authorization.

## Establish the project context

Before making detailed claims:

1. Read `site/content/contribute/proposals/_index.md` to determine whether the change needs a formal proposal and to confirm the current status lifecycle.
2. For a project proposal, use `site/content/contribute/proposals/NNNN-template.md` as the authoritative structure. Preserve its high-signal sections; mark a section not applicable with a short reason instead of silently dropping it.
3. Read `site/content/docs/concepts/architecture.md` and the relevant GPU or ComputeDomain concept page.
4. Trace the affected implementation under `cmd/`, API contract under `api/`, shared packages under `pkg/`, dynamic manifests under `templates/`, and install-time wiring under `deployments/helm/dra-driver-nvidia-gpu/`.
5. Inspect adjacent tests, demos, feature-gate definitions, and documentation. Use current code and manifests to resolve disagreements with prose.

Do not start with `vendor/` or generated `pkg/nvidia.com/` clients. Identify generated outputs explicitly: Kubernetes clients/informers/listers under `pkg/nvidia.com/`, `zz_generated.deepcopy.go`, and Helm CRDs derive from handwritten APIs and `make generate`.

## Choose the deliverable

### Scope analysis

Use scope analysis when the main question is whether to do the work, where it belongs, or how large it is. Conclude with:

- the user problem and named workload or consumer;
- current behavior and the gap, with repository evidence;
- the owning layer and why;
- proposal-required versus direct-PR classification;
- affected components and contracts;
- smallest valuable slice and explicit non-goals;
- decisions or evidence still needed.

Apply the repository's proposal threshold. A formal proposal is required for a new or graduating feature gate, significant behavior change, user-facing API or checkpoint schema change, external dependency, upstream Kubernetes dependency, or multi-node ComputeDomain/IMEX coordination change. Bug fixes, docs-only work, internal refactors, no-impact dependency bumps, and design-preserving increments under an existing gate normally go directly to a PR.

Test for “wrong layer” early:

- Generic Kubernetes DRA API or scheduler semantics may belong upstream.
- GPU driver lifecycle, node preparation, and cluster enablement may belong in GPU Operator or another node-management layer.
- Legacy extended-resource behavior may belong in the device plugin path.
- Container injection or CDI/toolkit semantics may belong in NVIDIA Container Toolkit or the runtime integration.
- Vendor-specific discovery, ResourceSlice publication, claim preparation, GPU/MIG/VFIO configuration, and ComputeDomain/IMEX orchestration are candidates for this driver.

Also test whether existing CEL selectors, `matchAttribute`, DeviceClasses, opaque configs, CRDs, Helm values, or feature gates already solve the use case. Treat the list above as prompts for evidence, not automatic ownership rules.

### Project proposal

When creating a proposal file, select the next unused four-digit number in `site/content/contribute/proposals/`, use a short kebab-case filename, and start at `Status: provisional`. Recheck for numbering conflicts before handoff. Do not invent authors, issue numbers, measured results, compatibility guarantees, or upstream commitments; retain clear placeholders or questions where evidence is missing.

Draft the template around these review invariants:

- The summary works as a one-paragraph release note.
- Motivation names a concrete workload, downstream consumer, or user class.
- Goals are measurable and imply tests; non-goals fence related work.
- “Why this driver?” compares the plausible adjacent ownership layers.
- A concrete manifest, Helm value, API object, or CLI example exposes the user experience before internals.
- Affected components name logical and generated consequences.
- Every new persistent or runtime state has one authoritative writer and defined readers.
- The smallest useful slice can merge and ship independently.
- API additions distinguish user-facing contract from implementation detail.
- Upgrade, downgrade, rollback, in-flight claim, and version-skew behavior are explicit.
- Environment floors cover Kubernetes, NVIDIA driver, GPU generation, MIG/NVLink/IMEX/Fabric Manager, and required upstream gates where relevant.
- The test plan names likely files, suites, fixtures, or CI jobs rather than only test categories.
- Alternatives include current primitives, adjacent NVIDIA implementations, and relevant upstream work.
- Drawbacks steelman the case against the design, and open questions request specific maintainer decisions.

### ADR

First search the current checkout for an ADR or decision-record convention. This repository may not have a dedicated ADR directory or template; do not invent a permanent location when none exists. If the decision meets the formal proposal threshold, recommend the project proposal format. Otherwise produce a compact ADR with status, date, context, decision drivers, considered options, decision, consequences, compatibility/rollback impact, and follow-up work. Separate decided facts from unresolved questions.

### Implementation plan

Start from the accepted design or clearly label design assumptions that still need approval. Map each phase to:

- user-visible outcome and acceptance criteria;
- affected components, source paths, and important symbols or callbacks;
- API, checkpoint, ResourceSlice, CDI, Helm, RBAC, template, metric, and documentation changes;
- generated outputs and the source command that owns them;
- unit, integration, BATS, mock-NVML, and real-GPU/ComputeDomain coverage as applicable;
- upgrade sequencing, rollback point, and telemetry used to detect failure.

Prefer vertical slices that leave the tree buildable and testable. Put API/defaulting/validation before consumers; shared state format before multiple readers; deployment wiring after binary behavior; generated artifacts after handwritten contracts; documentation and release-note updates in the phase where behavior becomes usable. Do not disguise unresolved design choices as implementation steps.

## Build a feature-gate plan

For a new gate or graduation, inspect `pkg/featuregates/featuregates.go`, `pkg/featuregates/featuregates_test.go`, `pkg/flags/featuregates.go`, `site/content/docs/reference/feature-gates.md`, Helm feature-gate propagation, and every component that evaluates the gate.

Specify:

- gate name, stage, default, and the driver SemVer major/minor for its `VersionedSpecs` entry;
- exact behavior when disabled and enabled;
- binaries and templates that consume or propagate it;
- dependencies, mutual exclusions, and startup validation;
- required Kubernetes gates/API versions, hardware, driver versions, and external services;
- persistent-state and version-skew behavior when components disagree or a rollback disables the gate;
- Alpha-to-Beta-to-Stable criteria based on feature completeness, named interoperability combinations, stability evidence, and soak time;
- removal or lock-to-default expectations when the project reaches the applicable lifecycle stage.

Follow existing project conventions unless the proposal justifies a deviation: Alpha gates are normally off, Beta gates normally on, and driver-local `Version` fields use driver SemVer. Do not confuse those versions with `featureGateEmulationVersion`, which tracks the vendored Kubernetes minor. Include updates to gate validation/tests, Helm examples or validation, feature-gate reference docs, relevant user guide/API docs, release notes, and the bug-report gate list when applicable.

## Review a design

Lead with a readiness finding: ready for maintainer review, needs revision, or blocked on named decisions. Then report findings in descending impact, with exact section and repository evidence. Focus on omissions that could change the design or make it unsafe to ship:

- unclear problem, user, success criteria, or non-goals;
- functionality in the wrong ownership layer;
- missing user-facing example or speculative public API;
- split-brain state ownership or ambiguous reconciliation;
- prepare/unprepare races, retries, partial failure, force deletion, node reboot, daemon restart, or checkpoint recovery;
- controller/daemon coordination, leader election, network partition, clique membership, or DNS identity for ComputeDomains;
- upgrade/downgrade, in-flight claims, skew, defaults, and feature-gate composition;
- ResourceSlice scheduling assumptions, CDI/runtime injection, privileged mounts, NVML, IMEX, or Fabric Manager safety;
- insufficient testability, hardware-only coverage without a justified mock boundary, or missing observability;
- unexamined simpler alternatives, upstream dependencies, or operational drawbacks.

Distinguish blocking findings from optional improvements. Ask for a concrete decision when multiple choices are viable. Do not rewrite the entire document during review unless the user asks; provide targeted replacement text for sections that need it.

## Deliver a maintainer-ready result

Use precise local paths and symbols for code claims. Label facts, proposals, assumptions, and open questions distinctly. Keep the main narrative centered on the user-visible contract and the end-to-end request or lifecycle flow; directory inventories belong in affected-components or implementation sections.

End drafts with a short readiness checklist containing only unresolved items. End reviews with the minimum decisions or revisions needed to advance to the next status. Official approval comes from the repository's current `OWNERS`; commit history can suggest expertise but is not ownership evidence.
