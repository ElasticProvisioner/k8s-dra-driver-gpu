---
name: dra-release-support-docs-readiness
description: Guide release readiness, supportability, documentation updates, known-issue capture, and stale-source refresh for the NVIDIA DRA Driver for GPUs. Use when asked for a release checklist, support handoff, docs readiness review, version matrix, or release-note impact analysis.
metadata:
  author: "DRA Driver for NVIDIA GPUs team"
---

# DRA release, support, and documentation readiness

Produce an evidence-backed readiness assessment for a specific release or change range. Reconcile code, packaging, compatibility, documentation, tests, artifacts, and support guidance; do not reduce readiness to a generic checklist or a green CI badge.

Ground the review in the current checkout and the target branch or tag. Release instructions and documentation can lag implementation, so verify their claims against automation, chart templates, API sources, and tests. Clearly distinguish observed facts, proposed edits, external evidence, and items that remain unverified.

This skill assesses and prepares release-facing material. Use the build/test/CI skill for executing validation, the API/CRD/feature-gate skill for compatibility-sensitive implementation changes, the operations skill for a live support incident, and the proposal skill when unresolved behavior requires a design decision.

## Define the release frame

Establish before reviewing:

- Target version, release type (patch, minor, major, prerelease, or development), target branch, comparison base, and intended tag/branch names.
- Whether the task covers one PR, a commit range, a release candidate, or a final published release.
- Installation paths in scope: direct Helm, GPU Operator-managed, local/demo, or all supported paths.
- Resource paths in scope: GPU allocation, MIG, sharing, VFIO, GPU health, ComputeDomains/IMEX, webhook, metrics, or infrastructure only.
- Supported Kubernetes, NVIDIA driver, Container Toolkit/runtime, NFD/GFD, GPU Operator, hardware, and feature-gate combinations claimed for the release.
- Required deliverables: checklist, release notes, upgrade notes, documentation patch, compatibility matrix, known-issues list, support handoff, or go/no-go assessment.

Resolve the comparison range explicitly. For a release review, prefer the previous release tag to the target commit; for a patch review, compare against the appropriate release branch or prior patch tag. Record the exact commits so a later reviewer can reproduce the result.

Do not tag, push, create a GitHub release, promote images, edit an external support system, or announce a release unless the user separately authorizes that exact action. A readiness review may recommend those steps without performing them.

## Build a change-impact inventory

Start with the semantic diff, not filenames alone. Review commits and changed paths, then classify user-facing impact:

| Change area | Release and support questions |
| --- | --- |
| API, CRD, or opaque config | Is the field served, stored, defaulted, validated, generated, and documented? Can old objects and clients continue to work? |
| Feature gate | What is its stage and default? Which components consume it? Does Kubernetes require a corresponding gate or minimum version? Are incompatible combinations rejected? |
| ResourceSlice or DeviceClass | Did device names, attributes, capacity, selectors, taints, pool layout, or scheduling behavior change? |
| Prepare, CDI, or checkpoint | Can existing allocated/prepared claims survive rollout, restart, and host reboot? Is downgrade safe? What recovery evidence exists? |
| Helm chart | Did values, defaults, image tags, RBAC, CRDs, security context, probes, labels, mounts, affinity, or generated object names change? |
| ComputeDomain/IMEX | Did lifecycle mode, clique ownership/readiness, generated resources, topology requirements, or daemon compatibility change? |
| Prerequisite or dependency | Did minimum Kubernetes, driver, runtime, Toolkit, NFD/GFD, GPU Operator, or hardware support change? |
| Observability | Did metric names/labels, endpoints, logs, events, health checks, or troubleshooting signals change? |
| Example or test | Does it describe supported behavior, a compatibility path, or test-only behavior? Is the API version and hardware assumption current? |

Use the PR template's `release-note` and `docs` sections as inputs, not proof. Reconstruct missing or incomplete impact from the code and tests. Avoid listing internal refactors unless they alter operator behavior, supportability, risk, performance, security, compatibility, or artifacts.

For each user-facing change, capture:

- Previous behavior and new behavior.
- Who is affected and under which configuration.
- Default versus opt-in behavior and feature maturity.
- Required action before, during, or after upgrade.
- Upgrade and downgrade implications.
- Documentation, tests, telemetry, and known-issue consequences.

## Reconcile version and artifact surfaces

Treat the following as separate contracts and make their formatting explicit:

- Root `VERSION`: release automation input and image tag, with a `v` prefix.
- Helm `deployments/helm/dra-driver-nvidia-gpu/Chart.yaml`: `version` and `appVersion`, without a `v` prefix; chart templates add `v` where building the default image tag.
- `site/hugo.toml`: `driver_version` without `v` and `driver_release_tag` with `v`; update both together for a published documentation target.
- Git tag and release branch: verify current naming from `.github/workflows/release-automation.yml` rather than relying only on prose in `RELEASE.md`.
- Published image, chart, generated install manifest, and GitHub release artifact: verify version and digest alignment independently.

Search for stale hardcoded versions and identities in first-party content:

```bash
rg -n 'v[0-9]+\.[0-9]+\.[0-9]+|[0-9]+\.[0-9]+\.[0-9]+-dev' \
  README.md RELEASE.md VERSION deployments site demo tests hack .github
rg -n 'NVIDIA/k8s-dra-driver-gpu|nvidia-dra-driver-gpu|dra-driver-nvidia-gpu' \
  README.md RELEASE.md deployments site demo tests hack .github
rg -n 'resource.k8s.io/v1(alpha|beta)[0-9]?|resource.k8s.io/v1' \
  README.md deployments site demo tests
```

Classify each match before editing. Historical upgrade sections and intentional compatibility examples should retain old versions; current install commands, latest-release links, prerequisites, and generic examples should normally use the current site parameters or target version.

Do not claim artifact readiness from source alignment alone. Record whether images and charts were built, whether digests were verified in staging and production registries, whether generated manifests reference the intended image, and whether the GitHub release assets exist. Mark external checks as not verified when they were not performed.

## Review documentation as an executable contract

Map each behavior change to the smallest authoritative documentation set:

- `README.md`: concise project purpose, support posture, and primary entry points.
- `site/content/docs/prerequisites.md`: version and hardware compatibility matrix, required services, and installation-owner boundaries.
- `site/content/docs/install.md`: supported installation paths, values, safety acknowledgements, and initial verification.
- `site/content/docs/upgrade.md`: source-to-target procedure, preconditions, migration ordering, action-required changes, downgrade boundary, and post-upgrade proof.
- `site/content/docs/reference/feature-gates.md`: stage, default, component scope, dependencies, incompatibilities, and removal plan.
- `site/content/docs/reference/api.md`, Helm values, and ResourceSlice attributes: exact operator-facing contracts.
- Concept and guide pages: behavior, mental model, mode-specific configuration, and validation.
- `demo/` examples: runnable API-versioned manifests that match current supported behavior.
- `RELEASE.md` and release automation: maintainer process and actual automated side effects.

Verify commands against current flags, paths, chart values, object names, API versions, and templates. Verify links and anchors where possible. Render the site when content structure, shortcodes, tables, alerts, or navigation changes; use the workflow in `site/content/contribute/docs.md` and distinguish a successful site build from semantic review.

Treat documentation about documentation as fallible. If a guide references a missing directory, obsolete script, renamed repository, superseded registry, or removed workflow, report the mismatch and identify the current source of truth instead of inventing the missing content. Search callers before removing a stale path because external automation or release branches may still depend on it.

## Build the compatibility and support matrix

Create only dimensions supported by evidence. At minimum, consider:

- Driver/chart release and installation owner.
- Kubernetes version and DRA API/gates.
- GPU allocation versus ComputeDomain enablement.
- NVIDIA driver, Container Toolkit/runtime with CDI, NFD, and GFD versions.
- GPU family, MIG capability, VFIO/IOMMU requirements, and MNNVL topology.
- Feature-gate states and known incompatible combinations.
- Direct install versus GPU Operator-owned prerequisites and lifecycle.
- Upgrade source versions and downgrade support.

Use `site/content/docs/prerequisites.md`, feature-gate docs, chart validation, code startup checks, CI/test matrices, and operator documentation where applicable. Do not convert one tested combination into a broad support promise. Label entries as supported, unsupported, experimental, tested, documented-only, or unknown according to actual evidence, and define those terms in the deliverable.

When different sources disagree, report the conflict with locations and likely owner. Prefer an explicit startup validation or code-enforced invariant over stale prose, but do not silently rewrite a public support commitment without maintainer judgment.

## Capture known issues for action

Include an issue only when the limitation or defect has concrete evidence. Record:

- Short title and affected versions/configurations/hardware.
- Symptom and operator-visible detection signal.
- Impact and severity without speculation.
- Trigger or precondition, when known.
- Workaround and its risks, or state that none is verified.
- Fixed version/status and links to the owning issue, PR, or source evidence.
- Upgrade, downgrade, data/checkpoint, or cleanup implications.
- Support collection guidance: exact objects, logs, events, metrics, and identifiers needed.

Separate known limitations from regressions, documentation gaps, and unresolved risks. A feature being alpha or unsupported is not automatically a known issue. Do not promise a fix version that is not committed, and do not publish destructive workarounds such as checkpoint deletion, PCI rebinding, finalizer removal, or service changes without exact scope and safety conditions.

## Refresh stale sources deliberately

When asked to refresh stale material:

1. Identify the claim and every maintained source that repeats or derives it.
2. Determine the authoritative owner: handwritten API/code, chart values/templates, generated artifacts, tests, release automation, or public support policy.
3. Update the canonical source first. Regenerate derived content through the repository workflow when required; do not hand-edit generated CRDs or clients.
4. Update all affected docs, examples, upgrade notes, release-note text, and support matrices while preserving intentional historical sections.
5. Search again for contradictory terminology, versions, defaults, flags, links, and object names.
6. Validate the smallest relevant build/test tier and report what remains unverified.

Do not turn a historical release procedure into the latest-release procedure by global replacement. Preserve source-to-target specificity in upgrade notes and distinguish current defaults from old behavior.

## Apply readiness gates

Report each gate as `ready`, `blocked`, `not applicable`, or `not verified`, with direct evidence and an owner for remaining work:

- Scope and change inventory are complete for the chosen comparison range.
- Version surfaces, chart/image tags, and automation agree.
- API, CRD, feature-gate, ResourceSlice, and checkpoint compatibility are resolved.
- Direct Helm and GPU Operator ownership boundaries are documented.
- Prerequisites and support matrix match enforced and tested behavior.
- Install, upgrade, downgrade, rollback, and cleanup guidance reflects the release risk.
- User-facing changes have release notes and documentation coverage.
- Known issues include detection, impact, safe workaround status, and support evidence.
- Required generated artifacts and release assets are reproducible and version-correct.
- Relevant unit, lint, generation, Helm, site, mock, and hardware test evidence is recorded.
- Support can identify component ownership, gather diagnostics, and distinguish expected transients from failures.

A release is not ready merely because no blocker was found in an incomplete review. Use `not verified` for missing evidence. Reserve `blocked` for a concrete unmet release requirement, and state the decision authority when support policy or compatibility promises require maintainer approval.

## Shape the deliverable

Lead with target version/range and overall readiness, then provide:

- Blocking issues and decisions first.
- A compact gate table with status, evidence, owner, and next action.
- User-facing change summary grouped by impact rather than commit order.
- Version/support matrix with evidence strength.
- Documentation and stale-source changes required by path.
- Known issues and support handoff.
- Validation performed, external artifact checks performed, and explicit gaps.

For release-note text, state the user-visible outcome, affected configurations, and required action. Avoid implementation-only detail, marketing language, unsupported superlatives, and claims broader than the tested support matrix.

## Follow source ownership

Use these paths to verify the current release contract:

- `VERSION`, `RELEASE.md`, and `.github/workflows/release-automation.yml`: version trigger, tag, branch, and release process.
- `deployments/helm/dra-driver-nvidia-gpu/Chart.yaml`, `values.yaml`, `deployments/helm/dra-driver-nvidia-gpu/templates/`, and `crds/`: chart/app versions, defaults, validation, Kubernetes compatibility, generated resources, and packaged CRDs.
- `hack/build-and-publish-image.sh`, `hack/build-and-publish-chart.sh`, and Makefile manifest targets: artifact construction and registry inputs.
- `.github/PULL_REQUEST_TEMPLATE.md`, commit history, and changed tests: candidate release notes and intended user-facing impact.
- `site/hugo.toml`, `site/content/contribute/docs.md`, and `site/content/docs/`: published release variables, site workflow, prerequisites, install, upgrade, reference, concept, and guide content.
- `api/nvidia.com/resource/v1beta1/` and `pkg/nvidia.com/`: handwritten API contracts and generated consumers.
- `cmd/`, `pkg/metrics/`, Helm templates, and adjacent tests: behavior and observability when prose is ambiguous.
- `.github/workflows/`, `tests/bats/`, `test/e2e/`, and `hack/ci/`: actual CI coverage and hardware/environment assumptions.

When the release depends on an external project such as Kubernetes, GPU Operator, Container Toolkit, test-infra, or `kubernetes/k8s.io` image promotion, cite the exact external version or artifact checked and keep ownership explicit.
