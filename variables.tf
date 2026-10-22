variable "gcp_project_id" {
    description = "This is gcp project id"
    type        = string
#    default = "rock-loop-449918-b0"
}

variable "region" {
    description = "This is gcp region"
    type        = string
#    default = "us-central1"
}

variable "zone" {
  description = "This is GCP Zone"
  type        = string
#  default     = "us-central1-a"
}

variable "vm_name" {
  description = "This is Name of the VM"
  type        = string
#  default     = "my-vm"
}