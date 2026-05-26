#!/usr/bin/env bash
#
# Generates a kubeconfig for a given ServiceAccount using either:
#   - a temporary token (TokenRequest API via `kubectl create token`), or
#   - a permanent token (long-lived `kubernetes.io/service-account-token` Secret).
#
# Requirements: Kubernetes >= 1.24, kubectl on PATH.

set -euo pipefail

readonly DEFAULT_NAMESPACE="default"
readonly DEFAULT_TOKEN_TYPE="temporary"
readonly DEFAULT_DURATION="24h"
readonly SECRET_WAIT_RETRIES=30
readonly SECRET_WAIT_INTERVAL=1

# Print usage information.
print_help() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] <service_account>

Generate a kubeconfig file for a Kubernetes ServiceAccount.

Arguments:
  service_account         Name of the target ServiceAccount.

Options:
  -n, --namespace NAME    Namespace of the ServiceAccount
                          (default: current context's namespace, or '${DEFAULT_NAMESPACE}').
  -t, --type TYPE         Token type: 'temporary' or 'permanent'
                          (default: '${DEFAULT_TOKEN_TYPE}').
  -d, --duration DUR      Duration for temporary tokens, e.g. '1h', '24h'
                          (default: '${DEFAULT_DURATION}'; ignored for permanent).
  -o, --output FILE       Output path for the generated kubeconfig
                          (default: '<service_account>-kubeconfig.yaml').
  -h, --help              Show this help message and exit.

Notes:
  - Temporary tokens are issued via the TokenRequest API and expire automatically.
  - Permanent tokens are backed by a long-lived Secret. Prefer temporary unless
    a long-lived credential is genuinely required (e.g. legacy CI integrations).
EOF
}

# Parse CLI arguments into global variables.
parse_args() {
  serviceAccount=""
  namespace=""
  tokenType="${DEFAULT_TOKEN_TYPE}"
  duration="${DEFAULT_DURATION}"
  outputFile=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n|--namespace) namespace="${2:?missing value for $1}"; shift 2 ;;
      -t|--type)      tokenType="${2:?missing value for $1}"; shift 2 ;;
      -d|--duration)  duration="${2:?missing value for $1}"; shift 2 ;;
      -o|--output)    outputFile="${2:?missing value for $1}"; shift 2 ;;
      -h|--help)      print_help; exit 0 ;;
      -*)             echo "Error: unknown option '$1'" >&2; print_help; exit 1 ;;
      *)
        if [[ -z "${serviceAccount}" ]]; then
          serviceAccount="$1"
        else
          echo "Error: unexpected positional argument '$1'" >&2
          exit 1
        fi
        shift
        ;;
    esac
  done

  if [[ -z "${serviceAccount}" ]]; then
    echo "Error: <service_account> is required." >&2
    print_help
    exit 1
  fi

  if [[ "${tokenType}" != "temporary" && "${tokenType}" != "permanent" ]]; then
    echo "Error: --type must be 'temporary' or 'permanent', got '${tokenType}'." >&2
    exit 1
  fi

  if [[ -z "${namespace}" ]]; then
    namespace="$(kubectl config view --minify -o jsonpath='{..namespace}')"
    namespace="${namespace:-${DEFAULT_NAMESPACE}}"
  fi

  # Validate names match k8s naming rules (lowercase letters, digits, hyphens, max 63 chars)
  # to prevent YAML injection when values are interpolated into Secret/kubeconfig manifests.
  local k8s_name_re='^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$'
  if [[ ! "${serviceAccount}" =~ ${k8s_name_re} ]]; then
    echo "Error: service account name '${serviceAccount}' must be lowercase letters, digits, and hyphens only." >&2
    exit 1
  fi
  if [[ ! "${namespace}" =~ ${k8s_name_re} ]]; then
    echo "Error: namespace '${namespace}' must be lowercase letters, digits, and hyphens only." >&2
    exit 1
  fi

  if [[ -z "${outputFile}" ]]; then
    outputFile="${serviceAccount}-kubeconfig.yaml"
  fi
}

# Read cluster name, server URL, and inlined CA data from the current context.
get_cluster_details() {
  clusterName="$(kubectl config view --minify --flatten -o jsonpath='{.clusters[0].name}')"
  server="$(kubectl config view --minify --flatten -o jsonpath='{.clusters[0].cluster.server}')"
  ca="$(kubectl config view --minify --flatten -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')"

  if [[ -z "${clusterName}" || -z "${server}" || -z "${ca}" ]]; then
    echo "Error: could not extract cluster name, server, or CA data from the current context." >&2
    exit 1
  fi
}

# Abort if the target ServiceAccount does not exist.
verify_service_account_exists() {
  if ! kubectl get serviceaccount "${serviceAccount}" -n "${namespace}" >/dev/null 2>&1; then
    echo "Error: ServiceAccount '${serviceAccount}' not found in namespace '${namespace}'." >&2
    exit 1
  fi
}

# Issue a temporary token via the TokenRequest API.
issue_temporary_token() {
  echo "Requesting temporary token (duration: ${duration})..."
  token="$(kubectl create token "${serviceAccount}" -n "${namespace}" --duration="${duration}")"
  if [[ -z "${token}" ]]; then
    echo "Error: failed to issue temporary token." >&2
    exit 1
  fi
}

# Apply a long-lived service-account-token Secret bound to the ServiceAccount.
apply_permanent_token_secret() {
  local secretName="$1"
  echo "Creating long-lived Secret '${secretName}' for ServiceAccount '${serviceAccount}'..."
  kubectl apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${secretName}
  namespace: ${namespace}
  annotations:
    kubernetes.io/service-account.name: "${serviceAccount}"
type: kubernetes.io/service-account-token
EOF
}

# Poll until the token controller populates the Secret's token field.
wait_for_secret_token() {
  local secretName="$1"
  local populatedToken
  for _ in $(seq 1 "${SECRET_WAIT_RETRIES}"); do
    populatedToken="$(kubectl get secret "${secretName}" -n "${namespace}" \
      -o jsonpath='{.data.token}' 2>/dev/null || true)"
    if [[ -n "${populatedToken}" ]]; then
      return 0
    fi
    sleep "${SECRET_WAIT_INTERVAL}"
  done
  echo "Error: Secret '${secretName}' was not populated after $((SECRET_WAIT_RETRIES * SECRET_WAIT_INTERVAL))s." >&2
  exit 1
}

# Issue a permanent token by creating a Secret and reading its populated token.
issue_permanent_token() {
  local secretName="${serviceAccount}-long-lived-token"
  apply_permanent_token_secret "${secretName}"
  wait_for_secret_token "${secretName}"
  token="$(kubectl get secret "${secretName}" -n "${namespace}" \
    -o jsonpath='{.data.token}' | base64 --decode)"
}

# Render the kubeconfig file with 0600 permissions (contains a bearer token).
render_kubeconfig() {
  echo "Rendering kubeconfig to '${outputFile}'..."
  if [[ -L "${outputFile}" ]]; then
    echo "Error: '${outputFile}' is a symlink; refusing to write bearer token to symlink target." >&2
    exit 1
  fi
  rm -f -- "${outputFile}"
  (umask 077 && cat > "${outputFile}" <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: ${clusterName}
    cluster:
      certificate-authority-data: ${ca}
      server: ${server}
contexts:
  - name: ${serviceAccount}@${clusterName}
    context:
      cluster: ${clusterName}
      namespace: ${namespace}
      user: ${serviceAccount}
users:
  - name: ${serviceAccount}
    user:
      token: ${token}
current-context: ${serviceAccount}@${clusterName}
EOF
)
  echo "Done. Kubeconfig written to: ${outputFile}"
}

main() {
  parse_args "$@"
  get_cluster_details
  verify_service_account_exists

  case "${tokenType}" in
    temporary) issue_temporary_token ;;
    permanent) issue_permanent_token ;;
  esac

  render_kubeconfig
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
