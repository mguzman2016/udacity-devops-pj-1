provider "azurerm" {
  features {}
}

# Use an existing resource group by importing it
# Pre-import step:
# terraform import azurerm_resource_group.main /subscriptions/{SUBSCRIPTION_ID}/resourceGroups/{RESOURCE_GROUP_NAME}
# terraform import azurerm_resource_group.main /subscriptions/1780bc89-8672-4bcd-8b0f-016eb40d22da/resourceGroups/Azuredevops
data "azurerm_resource_group" "main" {
  name = var.resource_group
}

# Create a Virtual network
resource "azurerm_virtual_network" "vms_net" {
  name                = "${var.prefix}-network"
  address_space       = ["10.0.0.0/16"]
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name

  tags = {
    env = "Production"
  }
}

# And a subnet on that virtual network
resource "azurerm_subnet" "vms_internal" {
  name                 = "internal"
  resource_group_name  = data.azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.vms_net.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_network_security_group" "vms" {
  name                = "${var.prefix}-net-sg"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name

  # Rule 1: Allow load balancer probes
  security_rule {
    name                       = "${var.prefix}-allow-azure-load-balancer"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  # Rule 2: Allow backend communication between VMs (VNet to VNet)
  security_rule {
    name                       = "${var.prefix}-vnet-allow"
    priority                   = 102
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  # Rule 3: Allow traffic from the Load Balancer frontend IP (client traffic)
  security_rule {
    name                       = "${var.prefix}-allow-lb-client-traffic"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "0.0.0.0/0"
    destination_address_prefix = "*"
  }

  # Rule 4: Allow outbound traffic from VMs to the load balancer/backend
  security_rule {
    name                       = "${var.prefix}-vnet-outbound"
    priority                   = 200
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "VirtualNetwork"
  }

  # Rule 5: Deny all inbound traffic (default deny rule after specific allows)
  security_rule {
    name                       = "${var.prefix}-deny-all"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "0.0.0.0/0"
    destination_address_prefix = "*"
  }

  tags = {
    environment = "Production"
  }
}

# Add to subnet
resource "azurerm_subnet_network_security_group_association" "vms_nsg_assoc" {
  subnet_id                 = azurerm_subnet.vms_internal.id
  network_security_group_id = azurerm_network_security_group.vms.id
}

# Create network interfaces for each VM
resource "azurerm_network_interface" "vms_nics" {
    count                   = var.vm_count
    name                    = "${var.prefix}-nic-${count.index}"
    location                = data.azurerm_resource_group.main.location
    resource_group_name     = data.azurerm_resource_group.main.name

    ip_configuration {
        name                          = "${var.prefix}-ipconfig-${count.index}"
        private_ip_address_allocation = "Dynamic"
        subnet_id                     = azurerm_subnet.vms_internal.id
    }

    tags = {
        environment = "Production"
    }
}

# Create a public IP for the load balancer
resource "azurerm_public_ip" "lb_public_ip" {
  name                = "${var.prefix}-load-balancer-public-ip"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
  allocation_method   = "Static"

  tags = {
    environment = "Production"
  }
}

# Backend address pool
resource "azurerm_network_interface_backend_address_pool_association" "nic_load_balancer_pool" {
  count = var.vm_count
  network_interface_id = azurerm_network_interface.vms_nics[count.index].id
  ip_configuration_name = "${var.prefix}-ipconfig-${count.index}"
  backend_address_pool_id = azurerm_lb_backend_address_pool.load_balancer_pool.id
}

# Create Public Load Balancer
resource "azurerm_lb" "load_balancer" {
  name                    = "${var.prefix}-load-balancer"
  location                = data.azurerm_resource_group.main.location
  resource_group_name     = data.azurerm_resource_group.main.name
  sku                     = "Standard"

  frontend_ip_configuration {
    name                 = "${var.prefix}-load-balancer-ip"
    public_ip_address_id = azurerm_public_ip.lb_public_ip.id
  }

  tags = {
    environment = "Production"
  }
}

# Address pool association
resource "azurerm_lb_backend_address_pool" "load_balancer_pool" {
  loadbalancer_id      = azurerm_lb.load_balancer.id
  name                 = "${var.prefix}-pool"
}

# probe
resource "azurerm_lb_probe" "http_probe" {
  loadbalancer_id     = azurerm_lb.load_balancer.id
  name                = "${var.prefix}-http-probe"
  port                = 80
}

resource "azurerm_lb_rule" "http_rule" {
  loadbalancer_id                 = azurerm_lb.load_balancer.id
  name                            = "${var.prefix}-http-rule"
  protocol                        = "Tcp"
  frontend_port                   = 80
  backend_port                    = 80
  frontend_ip_configuration_name  = "${var.prefix}-load-balancer-ip"
  backend_address_pool_ids        = [azurerm_lb_backend_address_pool.load_balancer_pool.id]
  probe_id                        = azurerm_lb_probe.http_probe.id
}

# VM availability set
resource "azurerm_availability_set" "vms_availability_set" {
  name                = "${var.prefix}-availability-set"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name

  tags = {
    environment = "Production"
  }
}

# Fetch Packer-built custom image
data "azurerm_image" "packer_image" {
  name                = "udacity-ubuntu-image"
  resource_group_name = var.resource_group
}

resource "azurerm_virtual_machine" "vms" {
  count               = var.vm_count
  name                = "${var.prefix}-vm-${count.index}"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  availability_set_id = azurerm_availability_set.vms_availability_set.id

  network_interface_ids = [azurerm_network_interface.vms_nics[count.index].id]
  vm_size               = "Standard_B1s"

  storage_image_reference {
    id = "${data.azurerm_image.packer_image.id}"
  }

  storage_os_disk {
    name              = "${var.prefix}-osdisk-${count.index}"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "${var.prefix}-vm-${count.index}"
    admin_username = "azureuser"
    admin_password = "@dminP@ssw0rd024728!"
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }

  tags = {
    environment = "Production"
  }
}
