output "ssm_parameter_name" {
  description = "Name of the SSM parameter holding the CloudWatch Agent configuration."
  value       = aws_ssm_parameter.cloudwatch_agent_config.name
}

output "ssm_parameter_arn" {
  description = "ARN of the SSM parameter holding the CloudWatch Agent configuration."
  value       = aws_ssm_parameter.cloudwatch_agent_config.arn
}

output "ssm_association_id" {
  description = "ID of the SSM association that deploys and configures the CloudWatch Agent."
  value       = aws_ssm_association.cloudwatch_agent.association_id
}
