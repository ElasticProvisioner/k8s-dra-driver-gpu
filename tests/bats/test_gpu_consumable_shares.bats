# shellcheck disable=SC2148
# shellcheck disable=SC2329

# Tests for ConsumableShares GPU sharing mode.
# Requires feature gate: ConsumableShares=true.

setup_file() {
  load 'helpers.sh'
  _common_setup
  local _iargs=("--set" "logVerbosity=6"
    "--set" "featureGates.MPSSupport=true"
    "--set" "featureGates.ConsumableShares=true"
    "--set" "consumableShares=4")
  if [ "${DISABLE_COMPUTE_DOMAINS:-}" = "true" ]; then
    _iargs+=("--set" "resources.computeDomains.enabled=false")
  fi
  iupgrade_wait "${TEST_CHART_REPO}" "${TEST_CHART_VERSION}" _iargs
}

setup() {
  load 'helpers.sh'
  _common_setup
  log_objects
}

bats::on_failure() {
  echo -e "\n\nFAILURE HOOK START"
  log_objects
  show_kubelet_plugin_error_logs
  show_gpu_plugin_log_tails
  echo -e "FAILURE HOOK END\n\n"
}

# bats test_tags=fastfeedback,gpu-sharing,consumable-shares
@test "GPUs: ConsumableShares — memory mode with 2 independent pods" {
  local _specpath="tests/bats/specs/gpu-consumable-shares-memory.yaml"

  kubectl apply -f "${_specpath}"
  kubectl wait --for=condition=READY pods "pod-share-memory-0" --timeout=45s
  kubectl wait --for=condition=READY pods "pod-share-memory-1" --timeout=45s

  run kubectl logs "pod-share-memory-0" -c ctr
  assert_output --partial "UUID: GPU-"
  local uid0="${output}"

  run kubectl logs "pod-share-memory-1" -c ctr
  assert_output --partial "UUID: GPU-"
  local uid1="${output}"

  assert_equal "$uid0" "$uid1"

  kubectl delete -f "${_specpath}"
  kubectl wait --for=delete pods "pod-share-memory-0" --timeout=30s
  kubectl wait --for=delete pods "pod-share-memory-1" --timeout=30s
}

# bats test_tags=fastfeedback,gpu-sharing,consumable-shares
@test "GPUs: ConsumableShares — integer shares mode with 2 independent pods" {
  local _specpath="tests/bats/specs/gpu-consumable-shares-integer.yaml"

  kubectl apply -f "${_specpath}"
  kubectl wait --for=condition=READY pods "pod-share-integer-0" --timeout=45s
  kubectl wait --for=condition=READY pods "pod-share-integer-1" --timeout=45s

  run kubectl logs "pod-share-integer-0" -c ctr
  assert_output --partial "UUID: GPU-"
  local uid0="${output}"

  run kubectl logs "pod-share-integer-1" -c ctr
  assert_output --partial "UUID: GPU-"
  local uid1="${output}"

  assert_equal "$uid0" "$uid1"

  kubectl delete -f "${_specpath}"
  kubectl wait --for=delete pods "pod-share-integer-0" --timeout=30s
  kubectl wait --for=delete pods "pod-share-integer-1" --timeout=30s
}

# bats test_tags=fastfeedback,gpu-sharing,consumable-shares
@test "GPUs: ConsumableShares — MPS request fails when consumable shares enabled" {
  local _specpath="tests/bats/specs/gpu-mps.yaml"

  kubectl apply -f "${_specpath}"
  # Pod should fail to reach READY because driver rejects MPS under consumable shares
  run kubectl wait --for=condition=READY pods "pod-mps" --timeout=15s
  [ "$status" -ne 0 ]

  kubectl delete --ignore-not-found -f "${_specpath}"
}
