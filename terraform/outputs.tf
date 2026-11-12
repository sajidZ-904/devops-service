output "instance_id" {
  value = aws_instance.app.id
}

output "instance_private_ip" {
  value = aws_instance.app.private_ip
}

output "log_group" {
  value = aws_cloudwatch_log_group.app.name
}
