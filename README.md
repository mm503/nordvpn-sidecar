# NordVPN Sidecar Container

A lightweight sidecar VPN solution for Kubernetes pods that redirects all pod traffic through NordVPN with optional split tunneling support.

## Features

- **Full Traffic Redirection**: Routes all pod traffic through NordVPN
- **Split Tunneling**: Configurable subnet exclusions (Kubernetes, LAN, etc.)
- **Minimal Footprint**: Ubuntu LTS base with only NordVPN packages
- **Auto-Reconnection**: Configurable retry logic for connection stability
- **Kill Switch**: Prevents traffic leaks when VPN disconnects

## Container Details

- **Base Image**: Ubuntu 24.04 LTS
- **Architecture Support**: Multi-arch (linux/amd64, linux/arm64)
- **Components**: Ubuntu + NordVPN packages only
- **Customization**: Single entrypoint.sh script
- **Image Tags**: Correspond to NordVPN client versions
- **Automated Updates**: Renovate bot automatically updates NordVPN versions

## Configuration

### Required Environment Variables

```yaml
- name: TOKEN
  valueFrom:
    secretKeyRef:
      name: nordvpn-credentials
      key: token
```

### Optional Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MAX_RECONNECT_ATTEMPTS` | `5` | Maximum reconnection attempts |
| `RECONNECT_INTERVAL` | `30` | Seconds between reconnection attempts |
| `NORDVPN_KILLSWITCH` | `on` | Enable/disable kill switch (`on`/`off`) |
| `NORDVPN_COUNTRY` | unset | Target country (e.g., `United_States`) |
| `NORDVPN_CITY` | unset | Target city (e.g., `Dallas`) |
| `ALLOW_SUBNETS` | unset | Comma-separated subnets for split tunneling |

## Implementation

### 1. Create NordVPN Credentials Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: nordvpn-credentials
type: Opaque
data:
  token: <base64-encoded-nordvpn-token>
```

### 2. Add Sidecar to Pod Specification

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: example-pod
spec:
  initContainers:
  - name: nordvpn-sidecar
    image: mm404/nordvpn-sidecar:latest
    restartPolicy: Always
    env:
    - name: TOKEN
      valueFrom:
        secretKeyRef:
          name: nordvpn-credentials
          key: token
    - name: ALLOW_SUBNETS   # Kubernetes networking, LAN
      value: "10.42.0.0/16,10.43.0.0/16,192.168.q.0/24"
    - name: NORDVPN_COUNTRY
      value: United_States  # Run "nordvpn contries" to see all options
    - name: NORDVPN_CITY    # Run "nordvpn cities United_States" to see city options for US
      value: Miami
    - name: MAX_RECONNECT_ATTEMPTS
      value: "10"
    - name: RECONNECT_INTERVAL
      value: "60"
    securityContext:
      capabilities:
        add:
        - NET_ADMIN         # Required for VPN to work
  containers:
  - name: main-container
    image: your-app:latest
```

## Split Tunneling Configuration

### Common Subnet Exclusions

- **Kubernetes Pod Network**: `10.42.0.0/16` (k3s default)
- **Kubernetes Service Network**: `10.43.0.0/16` (k3s default)
- **Local LAN**: `192.168.x.0/24` (adjust to your network)
- **Docker Networks**: `172.17.0.0/16` (if applicable)

### Example ALLOW_SUBNETS Values

```yaml
# Minimal (Kubernetes only)
ALLOW_SUBNETS: "10.42.0.0/16,10.43.0.0/16"

# With LAN access
ALLOW_SUBNETS: "10.42.0.0/16,10.43.0.0/16,192.168.1.0/24"
```

## Security Considerations

- **Required Capability**: `NET_ADMIN` for network manipulation
- **Secret Management**: Store NordVPN token in Kubernetes secrets
- **Network Policies**: Consider additional pod network restrictions
- **Resource Limits**: Set appropriate CPU/memory limits for the sidecar

## Troubleshooting

### Connection Issues
- Verify NordVPN token validity
- Check country/city name formatting
- Review pod logs for connection errors

### Split Tunneling Problems
- Validate subnet CIDR notation
- Ensure subnets don't conflict with VPN routing
- Test connectivity to excluded subnets

### Performance Impact
- Monitor sidecar resource usage
- Adjust reconnection parameters for stability
- Consider regional server selection for latency

## Versioning

This project uses the NordVPN client version as its release version. Image tags correspond to NordVPN client versions (following [semver](https://semver.org/)).

### Image Tags

- `latest`: Most recent stable release
- `{version}`: NordVPN client version (e.g., `4.2.2`)

### Release Process

Releases are created automatically via GitHub Actions when changes are pushed to main:
1. `NORDVPN_VERSION` in Dockerfile is updated (typically via Renovate bot)
2. Multi-arch Docker images are built for linux/amd64 and linux/arm64
3. Images are pushed to Docker Hub as `mm404/nordvpn-sidecar:latest` and `mm404/nordvpn-sidecar:{version}`
4. GitHub release is created with the version tag
5. Release notes are auto-generated from commit history

The CI workflow also validates pull requests by building (but not pushing) multi-arch images.

See [CONTRIBUTING.md](CONTRIBUTING.md) for details on commit message format.
