# In AWS Academy Learner Lab you cannot create IAM roles, so learner_lab = true
# skips everything in this file and uses the pre-made LabInstanceProfile instead.
locals {
  create_iam = !var.learner_lab
}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# ---------------- Jenkins role: push to ECR, write reports to S3 ----------------
resource "aws_iam_role" "jenkins" {
  count = local.create_iam ? 1 : 0

  name               = "${var.project}-jenkins"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

# Object ARNs need a wildcard suffix; access is scoped to the builds/ prefix of one bucket.
#tfsec:ignore:aws-iam-no-policy-wildcards
data "aws_iam_policy_document" "jenkins" {
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"] # AWS only supports "*" for this action
    resources = ["*"]
  }
  statement {
    sid = "EcrPushPull"
    actions = [
      "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:CompleteLayerUpload",
      "ecr:DescribeImages", "ecr:DescribeImageScanFindings", "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload", "ecr:PutImage", "ecr:UploadLayerPart",
    ]
    resources = [aws_ecr_repository.app.arn]
  }
  statement {
    sid       = "ReportsList"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.reports.arn]
  }
  statement {
    sid       = "ReportsWrite"
    actions   = ["s3:PutObject", "s3:GetObject"]
    resources = ["${aws_s3_bucket.reports.arn}/builds/*"]
  }
  statement {
    sid       = "UseKmsKey"
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.main.arn]
  }
}

resource "aws_iam_role_policy" "jenkins" {
  count = local.create_iam ? 1 : 0

  name   = "ci-permissions"
  role   = aws_iam_role.jenkins[0].id
  policy = data.aws_iam_policy_document.jenkins.json
}

resource "aws_iam_role_policy_attachment" "jenkins_cw" {
  count = local.create_iam ? 1 : 0

  role       = aws_iam_role.jenkins[0].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "jenkins_ssm" {
  count = local.create_iam ? 1 : 0

  role       = aws_iam_role.jenkins[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "jenkins" {
  count = local.create_iam ? 1 : 0

  name = "${var.project}-jenkins"
  role = aws_iam_role.jenkins[0].name
}

# ---------------- k8s node role: pull from ECR, ship logs ----------------
resource "aws_iam_role" "k8s" {
  count = local.create_iam ? 1 : 0

  name               = "${var.project}-k8s-node"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "k8s_ecr" {
  count = local.create_iam ? 1 : 0

  role       = aws_iam_role.k8s[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "k8s_cw" {
  count = local.create_iam ? 1 : 0

  role       = aws_iam_role.k8s[0].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "k8s_ssm" {
  count = local.create_iam ? 1 : 0

  role       = aws_iam_role.k8s[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "k8s_kms" {
  statement {
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.main.arn]
  }
}

resource "aws_iam_role_policy" "k8s_kms" {
  count = local.create_iam ? 1 : 0

  name   = "decrypt-ecr-images"
  role   = aws_iam_role.k8s[0].id
  policy = data.aws_iam_policy_document.k8s_kms.json
}

resource "aws_iam_instance_profile" "k8s" {
  count = local.create_iam ? 1 : 0

  name = "${var.project}-k8s-node"
  role = aws_iam_role.k8s[0].name
}
