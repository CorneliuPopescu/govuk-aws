# == Manifest: projects::app-api-lb
#
# Frontend application servers
#
# === Variables:
#
# aws_region
# stackname
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

variable "ssh_public_key" {
  type        = "string"
  description = "Default public key material"
}

# Resources
# --------------------------------------------------------------
terraform {
  backend          "s3"             {}
  required_version = "= 0.9.10"
}

provider "aws" {
  region = "${var.aws_region}"
}

resource "aws_elb" "api-lb_elb" {
  name            = "${var.stackname}-api-lb"
  subnets         = ["${data.terraform_remote_state.infra_networking.private_subnet_ids}"]
  security_groups = ["${data.terraform_remote_state.infra_security_groups.sg_api-lb_elb_id}"]
  internal        = "true"

  listener {
    instance_port     = 443
    instance_protocol = "tcp"
    lb_port           = 443
    lb_protocol       = "tcp"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3

    target   = "TCP:443"
    interval = 30
  }

  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags = "${map("Name", "${var.stackname}-api-lb", "Project", var.stackname, "aws_migration", "api_lb")}"
}

resource "aws_route53_record" "api-lb_service_record" {
  zone_id = "${data.terraform_remote_state.infra_stack_dns_zones.internal_zone_id}"
  name    = "api-lb.${data.terraform_remote_state.infra_stack_dns_zones.internal_domain_name}"
  type    = "A"

  alias {
    name                   = "${aws_elb.api-lb_elb.dns_name}"
    zone_id                = "${aws_elb.api-lb_elb.zone_id}"
    evaluate_target_health = true
  }
}

module "api-lb" {
  source                               = "../../modules/aws/node_group"
  name                                 = "${var.stackname}-api-lb"
  vpc_id                               = "${data.terraform_remote_state.infra_vpc.vpc_id}"
  default_tags                         = "${map("Project", var.stackname, "aws_stackname", var.stackname, "aws_migration", "api_lb", "aws_hostname", "api-lb-1")}"
  instance_subnet_ids                  = "${data.terraform_remote_state.infra_networking.private_subnet_ids}"
  instance_security_group_ids          = ["${data.terraform_remote_state.infra_security_groups.sg_api-lb_id}", "${data.terraform_remote_state.infra_security_groups.sg_management_id}"]
  instance_type                        = "t2.medium"
  create_instance_key                  = true
  instance_key_name                    = "${var.stackname}-api-lb"
  instance_public_key                  = "${var.ssh_public_key}"
  instance_additional_user_data_script = "${file("${path.module}/additional_user_data.txt")}"
  instance_elb_ids                     = ["${aws_elb.api-lb_elb.id}"]
  asg_max_size                         = "2"
  asg_min_size                         = "2"
  asg_desired_capacity                 = "2"
}

# Outputs
# --------------------------------------------------------------

output "api-lb_elb_dns_name" {
  value       = "${aws_elb.api-lb_elb.dns_name}"
  description = "DNS name to access the api-lb service"
}

output "service_dns_name" {
  value       = "${aws_route53_record.api-lb_service_record.fqdn}"
  description = "DNS name to access the service"
}