---
name: dra-build-test-codegen-ci
description: Guide local builds, formatting, linting, code generation, unit and integration tests, BATS, end-to-end coverage, dependency checks, PR preparation, and CI debugging for the DRA Driver for NVIDIA GPUs. Use when a user asks how to test or validate a change, prepare a PR, run codegen, reproduce or debug CI, choose test coverage, or check whether a change is ready to merge.
metadata:
  author: "DRA Driver for NVIDIA GPUs team"
---

# DRA Build, Test, Codegen, and CI

Choose the smallest test tier that can disprove the change, then expand toward the repository's CI gates. Ground commands in the current `Makefile`, `tests/bats/Makefile`, and `.github/workflows/`; these evolve.

Do not treat “run tests” as authorization to touch a Kubernetes cluster. Unit tests and local builds are the default. BATS, Go e2e, image copying, cluster creation, and CI harness scripts can mutate or delete cluster resources; inspect the current context and obtain explicit confirmation unless the user already requested that exact live-cluster action.

## Understand the local targets

| Goal | Preferred entry point | Important behavior |
|---|---|---|
| Compile packages | `make build` | Runs `go build ./...` with the Makefile's `GOOS`, `GOARCH`, and compiler settings. Defaults target Linux. |
| Compile all five commands | `make cmds` | Builds every directory under `cmd/`; uses CGO and embeds version/commit metadata. Use `make cmd-<name>` for one binary. |
| Focused Go test | `go test ./path/to/package` | Fast iteration. Add the relevant test name or race mode when needed; do not replace broader verification with a single happy-path test. |
| Project unit suite | `make test` | Builds packages and commands first, then runs all module tests with `-race`, coverage, verbose output, and writes `coverage.out`. |
| Lint and formatting checks | `make golangci-lint` | Uses `.golangci.yaml`; includes gofmt and goimports formatters plus project linters. `make fmt` rewrites Go files and is broader than a check. |
| Helm chart lint | `make helm-lint` | Lints `deployments/helm/dra-driver-nvidia-gpu`; add targeted `helm template` cases for values and failure paths. |
| Generate API artifacts | `make generate` | Regenerates deepcopy, CRDs, clientset, listers, and informers, then formats the Go module. This mutates and replaces generated trees. |
| CI-style Go checks | `make check` | Runs golangci-lint and `check-generate`; see the clean-tree caveat below. |
| Dependency normalization | `make vendor` | Runs `go mod tidy`, `go mod vendor`, and `go mod verify`, mutating module and vendor files. |
| Runtime container image | `make -f deployments/container/Makefile build` | Builds the driver image. The root `make build-image` instead builds the development-tooling image. |

Use the Go version discovered by `./hack/golang-version.sh`, which reads the development Dockerfile and is also used by GitHub Actions. Code-generation tools are pinned or declared under `deployments/devel/`; install them with `make -C deployments/devel install-tools` when local installation is appropriate. This can download and write tools into the Go binary location.

To use the development container, prefix supported targets with `docker-` and set `BUILD_DEVEL_IMAGE=yes`, for example `BUILD_DEVEL_IMAGE=yes make docker-generate`. Docker access, image builds, and dependency downloads may require authorization in restricted environments.

## Handle generated code safely

The handwritten sources are under `api/nvidia.com/resource/v1beta1/`. Generated outputs include:

- `api/**/zz_generated.deepcopy.go`;
- `deployments/helm/dra-driver-nvidia-gpu/crds/`;
- `pkg/nvidia.com/clientset/`;
- `pkg/nvidia.com/listers/`;
- `pkg/nvidia.com/informers/`.

Before `make generate`, inspect `git status` and determine whether those paths or Go formatting overlap unrelated user changes. The target removes and recreates generated directories and runs `make fmt`; do not run it over ambiguous overlapping work.

After generation, review the semantic diff:

- CRD requiredness, defaults, validation, list semantics, and served fields;
- deepcopy coverage for new pointers, slices, and maps;
- client, lister, and informer resources and pluralization;
- unexpected formatting outside the intended change;
- deletions or broad churn that indicate a tool-version mismatch.

`make check-generate` is not a read-only “is codegen current?” command. It runs `make generate` and then `git diff --exit-code HEAD` for the whole tree. It therefore fails on normal uncommitted source or generated changes even when generation is correct. Use it to reproduce CI from a clean commit or disposable clean checkout. During active development, run `make generate`, inspect the resulting diff, and confirm a second generation produces no additional changes through an appropriate clean-tree workflow.

The same caveat applies to `make check`: it includes `check-generate`. Do not report its expected dirty-tree diff as a code-generation failure.

## Handle module changes

Root dependencies live in `go.mod`, `go.sum`, and `vendor/`; code-generation tool dependencies have a separate module under `deployments/devel/`.

- Run `make vendor` after an intentional root dependency change and inspect all three outputs.
- Run the development module's normalization/check when `deployments/devel/go.mod`, `go.sum`, or its vendor tree changes.
- `make check-modules` runs `make vendor` and then compares root dependency files with `HEAD`. It is designed for a clean CI checkout; an intentional uncommitted dependency diff makes it fail until that diff is part of `HEAD`.
- CI runs both the root and `deployments/devel` module checks. A passing `go test` does not prove vendoring is current.

## Select tests by change

- Go implementation or bug fix: adjacent package tests first, then `make test` and lint.
- API or CRD: API/defaulting/validation tests, affected controller/plugin tests, `make generate`, Helm lint, and upgrade coverage when stored objects change.
- Opaque config or webhook: API tests, both direct kubelet validation paths that consume the config, and webhook tests for ResourceClaims and ResourceClaimTemplates.
- ResourceSlice publication or scheduling contract: producer unit tests, `test/e2e/` when its scenarios cover the attribute/capacity, and the matching BATS or mock-NVML path.
- Checkpoint or recovery logic: version/conversion/checksum unit tests plus upgrade/downgrade and restart BATS coverage.
- Helm-only change: `make helm-lint` plus targeted rendering with representative valid, disabled, invalid, and upgrade values. GitHub's Helm job only runs chart lint.
- Dependency change: targeted build/tests, root or development vendoring as applicable, and module checks from a clean commit.
- Documentation-only change: do not run GPU suites by reflex; use the documentation workflow described under `site/content/contribute/docs.md` when rendering matters.

When reporting validation, distinguish tests actually run from tests recommended or unavailable. Include the exact command, result, and any skipped hardware, cluster, or version combination.

## Run live-cluster tests deliberately

Read `tests/bats/README.md` and the variable block in `tests/bats/Makefile` before recommending or running BATS. Resolve and show the current Kubernetes context and cluster, intended chart/image, GPU topology, and cleanup behavior before execution.

Key entry points:

- `make bats` runs the complete BATS suite through a container.
- `make bats-gpu` and `make bats-cd` select broad GPU or ComputeDomain subsets.
- `make -f tests/bats/Makefile tests-gpu-single`, `tests-gpu-a10`, `tests-gpu-dynmig`, or `tests-mock-nvml` select environment-specific subsets.
- `TEST_FILTER_TAGS` narrows tagged tests. `BATS_ARGS` controls output and abort behavior.
- `make test-e2e` runs the Go/Ginkgo suite against the current `kubectl` context; it assumes a compatible cluster, GPU Operator setup, and installed driver. It writes JUnit output under `ARTIFACTS`.

BATS is invasive. Its default flow cleans resources from the currently configured cluster, installs a chart, and stops on the first failure. By default it targets a staging chart derived from the checkout revision, not the local chart. Testing local code requires a locally built image available to every node and `TEST_CHART_LOCAL=1`. Do not set `SKIP_CLEANUP=true` casually; it changes isolation assumptions and can leave state that invalidates later results.

The mock-NVML harness at `hack/ci/mock-nvml/e2e-test.sh` creates and deletes a Kind cluster and host-side mock GPU artifacts. It is CPU-only coverage but still requires Docker, elevated host operations in parts of setup, network downloads, and cluster mutation. The Lambda harness under `hack/ci/lambda/` is for real-GPU Prow lanes and should not be treated as an ordinary local command.

Capture the BATS run directory and cluster artifacts. On failure, collect driver containers, controller, kubelet, events, ResourceClaims, ResourceSlices, DeviceClasses, checkpoint contents when relevant, and the exact chart/image/version inputs before cleanup destroys evidence.

## Reproduce and debug CI

Map the failing job to its local equivalent before changing code:

- GitHub `ci` calls reusable basic checks for Helm lint, Go lint/generated/module checks, unit tests, builds, and CodeQL.
- The Go check job installs codegen tools, runs golangci-lint, `make check-generate`, root `make check-modules`, and the development-module check.
- The unit job runs `make test`; the build job runs `make build`; CodeQL builds with `make build`.
- `mock-nvml-e2e.yaml` is path-filtered and runs the CPU-only Kind/BATS harness for relevant code, package, deployment, test, and module changes.
- `.github/workflows/tests.yaml` does not execute BATS; it records that GPU integration suites run in Prow.
- Real-GPU and ComputeDomain presubmits are configured in Kubernetes test-infra and use `hack/ci/lambda/e2e-test.sh` with hardware-specific filters.

Debug the first causal failure, not later cancellation or cascade noise. Reproduce the CI Go version, codegen tool versions, vendored module mode, OS/architecture, values, feature gates, and test subset. For a generated-code failure, inspect the CI-produced diff. For mock or real-GPU failures, inspect uploaded artifacts and capability filters before assuming the test is flaky.

Do not call a failure flaky from a single run. Look for a prior issue, nondeterministic ordering, timing-sensitive logs, resource leakage, or a hardware/version-specific branch. If an authorized rerun passes, preserve both outcomes and explain the suspected source rather than treating the rerun as a fix.

## Prepare a PR-ready handoff

Summarize:

- change areas and the test tier selected for each;
- commands run and their outcomes;
- generated or vendored artifacts reviewed;
- Helm render combinations checked;
- cluster, GPU, Kubernetes, NVIDIA driver, chart, image, and feature-gate details for integration tests;
- CI-only or hardware-specific coverage left to presubmit;
- known gaps, flakes, or cleanup state.

PR readiness means the checked-in result is reproducible from a clean checkout. It does not mean every invasive or expensive suite must be run locally; it does require identifying which CI lane owns the remaining evidence.
