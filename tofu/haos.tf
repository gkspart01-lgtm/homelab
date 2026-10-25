# Home Assistant OS — eigenes UEFI-Image, kein Klon aus dem Debian-Template 9000.
#
# Warum eine eigene Ressource: HAOS bringt eine eigene Partitionierung
# (hassos-boot, kernel0/1, system0/1, bootstate, overlay, data) und bootet nur
# per UEFI. Ein Klon des Debian-Templates wäre ein anderes Betriebssystem.
#
# Der Host muss OVMF/UEFI können — in einem *verschachtelten* PVE (PVE in einer VM
# in einer VM) ist OVMF nicht nutzbar, siehe proxmox-vm-setup §2e.

resource "proxmox_virtual_environment_vm" "haos" {
  count = var.haos.enabled ? 1 : 0

  name        = "haos"
  description = "Home Assistant OS ${var.haos.version} (UEFI, eigenes Image, von OpenTofu verwaltet)"
  tags        = concat(["iac", "smarthome"], var.haos.tags)
  node_name   = var.defaults.node
  vm_id       = var.haos.vmid
  started     = true
  on_boot     = true

  # HAOS ist UEFI-only
  bios    = "ovmf"
  machine = "q35"

  agent {
    enabled = true
    trim    = true
  }

  cpu {
    cores = var.haos.cores
    type  = "host"
  }

  memory {
    dedicated = var.haos.memory
  }

  efi_disk {
    datastore_id      = var.defaults.datastore
    type              = "4m"
    pre_enrolled_keys = false
  }

  disk {
    datastore_id = var.defaults.datastore
    interface    = "scsi0"
    size         = var.haos.disk
    file_format  = "raw"
    import_from  = var.haos.image
    discard      = "on"
    ssd          = true
  }

  network_device {
    bridge = var.defaults.bridge
    model  = "virtio"
  }

  serial_device {
    device = "socket"
  }

  # Kein initialization-Block: HAOS nutzt kein cloud-init. Die Adresse kommt per
  # DHCP; eine feste IP wird im HA-UI (Einstellungen -> System -> Netzwerk) oder
  # per DHCP-Reservierung auf die MAC gesetzt.
}

output "haos" {
  description = "Home Assistant OS (DHCP; IP im Router/HA-UI nachsehen)"
  value = var.haos.enabled ? {
    id    = var.haos.vmid
    cores = var.haos.cores
    ram   = "${var.haos.memory} MB"
    disk  = "${var.haos.disk} GB"
    url   = "http://<dhcp-ip>:8123"
  } : null
}
