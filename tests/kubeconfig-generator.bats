#!/usr/bin/env bats

setup() {
  export SCRIPT="${BATS_TEST_DIRNAME}/../src/kubeconfig-generator.sh"
  TEST_TMPDIR=$(mktemp -d)
  export TEST_TMPDIR
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

@test "help flag shows usage information" {
  run bash "$SCRIPT" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"service_account"* ]]
  [[ "$output" == *"--namespace"* ]]
  [[ "$output" == *"--type"* ]]
  [[ "$output" == *"--duration"* ]]
}

@test "missing service account shows error" {
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Error: <service_account> is required"* ]]
}

@test "parse_args stores service account positional argument" {
  run bash -c "source '$SCRIPT'; parse_args -n test-ns 'my-sa'; echo \$serviceAccount"
  [ "$status" -eq 0 ]
  [[ "$output" == *"my-sa"* ]]
}

@test "parse_args stores -n value into namespace variable" {
  run bash -c "source '$SCRIPT'; parse_args -n my-ns my-sa; echo \$namespace"
  [ "$status" -eq 0 ]
  [[ "$output" == *"my-ns"* ]]
}

@test "parse_args stores --namespace value into namespace variable" {
  run bash -c "source '$SCRIPT'; parse_args --namespace my-ns my-sa; echo \$namespace"
  [ "$status" -eq 0 ]
  [[ "$output" == *"my-ns"* ]]
}

@test "parse_args stores -t value into tokenType variable" {
  run bash -c "source '$SCRIPT'; parse_args -n test-ns -t temporary my-sa; echo \$tokenType"
  [ "$status" -eq 0 ]
  [[ "$output" == *"temporary"* ]]
}

@test "parse_args stores --type permanent value into tokenType variable" {
  run bash -c "source '$SCRIPT'; parse_args -n test-ns --type permanent my-sa; echo \$tokenType"
  [ "$status" -eq 0 ]
  [[ "$output" == *"permanent"* ]]
}

@test "parse_args stores -d value into duration variable" {
  run bash -c "source '$SCRIPT'; parse_args -n test-ns -d 72h my-sa; echo \$duration"
  [ "$status" -eq 0 ]
  [[ "$output" == *"72h"* ]]
}

@test "parse_args stores --duration value into duration variable" {
  run bash -c "source '$SCRIPT'; parse_args -n test-ns --duration 1h my-sa; echo \$duration"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1h"* ]]
}

@test "parse_args stores -o value into outputFile variable" {
  run bash -c "source '$SCRIPT'; parse_args -n test-ns -o /tmp/out.yaml my-sa; echo \$outputFile"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/tmp/out.yaml"* ]]
}

@test "parse_args stores --output value into outputFile variable" {
  run bash -c "source '$SCRIPT'; parse_args -n test-ns --output /tmp/config my-sa; echo \$outputFile"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/tmp/config"* ]]
}

@test "default output file is derived from service account name" {
  run bash -c "source '$SCRIPT'; parse_args -n test-ns my-sa; echo \$outputFile"
  [ "$status" -eq 0 ]
  [[ "$output" == *"my-sa-kubeconfig.yaml"* ]]
}

@test "invalid token type is rejected" {
  run bash "$SCRIPT" -t invalid my-sa
  [ "$status" -eq 1 ]
  [[ "$output" == *"--type must be 'temporary' or 'permanent'"* ]]
}

@test "multiple positional service accounts are rejected" {
  run bash "$SCRIPT" sa1 sa2
  [ "$status" -eq 1 ]
  [[ "$output" == *"Error: unexpected positional argument"* ]]
}

@test "unknown option is rejected" {
  run bash "$SCRIPT" --unknown my-sa
  [ "$status" -eq 1 ]
  [[ "$output" == *"Error: unknown option"* ]]
}

@test "missing value for option is rejected" {
  run bash "$SCRIPT" -n
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing value"* ]]
}

@test "default token type is temporary" {
  run bash -c "source '$SCRIPT'; parse_args -n test-ns my-sa; echo \$tokenType"
  [ "$status" -eq 0 ]
  [[ "$output" == *"temporary"* ]]
}

@test "default duration is 24h" {
  run bash -c "source '$SCRIPT'; parse_args -n test-ns my-sa; echo \$duration"
  [ "$status" -eq 0 ]
  [[ "$output" == *"24h"* ]]
}

@test "kubeconfig file is created with 0600 permissions" {
  # Write a kubectl mock to a temp dir, prepend that dir to PATH.
  # Patterns match on the trailing jsonpath field name to avoid
  # glob-special `[` characters that appear in jsonpath args.
  local mock_dir
  mock_dir="$(mktemp -d)"
  cat > "${mock_dir}/kubectl" <<'MOCK_EOF'
#!/usr/bin/env bash
case "$*" in
  *".name}"*)                    echo "test-cluster" ;;
  *".server}"*)                  echo "https://test-server:443" ;;
  *"certificate-authority-data"*) echo "dGVzdGNh" ;;
  *"config"*)                    echo "default" ;;
  *"get serviceaccount"*)        exit 0 ;;
  *"create token"*)              echo "test-token-value" ;;
  *)                             exit 1 ;;
esac
MOCK_EOF
  chmod +x "${mock_dir}/kubectl"

  local out_file="${TEST_TMPDIR}/generated.yaml"
  run env PATH="${mock_dir}:$PATH" bash "$SCRIPT" -o "${out_file}" test-sa

  [ -f "${out_file}" ]
  local perms
  perms="$(stat -c %a "${out_file}")"
  [ "${perms}" = "600" ]

  rm -rf "${mock_dir}"
}

@test "get_cluster_details extracts name, server, and ca from kubectl output" {
  # Patterns match on trailing jsonpath field names to sidestep glob-special `[`.
  run bash -c "
    source '$SCRIPT'
    kubectl() {
      case \"\$*\" in
        *\".name}\"*)                    echo 'test-cluster' ;;
        *\".server}\"*)                  echo 'https://test-server:443' ;;
        *\"certificate-authority-data\"*) echo 'dGVzdGNh' ;;
        *) echo '' ;;
      esac
    }
    export -f kubectl
    get_cluster_details
    echo \"cluster=\${clusterName} server=\${server} ca=\${ca}\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"cluster=test-cluster"* ]]
  [[ "$output" == *"server=https://test-server:443"* ]]
  [[ "$output" == *"ca=dGVzdGNh"* ]]
}

@test "refuses to write kubeconfig when outputFile is a symlink" {
  local mock_dir link_target
  mock_dir="$(mktemp -d)"
  cat > "${mock_dir}/kubectl" <<'MOCK_EOF'
#!/usr/bin/env bash
case "$*" in
  *".name}"*)                    echo "test-cluster" ;;
  *".server}"*)                  echo "https://test-server:443" ;;
  *"certificate-authority-data"*) echo "dGVzdGNh" ;;
  *"config"*)                    echo "default" ;;
  *"get serviceaccount"*)        exit 0 ;;
  *"create token"*)              echo "test-token-value" ;;
  *)                             exit 1 ;;
esac
MOCK_EOF
  chmod +x "${mock_dir}/kubectl"

  link_target="${TEST_TMPDIR}/real-target"
  touch "${link_target}"
  ln -s "${link_target}" "${TEST_TMPDIR}/link.yaml"

  run env PATH="${mock_dir}:$PATH" bash "$SCRIPT" -o "${TEST_TMPDIR}/link.yaml" test-sa
  [ "$status" -eq 1 ]
  [[ "$output" == *"is a symlink"* ]]

  rm -rf "${mock_dir}"
}

@test "rejects service account name with uppercase or underscore characters" {
  run bash "$SCRIPT" -n test-ns "Invalid_SA"
  [ "$status" -eq 1 ]
  [[ "$output" == *"lowercase letters, digits, and hyphens only"* ]]
}

@test "script enforces set -euo pipefail" {
  local content
  content="$(<"$SCRIPT")"
  [[ "$content" == *"set -euo pipefail"* ]]
}

@test "script has header documentation" {
  local content
  content="$(<"$SCRIPT")"
  [[ "$content" == *"Generates a kubeconfig"* ]]
  [[ "$content" == *"Requirements: Kubernetes"* ]]
}
