variable "resource_group" {
  description = "The resource group to be used"
}

variable "prefix" {
  description = "The prefix that will be used for all resources in this template"
}

variable "location" {
  description = "The Azure Region in which all resources in this example should be created."
  default     = "East US"
}

variable "vm_count" {
    description = "How many Virtual Machines should be created?"
    default = 2
}