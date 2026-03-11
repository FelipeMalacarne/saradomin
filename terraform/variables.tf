variable "cloudflare_api_token" {
  description = "Cloudflare API Token"
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare Account ID"
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Zone ID for ftm.dev.br"
  type        = string
}

variable "cloudflare_zone" {
  description = "Domain (e.g. ftm.dev.br)"
  type        = string
}
