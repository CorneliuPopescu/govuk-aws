/**
* ## Project: app-publishing-api-db-admin
*
* DB admin boxes for publishing-api's RDS instance
*/
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

variable "remote_state_infra_database_backups_bucket_key_stack" {
  type        = "string"
  description = "Override stackname path to infra_database_backups_bucket remote state"
  default     = ""
}

# Resources
# --------------------------------------------------------------
terraform {
  backend          "s3"             {}
  required_version = "= 0.11.7"
}

provider "aws" {
  region  = "${var.aws_region}"
  version = "1.40.0"
}

resource "aws_elb" "publishing-api-db-admin_elb" {
  name            = "${var.stackname}-publishing-api-db-admin"
  subnets         = ["${data.terraform_remote_state.infra_networking.private_subnet_ids}"]
  security_groups = ["${data.terraform_remote_state.infra_security_groups.sg_publishing-api-db-admin_elb_id}"]
  internal        = "true"

  access_logs {
    bucket        = "${data.terraform_remote_state.infra_monitoring.aws_logging_bucket_id}"
    bucket_prefix = "elb/${var.stackname}-publishing-api-db-admin-internal-elb"
    interval      = 60
  }

  listener {
    instance_port     = 22
    instance_protocol = "tcp"
    lb_port           = 22
    lb_protocol       = "tcp"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3

    target   = "TCP:22"
    interval = 30
  }

  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags = "${map("Name", "${var.stackname}-publishing-api-db-admin", "Project", var.stackname, "aws_environment", var.aws_environment, "aws_migration", "publishing_api_db_admin")}"
}

module "publishing-api-db-admin" {
  source                        = "../../modules/aws/node_group"
  name                          = "${var.stackname}-publishing-api-db-admin"
  vpc_id                        = "${data.terraform_remote_state.infra_vpc.vpc_id}"
  default_tags                  = "${map("Project", var.stackname, "aws_stackname", var.stackname, "aws_environment", var.aws_environment, "aws_migration", "publishing_api_db_admin", "aws_hostname", "publishing-api-db-admin-1")}"
  instance_subnet_ids           = "${data.terraform_remote_state.infra_networking.private_subnet_ids}"
  instance_security_group_ids   = ["${data.terraform_remote_state.infra_security_groups.sg_publishing-api-db-admin_id}", "${data.terraform_remote_state.infra_security_groups.sg_management_id}"]
  instance_type                 = "t3.medium"
  instance_additional_user_data = "${join("\n", null_resource.user_data.*.triggers.snippet)}"
  instance_elb_ids_length       = "1"
  instance_elb_ids              = ["${aws_elb.publishing-api-db-admin_elb.id}"]
  asg_max_size                  = "1"
  asg_min_size                  = "1"
  asg_desired_capacity          = "1"
  asg_notification_topic_arn    = "${data.terraform_remote_state.infra_monitoring.sns_topic_autoscaling_group_events_arn}"
  root_block_device_volume_size = "64"
}

resource "aws_route53_record" "publishing-api_db_admin_service_record" {
  zone_id = "${data.terraform_remote_state.infra_stack_dns_zones.internal_zone_id}"
  name    = "publishing-api-db-admin.${data.terraform_remote_state.infra_stack_dns_zones.internal_domain_name}"
  type    = "A"

  alias {
    name                   = "${aws_elb.publishing-api-db-admin_elb.dns_name}"
    zone_id                = "${aws_elb.publishing-api-db-admin_elb.zone_id}"
    evaluate_target_health = true
  }
}

module "alarms-autoscaling-publishing-api-db-admin" {
  source                            = "../../modules/aws/alarms/autoscaling"
  name_prefix                       = "${var.stackname}-publishing-api-db-admin"
  autoscaling_group_name            = "${module.publishing-api-db-admin.autoscaling_group_name}"
  alarm_actions                     = ["${data.terraform_remote_state.infra_monitoring.sns_topic_cloudwatch_alarms_arn}"]
  groupinserviceinstances_threshold = "1"
}

module "alarms-ec2-publishing-api-db-admin" {
  source                   = "../../modules/aws/alarms/ec2"
  name_prefix              = "${var.stackname}-publishing-api-db-admin"
  autoscaling_group_name   = "${module.publishing-api-db-admin.autoscaling_group_name}"
  alarm_actions            = ["${data.terraform_remote_state.infra_monitoring.sns_topic_cloudwatch_alarms_arn}"]
  cpuutilization_threshold = "85"
}

data "terraform_remote_state" "infra_database_backups_bucket" {
  backend = "s3"

  config {
    bucket = "${var.remote_state_bucket}"
    key    = "${coalesce(var.remote_state_infra_database_backups_bucket_key_stack, var.stackname)}/infra-database-backups-bucket.tfstate"
    region = "eu-west-1"
  }
}

resource "aws_iam_role_policy_attachment" "write_publishing-api-db-admin_database_backups_iam_role_policy_attachment" {
  count      = 1
  role       = "${module.publishing-api-db-admin.instance_iam_role_name}"
  policy_arn = "${data.terraform_remote_state.infra_database_backups_bucket.publishing-api_dbadmin_write_database_backups_bucket_policy_arn}"
}

resource "aws_iam_role_policy_attachment" "integration_read_publishing-api-db-admin_database_backups_iam_role_policy_attachment" {
  count      = "${var.aws_environment == "integration" ? 1 : 0}"
  role       = "${module.publishing-api-db-admin.instance_iam_role_name}"
  policy_arn = "${data.terraform_remote_state.infra_database_backups_bucket.integration_publishing-api_dbadmin_read_database_backups_bucket_policy_arn}"
}

resource "aws_iam_role_policy_attachment" "staging_read_publishing-api-db-admin_database_backups_iam_role_policy_attachment" {
  count      = "${var.aws_environment == "staging" ? 1 : 0}"
  role       = "${module.publishing-api-db-admin.instance_iam_role_name}"
  policy_arn = "${data.terraform_remote_state.infra_database_backups_bucket.staging_publishing-api_dbadmin_read_database_backups_bucket_policy_arn}"
}

# Outputs
# --------------------------------------------------------------

output "publishing-api-db-admin_elb_dns_name" {
  value       = "${aws_elb.publishing-api-db-admin_elb.dns_name}"
  description = "DNS name to access the publishing-api-db-admin service"
}
