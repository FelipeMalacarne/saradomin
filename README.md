# saradomin

Home server GitOps repo. Single-node k3s cluster managed with ArgoCD + KSOPS.

**Hardware:** Intel N97 · 16GB RAM · 512GB NVMe

## Access

| Service | URL | Access |
|---|---|---|
| ArgoCD | https://argocd.saradomin | Tailscale |
| Grafana | https://grafana.saradomin | Tailscale |
| Jellyfin | https://jellyfin.saradomin | Tailscale |
| qBittorrent | https://qbit.saradomin | Tailscale |
| Radarr | https://radarr.saradomin | Tailscale |
| Sonarr | https://sonarr.saradomin | Tailscale |
| Prowlarr | https://prowlarr.saradomin | Tailscale |
| Bazarr | https://bazarr.saradomin | Tailscale |
| Pihole | https://pihole.saradomin | Tailscale |
| Jellyfin (public) | https://jellyfin.ftm.dev.br | Cloudflare |
| Vaultwarden | https://vault.ftm.dev.br | Cloudflare |
| Jellyseerr | https://request.ftm.dev.br | Cloudflare |

`*.saradomin` hostnames resolve via Tailscale split DNS → CoreDNS → Traefik.

## Trusting the internal CA

`*.saradomin` services use a private CA. You need to trust it once per device to avoid browser warnings.

**1. Export the CA cert from the cluster:**

```bash
kubectl get secret saradomin-ca-secret -n networking \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > saradomin-ca.crt
```

**2. Trust it on each device:**

**macOS**
```bash
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain saradomin-ca.crt
```

**iOS / iPadOS**
1. AirDrop `saradomin-ca.crt` to the device
2. Settings → General → VPN & Device Management → install the profile
3. Settings → General → About → Certificate Trust Settings → enable full trust

**Android**
Settings → Security → Encryption & credentials → Install certificate → CA certificate

**Arch Linux**
```bash
sudo trust anchor --store saradomin-ca.crt
```

**Debian / Ubuntu**
```bash
sudo cp saradomin-ca.crt /usr/local/share/ca-certificates/saradomin-ca.crt
sudo update-ca-certificates
```

**Windows**
```powershell
Import-Certificate -FilePath saradomin-ca.crt -CertStoreLocation Cert:\LocalMachine\Root
```
