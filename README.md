# msi-terraform-cloudwatch-agent

CloudWatch Agent deployment module for EC2 — enables memory and disk metrics
that aren't emitted by default.

## Purpose

AWS does not natively emit EC2 memory or disk usage/IO metrics on either OS.
Per the org's monitoring standard, any EC2 instance that needs memory or disk
alert thresholds enforced must have the CloudWatch Agent installed and
configured. Linux and Windows use entirely different Agent config schemas
(plugin names vs. performance-counter object/counter names), so `os_type`
selects the right one — see Inputs below.

This module deploys that configuration to a target set of EC2 instances via
SSM:

- Writes the CloudWatch Agent JSON config to an `aws_ssm_parameter`.
- Creates an `aws_ssm_association` against the AWS-managed
  `AmazonCloudWatch-ManageAgent` document, which installs/configures the
  agent on the targeted instances and points it at that parameter.
- Optionally (`manage_iam_policies`, default `true`) attaches the
  `CloudWatchAgentServerPolicy` and `AmazonSSMManagedInstanceCore` managed
  policies to an existing IAM role.

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
- When `manage_iam_policies = true` (the default), you pass in the name of
  that existing IAM role via `instance_iam_role_name` — this module attaches
  the additional managed policies required for the CloudWatch Agent to
  function, it does not create the role or its trust policy.

### Shared IAM roles — set `manage_iam_policies = false`

An IAM role's policy attachments can only be safely owned by **one**
Terraform state. If multiple instances (and therefore multiple invocations
of this module, e.g. one per per-instance monitoring ticket) share the same
IAM role, only the *first* invocation against that role should set
`manage_iam_policies = true` (or a single account/fleet-level invocation
should own it). Every other invocation targeting instances on that same
role — or targeting an instance whose role already has these policies
attached some other way — must set `manage_iam_policies = false` and omit
`instance_iam_role_name`. Getting this wrong means two states fight over the
same attachment, and destroying either one detaches the policy for every
instance on the shared role.

## Usage

### Linux

```hcl
module "cloudwatch_agent" {
  source = "git::https://github.com/MemberSolutionsInc/msi-terraform-cloudwatch-agent.git?ref=v0.2.0"

  os_type                 = "linux"
  instance_iam_role_name  = "efit-lucee-prod-instance-role"

  target_tag_key   = "CloudWatchAgent"
  target_tag_value = "enabled"

  mount_paths                 = ["/", "/data"]
  metrics_collection_interval = 60

  association_name = "efitawsprod-cloudwatch-agent"
}
```

### Windows

```hcl
module "cloudwatch_agent" {
  source = "git::https://github.com/MemberSolutionsInc/msi-terraform-cloudwatch-agent.git?ref=v0.2.0"

  os_type = "windows"

  # This instance's role already has the required policies attached
  # (managed by another invocation, or attached outside Terraform).
  manage_iam_policies = false

  target_instance_ids    = ["i-0fad170ef80facf91"]
  windows_disk_resources  = ["*"]

  association_name = "app3-prod-d-cloudwatch-agent"
}
```

To target explicit instances instead of a tag, set `target_instance_ids`
(this takes precedence over `target_tag_key`/`target_tag_value` whenever it
is non-empty).

### Why PhysicalDisk always collects `_Total`, not per-drive

CloudWatch metric alarms can't use the `SEARCH()` function (`ValidationError:
SEARCH is not supported on Metric Alarms` — confirmed live, not a doc
assumption), so an alarm on Windows `PhysicalDisk "% Disk Time"` needs a
dimension value known ahead of time. The physical-disk instance name
Windows assigns (e.g. `"0 C:"`) isn't predictable from Terraform the way a
drive letter is, but `"_Total"` — Perfmon's well-known aggregate instance
across all physical disks — is. This module always collects `_Total` for
PhysicalDisk regardless of `windows_disk_resources`, so
msi-terraform-cloudwatch-alarms' disk-I/O-wait alarm has a fixed dimension
to alarm on.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `os_type` | `"linux"` or `"windows"` — selects the Agent config schema | `string` | `"linux"` | no |
| `mount_paths` | Linux only. Disk paths to monitor for `disk_used_percent` metrics | `list(string)` | `["/"]` | no |
| `windows_disk_resources` | Windows only. LogicalDisk drive letters to monitor for `% Free Space` (e.g. `["C:"]`, or `["*"]` for all) — does **not** affect PhysicalDisk, which always collects the `_Total` aggregate (see below) | `list(string)` | `["*"]` | no |
| `metrics_collection_interval` | Interval, in seconds, at which the CloudWatch Agent collects metrics | `number` | `60` | no |
| `target_instance_ids` | Explicit list of EC2 instance IDs to target. Takes precedence over the tag inputs when non-empty | `list(string)` | `[]` | no |
| `target_tag_key` | Tag key used to target instances when `target_instance_ids` is empty | `string` | `""` | no |
| `target_tag_value` | Tag value used to target instances when `target_instance_ids` is empty | `string` | `""` | no |
| `manage_iam_policies` | Whether this invocation attaches the required managed policies to `instance_iam_role_name`. Set `false` for shared-role instances already covered elsewhere | `bool` | `true` | no |
| `instance_iam_role_name` | Name of the existing IAM role attached to the target EC2 instances. Required when `manage_iam_policies = true` | `string` | `""` | conditionally |
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
