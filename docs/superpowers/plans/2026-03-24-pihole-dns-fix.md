# Pi-hole DNS Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Pi-hole the sole DNS resolver for all Tailscale devices, replacing the separate CoreDNS-saradomin deployment.

**Architecture:** Remove `hostNetwork: true` from Pi-hole so it runs as a normal pod. Add a Tailscale LoadBalancer service (`pihole-dns`) that exposes port 53 UDP+TCP, giving Tailscale devices a stable hostname to use as their nameserver. CoreDNS-saradomin is then cascade-deleted and removed from git.

**Tech Stack:** Kubernetes (k3s), ArgoCD, Tailscale operator, Kustomize, kubectl

---

## File Map

| Action | File |
|--------|------|
| Modify | `kubernetes/apps/networking/pihole/deployment.yaml` |
| Create | `kubernetes/apps/networking/pihole/service-dns.yaml` |
| Modify | `kubernetes/apps/networking/pihole/kustomization.yaml` |
| Delete | `kubernetes/apps/networking/coredns-saradomin/` (entire directory) |

---

## Task 1: Remove hostNetwork from Pi-hole deployment

**Files:**
- Modify: `kubernetes/apps/networking/pihole/deployment.yaml`

- [ ] **Step 1: Edit the deployment**

Remove these two lines from `kubernetes/apps/networking/pihole/deployment.yaml`:

```yaml
# Remove these:
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
```

The result under `spec.template.spec` should go directly from `containers:` with no `hostNetwork` or `dnsPolicy` fields. `DNSMASQ_LISTENING=all` already in the env vars handles listening on all pod interfaces.

- [ ] **Step 2: Commit**

```bash
git add kubernetes/apps/networking/pihole/deployment.yaml
git commit -m "fix(pihole): remove hostNetwork, use standard pod networking"
```

---

## Task 2: Add Tailscale DNS service for Pi-hole

**Files:**
- Create: `kubernetes/apps/networking/pihole/service-dns.yaml`
- Modify: `kubernetes/apps/networking/pihole/kustomization.yaml`

- [ ] **Step 1: Create the service file**

Create `kubernetes/apps/networking/pihole/service-dns.yaml`:

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

- [ ] **Step 2: Register it in kustomization**

In `kubernetes/apps/networking/pihole/kustomization.yaml`, add `service-dns.yaml` to the `resources` list:

```yaml
resources:
  - deployment.yaml
  - pvc.yaml
  - configmap-dnsmasq.yaml
  - ingress.yaml
  - service-dns.yaml
```

- [ ] **Step 3: Commit**

```bash
git add kubernetes/apps/networking/pihole/service-dns.yaml kubernetes/apps/networking/pihole/kustomization.yaml
git commit -m "feat(pihole): add Tailscale LoadBalancer service for DNS (port 53)"
```

---

## Task 3: Push and verify Pi-hole DNS is reachable

- [ ] **Step 1: Push to trigger ArgoCD sync**

```bash
git push
```

- [ ] **Step 2: Wait for ArgoCD to sync**

Watch the pihole app sync in ArgoCD UI (`https://argocd.saradomin`) or run:

```bash
kubectl rollout status deployment/pihole -n networking
```

Expected: `deployment "pihole" successfully rolled out`

- [ ] **Step 3: Confirm the Tailscale service is provisioned**

```bash
kubectl get svc pihole-dns -n networking
```

Expected: `TYPE: LoadBalancer`, `EXTERNAL-IP` shows a Tailscale IP (not `<pending>`). This may take ~30 seconds after sync.

- [ ] **Step 4: Find the pihole-dns Tailscale IP**

```bash
kubectl get svc pihole-dns -n networking -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

Note this IP — call it `<PIHOLE_DNS_IP>`.

- [ ] **Step 5: Verify Pi-hole responds to DNS queries**

From any Tailscale-connected device (or the cluster node):

```bash
dig pihole.saradomin @<PIHOLE_DNS_IP>
```

Expected: returns `100.79.221.47` in the ANSWER section.

```bash
dig google.com @<PIHOLE_DNS_IP>
```

Expected: returns valid A records (confirms upstream forwarding works).

---

## Task 4: Switch Tailscale split DNS to Pi-hole (manual)

This step is done in the Tailscale admin panel — no git changes needed.

- [ ] **Step 1: Open Tailscale admin DNS settings**

Go to: https://login.tailscale.com/admin/dns

- [ ] **Step 2: Update nameservers**

Under **Nameservers → Custom nameservers**:
1. Remove the existing entry pointing to `dns-saradomin`
2. Add the `pihole-dns` hostname (or use `<PIHOLE_DNS_IP>` from Task 3)
3. Enable **Override local DNS**
4. Save

- [ ] **Step 3: Verify from a Tailscale device**

On any device connected to Tailscale (phone, laptop, etc.):

```bash
dig pihole.saradomin
# Expected: 100.79.221.47

dig doubleclick.net
# Expected: 0.0.0.0 (ad domain, should be blocked by Pi-hole)
```

Also confirm `https://pihole.saradomin` loads the Pi-hole admin UI and the Query Log shows traffic.

---

## Task 5: Remove CoreDNS-saradomin

Only proceed once Task 4 is verified working.

The root ArgoCD app has `automated.prune: true` and `selfHeal: true` — it will recreate the `coredns-saradomin` Application within seconds if the git directory still exists. The correct GitOps approach is to delete from git and push in one step; ArgoCD's root app will prune the Application object, which in turn removes the live child resources.

**Files:**
- Delete: `kubernetes/apps/networking/coredns-saradomin/` (entire directory — 5 files: `application.yaml`, `configmap.yaml`, `deployment.yaml`, `kustomization.yaml`, `service.yaml`)

- [ ] **Step 1: Delete the directory from git and push atomically**

```bash
rm -rf kubernetes/apps/networking/coredns-saradomin/
git add -A kubernetes/apps/networking/coredns-saradomin/
git commit -m "chore(coredns-saradomin): remove redundant DNS deployment, replaced by pihole-dns"
git push
```

ArgoCD's root app will detect that `coredns-saradomin/application.yaml` is gone and prune the `coredns-saradomin` Application object. That Application's own `prune: true` then removes its child Deployment, ConfigMap, and Service from the `networking` namespace.

- [ ] **Step 2: Confirm live resources are gone**

```bash
kubectl get deploy,svc,configmap -n networking | grep coredns
```

Expected: no output. If anything lingers after ~60 seconds, clean up manually:

```bash
argocd app delete coredns-saradomin --cascade
```

- [ ] **Step 3: Confirm ArgoCD root app is healthy**

In the ArgoCD UI (`https://argocd.saradomin`), verify the root app and pihole app show `Synced` / `Healthy`. The `coredns-saradomin` application entry should be gone.

---

## Rollback

If DNS breaks after Task 4:
1. In Tailscale admin, revert nameserver back to `dns-saradomin`
2. If Task 5 was already done, revert:
   ```bash
   git revert HEAD
   git push
   # Wait for ArgoCD to re-deploy coredns-saradomin
   ```
