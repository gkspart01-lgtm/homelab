provider "proxmox" {
  endpoint  = var.proxmox.endpoint
  api_token = var.proxmox.api_token
  insecure  = var.proxmox.insecure
  ssh {
    agent    = true
    username = var.proxmox.ssh_user
  }
}

locals {
  active = { for name, g in var.guests : name => g if g.enabled }
  vms    = { for name, g in local.active : name => g if g.type == "vm" }
  lxcs   = { for name, g in local.active : name => g if g.type == "lxc" }

  ipv4 = { for name, g in local.active : name => {
    address = g.ip
    gateway = g.ip == "dhcp" ? null : var.defaults.gateway
  } }
}

# --- VMs: Klon aus dem Debian-13-cloud-init-Template (VMID 9000) -------------
resource "proxmox_virtual_environment_vm" "vm" {
  for_each = local.vms

  name        = each.key
  description = each.value.purpose
  tags        = concat(["iac"], each.value.tags)
  node_name   = var.defaults.node
  vm_id       = each.value.vmid
  started     = true
  on_boot     = true

  clone {
    vm_id = var.defaults.template_id
    full  = true
  }

  agent {
    enabled = true
    trim    = true
  }

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = var.defaults.datastore
    interface    = "scsi0"
    size         = each.value.disk
    discard      = "on"
    file_format  = "raw"
  }

  network_device {
    bridge = var.defaults.bridge
    model  = "virtio"
  }

  initialization {
    datastore_id = var.defaults.datastore
    ip_config {
      ipv4 {
        address = local.ipv4[each.key].address
        gateway = local.ipv4[each.key].gateway
      }
    }
    dns {
      domain  = var.defaults.searchdomain
      servers = [var.defaults.dns]
    }
    user_account {
      username = "debian"
      keys     = var.defaults.ssh_keys
    }
  }
}

# --- LXC-Container (Forgejo, Hermes, Monitoring, ...) ------------------------
resource "proxmox_virtual_environment_container" "lxc" {
  for_each = local.lxcs

  node_name     = var.defaults.node
  vm_id         = each.value.vmid
  description   = each.value.purpose
  tags          = concat(["iac"], each.value.tags)
  unprivileged  = each.value.unprivileged
  start_on_boot = true
  started       = true

  cpu {
    cores = each.value.cores
  }

  memory {
    dedicated = each.value.memory
    swap      = 512
  }

  disk {
    datastore_id = var.defaults.datastore
    size         = each.value.disk
  }

  network_interface {
    name   = "eth0"
    bridge = var.defaults.bridge
  }

  operating_system {
    template_file_id = each.value.template != "" ? each.value.template : var.defaults.lxc_template
    type             = "debian"
  }

  initialization {
    hostname = each.key
    ip_config {
      ipv4 {
        address = local.ipv4[each.key].address
        gateway = local.ipv4[each.key].gateway
      }
    }
    dns {
      domain  = var.defaults.searchdomain
      servers = [var.defaults.dns]
    }
    user_account {
      keys = var.defaults.ssh_keys
    }
  }

  features {
    nesting = true
  }
}

output "guests" {
  value = {
    for name, g in local.active :
    name => { type = g.type, id = g.vmid, ram = "${g.memory} MB", ip = g.ip }
  }
}

output "ram_total_mb" {
  description = "Reservierter RAM aller aktiven Gaeste. 16384 MB ist die harte Grenze des Hosts."
  value       = sum([for g in local.active : g.memory])
}

output "ram_reserve_mb" {
  description = "Was fuer Host + Reserve uebrig bleibt"
  value       = 16384 - sum([for g in local.active : g.memory])
}
