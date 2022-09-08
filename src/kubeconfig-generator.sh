#!/usr/bin/env bash

set -e

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

  secretName=$(kubectl --namespace "$namespace" get serviceAccount "$serviceAccount" -o jsonpath='{.secrets[0].name}')
  ca=$(kubectl --namespace "$namespace" get secret "$secretName" -o jsonpath='{.data.ca\.crt}')
  token=$(kubectl --namespace "$namespace" get secret "$secretName" -o jsonpath='{.data.token}' | base64 --decode)
}

render_kubeconfig() {
  cat > kubeconfig <<EOF
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
}

main() {
  parse_args "$@"

  get_cluster_details
  get_sa_details
  render_kubeconfig
}

main "$@"