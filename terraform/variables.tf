variable "project" {
  description = "Name prefix for every resource"
  type        = string
  default     = "shipguard"
}

variable "owner" {
  description = "Your name, used in tags"
  type        = string
  default     = "devops-student"
}

variable "aws_region" {
  description = "AWS region (ap-south-1 = Mumbai)"
  type        = string
  default     = "ap-south-1"
}

variable "my_ip_cidr" {
  description = "Your public IP in CIDR form, e.g. 203.0.113.10/32. Only this IP can reach SSH, Jenkins, SonarQube and the app."
  type        = string

  validation {
    condition     = can(cidrhost(var.my_ip_cidr, 0)) && var.my_ip_cidr != "0.0.0.0/0"
    error_message = "my_ip_cidr must be a valid CIDR and must not be 0.0.0.0/0."
  }
}

variable "alert_email" {
  description = "Email address that receives CloudWatch alarm notifications"
  type        = string
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key used for EC2 access"
  type        = string
  default     = "~/.ssh/shipguard.pub"
}

variable "availability_zone" {
  description = "AZ for the subnet (pinned so the plan never drifts)"
  type        = string
  default     = "ap-south-1a"
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "jenkins_instance_type" {
  description = "Jenkins + SonarQube + scanners need ~8 GB RAM"
  type        = string
  default     = "t3.large"
}

variable "k8s_instance_type" {
  description = "Single-node k3s cluster"
  type        = string
  default     = "t3.small"
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "learner_lab" {
  description = "true for AWS Academy Learner Lab: use the pre-made LabInstanceProfile instead of creating IAM roles"
  type        = bool
  default     = false
}

variable "lab_instance_profile" {
  description = "Instance profile that exists in Learner Lab accounts"
  type        = string
  default     = "LabInstanceProfile"
}
