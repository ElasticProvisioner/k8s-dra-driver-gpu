#!/usr/bin/env bash
# Copyright The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# verify-mock-gpu.sh -- Validate mock NVML installation at each layer.
#
# Runs a sequence of checks from low-level (library symbols) to high-level
# (nvidia-smi output, Docker container injection). Exits non-zero on first failure.
#
# Usage:
#   GPU_PROFILE=gb200 GPU_COUNT=8 ./verify-mock-gpu.sh
#   GPU_PROFILE=gb200 GPU_COUNT=8 VERIFY_DOCKER=true ./verify-mock-gpu.sh
set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hack/ci/mock-nvml/common.sh
source "${SCRIPT_DIR}/common.sh"
VERIFY_DOCKER="${VERIFY_DOCKER:-false}"

EXPECTED_NAME="$(mock_nvml_expected_name "${GPU_PROFILE}")"
EXPECTED_DRIVER="${DRIVER_VERSION}"

PASS=0
FAIL=0
SKIP=0

check() {
  local desc="$1"
  shift
  echo -n "  CHECK: ${desc} ... "
  if "$@" > /dev/null 2>&1; then
    echo "PASS"
    PASS=$((PASS + 1))
  else
    echo "FAIL"
    FAIL=$((FAIL + 1))
  fi
}

check_output() {
  local desc="$1"
  local expected="$2"
  shift 2
  echo -n "  CHECK: ${desc} ... "
  local output
  if output=$("$@" 2>&1); then
    if echo "${output}" | grep -qF "${expected}"; then
      echo "PASS"
      PASS=$((PASS + 1))
    else
      echo "FAIL (expected '${expected}' in output)"
      echo "    got: $(echo "${output}" | head -3)"
      FAIL=$((FAIL + 1))
    fi
  else
    echo "FAIL (command failed)"
    FAIL=$((FAIL + 1))
  fi
}

check_count() {
  local desc="$1"
  local expected_count="$2"
  shift 2
  echo -n "  CHECK: ${desc} ... "
  local output
  if output=$("$@" 2>&1); then
    local actual_count
    actual_count=$(echo "${output}" | wc -l)
    if [ "${actual_count}" -eq "${expected_count}" ]; then
      echo "PASS (${actual_count})"
      PASS=$((PASS + 1))
    else
      echo "FAIL (expected ${expected_count}, got ${actual_count})"
      FAIL=$((FAIL + 1))
    fi
  else
    echo "FAIL (command failed)"
    FAIL=$((FAIL + 1))
  fi
}

skip_check() {
  local desc="$1"
  local reason="$2"
  echo "  SKIP: ${desc} (${reason})"
  SKIP=$((SKIP + 1))
}

NVIDIA_SMI="${DRIVER_ROOT}/usr/bin/nvidia-smi"

# =========================================================================
echo "=== Layer 1: Mock NVML Library ==="
# =========================================================================
check "libnvidia-ml.so exists" \
  test -f "${DRIVER_ROOT}/usr/lib64/libnvidia-ml.so"

check "libnvidia-ml.so.1 symlink exists" \
  test -L "${DRIVER_ROOT}/usr/lib64/libnvidia-ml.so.1"

check "libnvidia-ml.so is ELF shared object" \
  file "${DRIVER_ROOT}/usr/lib64/libnvidia-ml.so" -b

# Check that key NVML symbols are exported
check_output "nvmlInit_v2 symbol exported" "nvmlInit_v2" \
  nm -D "${DRIVER_ROOT}/usr/lib64/libnvidia-ml.so"

check_output "nvmlDeviceGetCount_v2 symbol exported" "nvmlDeviceGetCount_v2" \
  nm -D "${DRIVER_ROOT}/usr/lib64/libnvidia-ml.so"

check_output "nvmlDeviceGetName symbol exported" "nvmlDeviceGetName" \
  nm -D "${DRIVER_ROOT}/usr/lib64/libnvidia-ml.so"

check_output "nvmlDeviceGetMemoryInfo symbol exported" "nvmlDeviceGetMemoryInfo" \
  nm -D "${DRIVER_ROOT}/usr/lib64/libnvidia-ml.so"

check_output "nvmlDeviceGetArchitecture symbol exported" "nvmlDeviceGetArchitecture" \
  nm -D "${DRIVER_ROOT}/usr/lib64/libnvidia-ml.so"

# =========================================================================
echo ""
echo "=== Layer 2: GPU Profile Config ==="
# =========================================================================
check "config.yaml exists at driver root" \
  test -f "${DRIVER_ROOT}/config/config.yaml"

check_output "config has correct GPU name" "${EXPECTED_NAME}" \
  cat "${DRIVER_ROOT}/config/config.yaml"

check_output "config has correct driver version" "${EXPECTED_DRIVER}" \
  cat "${DRIVER_ROOT}/config/config.yaml"

check_output "config has num_devices injected" "num_devices: ${GPU_COUNT}" \
  cat "${DRIVER_ROOT}/config/config.yaml"

# =========================================================================
echo ""
echo "=== Layer 2b: Mock PCI NUMA sysfs ==="
# =========================================================================
FIRST_PCI_BUS_ID=$(awk '/^[[:space:]]+bus_id:/ { gsub(/"/, "", $2); print tolower($2); exit }' "${DRIVER_ROOT}/config/config.yaml")
if [ -n "${FIRST_PCI_BUS_ID}" ]; then
  check "mock PCI sysfs numa_node exists for ${FIRST_PCI_BUS_ID}" \
    test -f "${DRIVER_ROOT}/sys/bus/pci/devices/${FIRST_PCI_BUS_ID}/numa_node"

  check_output "mock NUMA SLIT exposes same-socket distance" "10 12" \
    cat "${DRIVER_ROOT}/sys/devices/system/node/node0/distance"

  check_output "mock NUMA socket hint exists" "0" \
    cat "${DRIVER_ROOT}/sys/devices/system/cpu/cpu0/topology/physical_package_id"
else
  skip_check "mock PCI NUMA sysfs" "no PCI bus IDs in profile"
fi

# =========================================================================
echo ""
echo "=== Layer 3: Device Nodes ==="
# =========================================================================
for i in $(seq 0 $((GPU_COUNT - 1))); do
  check "/dev/nvidia${i} exists" \
    test -e "${DEV_ROOT}/nvidia${i}"
done

check "/dev/nvidiactl exists" \
  test -e "${DEV_ROOT}/nvidiactl"

check "/dev/nvidia-uvm exists" \
  test -e "${DEV_ROOT}/nvidia-uvm"

# =========================================================================
echo ""
echo "=== Layer 4: nvidia-smi Binary ==="
# =========================================================================
if [ -f "${NVIDIA_SMI}" ]; then
  check "nvidia-smi is executable" \
    test -x "${NVIDIA_SMI}"

  check_output "nvidia-smi RPATH set to \$ORIGIN/../lib64" '$ORIGIN/../lib64' \
    patchelf --print-rpath "${NVIDIA_SMI}"
else
  skip_check "nvidia-smi binary" "not installed (SKIP_NVIDIA_SMI was set)"
fi

# =========================================================================
echo ""
echo "=== Layer 5: nvidia-smi Output (Host) ==="
# =========================================================================
if [ -f "${NVIDIA_SMI}" ]; then
  check_output "nvidia-smi shows correct GPU name" "${EXPECTED_NAME}" \
    "${NVIDIA_SMI}"

  check_output "nvidia-smi shows correct driver version" "${EXPECTED_DRIVER}" \
    "${NVIDIA_SMI}"

  check_count "nvidia-smi -L shows ${GPU_COUNT} GPUs" "${GPU_COUNT}" \
    "${NVIDIA_SMI}" -L

  # Verify UUIDs are unique
  echo -n "  CHECK: nvidia-smi UUIDs are unique ... "
  UUID_COUNT=$("${NVIDIA_SMI}" -L | grep -oP 'UUID: \K[^ ]+' | sort -u | wc -l)
  if [ "${UUID_COUNT}" -eq "${GPU_COUNT}" ]; then
    echo "PASS (${UUID_COUNT} unique UUIDs)"
    PASS=$((PASS + 1))
  else
    echo "FAIL (expected ${GPU_COUNT} unique, got ${UUID_COUNT})"
    FAIL=$((FAIL + 1))
  fi
else
  skip_check "nvidia-smi output" "binary not installed"
fi

# =========================================================================
echo ""
echo "=== Layer 6: Compatibility Symlinks ==="
# =========================================================================
check "/run/nvidia/driver symlink exists" \
  test -L /run/nvidia/driver

check_output "/run/nvidia/driver points to driver root" "${DRIVER_ROOT}" \
  readlink -f /run/nvidia/driver

# =========================================================================
echo ""
echo "=== Layer 7: CDI Spec ==="
# =========================================================================
CDI_SPEC="/var/run/cdi/nvidia-mock.yaml"
check "CDI spec exists" \
  test -f "${CDI_SPEC}"

check_output "CDI spec has correct kind" "nvidia.com/gpu" \
  cat "${CDI_SPEC}"

check_output "CDI spec has 'all' device" 'name: "all"' \
  cat "${CDI_SPEC}"

# Check per-GPU entries
for i in $(seq 0 $((GPU_COUNT - 1))); do
  check_output "CDI spec has device ${i}" "name: \"${i}\"" \
    cat "${CDI_SPEC}"
done

# Check nvidia-ctk if available
if command -v nvidia-ctk > /dev/null 2>&1; then
  check_output "nvidia-ctk sees CDI devices" "nvidia.com/gpu" \
    nvidia-ctk cdi list
else
  skip_check "nvidia-ctk CDI validation" "nvidia-ctk not installed"
fi

# =========================================================================
echo ""
echo "=== Layer 8: Docker Container (mock GPU visible inside container) ==="
# =========================================================================
if [ "${VERIFY_DOCKER}" = "true" ] && command -v docker > /dev/null 2>&1; then
  # Test 1: Simple volume mount (no CDI)
  echo -n "  CHECK: nvidia-smi works in container (volume mount) ... "
  CONTAINER_OUTPUT=$(docker run --rm \
    -v "${DRIVER_ROOT}:/run/nvidia/driver:ro" \
    -e MOCK_NVML_CONFIG=/run/nvidia/driver/config/config.yaml \
    debian:bookworm-slim \
    /run/nvidia/driver/usr/bin/nvidia-smi -L 2>&1) || true

  CONTAINER_GPU_COUNT=$(echo "${CONTAINER_OUTPUT}" | grep -c "GPU " || true)
  if [ "${CONTAINER_GPU_COUNT}" -eq "${GPU_COUNT}" ]; then
    echo "PASS (${CONTAINER_GPU_COUNT} GPUs)"
    PASS=$((PASS + 1))
  else
    echo "FAIL (expected ${GPU_COUNT}, got ${CONTAINER_GPU_COUNT})"
    echo "    output: $(echo "${CONTAINER_OUTPUT}" | head -3)"
    FAIL=$((FAIL + 1))
  fi

  # Test 2: CDI injection (requires nvidia-container-toolkit configured)
  if command -v nvidia-ctk > /dev/null 2>&1; then
    echo -n "  CHECK: nvidia-smi works in container (CDI injection) ... "
    CDI_OUTPUT=$(docker run --rm \
      --device nvidia.com/gpu=all \
      -e MOCK_NVML_CONFIG=/run/nvidia/driver/config/config.yaml \
      -v "${DRIVER_ROOT}/config/config.yaml:/run/nvidia/driver/config/config.yaml:ro" \
      debian:bookworm-slim \
      nvidia-smi -L 2>&1) || true

    CDI_GPU_COUNT=$(echo "${CDI_OUTPUT}" | grep -c "GPU " || true)
    if [ "${CDI_GPU_COUNT}" -eq "${GPU_COUNT}" ]; then
      echo "PASS (${CDI_GPU_COUNT} GPUs via CDI)"
      PASS=$((PASS + 1))
    else
      echo "FAIL (expected ${GPU_COUNT}, got ${CDI_GPU_COUNT})"
      echo "    output: $(echo "${CDI_OUTPUT}" | head -5)"
      FAIL=$((FAIL + 1))
    fi
  else
    skip_check "CDI container injection" "nvidia-ctk not installed"
  fi
else
  if [ "${VERIFY_DOCKER}" != "true" ]; then
    skip_check "Docker container tests" "VERIFY_DOCKER not set to true"
  else
    skip_check "Docker container tests" "Docker not installed"
  fi
fi

# =========================================================================
echo ""
echo "========================================="
echo "  Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo "========================================="

if [ "${FAIL}" -gt 0 ]; then
  echo ""
  echo "VERIFICATION FAILED"
  exit 1
fi

echo ""
echo "ALL CHECKS PASSED"
