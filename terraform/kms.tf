# One customer-managed key encrypts S3, ECR, CloudWatch Logs and SNS.
resource "aws_kms_key" "main" {
  description             = "${var.project} encryption key"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms.json
}

resource "aws_kms_alias" "main" {
  name          = "alias/${var.project}"
  target_key_id = aws_kms_key.main.key_id
}

data "aws_iam_policy_document" "kms" {
  #checkov:skip=CKV_AWS_109:Key policies must reference the key as "*"; access is limited to this account
  #checkov:skip=CKV_AWS_111:Key policies must reference the key as "*"; access is limited to this account
  #checkov:skip=CKV_AWS_356:Key policies must reference the key as "*"
  statement {
    sid       = "AccountRoot"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid       = "CloudWatchLogs"
    actions   = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logs.${var.aws_region}.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"]
    }
  }

  statement {
    sid       = "CloudWatchAlarmsToSNS"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
  }
}
