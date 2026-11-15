resource "aws_ecr_repository" "app" {
  name                 = var.project
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true # lets `terraform destroy` clean up in a lab

  image_scanning_configuration {
    scan_on_push = true # second opinion next to Trivy
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.main.arn
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the last 15 images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 15 }
      action       = { type = "expire" }
    }]
  })
}
