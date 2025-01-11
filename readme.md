# Azure Infrastructure Operations Project: Deploying a Scalable IaaS Web Server in Azure

### Introduction
For this project, you will write a Packer template and a Terraform template to deploy a customizable, scalable web server in Azure.

### Getting Started
1. Clone this repository.
2. Create your infrastructure as code.
3. Update this README to reflect how someone would use your code.

### Dependencies
1. Create an [Azure Account](https://portal.azure.com)  
2. Install the [Azure Command Line Interface (CLI)](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest)  
3. Install [Packer](https://www.packer.io/downloads)  
4. Install [Terraform](https://www.terraform.io/downloads.html)  

### Instructions

### General Overview of Files

The repository contains 3 folders:
- `azure/policy.json`: Contains the Azure policy to deny the creation of resources without tags.
- `packer/server.json`: Contains the Packer template to create an image on Azure.
- `terraform/`: Contains the Terraform files needed to create the infrastructure. This folder contains 3 important files:
  - `main.tf`
  - `vars.tf`
  - `output.tf`

### How to Run / Use the Project Files

#### First Step
Make sure you have logged into the Azure portal by running:

```bash
az login
```

#### Azure Policy
To apply the Azure policy, execute the following commands from the `azure` folder:

- Create the policy:

```bash
az policy definition create --name tagging_policy --display-name "Deny resources without tags" --description "Denies the creation of resources without tags" --rules policy.json --mode Indexed
```

- Assign the policy to an existing subscription:

```bash
az policy assignment create --name tagging_policy_assignment --policy tagging_policy --scope /subscriptions/{subscription_id} --display-name "Deny Resources Without Tags Assignment" --description "Assignment of policy to deny resources without tags"
```

- Verify the policy assignment:

```bash
az policy assignment list
```

You should see an output similar to `images/policy-assignment.png`.

#### Packer Template
To create the image with Packer, make sure that you have the following environment variables set:

```bash
export ARM_CLIENT_ID=<your_client_id>
export ARM_CLIENT_SECRET=<your_client_secret>
export ARM_SUBSCRIPTION_ID=<your_subscription_id>
export ARM_RESOURCE_GROUP=<resource_group_name>
export LOCATION=<location>
```

Once these are defined, run:

```bash
packer build server.json
```

After the image is built, verify it by running:

```bash
az image list
```

You should see an image with values similar to `images/packer.png`.

#### Terraform
Since for this project Terraform won't manage the subscription directly, make sure to run the following command before executing any `.tf` files:

```bash
terraform import azurerm_resource_group.main /subscriptions/{subscription_id}/resourceGroups/{resource_group_name}
```

Then run:

```bash
terraform plan -out solution.plan
```

You should see an output similar to `images/solution.png`.

To deploy the infrastructure, run:

```bash
terraform apply "solution.plan"
```

### Output

You should have the following resources created:

- **Custom VM Image**
    - Created with packer.

- **Resource Group** (`azurerm_resource_group.main`):
  - Resource group with a specified name and location.

- **Virtual Network** (`azurerm_virtual_network.vms_net`):
  - Virtual network with an address space `10.0.0.0/16`.

- **Subnet** (`azurerm_subnet.vms_internal`):
  - Subnet named `internal` with an address prefix `10.0.2.0/24` inside the virtual network.

- **Network Security Group (NSG)** (`azurerm_network_security_group.vms`):
  - Security group with the following rules:
    - Inbound TCP traffic is allowed within the subnet `10.0.2.0/24`.
    - Inbound traffic from `0.0.0.0/0` to the subnet is denied.

- **Subnet Network Security Group Association** (`azurerm_subnet_network_security_group_association.vms_nsg_assoc`):
  - Associates the subnet with the NSG.

- **Network Interfaces** (`azurerm_network_interface.vms_nics`):
  - Creates a number of network interfaces (depending on `var.vm_count`), each with a dynamic private IP address.

- **Public IP** (`azurerm_public_ip.lb_public_ip`):
  - Static public IP for the load balancer.

- **Load Balancer** (`azurerm_lb.load_balancer`):
  - Public load balancer with a frontend IP configuration linked to the public IP.

- **Backend Address Pool** (`azurerm_lb_backend_address_pool.load_balancer_pool`):
  - Backend pool for the load balancer.

- **Load Balancer Probe** (`azurerm_lb_probe.http_probe`):
  - HTTP health probe on port 80.

- **Load Balancer Rule** (`azurerm_lb_rule.http_rule`):
  - HTTP load balancing rule from port 80 frontend to backend.

- **Network Interface Backend Address Pool Association** (`azurerm_network_interface_backend_address_pool_association.nic_load_balancer_pool`):
  - Associates each network interface with the load balancer’s backend address pool.

- **Availability Set** (`azurerm_availability_set.vms_availability_set`):
  - Availability set for virtual machines to ensure high availability.

- **Packer Image Data** (`data.azurerm_image.packer_image`):
  - References a pre-built Packer image for use as the VM image.

- **Virtual Machines** (`azurerm_virtual_machine.vms`):
  - Creates a number of virtual machines (depending on `var.vm_count`) with the following properties:
    - Uses the Packer-built custom image.
    - Configured with a network interface and OS disk.
    - `Standard_B1s` VM size.
    - Username: `azureuser`, with a specified password.
    - Password authentication enabled for Linux.

### Key Variables:
- `var.resource_group`: Resource group name.
- `var.location`: Azure region.
- `var.prefix`: Prefix for resource names.
- `var.vm_count`: Number of virtual machines to create.