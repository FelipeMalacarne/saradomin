# Saradomin Deployment Status

## Done

### Infrastructure
- k3s single-node cluster
- ArgoCD + KSOPS (encrypted secrets via SOPS + age)
- Traefik (single Tailscale LoadBalancer at 100.79.221.47 — only Tailscale device for internal services)
- cert-manager + Let's Encrypt ClusterIssuer (Cloudflare DNS-01) for public domains
- Tailscale operator
- Longhorn storage + Cloudflare R2 backup
- Terraform: R2 buckets, Cloudflare tunnel, DNS records

### Networking / DNS
- CoreDNS deployment for `*.saradomin` → 100.79.221.47 wildcard resolution
- Tailscale split DNS configured: `saradomin` domain → CoreDNS Tailscale IP
- Private CA (`saradomin-internal-ca`) via cert-manager
- Wildcard TLS cert for `*.saradomin` with explicit SANs for all services
- Traefik TLSStore using the wildcard cert as default
- All `*.saradomin` ingresses on `websecure` (HTTPS, port 443)
- Cloudflare tunnel for public services (`vault.ftm.dev.br`, `jellyfin.ftm.dev.br`, `request.ftm.dev.br`)

### Services deployed
| Service | URL | Status |
|---|---|---|
| Pihole | https://pihole.saradomin | Running |
| Cloudflared | - | Running |
| Traefik | - | Running |
| cert-manager | - | Running |
| Longhorn | - | Running |
| Prometheus + Grafana | https://grafana.saradomin | Running |
| Vaultwarden | https://vault.ftm.dev.br | Running |
| Intel GPU plugin | - | Running |
| Jellyfin | https://jellyfin.saradomin / https://jellyfin.ftm.dev.br | Unhealthy ⚠️ |
| qBittorrent | https://qbit.saradomin | Running ✓ configured |
| Radarr | https://radarr.saradomin | Running ✓ configured |
| Sonarr | https://sonarr.saradomin | Running ✓ configured |
| Prowlarr | https://prowlarr.saradomin | Running ✓ connected to Radarr + Sonarr |
| Bazarr | https://bazarr.saradomin | Running ✓ connected to Radarr + Sonarr |
| FlareSolverr | internal only | Running |
| Jellyseerr | https://request.ftm.dev.br | Running — setup in progress |
| Recyclarr | CronJob (daily 03:00) | Deployed — needs secrets |
| exportarr | internal metrics | Deployed — needs secrets |

### Post-deploy configuration done
- qBittorrent: save paths, categories configured
- Radarr: qBittorrent download client + root folder `/data/media/movies`
- Sonarr: qBittorrent download client + root folder `/data/media/tv`
- Prowlarr: connected to Radarr + Sonarr, FlareSolverr proxy added
- Bazarr: connected to Radarr + Sonarr, subtitle providers enabled

---

## TODO

### Immediate
- [ ] **Fix Jellyfin** — unhealthy in ArgoCD, investigate pod logs
- [ ] **Complete Jellyseerr setup** — finish wizard (connect Jellyfin + Radarr + Sonarr)
- [ ] **Add torrent indexers in Prowlarr**
- [ ] **Trust CA cert on all devices** — see README for instructions per OS

### Secrets (need API keys from running services)
- [ ] Create `kubernetes/apps/media/recyclarr/secrets.dec.yaml` with Radarr + Sonarr API keys → `make encrypt`
- [ ] Create `kubernetes/apps/media/exportarr/secrets.dec.yaml` with Radarr + Sonarr + Prowlarr + Bazarr API keys → `make encrypt`

### Host filesystem (run on saradomin host)
- [ ] Create `/data/media/movies`, `/data/media/tv`, `/data/downloads/...` directories
- [ ] Create `media` user (UID/GID 1001) and own `/data`

### Remaining config
- [ ] Add HTTP → HTTPS redirect in Traefik for `*.saradomin`
- [ ] Replace Grafana `adminPassword: changeme` with SOPS secret
- [ ] Set pihole as DNS server (or confirm CoreDNS split DNS is working on all devices)
- [ ] Verify Jellyfin QuickSync: `ffmpeg -init_hw_device qsv=hw ...`
- [ ] Import Grafana dashboards: Radarr (15027), Sonarr (15028), qBittorrent (15315)
