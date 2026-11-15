output "jenkins_url" {
  value = "http://${aws_eip.node["jenkins"].public_ip}:8080"
}

output "sonarqube_url" {
  value = "http://${aws_eip.node["jenkins"].public_ip}:9000"
}

output "app_url" {
  value = "http://${aws_eip.node["k8s"].public_ip}:30080"
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "reports_bucket" {
  value = aws_s3_bucket.reports.bucket
}

output "cloudwatch_dashboard" {
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards/dashboard/${var.project}"
}

output "ssh_jenkins" {
  value = "ssh -i ~/.ssh/shipguard ubuntu@${aws_eip.node["jenkins"].public_ip}"
}

output "ssh_k8s" {
  value = "ssh -i ~/.ssh/shipguard ubuntu@${aws_eip.node["k8s"].public_ip}"
}

# Writes the Ansible inventory so you never copy IPs by hand.
resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/../ansible/inventory/hosts.ini"
  file_permission = "0644"
  content = templatefile("${path.module}/templates/inventory.tpl", {
    jenkins_ip         = aws_eip.node["jenkins"].public_ip
    jenkins_private_ip = aws_instance.node["jenkins"].private_ip
    k8s_ip             = aws_eip.node["k8s"].public_ip
    k8s_private_ip     = aws_instance.node["k8s"].private_ip
    aws_region         = var.aws_region
    ecr_repository_url = aws_ecr_repository.app.repository_url
    ecr_registry       = split("/", aws_ecr_repository.app.repository_url)[0]
    reports_bucket     = aws_s3_bucket.reports.bucket
    project            = var.project
  })
}
