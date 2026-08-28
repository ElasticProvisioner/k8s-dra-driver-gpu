---
name: dra-project-orientation
description: Orient agents to the DRA Driver for NVIDIA GPUs repository by explaining what it does, mapping its runtime components and request flows, locating implementation, documentation, tests, and deployment code, and identifying source ownership and generated boundaries. Use when asked what this repo does, where logic lives, how components fit together, who owns an area, or how to onboard.
metadata:
  author: "DRA Driver for NVIDIA GPUs team"
---

# DRA Project Orientation

Ground orientation answers in the current checkout. Use the map below as a routing aid, then inspect the relevant files before making detailed claims because features and component boundaries evolve.

## Start with the right sources

1. Locate the repository root with `git rev-parse --show-toplevel` when the working directory is uncertain.
2. Read `README.md` for the project summary and support status.
3. Read `site/content/docs/concepts/architecture.md` for the component model and the GPU and ComputeDomain request flows.
4. Read the relevant concept page:
   - `site/content/docs/concepts/gpu-allocation.md` for full GPU, MIG, sharing, and VFIO behavior.
   - `site/content/docs/concepts/compute-domains.md` for Multi-Node NVLink, IMEX, and driver-managed versus host-managed lifecycles.
5. Verify details against the applicable `cmd/<component>/` entry point and implementation. Treat code and deployment manifests as authoritative for current behavior when prose and implementation differ.

Avoid beginning in `vendor/` or generated clients. Search first-party code with exclusions such as `rg <term> cmd api pkg internal deployments templates site demo test tests hack -g '!pkg/nvidia.com/**'`. Include `pkg/nvidia.com/` only when tracing generated Kubernetes client behavior.

## Understand the system shape

This is a Go implementation of two Kubernetes Dynamic Resource Allocation drivers:

- `gpu.nvidia.com` allocates and configures full GPUs, MIG devices, shared GPU access, and VFIO passthrough.
- `compute-domain.nvidia.com` provides IMEX channel devices for ephemeral, isolated Multi-Node NVLink ComputeDomains.

The Helm chart deploys five binaries. Use these paths to find the owner of runtime behavior:

| Component | Role and first places to inspect |
|---|---|
| `cmd/gpu-kubelet-plugin/` | Per-node GPU DRA plugin. Start at `main.go` for configuration, `driver.go` for plugin startup, ResourceSlice publication, and kubelet Prepare/Unprepare callbacks, and `device_state.go` for the main claim preparation state machine. Continue to `allocatable.go`, `deviceinfo.go`, `mig.go`, `sharing.go`, `mps_capability.go`, `vfio-*.go`, `cdi.go`, `checkpoint*.go`, or `device_health.go` according to the feature. |
| `cmd/compute-domain-kubelet-plugin/` | Per-node ComputeDomain DRA plugin. Start at `main.go`, `driver.go`, and `device_state.go`; use `computedomain.go` for domain readiness/state, `cdi.go` for IMEX device injection, and `checkpoint*.go` for persisted preparation state. |
| `cmd/compute-domain-controller/` | Cluster controller for `ComputeDomain` lifecycle. Start at `controller.go` and `computedomain.go`; resource-specific managers in `daemonset.go`, `resourceclaimtemplate.go`, `node.go`, `cdclique.go`, and `cdstatus.go` own reconciliation, generated objects, cleanup, and status. |
| `cmd/compute-domain-daemon/` | Per-ComputeDomain node daemon that runs and supervises `nvidia-imex` and publishes peer/readiness information. Start at `main.go`, `controller.go`, and `process.go`; then inspect `cdclique.go` or `cdstatus.go`, `dnsnames.go`, and `podmanager.go`. |
| `cmd/webhook/` | Optional validating admission webhook for opaque configurations on `ResourceClaim` and `ResourceClaimTemplate` objects. Start at `main.go`; validation dispatch and Kubernetes API-version conversion live in `resource.go`. |

Keep these relationships explicit when explaining how components fit:

- GPU path: a claim's opaque config is defined under `api/`, optionally checked by the webhook, allocated by Kubernetes from ResourceSlices published by the GPU plugin, then prepared by that plugin into CDI devices for the container runtime.
- Driver-managed ComputeDomain path: the controller watches `ComputeDomain` CRs and creates per-domain DaemonSets and claim templates; daemon pods run IMEX and report membership/readiness; the ComputeDomain kubelet plugin validates readiness and injects selected IMEX channels.
- Host-managed ComputeDomain path: the host owns the IMEX daemon; the controller does not create per-domain daemon infrastructure, and the kubelet plugin checks the host daemon before injecting a channel.
- Both kubelet plugins run per node. The controller and webhook are cluster-level deployments; the ComputeDomain daemon is created per domain in driver-managed mode.

## Route contracts, shared code, and deployment wiring

- `api/nvidia.com/resource/v1beta1/` contains the handwritten NVIDIA API contracts, registration, defaulting/normalization, and validation for opaque GPU and ComputeDomain configs and the `ComputeDomain` and `ComputeDomainClique` CRs.
- `pkg/nvidia.com/` is generated clientset, informer, and lister code. `api/**/zz_generated.deepcopy.go` and Helm CRDs are also generated outputs. Change the API source rather than generated artifacts, then use `make generate` and `make check-generate` as appropriate.
- `pkg/featuregates/`, `pkg/flags/`, and `pkg/metrics/` hold cross-component feature gates, CLI/Kubernetes configuration, and metrics. `pkg/imex/` and `pkg/fabricmanager/` own shared domain-specific integrations; `pkg/flock/` and `pkg/workqueue/` provide reusable coordination primitives.
- `internal/common/` contains implementation shared only within this module; `internal/info/` contains build/version metadata.
- `deployments/helm/dra-driver-nvidia-gpu/` is the installation source of truth. Read `values.yaml`, `deployments/helm/dra-driver-nvidia-gpu/templates/kubeletplugin.yaml`, `deployments/helm/dra-driver-nvidia-gpu/templates/controller.yaml`, and the relevant RBAC, DeviceClass, CRD, or webhook template to learn whether and how code is enabled and wired.
- `templates/` contains manifests and configuration rendered dynamically by running components, including per-ComputeDomain and MPS resources. Do not confuse these with the install-time Helm templates.
- `deployments/container/` builds the runtime image. `deployments/devel/` defines the development-tooling image and code-generation tools.

## Route documentation and onboarding

- `site/content/docs/` is the documentation site's source. Use `install.md`, `prerequisites.md`, and `upgrade.md` for lifecycle tasks; `guides/` for user workflows; and `reference/` for APIs, feature gates, Helm values, and ResourceSlice attributes.
- `demo/specs/` provides concrete claims and workloads. `demo/clusters/` contains kind, nvkind, GKE, and OpenShift setup helpers.
- `site/content/contribute/development.md` gives the build, unit-test, code-generation, lint, Helm, and local-cluster loop. Confirm target definitions in the root `Makefile`.
- Unit tests live beside Go implementation files. `test/e2e/` is the Go/Ginkgo GPU allocation suite. `tests/bats/` is the broader, invasive live-cluster integration suite; read its `README.md` before recommending it. CI-specific cluster harnesses live under `hack/ci/`, while GitHub checks live in `.github/workflows/`.
- `CONTRIBUTING.md`, `RELEASE.md`, and `site/content/contribute/` cover contribution and release processes.

For a general onboarding request, propose this reading path: `README.md` → architecture → the relevant GPU or ComputeDomain concept page → the corresponding `cmd/` component → its Helm template → adjacent unit tests → one matching demo. Add `site/content/contribute/development.md` before suggesting local changes.

## Determine ownership accurately

- Read the root `OWNERS` file for official reviewer and approver roles. It is the only first-party `OWNERS` file in this repository, so it applies repo-wide unless the current checkout adds a more specific ownership file.
- Ignore ownership files inside `vendor/`; they describe upstream dependencies, not this project.
- Describe logical source ownership by directory or component using the map above. Do not assign an individual as the owner of a subsystem without an explicit, scoped ownership source.
- If the user asks for likely historical expertise rather than formal ownership, `git log -- <path>` may provide context. Label that as commit history, not official ownership.

## Shape the answer to the request

- For “what does this repo do?”, lead with the two drivers, then distinguish cluster-level and node-level components.
- For “where does this logic live?”, name the narrowest relevant directory, file, and important symbol or callback; trace one layer upstream and downstream when that clarifies the flow.
- For “how do components fit?”, explain either the GPU request flow or the ComputeDomain lifecycle instead of listing every directory.
- For onboarding, give a short reading and hands-on path tailored to GPU allocation, ComputeDomains, deployment, documentation, or testing.
- For ownership, separate official review/approval ownership from the component that logically owns the implementation.

Link to exact repository paths in the final answer. State which files were inspected, call out generated code, feature-gated behavior, and defaults that can change, and avoid presenting demos or documentation prose as proof of runtime behavior without checking the implementation and Helm wiring.
