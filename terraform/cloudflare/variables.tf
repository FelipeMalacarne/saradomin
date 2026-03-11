variable "api_token" {
  description = "Cloudflare API Token"
  type        = string
  sensitive   = true
}

variable "account_id" {
  description = "Cloudflare Account ID"
  type        = string
}

variable "zone_id" {
  description = "Zone ID for ftm.dev.br"
  type        = string
}

variable "zone" {
  description = "Domain (e.g. ftm.dev.br)"
  type        = string
}
