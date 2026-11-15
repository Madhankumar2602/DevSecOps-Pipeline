resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.project}-vpc" }
}

# Lock down the default SG so nothing accidentally uses it.
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project}-default-locked" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project}-igw" }
}

# Public subnet keeps the lab cheap (no NAT Gateway). Access is restricted by SGs to your IP only.
#tfsec:ignore:aws-ec2-no-public-ip-subnet
resource "aws_subnet" "public" {
  #checkov:skip=CKV_AWS_130:Lab uses a public subnet to avoid NAT Gateway cost; SGs allow only my_ip_cidr
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1)
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.project}-public-a" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "${var.project}-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ---- VPC Flow Logs -> CloudWatch ----
resource "aws_cloudwatch_log_group" "flow" {
  #checkov:skip=CKV_AWS_338:Lab keeps logs 30 days to control cost (production would use >= 365)
  name              = "/${var.project}/vpc-flow-logs"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.main.arn
}

resource "aws_flow_log" "main" {
  count = local.create_iam ? 1 : 0 # needs its own IAM role, which Learner Lab blocks

  vpc_id          = aws_vpc.main.id
  traffic_type    = "REJECT"
  iam_role_arn    = aws_iam_role.flow_logs[0].arn
  log_destination = aws_cloudwatch_log_group.flow.arn
}

data "aws_iam_policy_document" "flow_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  count = local.create_iam ? 1 : 0

  name               = "${var.project}-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_assume.json
}

data "aws_iam_policy_document" "flow_write" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
    resources = ["${aws_cloudwatch_log_group.flow.arn}:*"]
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  count = local.create_iam ? 1 : 0

  name   = "write-flow-logs"
  role   = aws_iam_role.flow_logs[0].id
  policy = data.aws_iam_policy_document.flow_write.json
}
