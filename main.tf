locals {
  cloudwatch_agent_config = {
    metrics = {
      metrics_collection_interval = var.metrics_collection_interval
      metrics_collected = {
        mem = {
          measurement = [
            "mem_used_percent",
          ]
        }
        disk = {
          measurement = [
            "disk_used_percent",
          ]
          resources = var.mount_paths
        }
        diskio = {
          measurement = [
            "diskio_io_time",
            "diskio_read_bytes",
            "diskio_write_bytes",
            "diskio_reads",
            "diskio_writes",
          ]
        }
      }
    }
  }

  cloudwatch_agent_config_json = jsonencode(local.cloudwatch_agent_config)

  # SSM String parameters are capped at 4KB; fall back to Advanced tier for
  # larger configs (e.g. many mount_paths entries).
  ssm_parameter_tier = length(local.cloudwatch_agent_config_json) > 4096 ? "Advanced" : "Standard"

  # Target by explicit instance IDs when provided, otherwise fall back to
  # tag key/value targeting.
  use_instance_ids = length(var.target_instance_ids) > 0

  targets = local.use_instance_ids ? [
    {
      key    = "InstanceIds"
      values = var.target_instance_ids
    }
    ] : [
    {
      key    = "tag:${var.target_tag_key}"
      values = [var.target_tag_value]
    }
  ]
}

resource "aws_ssm_parameter" "cloudwatch_agent_config" {
  name  = "/msi/cloudwatch-agent/${var.association_name}/config"
  type  = "String"
  tier  = local.ssm_parameter_tier
  value = local.cloudwatch_agent_config_json

  description = "CloudWatch Agent configuration (mem_used_percent, disk_used_percent, diskio_*) managed by msi-terraform-cloudwatch-agent"
}

resource "aws_ssm_association" "cloudwatch_agent" {
  name             = "AmazonCloudWatch-ManageAgent"
  association_name = var.association_name

  parameters = {
    action                        = "configure"
    mode                          = "ec2"
    optionalConfigurationSource   = "ssm"
    optionalConfigurationLocation = aws_ssm_parameter.cloudwatch_agent_config.name
    optionalRestart               = "yes"
  }

  dynamic "targets" {
    for_each = local.targets
    content {
      key    = targets.value.key
      values = targets.value.values
    }
  }
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent_server_policy" {
  role       = var.instance_iam_role_name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = var.instance_iam_role_name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
