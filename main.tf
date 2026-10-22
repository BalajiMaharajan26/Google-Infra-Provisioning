resource "google_compute_network" "vpc_1" {
  name                    = "vpc-1"
  auto_create_subnetworks = false
}

resource "google_compute_network" "vpc_2" {
  name                    = "vpc-2"
  auto_create_subnetworks = false
}

# Create Subnet for VPC-1
resource "google_compute_subnetwork" "subnet_1" {
  name          = "subnet-1"
  network       = google_compute_network.vpc_1.self_link
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
}

# Create Subnet for VPC-2
resource "google_compute_subnetwork" "subnet_2" {
  name          = "subnet-2"
  network       = google_compute_network.vpc_2.self_link
  ip_cidr_range = "10.0.2.0/24"
  region        = var.region
}

# Allow SSH & ICMP in VPC-1
resource "google_compute_firewall" "firewall_vpc_1" {
  name    = "allow-ssh-icmp-vpc-1"
  network = google_compute_network.vpc_1.self_link

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
}

# Allow SSH & ICMP in VPC-2
resource "google_compute_firewall" "firewall_vpc_2" {
    name = "allow-ssh-icmp-vpc-2"
    network = google_compute_network.vpc_2.self_link

    allow {
        protocol = "icmp"
    }

    allow {
        protocol = "tcp"
        ports = ["22"]
    }

    source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_instance" "vm-terraform" {
  name         = var.vm_name
  machine_type = "e2-medium"
  zone         = "us-central1-a"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
      size = "15"
      labels = {
        my_label = "value"
      }
    }
  }

  network_interface {
    network = google_compute_network.vpc_1.self_link
    subnetwork = google_compute_subnetwork.subnet_1.self_link

    access_config {
      // Ephemeral public IP
    }
  }

  network_interface {
    network = google_compute_network.vpc_2.self_link
    subnetwork = google_compute_subnetwork.subnet_2.self_link

    # No External access for second interface
  }

  metadata = {
    foo = "bar"
  }

  metadata_startup_script = "echo hi > /test.txt"
}