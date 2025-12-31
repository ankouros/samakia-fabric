variable "iso_url" {
  type = string
}

variable "iso_checksum" {
  type = string
}

variable "vm_name" {
  type = string
}

variable "output_dir" {
  type = string
}

variable "ssh_username" {
  type    = string
  default = "packer"
}

variable "ssh_password" {
  type      = string
  sensitive = true
}

variable "ssh_timeout" {
  type    = string
  default = "30m"
}

variable "disk_size" {
  type    = string
  default = "20G"
}

variable "memory" {
  type    = number
  default = 2048
}

variable "cpus" {
  type    = number
  default = 2
}

variable "headless" {
  type    = bool
  default = true
}

variable "boot_command" {
  type    = list(string)
  default = []
}

variable "boot_wait" {
  type    = string
  default = "5s"
}

variable "ansible_playbook_path" {
  type = string
}

variable "image_id" {
  type = string
}

variable "image_version" {
  type = string
}

variable "build_time" {
  type    = string
  default = "unknown"
}
