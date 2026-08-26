locals {
  # metrics_collection_interval is set per-category below, not as a
  # top-level default under "metrics" — confirmed live against a real
  # (older, v1.0) CloudWatch Agent: "Additional property
  # metrics_collection_interval is not allowed" under path /metrics. Setting
  # it per-category is the form supported across agent versions.
  linux_metrics_collected = {
    mem = {
      measurement = [
        "mem_used_percent",
      ]
      metrics_collection_interval = var.metrics_collection_interval
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
      drop_device                 = true
      metrics_collection_interval = var.metrics_collection_interval
    }
    diskio = {
      measurement = [
        "diskio_io_time",
        "diskio_read_bytes",
        "diskio_write_bytes",
        "diskio_reads",
        "diskio_writes",
      ]
      metrics_collection_interval = var.metrics_collection_interval
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
      metrics_collection_interval = var.metrics_collection_interval
    }
    LogicalDisk = {
      measurement = [
        "% Free Space",
      ]
      resources                   = var.windows_disk_resources
      metrics_collection_interval = var.metrics_collection_interval
    }
    PhysicalDisk = {
      measurement = [
        "% Disk Time",
      ]
      # Deliberately "*" (all instances), not just ["_Total"] — confirmed
      # live that requesting only "_Total" as a single named resource made
      # CWAgent publish it for ~5-6 minutes after startup then silently stop
      # (no error logged; the underlying Windows Perfmon counter kept
      # working fine when queried directly via Get-Counter, so this is a
      # CWAgent collection quirk, not an OS-level problem). Network
      # Interface, which already used "*", published continuously the whole
      # time. windows_disk_resources isn't used here since alarms still key
      # off "_Total" specifically (a plain per-drive instance name like
      # "0 C:" isn't predictable from Terraform).
      resources                   = ["*"]
      metrics_collection_interval = var.metrics_collection_interval
    }
    "Network Interface" = {
      measurement = [
        "Packets Received Errors",
        "Packets Outbound Errors",
      ]
      resources                   = ["*"]
      metrics_collection_interval = var.metrics_collection_interval
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
