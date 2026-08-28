---
name: dra-compute-domain-imex-workflows
description: Explain, design, and troubleshoot NVIDIA ComputeDomain and IMEX workflows across MNNVL topology, daemon lifecycle, clique readiness, DRA channel allocation, and workload injection. Use when asked about ComputeDomains, IMEX, MNNVL, GB200 or GB300 systems, clique readiness, or channel injection.
metadata:
  author: "DRA Driver for NVIDIA GPUs team"
---

# ComputeDomain and IMEX workflows

Reason from the current checkout and observed cluster state. Keep the cluster controller, per-domain daemon, DRA kubelet plugin, Kubernetes scheduler, and container runtime distinct; each owns a different transition in the workflow.

This skill covers `compute-domain.nvidia.com`. A ComputeDomain channel does not allocate GPUs. Workloads must request GPUs separately and must coordinate worker count, placement, and MNNVL topology at the application or workload-controller layer.

## Establish the environment and contract

Before explaining or changing a workflow, identify:

- The hardware topology. ComputeDomains require Grace Blackwell Multi-Node NVLink systems such as NVIDIA HGX GB200 NVL72 or GB300 NVL72; a set of ordinary GPU nodes is not equivalent.
- The driver, Container Toolkit/CDI, Kubernetes DRA API, NFD, and GFD versions against `site/content/docs/prerequisites.md`.
- Which component owns `nvidia.com/gpu.clique`: GFD or the ComputeDomain kubelet plugin. Do not configure competing owners.
- Whether `resources.computeDomains.enabled` is true and whether IMEX is `driverManaged` or `hostManaged`.
- The states of `IMEXDaemonsWithDNSNames`, `ComputeDomainCliques`, `HostManagedIMEXDaemon`, and `CrashOnNVLinkFabricErrors` in the installed release.
- The ComputeDomain namespace, name, UID, generated workload claim-template name, selected nodes, and driver namespace.
- Whether the request is stuck during controller reconciliation, DRA allocation, driver-managed daemon bootstrap, local readiness, CDI injection, workload execution, or cleanup.

Use the current concept, prerequisites, workload guide, Helm values, API types, and code. Some older demos use superseded DeviceClass names, nonzero `numNodes`, or omit the topology checks expected by current documentation; do not treat them as the current contract without verification.

## Keep the domain objects distinct

- **ComputeDomain:** a namespaced, immutable `resource.nvidia.com/v1beta1` orchestration resource. Its controller-generated opaque configs use the object's UID as `domainID`; the human-readable name is not the domain identifier.
- **MNNVL clique:** nodes attached to the same NVLink fabric partition, identified from NVML and represented by `nvidia.com/gpu.clique`. A ComputeDomain can observe more than one clique; daemon peer configuration and readiness are grouped by clique.
- **IMEX daemon:** `nvidia-imex`, which brokers cross-node GPU memory exchange. The driver either runs one daemon per participating node and ComputeDomain or validates an administrator-managed host service.
- **ComputeDomainClique:** a namespaced CR in the driver namespace named `<compute-domain-uid>.<clique-id>`. Its `daemons` entries carry node name, pod IP, clique ID, stable index, and readiness.
- **IMEX channel:** a character device such as `/dev/nvidia-caps-imex-channels/channel0`, allocated through DRA and injected through CDI.
- **Workload ResourceClaimTemplate:** generated in the ComputeDomain namespace using the name in `spec.channel.resourceClaimTemplate.name`. Workload pods reference this template; users normally should not hand-author the opaque `domainID` config.

Do not use `ComputeDomain.status.status` as the workload's admission mechanism. The API explicitly treats it as debugging guidance; the kubelet plugin checks local readiness during Prepare.

## Select the IMEX lifecycle mode

| Mode | Owner and behavior |
| --- | --- |
| `driverManaged` | Default. The controller creates a per-ComputeDomain daemon DaemonSet and daemon claim template; daemon pods start `nvidia-imex`, register with their clique, and report readiness. The host `nvidia-imex.service` must not compete with them. |
| `hostManaged` | The administrator owns a continuously running host `nvidia-imex` service. The controller creates only the workload claim template; no per-domain daemon DaemonSet, daemon claim template, node label, or ComputeDomainClique is expected. Requires `HostManagedIMEXDaemon=true`. |

The only supported isolation setting is currently `domain`. `channel` is reserved but rejected at startup. Changing mode or isolation with active ComputeDomains is unsupported: drain ComputeDomain workloads and remove the ComputeDomains before changing either value.

When GPU Operator manages prerequisites or installation, defer operator-specific lifecycle instructions to the GPU Operator project. Continue using this skill for runtime object flow, readiness, and workload injection reasoning.

## Trace the driver-managed bootstrap loop

The driver-managed path is deliberately co-dependent. Trace it in this order:

1. A user creates a `ComputeDomain` with a workload `ResourceClaimTemplate` name and normally `numNodes: 0`.
2. `compute-domain-controller` adds a finalizer and creates:
   - The named workload `ResourceClaimTemplate` in the ComputeDomain namespace.
   - A daemon `ResourceClaimTemplate` in the driver namespace.
   - A per-ComputeDomain daemon DaemonSet in the driver namespace.
3. The daemon DaemonSet selects nodes labeled `resource.nvidia.com/computeDomain=<compute-domain-uid>`. Initially it may have no pods; this is not by itself a controller failure.
4. A workload pod references the generated template. The scheduler allocates `channel-0` from a `compute-domain.nvidia.com` ResourceSlice on a compatible node and records the driver, pool, device, and request in the generated claim's `status.allocation`.
5. Kubelet calls the ComputeDomain plugin's Prepare. The plugin verifies namespace/UID linkage and channel availability, then adds the ComputeDomain label to that node. It returns a retryable readiness error until the node's domain daemon becomes ready.
6. The new node label causes the per-domain DaemonSet pod to schedule there. Its generated daemon claim allocates `daemon-0` on the same node.
7. Preparing the daemon claim creates the domain config directory and template, returns CDI devices for the NVIDIA base spec and claim-specific environment/mounts, and includes the fabric-IMEX management device on a fabric-attached node.
8. The container runtime applies CDI. The `compute-domain-daemon` wrapper receives the ComputeDomain identity and `/imexd` mount, joins the appropriate clique, builds peer configuration, starts and supervises `nvidia-imex`, and reports its pod readiness.
9. With `ComputeDomainCliques` enabled, the daemon creates or updates `<uid>.<clique-id>` and its own daemon entry. The controller reflects clique information into `ComputeDomain.status.nodes` and cleans stale entries. With the gate disabled, the daemon writes the legacy node information directly to ComputeDomain status.
10. A later workload Prepare sees the current node ready, generates claim-specific CDI edits for the requested IMEX channel devices, checkpoints the prepared claim, and returns CDI IDs. The runtime then injects the character devices into the consuming container.

The plugin disables library-level serialization because workload-channel and daemon-claim Prepare calls must make progress together. It serializes its own state mutations and retries retryable Prepare/Unprepare work within a bounded request window; kubelet can retry later. A workload pod in `ContainerCreating` while its per-domain daemon is bootstrapping can therefore be expected transient behavior.

## Trace host-managed preparation separately

In host-managed mode:

1. The controller admits the ComputeDomain, creates only its workload claim template, and marks the global ComputeDomain status Ready.
2. The workload channel claim allocates `channel-0`. The controller forces generated config to `Single`, even when the ComputeDomain requested `All`.
3. During Prepare on a fabric-attached node, the kubelet plugin runs `nvidia-imex-ctl -q --u=<socket>` under the configured driver root and requires a `READY` response from the host service.
4. When the check succeeds, the plugin emits CDI edits for channel 0. When it fails, Prepare is retried; the pod must not start silently without a ready host daemon.

Global `ComputeDomain` Ready in this mode means only that the controller admitted the resource and created its workload template. It says nothing about host service health. Validate the service and command socket on every possible workload node.

Host-managed mode currently shares the host IMEX domain and channel 0; it does not create per-ComputeDomain daemon isolation. Deleting a ComputeDomain removes the generated workload template but does not stop or reconfigure the host service.

## Understand publication, allocation, and channel modes

The ComputeDomain kubelet plugin enumerates local channel and daemon devices but publishes a narrow scheduler-facing view:

- In driver-managed mode, each node normally publishes `channel-0` and `daemon-0` under driver `compute-domain.nvidia.com`.
- In host-managed mode, `daemon-0` is intentionally omitted.
- Channel devices have `type: channel` and integer `id`; daemon devices have `type: daemon` and integer `id`.
- `compute-domain-default-channel.nvidia.com` selects `type == 'channel' && id == 0`.
- `compute-domain-daemon.nvidia.com` selects `type == 'daemon'` and is not rendered for host-managed mode.

The scheduler allocates one advertised DRA device. `spec.channel.allocationMode: All` does not make the scheduler allocate every channel: in driver-managed mode, the generated config still allocates channel 0 and Prepare injects every locally available channel. `Single` injects one. Host-managed mode always reduces `All` to `Single`.

The node-local checkpoint prevents two completed claims from owning the same channel ID concurrently. Distinguish “all containers in one pod use the same claim” from multiple independent claims trying to prepare channel 0 on the same node.

The opaque `ComputeDomainChannelConfig` and `ComputeDomainDaemonConfig` validate `domainID` as a safe path component and Kubernetes label value. The plugin also requires a channel claim's namespace to equal the referenced ComputeDomain's namespace. Inspect the controller-generated template before blaming scheduling.

## Interpret clique and readiness semantics

With the default DNS and clique gates:

- Set deprecated `numNodes` to `0`. Daemons start without waiting for a fixed peer count, and workloads are released after their local daemon is ready.
- Each clique allocates stable daemon indices used to build names such as `compute-domain-daemon-0000` and peer configuration.
- The kubelet plugin accepts the current node as ready when its daemon is Ready in the matching `ComputeDomainClique`; it retains a legacy `ComputeDomain.status.nodes` fallback for transitions.
- The controller derives global status from the accumulated node entries, but with `numNodes: 0` it can be Ready before any daemon exists. Local Prepare readiness is the meaningful gate.

When `IMEXDaemonsWithDNSNames=false`, `numNodes` must equal the expected worker-node count. Daemon peer configuration waits for that complete set, and workload Prepare remains blocked until the domain is joined. Treat this as a compatibility/downgrade path, not the default design.

An empty clique ID means the node is not fabric-attached. Current code can let a channel claim succeed without adding IMEX channel device edits on such a node. Require workload node affinity for `nvidia.com/gpu.clique` and verify the injected character device so a Running pod cannot become a false-positive test.

`nvidia.com/gpu.clique` describes physical fabric membership. `resource.nvidia.com/computeDomain=<uid>` is a transient driver-managed node label that activates the per-domain DaemonSet on a chosen node. Do not conflate or manually prepopulate them during ordinary use.

## Validate the complete workload result

Start with read-only observations:

```bash
kubectl get computedomain -A -o yaml
kubectl get computedomainclique -A -o yaml
kubectl get resourceclaimtemplate,resourceclaim -A -o wide
kubectl get resourceslice -o yaml
kubectl get deviceclass -o yaml
kubectl get daemonset,pod -A -l resource.nvidia.com/computeDomain=<compute-domain-uid> -o wide
kubectl get node <node-name> --show-labels
kubectl describe pod -n <namespace> <workload-pod>
kubectl get events -n <namespace> --sort-by=.lastTimestamp
```

Inspect logs from all three owners, using the actual installed names and labels:

- Controller Deployment, container `compute-domain`.
- Per-node kubelet-plugin DaemonSet, container `compute-domains`, on the workload node.
- Per-ComputeDomain daemon pod, container `compute-domain-daemon`, on that node.

Success requires more than Pod Running:

```bash
kubectl exec -n <namespace> <workload-pod> -- test -c /dev/nvidia-caps-imex-channels/channel0
kubectl exec -n <namespace> <workload-pod> -- ls -la /dev/nvidia-caps-imex-channels
```

For an MNNVL workload, also prove the intended workers landed on compatible clique-labeled nodes, received GPUs separately, and completed an inter-node operation such as the repository's nvbandwidth test. Channel presence proves injection, not cross-node correctness or performance.

## Diagnose at the first broken boundary

| Evidence | Likely boundary |
| --- | --- |
| No ComputeDomain controller or DeviceClasses | Helm wiring, resource enablement, API version, or controller startup |
| No `compute-domain.nvidia.com` ResourceSlice/channel 0 | kubelet-plugin registration, IMEX capability discovery, driver device nodes, or node targeting |
| ComputeDomain exists but no workload template | controller reconciliation, name/namespace conflict, RBAC, template rendering, or finalizer state |
| Driver-managed ComputeDomain has template and DaemonSet but zero daemon pods | expected until a workload Prepare labels a node, or a node-label/selector mismatch after allocation |
| Workload claim has no allocation | scheduler, DeviceClass, ResourceSlice pool, node affinity, or DRA API issue |
| Allocation exists and `FailedPrepareDynamicResources` repeats | inspect the selected node's ComputeDomain label, daemon pod/claim, config CDI, clique entry, and local readiness in that order |
| Daemon pod starts without injected identity or `/imexd` | CDI runtime integration or daemon-claim preparation |
| Daemon is running but clique entry is absent/NotReady | clique ID discovery, daemon API/RBAC, peer config, `nvidia-imex` process, probes, or stale entry handling |
| ComputeDomain is globally Ready but workload Prepare fails | global status is not local readiness; inspect the selected node's clique entry or host socket |
| Host-managed mode has no daemon/clique objects | expected; inspect the host service, matching socket path, driver root, and `nvidia-imex-ctl` result |
| Pod is Running but channel device is absent | non-fabric placement, missing container claim reference, CDI spec visibility, or runtime CDI support |
| Another channel claim fails as already allocated | node-local checkpoint ownership of the same channel ID; inspect existing prepared claims and pod lifecycle |
| ComputeDomain deletion hangs | inspect generated templates, daemon DaemonSet/claims, node labels, and finalizers before considering manual removal |

Correlate ComputeDomain namespace/name/UID, clique ID, node name, daemon pod IP/index, ResourceClaim UID, allocated pool/device, and CDI device ID explicitly. They identify different layers.

## Preserve operational boundaries

Read-only diagnosis does not authorize applying workloads, labeling nodes, changing Helm values, restarting plugins, stopping host services, or deleting ComputeDomains. Driver-managed and host-managed prerequisites invert the expected state of `nvidia-imex.service`; verify mode before suggesting service changes.

Do not force-remove ComputeDomain, DaemonSet, or ResourceClaimTemplate finalizers as a first cleanup step. The controller uses them to remove generated resources and transient node labels. Do not change IMEX mode/isolation, clique-label ownership, or host socket paths while active domains exist. If a user requests a mutation, identify exact nodes/domains, explain the expected transition, and define a rollback or stopping condition.

## Follow source ownership

- `site/content/docs/concepts/compute-domains.md` and `site/content/docs/concepts/architecture.md`: supported lifecycle modes and component flow.
- `site/content/docs/guides/compute-domain-workloads.md` and `site/content/docs/prerequisites.md`: current manifests, topology guardrails, host service configuration, and validation.
- `api/nvidia.com/resource/v1beta1/computedomain.go`, `computedomainclique.go`, and `computedomainconfig.go`: handwritten CR and opaque-config contracts. Helm CRDs and `pkg/nvidia.com/` clients are generated from these sources.
- `deployments/helm/dra-driver-nvidia-gpu/values.yaml`, `deployments/helm/dra-driver-nvidia-gpu/templates/controller.yaml`, `deployments/helm/dra-driver-nvidia-gpu/templates/kubeletplugin.yaml`, and `deployments/helm/dra-driver-nvidia-gpu/templates/deviceclass-compute-domain-*.yaml`: installation and process wiring.
- `cmd/compute-domain-controller/computedomain.go`, `daemonset.go`, `resourceclaimtemplate.go`, `cdclique.go`, `cdstatus.go`, and `node.go`: reconciliation, generated resources, status aggregation, labels, cleanup, and finalizers.
- `templates/compute-domain-*.tmpl.*`: runtime-generated DaemonSet, claim, and IMEX configuration inputs; these are not Helm templates.
- `cmd/compute-domain-kubelet-plugin/driver.go`, `device_state.go`, `computedomain.go`, `nvlib.go`, `deviceinfo.go`, `cdi.go`, and `checkpoint*.go`: ResourceSlice publication, Prepare retries, local readiness, channel/daemon CDI, and persisted state.
- `cmd/compute-domain-daemon/controller.go`, `cdclique.go`, `cdstatus.go`, `dnsnames.go`, `podmanager.go`, and `process.go`: clique membership, peer naming, readiness propagation, and `nvidia-imex` supervision.
- `pkg/imex/imex.go`: shared validation of mode and isolation.
- `demo/specs/imex/`, `tests/bats/test_cd_imex_chan_inject.bats`, and `tests/bats/test_cd_mnnvl_workload.bats`: examples and invasive live-cluster validation. Check them against current docs and implementation before reuse.

For API, CRD, opaque-config, or feature-gate changes, also load `dra-api-crd-feature-gate-change`. For installation or sample execution, load `dra-helm-demo-sample-workloads`; for CI or BATS execution, load `dra-build-test-codegen-ci`.

## Shape the response

Lead with the failing lifecycle boundary and mode. Show the evidence chain from ComputeDomain UID to generated template, allocated channel, selected node label, daemon claim/pod, clique readiness or host socket, returned CDI ID, and injected character device. Distinguish expected bootstrap delay from a stable failure, and distinguish channel injection from proof that the multi-node GPU workload is correctly placed and functioning.
