#!/usr/bin/env bats
#
# Integration tests — require a live Kubernetes cluster reachable via kubectl.
# Skipped automatically when no cluster is available.

setup() {
  export SCRIPT="${BATS_TEST_DIRNAME}/../src/kubeconfig-generator.sh"
  TEST_TMPDIR=$(mktemp -d)
  export TEST_TMPDIR

  if ! kubectl cluster-info >/dev/null 2>&1; then
    skip "no Kubernetes cluster available"
  fi

  export TEST_NAMESPACE="kubeconfig-generator-test"
  export TEST_SA="test-service-account"

  kubectl create namespace "${TEST_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl create serviceaccount "${TEST_SA}" -n "${TEST_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
}

teardown() {
  kubectl delete namespace "${TEST_NAMESPACE}" --ignore-not-found >/dev/null 2>&1 || true
  rm -rf "${TEST_TMPDIR}"
}

@test "generates a working kubeconfig with a temporary token" {
  local out_file="${TEST_TMPDIR}/temp-kubeconfig.yaml"

  run bash "$SCRIPT" -n "${TEST_NAMESPACE}" -o "${out_file}" "${TEST_SA}"
  [ "$status" -eq 0 ]

  [ -f "${out_file}" ]

  local perms
  perms="$(stat -c %a "${out_file}")"
  [ "${perms}" = "600" ]

  run kubectl --kubeconfig "${out_file}" auth whoami
  [ "$status" -eq 0 ]
  [[ "$output" == *"${TEST_SA}"* ]]
}

@test "generates a working kubeconfig with a permanent token" {
  local out_file="${TEST_TMPDIR}/perm-kubeconfig.yaml"

  run bash "$SCRIPT" -n "${TEST_NAMESPACE}" -t permanent -o "${out_file}" "${TEST_SA}"
  [ "$status" -eq 0 ]

  [ -f "${out_file}" ]

  local perms
  perms="$(stat -c %a "${out_file}")"
  [ "${perms}" = "600" ]

  run kubectl --kubeconfig "${out_file}" auth whoami
  [ "$status" -eq 0 ]
  [[ "$output" == *"${TEST_SA}"* ]]
}

@test "uses custom token duration for temporary tokens" {
  local out_file="${TEST_TMPDIR}/short-kubeconfig.yaml"

  run bash "$SCRIPT" -n "${TEST_NAMESPACE}" -d 1h -o "${out_file}" "${TEST_SA}"
  [ "$status" -eq 0 ]

  [ -f "${out_file}" ]

  # Verify token exists and kubeconfig is valid yaml
  run kubectl --kubeconfig "${out_file}" auth whoami
  [ "$status" -eq 0 ]
}

@test "exits with error when service account does not exist" {
  run bash "$SCRIPT" -n "${TEST_NAMESPACE}" nonexistent-sa
  [ "$status" -eq 1 ]
  [[ "$output" == *"Error: ServiceAccount 'nonexistent-sa' not found"* ]]
}

@test "exits with error when kubeconfig has no cluster data" {
  run env KUBECONFIG=/dev/null bash "$SCRIPT" "${TEST_SA}"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Error: could not extract cluster name, server, or CA data"* ]]
}

@test "output filename defaults to service-account-kubeconfig.yaml" {
  cd "${TEST_TMPDIR}"
  run bash "$SCRIPT" -n "${TEST_NAMESPACE}" "${TEST_SA}"
  [ "$status" -eq 0 ]

  [ -f "${TEST_TMPDIR}/${TEST_SA}-kubeconfig.yaml" ]
}
