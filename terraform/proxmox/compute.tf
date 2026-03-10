resource "proxmox_virtual_environment_download_file" "debian_cloud_image" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = var.proxmox_node_name

  url          = "https://cdimage.debian.org/cdimage/cloud/trixie/daily/latest/debian-13-generic-amd64-daily.qcow2"
  file_name    = "debian-13-generic-amd64.img"
}

# 1. Cloud-Init Bootstrapping Script
resource "proxmox_virtual_environment_file" "cloud_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node_name

  source_raw {
    data      = <<-EOF
      #cloud-config
      package_update: true
      packages:
        - curl
        - qemu-guest-agent
      write_files:
        - path: /usr/local/bin/bootstrap.sh
          permissions: "0755"
          content: |
            #!/usr/bin/env bash
            set -euo pipefail
            exec > >(tee /var/log/user-data.log) 2>&1

            echo "AdminBox Setup"
            curl -fsSLO https://raw.githubusercontent.com/Upwind1647/infrastructure-lab/main/scripts/setup_me.sh
            bash setup_me.sh

            echo "Docker install"
            curl -fsSL https://get.docker.com -o get-docker.sh
            sh get-docker.sh
            usermod -aG docker adminsetup

            echo "k3s install"
            ufw allow 6443/tcp
            curl -sfL https://get.k3s.io | sh -

            echo "permissions Kubeconfig"
            mkdir -p /home/adminsetup/.kube
            cp /etc/rancher/k3s/k3s.yaml /home/adminsetup/.kube/config
            chown -R adminsetup:adminsetup /home/adminsetup/.kube
            chmod 600 /home/adminsetup/.kube/config

      runcmd:
        - [ systemctl, enable, --now, qemu-guest-agent ]
        - [ bash, /usr/local/bin/bootstrap.sh ]
    EOF
    file_name = "k3s-bootstrap.yaml"
  }
}

# 2. K3s VM
resource "proxmox_virtual_environment_vm" "k3s_node" {
  name      = "k3s-master"
  node_name = var.proxmox_node_name
  vm_id     = 110

  agent {
    enabled = true
  }

  cpu {
    cores = 2
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 4096
  }

  disk {
    datastore_id = "local-lvm"
    file_id      = proxmox_virtual_environment_download_file.debian_cloud_image.id
    interface    = "virtio0"
    size         = 20
    discard      = "on"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
    user_data_file_id = proxmox_virtual_environment_file.cloud_config.id
  }

  network_device {
    bridge = "vmbr0"
  }
}
