variable "bucket_name" {
  description = "Bucket name were the bastion will store the logs"
}

variable "tags" {
  description = "A mapping of tags to assign"
  default     = {}
  type        = "map"
}

variable "region" {}

variable "cidrs" {
  description = "List of CIDRs than can access to the bastion. Default : 0.0.0.0/0"
  type        = "list"

  default = [
    "0.0.0.0/0",
  ]
}

variable "vpc_id" {
  description = "VPC id were we'll deploy the bastion"
}

variable "bastion_host_key_pair" {
  description = "Select the key pair to use to launch the bastion host"
}

variable "bastion_record_name" {
  description = "DNS record name to use for the bastion"
  default     = ""
}

variable "elb_subnets" {
  type        = "list"
  description = "List of subnet were the ELB will be deployed"
}

variable "auto_scaling_group_subnets" {
  type        = "list"
  description = "List of subnet were the Auto Scalling Group will deploy the instances"
}

variable "bastion_amis" {
  type = "map"

  default = {
    "us-east-1"      = "ami-f5f41398"
    "us-west-2"      = "ami-d0f506b0"
    "us-west-1"      = "ami-6e84fa0e"
    "eu-west-1"      = "ami-b0ac25c3"
    "eu-central-1"   = "ami-d3c022bc"
    "ap-southeast-1" = "ami-1ddc0b7e"
    "ap-northeast-2" = "ami-cf32faa1"
    "ap-northeast-1" = "ami-29160d47"
    "ap-southeast-2" = "ami-0c95b86f"
    "sa-east-1"      = "ami-fb890097"
  }
}

variable "bastion_instance_count" {
  default = 1
}

variable "duo_ikey" {
  description = "Duo Intergration Key"
  default     = "oj3iwfh339f3n"
}

variable "duo_skey" {
  description = "Duo Secret Key"
  default     = "oj3iwfh339f3n"
}

variable "duo_host_api" {
  description = "Duo Host API"
  default     = "duosecurity.com"
}

variable "company_name" {
  description = "Company name for MOTD"
  default     = "defaultcompanyname"
}
