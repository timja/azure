# This terraform plan describe the virtual machine needed to run cert.ci.jenkins.io
# This machine must remain in a private network.

resource "azurerm_resource_group" "certci" {
  name     = "${var.prefix}certci"
  location = "${var.location}"

  tags {
    env = "${var.prefix}"
  }
}

# This public ip is currently needed to whitelist this service on the ldap firewall.
# Once prodbean is migrated in a private network which doesn't conflict with public prod network,
# We can then remove this public IP and use private network
resource "azurerm_public_ip" "certci" {
  name                         = "${var.prefix}certci"
  location                     = "${var.location}"
  resource_group_name          = "${azurerm_resource_group.certci.name}"
  public_ip_address_allocation = "static"

  tags {
    env = "${var.prefix}"
  }
}

# Interface within a network without access from internet
resource "azurerm_network_interface" "certci_private" {
  name                    = "${var.prefix}-certci"
  location                = "${azurerm_resource_group.certci.location}"
  resource_group_name     = "${azurerm_resource_group.certci.name}"
  enable_ip_forwarding    = false
  internal_dns_name_label = "certci"

  ip_configuration {
    name                          = "${var.prefix}-private"
    subnet_id                     = "${azurerm_subnet.public_data.id}"
    private_ip_address_allocation = "static"
    private_ip_address            = "10.0.2.252"
    public_ip_address_id          = "${azurerm_public_ip.certci.id}"
  }

  tags {
    env = "${var.prefix}"
  }
}

resource "azurerm_virtual_machine" "certci" {
  name                = "${var.prefix}-certci"
  location            = "${azurerm_resource_group.certci.location}"
  resource_group_name = "${azurerm_resource_group.certci.name}"

  network_interface_ids = [
    "${azurerm_network_interface.certci_private.id}",
  ]

  primary_network_interface_id = "${azurerm_network_interface.certci_private.id}"
  vm_size                      = "Standard_D2s_v3"

  delete_os_disk_on_termination    = true
  delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name              = "${var.prefix}certci"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
    disk_size_gb      = "50"
    os_type           = "Linux"
  }

  os_profile {
    computer_name  = "cert.ci.jenkins.io"
    admin_username = "azureadmin"
    custom_data    = "${ var.prefix == "prod"? file("scripts/init-puppet.sh"): "#cloud-config" }"
  }

  os_profile_linux_config {
    disable_password_authentication = true

    ssh_keys {
      key_data = "${file("${var.ssh_pubkey_path}")}"
      path     = "/home/azureadmin/.ssh/authorized_keys"
    }
  }

  tags {
    env = "${var.prefix}"
  }
}

# Disk that will be used for jenkins home
resource "azurerm_managed_disk" "certci_data" {
  name                 = "certci-data"
  location             = "${azurerm_resource_group.certci.location}"
  resource_group_name  = "${azurerm_resource_group.certci.name}"
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = "300"

  tags {
    env = "${var.prefix}"
  }
}

resource "azurerm_virtual_machine_data_disk_attachment" "certci_data" {
  managed_disk_id    = "${azurerm_managed_disk.certci_data.id}"
  virtual_machine_id = "${azurerm_virtual_machine.certci.id}"
  lun                = "10"
  caching            = "ReadWrite"
}
