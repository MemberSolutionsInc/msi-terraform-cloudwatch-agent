locals {
  linux_metrics_collected = {
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
      # Without this, disk_used_percent also carries a "device" dimension
      # (e.g. /dev/xvda1) alongside "path" — since that value isn't knowable
      # ahead of time from Terraform, alarms keyed only on {InstanceId, path}
      # wouldn't match the metric at all.
      drop_device = true
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

  # Windows CloudWatch Agent uses performance-counter object/counter names,
  # not the Linux plugin schema above. PhysicalDisk "% Disk Time" is the
  # Windows equivalent of Linux diskio_io_time (disk I/O wait); "Network
  # Interface" error counters back the org standard's "CWAgent interface
  # counters" requirement for Network Errors on top of the native
  # NetworkPacketsIn/Out metrics.
  windows_metrics_collected = {
    Memory = {
      measurement = [
        "% Committed Bytes In Use",
      ]
    }
    LogicalDisk = {
      measurement = [
        "% Free Space",
      ]
      resources = var.windows_disk_resources
    }
    PhysicalDisk = {
      measurement = [
        "% Disk Time",
      ]
      # "_Total" is the well-known Windows Perfmon aggregate instance across
      # all physical disks — deliberately NOT var.windows_disk_resources
      # (drive letters). CloudWatch alarms can't use SEARCH() to match an
      # unknown per-disk instance name, so collecting only the aggregate
      # gives alarms a single, predictable dimension value to alarm on.
      resources = ["_Total"]
    }
    "Network Interface" = {
      measurement = [
        "Packets Received Errors",
        "Packets Outbound Errors",
      ]
      resources = ["*"]
    }
  }

  # jsonencode() each OS's full config to a string *before* branching on
  # os_type — the linux/windows metrics_collected objects have different
  # attributes, and a ternary that returns one or the other directly fails
  # Terraform's static type unification ("Inconsistent conditional result
  # types"). Strings unify fine.
  agent_config_base = {
    # Without this, CWAgent writes these metrics with no per-instance
    # dimension at all — every instance sharing a config would report into
    # the same undimensioned series, making per-instance alarming
    # impossible. ${aws:InstanceId} is a CWAgent-native placeholder
    # resolved from IMDS at agent startup.
    append_dimensions = {
      InstanceId = "$${aws:InstanceId}"
    }
    metrics_collection_interval = var.metrics_collection_interval
  }

  linux_config_json = jsonencode({
    metrics = merge(local.agent_config_base, {
      metrics_collected = local.linux_metrics_collected
    })
  })

  windows_config_json = jsonencode({
    metrics = merge(local.agent_config_base, {
      metrics_collected = local.windows_metrics_collected
    })
  })

  cloudwatch_agent_config_json = var.os_type == "windows" ? local.windows_config_json : local.linux_config_json

  # SSM String parameters are capped at 4KB; fall back to Advanced tier for
  # larger configs (e.g. many mount_paths/windows_disk_resources entries).
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

  description = "CloudWatch Agent configuration (${var.os_type}) managed by msi-terraform-cloudwatch-agent"

  tags = var.tags
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
  count = var.manage_iam_policies ? 1 : 0

  role       = var.instance_iam_role_name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"

  lifecycle {
    precondition {
      condition     = trimspace(var.instance_iam_role_name) != ""
      error_message = "instance_iam_role_name is required when manage_iam_policies = true."
    }
  }
}

resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  count = var.manage_iam_policies ? 1 : 0

  role       = var.instance_iam_role_name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
