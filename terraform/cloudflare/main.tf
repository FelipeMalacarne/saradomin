provider "cloudflare" {
  api_token = var.api_token
}

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 5.8.2"
    }
  }
}

# R2 buckets
# saradomin-tfstate is created manually (needed before terraform init can run)
resource "cloudflare_r2_bucket" "longhorn" {
  account_id = var.account_id
  name       = "saradomin-longhorn"
}

# Single tunnel handles both vault.* and jellyfin.* — Traefik routes by host header
resource "cloudflare_zero_trust_tunnel_cloudflared" "saradomin_tunnel" {
  account_id = var.account_id
  name       = "Terraform saradomin tunnel"
  config_src = "cloudflare"
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "saradomin_tunnel_token" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.saradomin_tunnel.id
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "saradomin_tunnel_config" {
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.saradomin_tunnel.id
  account_id = var.account_id
  config = {
    ingress = [
      {
        hostname = "vault.${var.zone}"
        service  = "http://traefik.networking.svc.cluster.local:80"
      },
      {
        hostname = "jellyfin.${var.zone}"
        service  = "http://traefik.networking.svc.cluster.local:80"
      },
      {
        service = "http_status:404"
      }
    ]
  }
}

resource "cloudflare_dns_record" "vault_dns" {
  zone_id = var.zone_id
  name    = "vault.${var.zone}"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.saradomin_tunnel.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
  comment = "[terraform] saradomin Vaultwarden"
}

resource "cloudflare_dns_record" "jellyfin_dns" {
  zone_id = var.zone_id
  name    = "jellyfin.${var.zone}"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.saradomin_tunnel.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
  comment = "[terraform] saradomin Jellyfin"
}
