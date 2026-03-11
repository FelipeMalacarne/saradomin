# Media Stack Plan: Jellyfin + ARR Stack

## Overview

Complete self-hosted media stack extending the initial saradomin plan with automated
movie/TV acquisition and management.

**Components:**
- **Jellyfin** — media server (Intel QuickSync HW transcode)
- **Radarr** — movie management
- **Sonarr** — TV show management
- **Prowlarr** — indexer aggregator (feeds Radarr + Sonarr)
- **Bazarr** — automatic subtitle downloads
- **qBittorrent** — torrent download client
- **Jellyseerr** — public media request portal (`request.ftm.dev.br`)

---

## Access Matrix

| Service     | Access                                          |
|-------------|-------------------------------------------------|
| Jellyfin    | Tailscale + Cloudflare → `jellyfin.ftm.dev.br`  |
| Jellyseerr  | Cloudflare → `request.ftm.dev.br` (public)      |
| Radarr      | Tailscale only                                  |
| Sonarr      | Tailscale only                                  |
| Prowlarr    | Tailscale only                                  |
| Bazarr      | Tailscale only                                  |
| qBittorrent | Tailscale only                                  |

---

## Architecture

```
Cloudflare Tunnel
  ├── jellyfin.ftm.dev.br  → Traefik → Jellyfin:8096
  └── request.ftm.dev.br   → Traefik → Jellyseerr:5055

Tailscale (internal)
  ├── jellyfin      → Jellyfin:8096
  ├── radarr        → Radarr:7878
  ├── sonarr        → Sonarr:8989
  ├── prowlarr      → Prowlarr:9696
  ├── bazarr        → Bazarr:6767
  └── qbittorrent   → qBittorrent:8080

Internal cluster (ClusterIP only)
  └── Jellyseerr → Jellyfin, Radarr, Sonarr
      Radarr/Sonarr → qBittorrent (download client)
      Prowlarr → Radarr, Sonarr (indexer push)
```

---

## Host Disk Layout

Run on `saradomin` host before deploying:

```bash
mkdir -p /data/media/movies /data/media/tv
mkdir -p /data/downloads/complete/movies /data/downloads/complete/tv
mkdir -p /data/downloads/incomplete
```

**Why single `/data` mount?** All apps that need both media and downloads must share the
same HostPath mount (`/data`) so the OS can create hardlinks between
`/data/downloads/complete/movies/` and `/data/media/movies/`. Hardlinks require both
paths to be on the same filesystem/device — mounting them separately would force file
copies and double disk usage.

```
/data/
├── media/
│   ├── movies/        ← Radarr root folder, Jellyfin library
│   └── tv/            ← Sonarr root folder, Jellyfin library
└── downloads/
    ├── complete/
    │   ├── movies/    ← qBittorrent category "movies"
    │   └── tv/        ← qBittorrent category "tv"
    └── incomplete/    ← qBittorrent in-progress
```

---

## Storage per App

| App          | Config PVC (Longhorn, R2 backup) | Data mount              |
|--------------|----------------------------------|-------------------------|
| Jellyfin     | 5Gi                              | HostPath `/data/media` (readOnly) |
| Radarr       | 2Gi                              | HostPath `/data` (rw)   |
| Sonarr       | 2Gi                              | HostPath `/data` (rw)   |
| Prowlarr     | 1Gi                              | —                       |
| Bazarr       | 1Gi                              | HostPath `/data/media` (rw, writes .srt) |
| qBittorrent  | 2Gi                              | HostPath `/data/downloads` (rw) |
| Jellyseerr   | 1Gi                              | —                       |

---

## Repository Structure to Create

```
kubernetes/apps/media/
├── intel-gpu-plugin/
│   ├── application.yaml       # Helm: intel.github.io/helm-charts
│   ├── gpu-device-plugin.yaml # GpuDevicePlugin CR
│   └── kustomization.yaml
│
├── jellyfin/
│   ├── application.yaml
│   ├── deployment.yaml        # nodeSelector: saradomin, gpu.intel.com/i915: "1"
│   ├── service.yaml           # ClusterIP :8096 (for Traefik ingress)
│   ├── service-tailscale.yaml # LoadBalancer tailscale, hostname: jellyfin
│   ├── ingress.yaml           # jellyfin.ftm.dev.br → websecure entrypoint
│   ├── pvc.yaml               # 5Gi Longhorn /config
│   └── kustomization.yaml
│
├── radarr/
│   ├── application.yaml
│   ├── deployment.yaml        # /config → PVC, /data → HostPath
│   ├── service.yaml           # Tailscale LB port 7878
│   ├── pvc.yaml               # 2Gi Longhorn /config
│   └── kustomization.yaml
│
├── sonarr/
│   ├── application.yaml
│   ├── deployment.yaml        # /config → PVC, /data → HostPath
│   ├── service.yaml           # Tailscale LB port 8989
│   ├── pvc.yaml               # 2Gi Longhorn /config
│   └── kustomization.yaml
│
├── prowlarr/
│   ├── application.yaml
│   ├── deployment.yaml        # /config → PVC only
│   ├── service.yaml           # Tailscale LB port 9696
│   ├── pvc.yaml               # 1Gi Longhorn /config
│   └── kustomization.yaml
│
├── bazarr/
│   ├── application.yaml
│   ├── deployment.yaml        # /config → PVC, /data/media → HostPath rw
│   ├── service.yaml           # Tailscale LB port 6767
│   ├── pvc.yaml               # 1Gi Longhorn /config
│   └── kustomization.yaml
│
├── qbittorrent/
│   ├── application.yaml
│   ├── deployment.yaml        # /config → PVC, /data/downloads → HostPath
│   ├── service.yaml           # Tailscale LB port 8080
│   ├── pvc.yaml               # 2Gi Longhorn /config
│   └── kustomization.yaml
│
└── jellyseerr/
    ├── application.yaml
    ├── deployment.yaml
    ├── service.yaml           # ClusterIP + Tailscale LB port 5055
    ├── ingress.yaml           # request.ftm.dev.br → websecure entrypoint
    ├── pvc.yaml               # 1Gi Longhorn /app/config
    └── kustomization.yaml
```

---

## Terraform Changes

File: `terraform/cloudflare/main.tf`

### 1 — Add Jellyseerr ingress rule to tunnel config (before the 404 catch-all)

```hcl
# Inside cloudflare_zero_trust_tunnel_cloudflared_config → config → ingress:
{
  hostname = "request.${var.zone}"
  service  = "http://traefik.networking.svc.cluster.local:80"
},
```

### 2 — Add DNS record

```hcl
resource "cloudflare_dns_record" "jellyseerr_dns" {
  zone_id = var.zone_id
  name    = "request.${var.zone}"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.saradomin_tunnel.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
  comment = "[terraform] saradomin Jellyseerr"
}
```

---

## Key Implementation Details

### Hardlink-safe volume pattern (Radarr / Sonarr)

Mount the entire `/data` tree as a single volume so the kernel can create hardlinks
between downloads and the media library:

```yaml
volumeMounts:
  - name: config
    mountPath: /config
  - name: data
    mountPath: /data          # /data/media and /data/downloads visible here
volumes:
  - name: config
    persistentVolumeClaim:
      claimName: radarr-config
  - name: data
    hostPath:
      path: /data
      type: Directory
```

Inside Radarr:
- Root folder → `/data/media/movies`
- Download client path → `/data/downloads`

### Jellyfin — Intel QuickSync

```yaml
resources:
  requests:
    gpu.intel.com/i915: "1"
  limits:
    gpu.intel.com/i915: "1"
nodeSelector:
  kubernetes.io/hostname: saradomin
```

`intel-gpu-plugin` must be `Healthy` before Jellyfin can schedule.

### Inter-service URLs (all cluster-internal)

| From       | To          | URL                                           |
|------------|-------------|-----------------------------------------------|
| Radarr     | qBittorrent | `http://qbittorrent.media.svc.cluster.local:8080` |
| Sonarr     | qBittorrent | `http://qbittorrent.media.svc.cluster.local:8080` |
| Prowlarr   | Radarr      | `http://radarr.media.svc.cluster.local:7878`  |
| Prowlarr   | Sonarr      | `http://sonarr.media.svc.cluster.local:8989`  |
| Jellyseerr | Jellyfin    | `http://jellyfin.media.svc.cluster.local:8096` |
| Jellyseerr | Radarr      | `http://radarr.media.svc.cluster.local:7878`  |
| Jellyseerr | Sonarr      | `http://sonarr.media.svc.cluster.local:8989`  |
| Bazarr     | Radarr      | `http://radarr.media.svc.cluster.local:7878`  |
| Bazarr     | Sonarr      | `http://sonarr.media.svc.cluster.local:8989`  |

---

## Deployment Order

### Pre-flight (host)
```bash
# On saradomin:
mkdir -p /data/media/movies /data/media/tv
mkdir -p /data/downloads/complete/movies /data/downloads/complete/tv /data/downloads/incomplete
```

### Phase 1 — GPU
- [ ] ArgoCD: deploy `intel-gpu-plugin`
- [ ] Verify: `kubectl get nodes -o json | jq '.items[].status.allocatable | with_entries(select(.key | startswith("gpu.intel")))' `
      → `"gpu.intel.com/i915": "1"`

### Phase 2 — Media server
- [ ] ArgoCD: deploy `jellyfin`
- [ ] Add libraries: Movies → `/data/media/movies`, TV → `/data/media/tv`
- [ ] Enable Intel QSV hardware transcoding in Jellyfin Dashboard → Playback

### Phase 3 — Download client
- [ ] ArgoCD: deploy `qbittorrent`
- [ ] Set default save path: `/data/downloads/complete`
- [ ] Add categories: `movies` → `/data/downloads/complete/movies`, `tv` → `/data/downloads/complete/tv`
- [ ] Set incomplete downloads path: `/data/downloads/incomplete`

### Phase 4 — Indexers + ARR
- [ ] ArgoCD: deploy `prowlarr`
- [ ] Add indexers in Prowlarr UI
- [ ] ArgoCD: deploy `radarr` and `sonarr`
- [ ] In Prowlarr → Apps: add Radarr and Sonarr (uses ClusterIP URLs above)
- [ ] In Radarr: add qBittorrent download client, set root folder `/data/media/movies`
- [ ] In Sonarr: add qBittorrent download client, set root folder `/data/media/tv`

### Phase 5 — Subtitles
- [ ] ArgoCD: deploy `bazarr`
- [ ] Connect Bazarr to Radarr + Sonarr, configure subtitle providers (OpenSubtitles, etc.)

### Phase 6 — Request portal
- [ ] ArgoCD: deploy `jellyseerr`
- [ ] `terraform apply` → creates `request.ftm.dev.br` DNS + tunnel rule
- [ ] Configure Jellyseerr: connect Jellyfin, Radarr, Sonarr
- [ ] Verify `request.ftm.dev.br` is reachable publicly

---

## Verification Checklist

- [ ] `gpu.intel.com/i915: "1"` in node allocatable
- [ ] Jellyfin transcode stream shows `h264_qsv` encoder in Dashboard → Active Streams
- [ ] Radarr: add a movie → job appears in qBittorrent
- [ ] Completed qBittorrent download hardlinked into `/data/media/movies/` (no extra disk used)
- [ ] Jellyfin library scan picks up new movie automatically
- [ ] Bazarr downloads `.srt` subtitle alongside movie file
- [ ] `request.ftm.dev.br` loads Jellyseerr
- [ ] Request a movie in Jellyseerr → Radarr searches and downloads it end-to-end

---

## Resource Limits

### The reality of single-node k3s

**On a single-node cluster, requests matter much less for scheduling** — there is only one
node, so a pod always gets scheduled regardless of declared requests. What matters:

- **Requests** → QoS class and eviction priority. Pods where `actual > limit` are first to
  be OOM-killed under memory pressure. Pods where `actual ≤ request` (Guaranteed class)
  are last.
- **Limits** → the hard ceiling. Exceed the memory limit → OOM killed. Exceed the CPU
  limit → throttled (not killed, just slow).
- **Set limits to reflect actual usage**, not wishful thinking. A limit lower than actual
  usage is not "conservative" — it's a scheduled OOM kill waiting for memory pressure.

### Current cluster reality (actual observed usage)

From `kubectl top` / Grafana at time of writing:

| | Value | Notes |
|-|-------|-------|
| Node RAM | 16 GB | |
| Memory utilization | 44.2% | ~7.1 GB actual in use |
| Memory requests commitment | 9.84% | ~1.57 GB defined — apps use 4-5× their requests |
| Memory limits commitment | 22.2% | ~3.55 GB defined — apps routinely exceed limits |
| CPU requests commitment | 37.1% | ~1,484m |
| CPU limits commitment | 75% | ~3,000m of 4,000m total |

**Known issue — ArgoCD exceeding its memory limit:**

| | Value |
|-|-------|
| Actual usage | 1.09 GiB |
| Declared request | 256 MiB |
| Declared limit | 512 MiB |
| Overage | 217% of limit |

ArgoCD is running at 2× its memory limit. Under current conditions there is enough free
RAM so the OOM killer ignores it, but adding ~2-3 GB of media stack workloads will raise
memory pressure. **Fix this before deploying the media stack** by raising ArgoCD's memory
limit in `kubernetes/bootstrap/argocd-values.yaml`:
```yaml
server:
  resources:
    requests:
      memory: 512Mi
    limits:
      memory: 1536Mi   # reflects actual ~1.09 GiB + headroom
```
Check other components too (repo-server, application-controller) with `kubectl top pod -n argocd`.

### Media stack resource table

N97 = 4 physical cores (no HT) = **4,000m total CPU**.
Available RAM after current 7.1 GB usage = **~8.9 GB**.

| App          | CPU request | CPU limit | Mem request | Mem limit | Typical actual |
|--------------|-------------|-----------|-------------|-----------|----------------|
| Jellyfin     | 200m        | 2000m     | 512Mi       | 2Gi       | 300-600Mi idle, spikes during scan |
| Radarr       | 50m         | 500m      | 256Mi       | 768Mi     | 200-400Mi |
| Sonarr       | 50m         | 500m      | 256Mi       | 768Mi     | 200-400Mi |
| Prowlarr     | 50m         | 300m      | 128Mi       | 384Mi     | 100-200Mi |
| Bazarr       | 25m         | 200m      | 128Mi       | 384Mi     | 80-150Mi |
| qBittorrent  | 100m        | 1000m     | 256Mi       | 768Mi     | 200-400Mi (grows with active torrents) |
| Jellyseerr   | 50m         | 300m      | 256Mi       | 512Mi     | 150-300Mi |
| FlareSolverr | 100m        | 500m      | 256Mi       | 768Mi     | 200-400Mi (Chromium per request) |
| **Total**    | **625m**    | **5,300m**| **2,048Mi** | **6.1Gi** | **~1.5-3 GB** |

**Post-media-stack estimate:**
- Actual usage: ~7.1 GB (current) + ~2 GB (media stack idle) = **~9 GB / 16 GB (56%)**
- CPU limits commitment rises to ~75% + new limits — fine for a home server
- ~7 GB remaining as buffer for bursts and OS page cache

> **Why Jellyfin CPU limit is 2000m (not 4000m):** With QuickSync, Jellyfin uses very
> little CPU during transcode (~5-15% per stream). The 2000m limit prevents library scans
> from monopolizing all 4 cores and starving every other pod. Sufficient for 1-2 software
> transcode fallback streams if QuickSync fails.

> **After deploying,** run `kubectl top pod -A` and compare actuals to limits. Raise any
> limit where actual usage regularly exceeds 80% of the limit.

---

## File Permissions (PUID / PGID)

All linuxserver.io images run as an internal `abc` user. The `PUID` / `PGID` env vars remap
that user to a host UID/GID so files written to HostPath mounts are owned correctly.

**On the saradomin host (one-time setup):**
```bash
# Create a dedicated media group and user
sudo groupadd -g 1001 media
sudo useradd -u 1001 -g media -s /usr/sbin/nologin -M mediauser

# Own the data directory
sudo chown -R 1001:1001 /data
sudo chmod -R 775 /data
```

**In every linuxserver.io deployment (Radarr, Sonarr, Prowlarr, Bazarr, qBittorrent):**
```yaml
env:
  - name: PUID
    value: "1001"
  - name: PGID
    value: "1001"
  - name: TZ
    value: "America/Sao_Paulo"
```

> Jellyfin uses its own image (not linuxserver.io). Set `JELLYFIN_PublishedServerUrl` instead.
> Jellyseerr also uses its own image — no PUID/PGID needed.

**Why this matters:** If Radarr runs as root (UID 0) and writes a file to `/data/media/movies/`,
that file will be owned by root. qBittorrent running as UID 1001 cannot hardlink or delete it,
and Jellyfin (running as its own user) may not be able to read it. Consistent UID/GID across
all containers and the host filesystem prevents this entire class of problems.

---

## FlareSolverr

Many torrent indexers (1337x, YTS, EZTV, etc.) sit behind Cloudflare's bot protection.
Prowlarr cannot scrape them directly. FlareSolverr is a headless browser proxy that solves
Cloudflare challenges and forwards the response to Prowlarr.

**Add to the media stack:**

```
kubernetes/apps/media/flaresolverr/
├── application.yaml
├── deployment.yaml    # ghcr.io/flaresolverr/flaresolverr:latest
├── service.yaml       # ClusterIP only — Prowlarr talks to it internally
└── kustomization.yaml
```

FlareSolverr does **not** need Tailscale or Ingress — Prowlarr reaches it at:
```
http://flaresolverr.media.svc.cluster.local:8191
```

**Deployment:**
```yaml
containers:
  - name: flaresolverr
    image: ghcr.io/flaresolverr/flaresolverr:latest
    env:
      - name: LOG_LEVEL
        value: info
      - name: TZ
        value: "America/Sao_Paulo"
    ports:
      - containerPort: 8191
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 500m
        memory: 512Mi
```

**Prowlarr configuration:** Settings → Indexers → Add FlareSolverr proxy → URL:
`http://flaresolverr.media.svc.cluster.local:8191`. Then tag each Cloudflare-protected
indexer with the `flaresolverr` tag.

---

## File Naming Conventions

Set these in Radarr and Sonarr **before** importing any media. Renaming later requires
re-scanning the entire library.

### Radarr — Movie naming format

Settings → Media Management → Standard Movie Format:
```
{Movie Title} ({Release Year}) {Quality Full}
```

Example output: `The Dark Knight (2008) Bluray-1080p`

Folder format:
```
{Movie Title} ({Release Year})
```

### Sonarr — Episode naming format

Settings → Media Management → Standard Episode Format:
```
{Series Title} - S{season:00}E{episode:00} - {Episode Title} {Quality Full}
```

Example output: `Breaking Bad - S01E01 - Pilot Bluray-1080p`

Series folder:
```
{Series Title} ({Series Year})
```

Season folder:
```
Season {season:00}
```

### Why these formats?

- Jellyfin identifies media by matching folder/file names against TMDB/TVDB. The
  `(Year)` suffix in folder names is critical for disambiguation (e.g. two shows named "The Office").
- `{Quality Full}` in the filename lets you see the quality at a glance without opening Jellyfin.
- Zero-padded season/episode numbers (`S01E01`) sort correctly in all file managers.

### Jellyfin library settings

- Enable "Store image files next to media" (Radarr/Sonarr can download artwork)
- Set "Metadata savers" to NFO files — Jellyfin reads these for metadata
- Enable "Real time monitoring" for instant library updates after new imports

---

## Recyclarr (Quality Profile Automation)

Recyclarr syncs TRaSH Guides quality profiles and custom formats to Radarr and Sonarr
automatically. Without it, quality profiles must be configured manually and drift over time.

**Implementation:** Kubernetes CronJob in the `media` namespace.

```
kubernetes/apps/media/recyclarr/
├── application.yaml
├── cronjob.yaml       # runs daily, calls Radarr + Sonarr APIs
├── configmap.yaml     # recyclarr.yml config
├── pvc.yaml           # 1Gi Longhorn (recyclarr cache)
└── kustomization.yaml
```

**`configmap.yaml` (recyclarr.yml):**
```yaml
radarr:
  main:
    base_url: http://radarr.media.svc.cluster.local:7878
    api_key: !env_var RADARR_API_KEY
    quality_definition:
      type: movie
    quality_profiles:
      - name: HD Bluray + WEB
        reset_unmatched_scores:
          enabled: true
        upgrade:
          allowed: true
          until_quality: Bluray-1080p
          until_score: 10000
    custom_formats:
      - trash_ids:
          - ed38b889b31be83fda192888e2286d83  # BR-DISK
          - 90a6f9a284dff5103f6346090e6280c8  # LQ
        assign_scores_to:
          - name: HD Bluray + WEB
            score: -10000

sonarr:
  main:
    base_url: http://sonarr.media.svc.cluster.local:8989
    api_key: !env_var SONARR_API_KEY
    quality_definition:
      type: series
    quality_profiles:
      - name: HD Bluray + WEB
        upgrade:
          allowed: true
          until_quality: Bluray-1080p
```

**`cronjob.yaml`:**
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: recyclarr
  namespace: media
spec:
  schedule: "0 3 * * *"   # daily at 03:00
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: recyclarr
              image: ghcr.io/recyclarr/recyclarr:latest
              args: ["sync"]
              env:
                - name: RADARR_API_KEY
                  valueFrom:
                    secretKeyRef:
                      name: recyclarr-secret
                      key: radarr_api_key
                - name: SONARR_API_KEY
                  valueFrom:
                    secretKeyRef:
                      name: recyclarr-secret
                      key: sonarr_api_key
              volumeMounts:
                - name: config
                  mountPath: /config
          volumes:
            - name: config
              persistentVolumeClaim:
                claimName: recyclarr-cache
```

API keys are retrieved from Radarr/Sonarr Settings → General → Security after first deploy.
Store them as a SOPS-encrypted secret:
```
kubernetes/apps/media/recyclarr/secrets.yaml  (encrypted)
```

---

## Monitoring — exportarr

`exportarr` exposes Prometheus metrics for Radarr, Sonarr, Prowlarr, and Bazarr (movies
wanted/missing/downloaded, queue depth, indexer health, etc.).

**Add to the media stack:**
```
kubernetes/apps/media/exportarr/
├── application.yaml
├── deployment.yaml    # ghcr.io/onedr0p/exportarr:latest (multi-instance)
├── service.yaml       # ClusterIP :9707 (Prometheus scrape target)
└── kustomization.yaml
```

Run one exportarr pod per ARR app (or use separate Deployments):
```yaml
# Example for Radarr exporter
containers:
  - name: exportarr-radarr
    image: ghcr.io/onedr0p/exportarr:latest
    args: ["radarr"]
    env:
      - name: PORT
        value: "9707"
      - name: URL
        value: "http://radarr.media.svc.cluster.local:7878"
      - name: APIKEY
        valueFrom:
          secretKeyRef:
            name: exportarr-secret
            key: radarr_api_key
    ports:
      - containerPort: 9707
```

**Prometheus scrape config** — add to `kube-prometheus-stack` values:
```yaml
prometheus:
  prometheusSpec:
    additionalScrapeConfigs:
      - job_name: exportarr-radarr
        static_configs:
          - targets: ['exportarr.media.svc.cluster.local:9707']
      - job_name: exportarr-sonarr
        static_configs:
          - targets: ['exportarr.media.svc.cluster.local:9708']
```

**Grafana dashboards:** Import from grafana.com:
- Radarr: dashboard ID `15027`
- Sonarr: dashboard ID `15028`
- qBittorrent: dashboard ID `15315`

---

## VPN Sidecar Template (gluetun — future use)

When VPN is needed, add `gluetun` as a sidecar to the qBittorrent pod. The sidecar
creates a network namespace that qBittorrent's container shares. All qBittorrent traffic
exits through the VPN; the web UI remains reachable from within the cluster via localhost.

```yaml
# In qbittorrent/deployment.yaml — replace single-container spec with:
spec:
  containers:
    - name: gluetun
      image: ghcr.io/qdm12/gluetun:latest
      securityContext:
        capabilities:
          add: ["NET_ADMIN"]
      env:
        - name: VPN_SERVICE_PROVIDER
          value: "mullvad"           # or "nordvpn", "protonvpn", etc.
        - name: VPN_TYPE
          value: "wireguard"
        - name: WIREGUARD_PRIVATE_KEY
          valueFrom:
            secretKeyRef:
              name: gluetun-secret
              key: wireguard_private_key
        - name: WIREGUARD_ADDRESSES
          valueFrom:
            secretKeyRef:
              name: gluetun-secret
              key: wireguard_addresses
        - name: SERVER_COUNTRIES
          value: "Netherlands"
      ports:
        - containerPort: 8888   # HTTP proxy (optional)
      resources:
        requests:
          cpu: 50m
          memory: 64Mi
        limits:
          cpu: 200m
          memory: 128Mi

    - name: qbittorrent
      image: linuxserver/qbittorrent:latest
      # No ports here — gluetun owns the network namespace
      # qBittorrent web UI is accessible via gluetun's localhost:8080
      env:
        - name: PUID
          value: "1001"
        - name: PGID
          value: "1001"
        - name: WEBUI_PORT
          value: "8080"
      volumeMounts:
        - name: config
          mountPath: /config
        - name: data
          mountPath: /data/downloads
```

The Service for qBittorrent still targets port `8080` — it reaches qBittorrent through
gluetun's shared network namespace.

Store VPN credentials as a SOPS-encrypted secret:
```
kubernetes/apps/media/qbittorrent/secrets.yaml  (encrypted, add when VPN is enabled)
```

---

## Image Versions

Using `latest` tags in production is risky — a bad upstream release can break the stack
with no easy rollback. Prefer pinned minor versions and let Renovate bot (or manual review)
bump them.

| App          | Recommended image                              |
|--------------|------------------------------------------------|
| Jellyfin     | `jellyfin/jellyfin:10.10`                      |
| Radarr       | `linuxserver/radarr:5`                         |
| Sonarr       | `linuxserver/sonarr:4`                         |
| Prowlarr     | `linuxserver/prowlarr:1`                       |
| Bazarr       | `linuxserver/bazarr:1`                         |
| qBittorrent  | `linuxserver/qbittorrent:5`                    |
| Jellyseerr   | `fallenbagel/jellyseerr:2`                     |
| FlareSolverr | `ghcr.io/flaresolverr/flaresolverr:v3`         |
| Recyclarr    | `ghcr.io/recyclarr/recyclarr:7`                |
| exportarr    | `ghcr.io/onedr0p/exportarr:v2`                 |

> **Renovate bot:** Add a `renovate.json` at the repo root to auto-open PRs when new image
> versions are available. ArgoCD will apply them automatically after merge.

---

## Notes

- **No VPN on qBittorrent for now** — see the gluetun sidecar template above when ready to add it
- **Sonarr v4** is the current stable release
- **linuxserver.io** images are preferred for ARR apps — `PUID`/`PGID` support is built-in
- **FlareSolverr must deploy before adding Cloudflare-protected indexers** in Prowlarr
- **Recyclarr API keys** come from the running Radarr/Sonarr instances — deploy those first, then create the recyclarr secret
