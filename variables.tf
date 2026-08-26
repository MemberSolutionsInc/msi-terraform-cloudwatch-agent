variable "os_type" {
  description = <<-EOT
    Operating system of the targeted instances. Selects which CloudWatch Agent
    metrics_collected schema is generated — Linux and Windows use entirely
    different plugin/counter names, so a single instance group in one
    invocation must be all one OS.
  EOT
  type        = string
  default     = "linux"

  validation {
    condition     = contains(["linux", "windows"], var.os_type)
    error_message = "os_type must be \"linux\" or \"windows\"."
  }
}

variable "mount_paths" {
  description = "Linux only. List of filesystem mount paths to monitor for disk_used_percent metrics."
  type        = list(string)
  default     = ["/"]
}

variable "windows_disk_resources" {
  description = "Windows only. List of LogicalDisk/PhysicalDisk instances to monitor (drive letters, e.g. [\"C:\", \"D:\"], or [\"*\"] for all)."
  type        = list(string)
  default     = ["*"]
}

variable "metrics_collection_interval" {
  description = "Interval, in seconds, at which the CloudWatch Agent collects metrics."
  type        = number
  default     = 60
}

variable "target_instance_ids" {
  description = "Explicit list of EC2 instance IDs to target with the SSM association. Takes precedence over target_tag_key/target_tag_value when non-empty."
  type        = list(string)
  default     = []
}

variable "target_tag_key" {
  description = "Tag key used to target instances when target_instance_ids is empty. Used together with target_tag_value."
  type        = string
  default     = ""
}

variable "target_tag_value" {
  description = "Tag value used to target instances when target_instance_ids is empty. Used together with target_tag_key."
  type        = string
  default     = ""
}

variable "manage_iam_policies" {
  description = <<-EOT
    Whether this invocation attaches CloudWatchAgentServerPolicy and
    AmazonSSMManagedInstanceCore to instance_iam_role_name.

    Set to false when targeting instances that share an IAM role with other
    instances already covered by a different invocation of this module (or
    where the role already has these policies attached some other way) — an
    IAM role's policy attachments can only be safely owned by one Terraform
    state at a time. Per-instance invocations against a shared role should
    set this false and rely on a single account/fleet-level invocation (or
    pre-existing attachment) to have granted the role access.
  EOT
  type        = bool
  default     = true
}

variable "instance_iam_role_name" {
  description = "Name of the existing IAM role attached to the target EC2 instances. Required when manage_iam_policies = true; ignored otherwise."
  type        = string
  default     = ""
}

variable "association_name" {
  description = "Name given to the SSM association that deploys and configures the CloudWatch Agent."
  type        = string
  default     = "msi-cloudwatch-agent-config"
}
