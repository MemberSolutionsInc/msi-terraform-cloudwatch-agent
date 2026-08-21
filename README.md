# msi-terraform-cloudwatch-agent

CloudWatch Agent deployment module for EC2 — enables memory and disk metrics
that aren't emitted by default.

## Purpose

AWS does not natively emit EC2 memory utilization (`mem_used_percent`) or
disk usage/IO metrics (`disk_used_percent`, `diskio_io_time`, and related
`diskio_*` fields). Per the org's monitoring standard, any EC2 instance that
needs memory or disk alert thresholds enforced must have the CloudWatch
Agent installed and configured.

This module deploys that configuration to a target set of EC2 instances via
SSM:

- Writes the CloudWatch Agent JSON config to an `aws_ssm_parameter`.
- Creates an `aws_ssm_association` against the AWS-managed
  `AmazonCloudWatch-ManageAgent` document, which installs/configures the
  agent on the targeted instances and points it at that parameter.
- Attaches the `CloudWatchAgentServerPolicy` and
  `AmazonSSMManagedInstanceCore` managed policies to an existing IAM role.

This is a per-account, per-instance-fleet action item from the org's
monitoring standard rollout checklist: **every EC2 instance that needs
memory/disk thresholds enforced needs this module applied against it**,
account by account, as part of the CloudWatch observability rollout.

## Prerequisites

This module does **not** create EC2 instances or IAM roles. It assumes:

- The target instances already exist and are registered with SSM (i.e. the
  SSM Agent is running and the instance role has a trust relationship that
  allows the `ssm.amazonaws.com` service, or more commonly, the EC2 instance
  profile role trusts `ec2.amazonaws.com` and already has an SSM-capable
  managed instance core policy path available).
- You pass in the name of that existing IAM role via
  `instance_iam_role_name` — this module attaches the additional managed
  policies required for the CloudWatch Agent to function (and
  `AmazonSSMManagedInstanceCore`, in case it isn't already attached), it
  does not create the role or its trust policy.

## Usage

```hcl
module "cloudwatch_agent" {
  source = "git::https://github.com/MemberSolutionsInc/msi-terraform-cloudwatch-agent.git?ref=v0.1.0"

  instance_iam_role_name = "efit-lucee-prod-instance-role"

  target_tag_key   = "CloudWatchAgent"
  target_tag_value = "enabled"

  mount_paths                 = ["/", "/data"]
  metrics_collection_interval = 60

  association_name = "efitawsprod-cloudwatch-agent"
}
```

To target explicit instances instead of a tag, set `target_instance_ids`
(this takes precedence over `target_tag_key`/`target_tag_value` whenever it
is non-empty):

```hcl
module "cloudwatch_agent" {
  source = "git::https://github.com/MemberSolutionsInc/msi-terraform-cloudwatch-agent.git?ref=v0.1.0"

  instance_iam_role_name = "efit-lucee-prod-instance-role"
  target_instance_ids    = ["i-0123456789abcdef0", "i-0fedcba9876543210"]
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `mount_paths` | Disk paths to monitor for `disk_used_percent` metrics | `list(string)` | `["/"]` | no |
| `metrics_collection_interval` | Interval, in seconds, at which the CloudWatch Agent collects metrics | `number` | `60` | no |
| `target_instance_ids` | Explicit list of EC2 instance IDs to target. Takes precedence over the tag inputs when non-empty | `list(string)` | `[]` | no |
| `target_tag_key` | Tag key used to target instances when `target_instance_ids` is empty | `string` | `""` | no |
| `target_tag_value` | Tag value used to target instances when `target_instance_ids` is empty | `string` | `""` | no |
| `instance_iam_role_name` | Name of the existing IAM role attached to the target EC2 instances | `string` | n/a | yes |
| `association_name` | Name given to the SSM association that deploys and configures the CloudWatch Agent | `string` | `"msi-cloudwatch-agent-config"` | no |

## Outputs

| Name | Description |
|------|-------------|
| `ssm_parameter_name` | Name of the SSM parameter holding the CloudWatch Agent configuration |
| `ssm_parameter_arn` | ARN of the SSM parameter holding the CloudWatch Agent configuration |
| `ssm_association_id` | ID of the SSM association that deploys and configures the CloudWatch Agent |

## Requirements

| Name | Version |
|------|---------|
| terraform | ~> 1.0 |
| aws | ~> 5.0 |
