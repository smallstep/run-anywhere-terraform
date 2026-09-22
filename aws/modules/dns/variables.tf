variable "domain" {
  description = "Base domain; this module creates its public zone. The CRL bucket name and every platform URL derive from it."
  type        = string
}

variable "lobby_eip_public_ips" {
  description = "The pre-allocated lobby NLB addresses from modules/network. Every platform A record answers with all of them."
  type        = list(string)
}
