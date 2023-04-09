#!/usr/bin/env bash

set -e

print_help() {
    echo "Usage: $(basename "$0") <service_account> <namespace>"
    echo "  <service_account>   Service Account to use for kubeconfig generation"
    echo "  <namespace>         Namespace of the service account (optional)"
}

parse_args() {
  serviceAccount=$1
  echo "Generating kubeconfig for the following service account: $serviceAccount"

  if [ $# -eq 2 ]; then
    namespace=$2
  else
    namespace=$(kubectl config view --minify -o jsonpath='{..namespace}')
    echo "No namespace specified, using currently selected namespace: $namespace"
  fi
}

get_cluster_details() {
  server="$(kubectl config view --minify -o jsonpath='{..server}')"
  echo Using the following endpoint: "$server"
  clusterName="$(kubectl config view --minify -o jsonpath='{.clusters[0].name}')"
}

get_sa_details() {
  local secretName
  local kubernetesVersion

  kubernetesVersion=$(kubectl version --short | grep Server | awk '{print $3}')

  if [[ "$kubernetesVersion" > "v1.23" ]]; then
    secretName="$serviceAccount"-sa-token
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: "$secretName"
  namespace: "$namespace"
  annotations:
    kubernetes.io/service-account.name: "$serviceAccount"
type: kubernetes.io/service-account-token
EOF
    echo "Giving the service account token some time to be generated..."
    sleep 10
  else
    secretName=$(kubectl --namespace "$namespace" get serviceAccount "$serviceAccount" -o jsonpath='{.secrets[0].name}')
  fi

  ca=$(kubectl --namespace "$namespace" get secret "$secretName" -o jsonpath='{.data.ca\.crt}')
  token=$(kubectl --namespace "$namespace" get secret "$secretName" -o jsonpath='{.data.token}' | base64 --decode)
}

render_kubeconfig() {
  echo "Rendering kubeconfig..."
  cat > "${clusterName}"-kubeconfig <<EOF
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
  echo "Kubeconfig generated successfully!"
}

main() {
  if [ "$1" == "-h" ] || [ "$1" == "--help" ] || [ $# -lt 1 ]; then
    print_help
    exit 0
  fi

  parse_args "$@"

  get_cluster_details
  get_sa_details
  render_kubeconfig
}

main "$@"
