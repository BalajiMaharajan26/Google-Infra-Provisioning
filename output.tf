output "vm_external_ip" {
  description = "External IP of the VM"
  value       = google_compute_instance.vm-terraform.network_interface[0].access_config[0].nat_ip
}

output "vm_internal_ip_1" {
  description = "Internal IP of the first network interface"
  value       = google_compute_instance.vm-terraform.network_interface[0].network_ip
}

output "vm_internal_ip_2" {
  description = "Internal IP of the second network interface"
  value       = google_compute_instance.vm-terraform.network_interface[1].network_ip
}