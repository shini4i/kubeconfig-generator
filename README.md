<div align="center">

# kubeconfig-generator
A simple script for generating kubeconfig for a provided service account

![GitHub last commit (branch)](https://img.shields.io/github/last-commit/shini4i/kubeconfig-generator/main?style=plastic)
![Version](https://img.shields.io/github/v/tag/shini4i/kubeconfig-generator?style=plastic)
![license](https://img.shields.io/github/license/shini4i/kubeconfig-generator?style=plastic)

</div>

## Requirements
- Kubernetes >= 1.24
- kubectl

## Installation
The script can be installed using brew:
```bash
brew install shini4i/tap/kubeconfig-generator
```

## Usage
```bash
kubeconfig-generator [OPTIONS] <service_account>
```

### Arguments
- `<service_account>` - Name of the target Kubernetes ServiceAccount (required)

### Options
- `-n, --namespace NAME` - Namespace of the ServiceAccount (default: current context's namespace, or 'default')
- `-t, --type TYPE` - Token type: 'temporary' or 'permanent' (default: 'temporary')
- `-d, --duration DUR` - Duration for temporary tokens, e.g. '1h', '24h' (default: '24h'; ignored for permanent)
- `-o, --output FILE` - Output path for the generated kubeconfig (default: '<service_account>-kubeconfig.yaml')
- `-h, --help` - Show help message and exit

### Examples

Generate kubeconfig with a temporary token (expires in 24 hours):
```bash
kubeconfig-generator my-sa -n my-namespace
```

Generate kubeconfig with a permanent token (long-lived credential):
```bash
kubeconfig-generator my-sa -n my-namespace -t permanent
```

Generate with custom token duration and output path:
```bash
kubeconfig-generator my-sa -n my-namespace -d 72h -o /tmp/my-kubeconfig.yaml
```

### Token Types

**Temporary (default)** - Uses the TokenRequest API to issue short-lived tokens that expire automatically. Recommended for security. The token lifetime is determined by the `--duration` flag.

**Permanent** - Creates a long-lived Secret to back a ServiceAccount token that persists until explicitly deleted. Use only when a long-lived credential is genuinely required (e.g., legacy CI/CD integrations without token rotation support).
