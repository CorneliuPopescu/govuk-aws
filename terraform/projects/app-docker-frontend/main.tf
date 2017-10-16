# == Manifest: projects::app-docker-frontend
#
# Docker Frontend application cluster
#
# === Variables:
#
# aws_region
# stackname
# aws_environment
# ssh_public_key
# instance_ami_filter_name
# elb_internal_certname
# app_service_records
# docker_manager_frontend_1_reserved_ips_subnet
# docker_manager_frontend_2_reserved_ips_subnet
# docker_manager_frontend_3_reserved_ips_subnet
# docker_manager_frontend_1_ip
# docker_manager_frontend_2_ip
# docker_manager_frontend_3_ip
#
# === Outputs:
#

variable "aws_region" {
  type        = "string"
  description = "AWS region"
  default     = "eu-west-1"
}

variable "stackname" {
  type        = "string"
  description = "Stackname"
}

variable "aws_environment" {
  type        = "string"
  description = "AWS Environment"
}

variable "ssh_public_key" {
  type        = "string"
  description = "Default public key material"
}

variable "instance_ami_filter_name" {
  type        = "string"
  description = "Name to use to find AMI images"
  default     = ""
}

variable "elb_internal_certname" {
  type        = "string"
  description = "The ACM cert domain name to find the ARN of"
}

variable "elb_external_certname" {
  type        = "string"
  description = "The ACM cert domain name to find the ARN of"
}

variable "app_service_records" {
  type        = "list"
  description = "List of application service names that get traffic via this loadbalancer"
  default     = []
}

variable "docker_manager_frontend_1_reserved_ips_subnet" {
  type        = "string"
  description = "Name of the subnet to place the reserved IP of the instance"
}

variable "docker_manager_frontend_2_reserved_ips_subnet" {
  type        = "string"
  description = "Name of the subnet to place the reserved IP of the instance"
}

variable "docker_manager_frontend_3_reserved_ips_subnet" {
  type        = "string"
  description = "Name of the subnet to place the reserved IP of the instance"
}

variable "docker_manager_frontend_1_ip" {
  type        = "string"
  description = "IP address of the private IP to assign to the instance"
}

variable "docker_manager_frontend_2_ip" {
  type        = "string"
  description = "IP address of the private IP to assign to the instance"
}

variable "docker_manager_frontend_3_ip" {
  type        = "string"
  description = "IP address of the private IP to assign to the instance"
}

# Resources
# --------------------------------------------------------------
terraform {
  backend          "s3"             {}
  required_version = "= 0.10.7"
}

provider "aws" {
  region  = "${var.aws_region}"
  version = "1.0.0"
}

data "aws_acm_certificate" "elb_internal_cert" {
  domain   = "${var.elb_internal_certname}"
  statuses = ["ISSUED"]
}

data "aws_acm_certificate" "elb_external_cert" {
  domain   = "${var.elb_external_certname}"
  statuses = ["ISSUED"]
}

resource "aws_elb" "docker-frontend_elb_internal" {
  name            = "${var.stackname}-docker-frontend-internal"
  subnets         = ["${data.terraform_remote_state.infra_networking.private_subnet_ids}"]
  security_groups = ["${data.terraform_remote_state.infra_security_groups.sg_docker-frontend_elb_internal_id}"]
  internal        = "true"

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 443
    lb_protocol       = "https"

    ssl_certificate_id = "${data.aws_acm_certificate.elb_internal_cert.arn}"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3

    target   = "TCP:80"
    interval = 30
  }

  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags = "${map("Name", "${var.stackname}-docker-frontend-internal", "Project", var.stackname, "aws_environment", var.aws_environment, "aws_migration", "docker_frontend")}"
}

resource "aws_route53_record" "service_record" {
  zone_id = "${data.terraform_remote_state.infra_stack_dns_zones.internal_zone_id}"
  name    = "docker-frontend.${data.terraform_remote_state.infra_stack_dns_zones.internal_domain_name}"
  type    = "A"

  alias {
    name                   = "${aws_elb.docker-frontend_elb_internal.dns_name}"
    zone_id                = "${aws_elb.docker-frontend_elb_internal.zone_id}"
    evaluate_target_health = true
  }
}

resource "aws_elb" "docker-frontend_elb_external" {
  name            = "${var.stackname}-docker-frontend-external"
  subnets         = ["${data.terraform_remote_state.infra_networking.public_subnet_ids}"]
  security_groups = ["${data.terraform_remote_state.infra_security_groups.sg_docker-frontend_elb_external_id}"]
  internal        = "false"

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 443
    lb_protocol       = "https"

    ssl_certificate_id = "${data.aws_acm_certificate.elb_external_cert.arn}"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3

    target   = "TCP:80"
    interval = 30
  }

  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags = "${map("Name", "${var.stackname}-docker-frontend-external", "Project", var.stackname, "aws_environment", var.aws_environment, "aws_migration", "docker_frontend")}"
}

resource "aws_route53_record" "portainer_record" {
  zone_id = "${data.terraform_remote_state.infra_stack_dns_zones.external_zone_id}"
  name    = "portainer.${data.terraform_remote_state.infra_stack_dns_zones.external_domain_name}"
  type    = "A"

  alias {
    name                   = "${aws_elb.docker-frontend_elb_external.dns_name}"
    zone_id                = "${aws_elb.docker-frontend_elb_external.zone_id}"
    evaluate_target_health = true
  }
}

module "docker-worker-frontend" {
  source                        = "../../modules/aws/node_group"
  name                          = "${var.stackname}-docker-worker-frontend"
  vpc_id                        = "${data.terraform_remote_state.infra_vpc.vpc_id}"
  default_tags                  = "${map("Project", var.stackname, "aws_stackname", var.stackname, "aws_environment", var.aws_environment, "aws_migration", "docker_worker_frontend", "aws_hostname", "docker-worker-frontend-1")}"
  instance_subnet_ids           = "${data.terraform_remote_state.infra_networking.private_subnet_ids}"
  instance_security_group_ids   = ["${data.terraform_remote_state.infra_security_groups.sg_docker-frontend_id}", "${data.terraform_remote_state.infra_security_groups.sg_management_id}"]
  instance_type                 = "t2.medium"
  create_instance_key           = true
  instance_key_name             = "${var.stackname}-docker-worker-frontend"
  instance_public_key           = "${var.ssh_public_key}"
  instance_additional_user_data = "${join("\n", null_resource.user_data.*.triggers.snippet)}"
  instance_elb_ids              = ["${aws_elb.docker-frontend_elb_internal.id}", "${aws_elb.docker-frontend_elb_external.id}"]
  instance_ami_filter_name      = "${var.instance_ami_filter_name}"
  asg_max_size                  = "2"
  asg_min_size                  = "2"
  asg_desired_capacity          = "2"
  root_block_device_volume_size = "30"
}

# Instance 1
resource "aws_network_interface" "docker-manager-frontend-1_eni" {
  subnet_id       = "${lookup(data.terraform_remote_state.infra_networking.private_subnet_reserved_ips_names_ids_map, var.docker_manager_frontend_1_reserved_ips_subnet)}"
  private_ips     = ["${var.docker_manager_frontend_1_ip}"]
  security_groups = ["${data.terraform_remote_state.infra_security_groups.sg_docker-frontend_id}"]

  tags {
    Name            = "${var.stackname}-docker-manager-frontend-1"
    Project         = "${var.stackname}"
    aws_hostname    = "docker-manager-frontend-1"
    aws_migration   = "docker_manager_frontend"
    aws_stackname   = "${var.stackname}"
    aws_environment = "${var.aws_environment}"
  }
}

module "docker-manager-frontend-1" {
  source                        = "../../modules/aws/node_group"
  name                          = "${var.stackname}-docker-manager-frontend-1"
  vpc_id                        = "${data.terraform_remote_state.infra_vpc.vpc_id}"
  default_tags                  = "${map("Project", var.stackname, "aws_stackname", var.stackname, "aws_environment", var.aws_environment, "aws_migration", "docker_manager_frontend", "aws_hostname", "docker-manager-frontend-1")}"
  instance_subnet_ids           = "${data.terraform_remote_state.infra_networking.private_subnet_ids}"
  instance_security_group_ids   = ["${data.terraform_remote_state.infra_security_groups.sg_docker-frontend_id}", "${data.terraform_remote_state.infra_security_groups.sg_management_id}"]
  instance_type                 = "t2.medium"
  create_instance_key           = true
  instance_key_name             = "${var.stackname}-docker-manager-frontend-1"
  instance_public_key           = "${var.ssh_public_key}"
  instance_additional_user_data = "${join("\n", null_resource.user_data.*.triggers.snippet)}"
  instance_elb_ids              = ["${aws_elb.docker-frontend_elb_internal.id}", "${aws_elb.docker-frontend_elb_external.id}"]
  instance_ami_filter_name      = "${var.instance_ami_filter_name}"
  asg_max_size                  = "1"
  asg_min_size                  = "1"
  asg_desired_capacity          = "1"
  root_block_device_volume_size = "30"
}

# Instance 2
resource "aws_network_interface" "docker-manager-frontend-2_eni" {
  subnet_id       = "${lookup(data.terraform_remote_state.infra_networking.private_subnet_reserved_ips_names_ids_map, var.docker_manager_frontend_2_reserved_ips_subnet)}"
  private_ips     = ["${var.docker_manager_frontend_2_ip}"]
  security_groups = ["${data.terraform_remote_state.infra_security_groups.sg_docker-frontend_id}"]

  tags {
    Name            = "${var.stackname}-docker-manager-frontend-2"
    Project         = "${var.stackname}"
    aws_hostname    = "docker-manager-frontend-2"
    aws_migration   = "docker_manager_frontend"
    aws_stackname   = "${var.stackname}"
    aws_environment = "${var.aws_environment}"
  }
}

module "docker-manager-frontend-2" {
  source                        = "../../modules/aws/node_group"
  name                          = "${var.stackname}-docker-manager-frontend-2"
  vpc_id                        = "${data.terraform_remote_state.infra_vpc.vpc_id}"
  default_tags                  = "${map("Project", var.stackname, "aws_stackname", var.stackname, "aws_environment", var.aws_environment, "aws_migration", "docker_manager_frontend", "aws_hostname", "docker-manager-frontend-2")}"
  instance_subnet_ids           = "${data.terraform_remote_state.infra_networking.private_subnet_ids}"
  instance_security_group_ids   = ["${data.terraform_remote_state.infra_security_groups.sg_docker-frontend_id}", "${data.terraform_remote_state.infra_security_groups.sg_management_id}"]
  instance_type                 = "t2.medium"
  create_instance_key           = true
  instance_key_name             = "${var.stackname}-docker-manager-frontend-2"
  instance_public_key           = "${var.ssh_public_key}"
  instance_additional_user_data = "${join("\n", null_resource.user_data.*.triggers.snippet)}"
  instance_elb_ids              = ["${aws_elb.docker-frontend_elb_internal.id}", "${aws_elb.docker-frontend_elb_external.id}"]
  instance_ami_filter_name      = "${var.instance_ami_filter_name}"
  asg_max_size                  = "1"
  asg_min_size                  = "1"
  asg_desired_capacity          = "1"
  root_block_device_volume_size = "30"
}

# Instance 3
resource "aws_network_interface" "docker-manager-frontend-3_eni" {
  subnet_id       = "${lookup(data.terraform_remote_state.infra_networking.private_subnet_reserved_ips_names_ids_map, var.docker_manager_frontend_3_reserved_ips_subnet)}"
  private_ips     = ["${var.docker_manager_frontend_3_ip}"]
  security_groups = ["${data.terraform_remote_state.infra_security_groups.sg_docker-frontend_id}"]

  tags {
    Name            = "${var.stackname}-docker-manager-frontend-3"
    Project         = "${var.stackname}"
    aws_hostname    = "docker-manager-frontend-3"
    aws_migration   = "docker_manager_frontend"
    aws_stackname   = "${var.stackname}"
    aws_environment = "${var.aws_environment}"
  }
}

module "docker-manager-frontend-3" {
  source                        = "../../modules/aws/node_group"
  name                          = "${var.stackname}-docker-manager-frontend-3"
  vpc_id                        = "${data.terraform_remote_state.infra_vpc.vpc_id}"
  default_tags                  = "${map("Project", var.stackname, "aws_stackname", var.stackname, "aws_environment", var.aws_environment, "aws_migration", "docker_manager_frontend", "aws_hostname", "docker-manager-frontend-3")}"
  instance_subnet_ids           = "${data.terraform_remote_state.infra_networking.private_subnet_ids}"
  instance_security_group_ids   = ["${data.terraform_remote_state.infra_security_groups.sg_docker-frontend_id}", "${data.terraform_remote_state.infra_security_groups.sg_management_id}"]
  instance_type                 = "t2.medium"
  create_instance_key           = true
  instance_key_name             = "${var.stackname}-docker-manager-frontend-3"
  instance_public_key           = "${var.ssh_public_key}"
  instance_additional_user_data = "${join("\n", null_resource.user_data.*.triggers.snippet)}"
  instance_elb_ids              = ["${aws_elb.docker-frontend_elb_internal.id}", "${aws_elb.docker-frontend_elb_external.id}"]
  instance_ami_filter_name      = "${var.instance_ami_filter_name}"
  asg_max_size                  = "1"
  asg_min_size                  = "1"
  asg_desired_capacity          = "1"
  root_block_device_volume_size = "30"
}

resource "aws_iam_policy" "docker-manager-frontend_iam_policy" {
  name   = "${var.stackname}-docker-manager-frontend-additional"
  path   = "/"
  policy = "${file("${path.module}/additional_policy.json")}"
}

resource "aws_iam_role_policy_attachment" "docker-manager-frontend-1_iam_role_policy_attachment" {
  role       = "${module.docker-manager-frontend-1.instance_iam_role_name}"
  policy_arn = "${aws_iam_policy.docker-manager-frontend_iam_policy.arn}"
}

resource "aws_iam_role_policy_attachment" "docker-manager-frontend-2_iam_role_policy_attachment" {
  role       = "${module.docker-manager-frontend-2.instance_iam_role_name}"
  policy_arn = "${aws_iam_policy.docker-manager-frontend_iam_policy.arn}"
}

resource "aws_iam_role_policy_attachment" "docker-manager-frontend-3_iam_role_policy_attachment" {
  role       = "${module.docker-manager-frontend-3.instance_iam_role_name}"
  policy_arn = "${aws_iam_policy.docker-manager-frontend_iam_policy.arn}"
}

# Outputs
# --------------------------------------------------------------

output "docker-frontend_elb_internal_dns_name" {
  value       = "${aws_elb.docker-frontend_elb_internal.dns_name}"
  description = "DNS name to access the docker-frontend service"
}

output "docker-frontend_elb_external_dns_name" {
  value       = "${aws_elb.docker-frontend_elb_external.dns_name}"
  description = "DNS name to access the docker-frontend service"
}

output "service_dns_name" {
  value       = "${aws_route53_record.service_record.name}"
  description = "DNS name to access the node service"
}
