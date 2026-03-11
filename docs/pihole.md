# Pi-hole

Ad-blocking DNS server running on saradomin, accessible via Tailscale only.

## Access

Admin UI: http://pihole (Tailscale hostname) or http://\<saradomin-tailscale-ip\>/admin

## Set as DNS for all Tailscale devices

1. Go to [Tailscale admin panel](https://login.tailscale.com/admin/dns)
2. Under **Nameservers → Custom nameservers**, add the saradomin Tailscale IP
3. Enable **Override local DNS** so all devices use Pi-hole

All Tailscale-connected devices will now have ad blocking automatically.

## How it works

Pi-hole runs with `hostNetwork: true` on the saradomin node, binding directly to port 53 on the node IP. DNS clients always connect to port 53, so hostNetwork is required (NodePort range 30000+ won't work for DNS).

The admin UI is exposed separately via a Tailscale LoadBalancer service on port 80 — it never touches the public internet.

## Adding blocklists

Admin UI → **Adlists** → paste a URL → **Update Gravity**

Recommended lists:
- `https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts` (default)
- `https://raw.githubusercontent.com/anudeepND/blacklist/master/adservers.txt`

## Whitelisting a domain

Admin UI → **Whitelist** → add domain

Or via CLI inside the pod:
```bash
kubectl exec -n networking deploy/pihole -- pihole -w example.com
```

## Checking query logs

Admin UI → **Query Log** — shows every DNS request from all Tailscale devices.

## Updating Pi-hole

ArgoCD tracks `pihole/pihole:latest`. To force a pull:
```bash
kubectl rollout restart deployment/pihole -n networking
```
