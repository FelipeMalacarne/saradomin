# Pi-hole DNS Fix Design

**Date:** 2026-03-24

## Problem

Pi-hole is deployed but not in the DNS path for any Tailscale device. The Tailscale split DNS currently points to `coredns-saradomin`, a separate CoreDNS deployment — meaning ad-blocking is completely inactive. Pi-hole also runs with `hostNetwork: true`, which binds it directly to host port 53, making it fragile and preventing a clean Tailscale service from fronting it.

## Goal

Pi-hole becomes the sole DNS resolver for all Tailscale devices. It handles:
- `*.saradomin` internal resolution → `100.79.221.47` (via existing dnsmasq config)
- Ad-blocking for all other queries (via Pi-hole blocklists)

CoreDNS-saradomin is removed entirely as it is redundant.

## Architecture

```
Tailscale devices
  └── DNS queries → pihole-dns (Tailscale LB, port 53) → Pi-hole pod
                                                           ├── *.saradomin → 100.79.221.47 (dnsmasq)
                                                           └── everything else → upstream (8.8.8.8, etc.)
```

No change to HTTP ingress paths:
- `*.saradomin` → Traefik (Tailscale LB at 100.79.221.47)
- `ftm.dev.br` → Cloudflare tunnel

## Changes

### 1. Pi-hole Deployment (`kubernetes/apps/networking/pihole/deployment.yaml`)
- Remove `hostNetwork: true`
- Remove `dnsPolicy: ClusterFirstWithHostNet` — the pod will implicitly use the Kubernetes default `ClusterFirst`, which is correct for a standard pod
- `DNSMASQ_LISTENING=all` remains (tells dnsmasq to listen on all pod interfaces)
- All other config unchanged

### 2. New Tailscale DNS Service (`kubernetes/apps/networking/pihole/service-dns.yaml`)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: pihole-dns
  namespace: networking
  annotations:
    tailscale.com/hostname: "pihole-dns"
spec:
  type: LoadBalancer
  loadBalancerClass: tailscale
  selector:
    app: pihole
  ports:
    - name: dns-udp
      port: 53
      targetPort: 53
      protocol: UDP
    - name: dns-tcp
      port: 53
      targetPort: 53
      protocol: TCP
```

The existing `pihole-admin` ClusterIP service (port 80, for Traefik ingress) is unchanged.

### 3. Update Pi-hole kustomization (`kubernetes/apps/networking/pihole/kustomization.yaml`)
Add `service-dns.yaml` to the `resources` list.

### 4. Remove CoreDNS-saradomin

**Step 4a — Cascade delete the ArgoCD Application before removing from git.**

The `coredns-saradomin` ArgoCD Application has no `resources-finalizer.argocd.io` finalizer, so deleting its git source would orphan the live Kubernetes resources (Deployment, ConfigMap, Service) in the cluster. To cleanly remove everything, delete the Application with cascade before merging the directory removal:

```bash
argocd app delete coredns-saradomin --cascade
```

Or via kubectl:

```bash
kubectl delete application coredns-saradomin -n argocd
# Then manually delete the live resources if not auto-cleaned
kubectl delete deployment,service,configmap -l app=coredns-saradomin -n networking
```

**Step 4b — Remove the directory from git.**

Delete `kubernetes/apps/networking/coredns-saradomin/` entirely (all five files).

## Deployment Ordering (Critical)

The steps must be executed in this order to avoid a DNS outage for all Tailscale devices:

1. **Merge and sync Pi-hole changes** (steps 1–3): remove `hostNetwork`, add `service-dns.yaml`. Pi-hole is now reachable at `pihole-dns:53`.
2. **Verify Pi-hole responds** at the new Tailscale address before touching DNS config.
3. **Update Tailscale admin panel**: replace `dns-saradomin` with `pihole-dns`, enable "Override local DNS".
4. **Verify DNS works** on a Tailscale device (both `.saradomin` and a public domain).
5. **Remove coredns-saradomin** (step 4a + 4b).

If coredns-saradomin is removed before step 3, all Tailscale devices will lose DNS until the Tailscale admin panel is updated.

## Manual Step — Tailscale Admin Panel (after step 2 above)

1. Go to **DNS → Nameservers → Custom nameservers**
2. Remove the current entry pointing to `dns-saradomin`
3. Add `pihole-dns`
4. Enable **Override local DNS**

## Rollback

If something goes wrong after the Tailscale DNS switch:
1. In Tailscale admin, revert the nameserver back to `dns-saradomin`
2. Revert the Pi-hole deployment commit in git (ArgoCD will re-apply)

CoreDNS-saradomin should only be removed (step 5) once Pi-hole DNS is confirmed working, making rollback straightforward.

## Definition of Done

- `dig pihole.saradomin @<pihole-dns-tailscale-ip>` returns `100.79.221.47`
- `dig doubleclick.net @<pihole-dns-tailscale-ip>` returns `0.0.0.0` (blocked)
- Pi-hole admin UI is accessible at `https://pihole.saradomin` and shows query logs
- CoreDNS-saradomin pod is gone from the cluster
