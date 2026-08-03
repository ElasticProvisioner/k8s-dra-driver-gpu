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

# common.sh -- Shared defaults for mock NVML CI scripts.
# Source this file; do not execute it directly.

# Ensure go-installed binaries (kind, etc.) are on PATH.
export PATH="${GOPATH:-$(go env GOPATH)}/bin:${PATH}"

GPU_PROFILE="${GPU_PROFILE:-gb200}"
GPU_COUNT="${GPU_COUNT:-8}"
K8S_TEST_INFRA_DIR="${K8S_TEST_INFRA_DIR:-$(go env GOPATH)/src/github.com/nvidia/k8s-test-infra}"
MOCK_ROOT="${MOCK_ROOT:-/var/lib/nvml-mock}"
DRIVER_ROOT="${DRIVER_ROOT:-${MOCK_ROOT}/driver}"
DEV_ROOT="${MOCK_ROOT}/dev"

# Derive driver version from profile. Blackwell profiles use 570.x to satisfy
# the compute-domain IMEXDaemonsWithDNSNames feature gate (>= 570.158.01).
case "${GPU_PROFILE}" in
  b200|gb200) DRIVER_VERSION="${DRIVER_VERSION:-570.170.01}" ;;
  *)          DRIVER_VERSION="${DRIVER_VERSION:-550.163.01}" ;;
esac

# Profile metadata lookup.
mock_nvml_expected_name() {
  case "$1" in
    a100)  echo "NVIDIA A100-SXM4-40GB" ;;
    h100)  echo "NVIDIA H100 80GB HBM3" ;;
    b200)  echo "NVIDIA B200" ;;
    gb200) echo "NVIDIA GB200" ;;
    l40s)  echo "NVIDIA L40S" ;;
    t4)    echo "NVIDIA T4" ;;
    *)     echo "UNKNOWN" ;;
  esac
}
