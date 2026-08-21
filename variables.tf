variable "mount_paths" {
  description = "List of filesystem mount paths to monitor for disk_used_percent metrics."
  type        = list(string)
  default     = ["/"]
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

variable "instance_iam_role_name" {
  description = "Name of the existing IAM role attached to the target EC2 instances. This module attaches the managed policies required for the CloudWatch Agent to this role; it does not create the role."
  type        = string
}

variable "association_name" {
  description = "Name given to the SSM association that deploys and configures the CloudWatch Agent."
  type        = string
  default     = "msi-cloudwatch-agent-config"
}
