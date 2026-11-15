# Every build's security reports (SonarQube, Trivy, Checkov, tfsec, ZAP) land here.
resource "aws_s3_bucket" "reports" {
  #checkov:skip=CKV_AWS_18:Access logging adds a second bucket; not needed for a lab
  #checkov:skip=CKV_AWS_144:Cross-region replication not needed for build reports
  #checkov:skip=CKV2_AWS_62:No event notifications needed for build reports
  bucket        = "${var.project}-reports-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "reports" {
  bucket = aws_s3_bucket.reports.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.main.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "reports" {
  bucket                  = aws_s3_bucket.reports.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id
  rule {
    id     = "expire-old-reports"
    status = "Enabled"
    filter {}
    expiration {
      days = 90
    }
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 3
    }
  }
}

# Deny any non-TLS access
data "aws_iam_policy_document" "reports_tls" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.reports.arn, "${aws_s3_bucket.reports.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "reports" {
  bucket     = aws_s3_bucket.reports.id
  policy     = data.aws_iam_policy_document.reports_tls.json
  depends_on = [aws_s3_bucket_public_access_block.reports]
}
