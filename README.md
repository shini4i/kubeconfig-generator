<div align="center">

# kubeconfig-generator
A simple script for generating kubeconfig for a provided service account

![GitHub Workflow Status](https://img.shields.io/github/workflow/status/shini4i/kubeconfig-generator/Brew%20Release?style=plastic)
![Version](https://img.shields.io/github/v/tag/shini4i/kubeconfig-generator?style=plastic)
![license](https://img.shields.io/github/license/shini4i/kubeconfig-generator?style=plastic)

</div>

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
