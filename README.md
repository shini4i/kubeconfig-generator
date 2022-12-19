<div align="center">

# kubeconfig-generator
A simple script for generating kubeconfig for a provided service account

![GitHub last commit (branch)](https://img.shields.io/github/last-commit/shini4i/kubeconfig-generator/main?style=plastic)
![Version](https://img.shields.io/github/v/tag/shini4i/kubeconfig-generator?style=plastic)
![license](https://img.shields.io/github/license/shini4i/kubeconfig-generator?style=plastic)

</div>

> :warning: Starting from Kubernetes version 1.22 ServiceAccount token secrets are no longer automatically created. You can read more about it [here](https://kubernetes.io/docs/concepts/configuration/secret/#service-account-token-secrets).

## Requirements
- kubectl

## Installation
The script can be installed using brew:
```bash
brew install shini4i/tap/kubeconfig-generator
```

## Usage
```bash
kubeconfig-generator <service_account> <namespace>
```

If the namespace is omitted, the currently selected namespace will be used.
