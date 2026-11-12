variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "environment" {
  type    = string
  default = "staging"

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment must be staging or production"
  }
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "app_image" {
  type        = string
  description = "Immutable registry image tag or digest"
}

variable "vpc_id" {
  type    = string
  default = ""
}

variable "subnet_id" {
  type    = string
  default = ""
}

variable "state_bucket" {
  type        = string
  description = "Existing globally unique S3 state bucket"
}
