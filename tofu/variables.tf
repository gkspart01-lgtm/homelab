variable "proxmox" {
  description = "Zugang zum Proxmox-Host (API-Token, vom Bootstrap angelegt)"
  type = object({
    endpoint  = string
    api_token = string
    insecure  = optional(bool, true)
    ssh_user  = optional(string, "root")
  })
}

variable "defaults" {
  description = "Vorgaben fuer alle Gaeste"
  type = object({
    node         = string
    datastore    = string
    bridge       = string
    lxc_template = string
    template_id  = number
    searchdomain = string
    gateway      = string
    dns          = string
    ssh_keys     = list(string)
  })
}

variable "guests" {
  description = "Alle VMs und LXC-Container. enabled=false = deaktiviert (RAM sparen)"
  type = map(object({
    enabled      = optional(bool, true)
    type         = string # "vm" | "lxc"
    vmid         = number
    cores        = number
    memory       = number                   # MB
    disk         = number                   # GB
    ip           = optional(string, "dhcp") # "dhcp" oder "192.168.178.20/21"
    tags         = optional(list(string), [])
    purpose      = optional(string, "")
    unprivileged = optional(bool, true)
    template     = optional(string, "") # abweichendes LXC-Template
  }))
}
