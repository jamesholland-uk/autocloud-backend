/*
 * Terraform variable declarations
 */


/*
 * GCP Variables
 */

variable "gcp_project_id" {
  description = "GCP Project ID"
  type = "string"
  default = "auto-hack-cloud"
}

variable "gcp_region" {
  description = ""
  type = "string"
  default = "europe-west2"
}

variable "gcp_zone" {
  description = ""
  type = "string"
  default = "europe-west2-b"
}

/*
 * Creds
 */

variable "gcp_credentials_file" {
  description = "Full path to the JSON credentials file"
  type = "string"
  default = "../gcp_compute_key_svc_auto-hack-cloud.json"
}

variable "gcp_ssh_key" {
    description = "Full path to the SSH public key file"
    type = "string"
    default = "../id_rsa.pub"
}

/*
 * autocloud variables
 */

variable "subnet-octet" {
  description = ""
  type = "string"
  default = "x"
}