variable "project_id" {
  type        = string
  description = "The GCP project ID to deploy resources into."
}

variable "region" {
  type        = string
  description = "The GCP region for the VPC and subnet."
  default     = "asia-southeast2"
}

variable "container_admin_users" {
  description = "List of users who should have roles/container.admin"
  type        = list(string)
  default     = [
    "user1@gmail.com",
    "user2@gmail.com",
    "devops@company.com"
  ]
}