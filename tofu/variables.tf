variable "proxmox" {
  description = "Zugang zum Proxmox-Host (API-Token, vom Bootstrap angelegt)"
  type = object({
    endpoint        = string
    api_token       = string
    insecure        = optional(bool, true)
    ssh_user        = optional(string, "root")
    ssh_private_key = optional(string, "/home/hermes/.ssh/id_ed25519")
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
    host_ram_mb  = optional(number, 16384)
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

variable "haos" {
  description = "Home Assistant OS als UEFI-VM (eigenes Image, kein Klon aus dem Debian-Template)"
  type = object({
    enabled = optional(bool, true)
    vmid    = number
    cores   = number
    memory  = number
    disk    = number
    version = string
    image   = string # volume-id des entpackten Images, z.B. local:iso/haos_ova-18.3.qcow2
    tags    = optional(list(string), [])
  })
}
