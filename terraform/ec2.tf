data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "main" {
  key_name   = "${var.project}-key"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

locals {
  instances = {
    jenkins = {
      type    = var.jenkins_instance_type
      sg      = aws_security_group.jenkins.id
      profile = var.learner_lab ? var.lab_instance_profile : aws_iam_instance_profile.jenkins[0].name
      disk    = 40
    }
    k8s = {
      type    = var.k8s_instance_type
      sg      = aws_security_group.k8s.id
      profile = var.learner_lab ? var.lab_instance_profile : aws_iam_instance_profile.k8s[0].name
      disk    = 20
    }
  }
}

resource "aws_instance" "node" {
  #checkov:skip=CKV_AWS_88:Public IP needed for lab access; SG restricts to my_ip_cidr
  for_each = local.instances

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = each.value.type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [each.value.sg]
  iam_instance_profile   = each.value.profile
  key_name               = aws_key_pair.main.key_name
  monitoring             = true
  ebs_optimized          = true

  metadata_options {
    http_tokens                 = "required" # IMDSv2 only
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 2 # allow containers on the host to use the instance role
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = each.value.disk
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = "${var.project}-${each.key}"
    Role = each.key
  }

  lifecycle {
    ignore_changes = [ami]
  }
}

# Elastic IPs keep the same public address when instances are stopped and started
# (Learner Lab stops them at the end of every session).
resource "aws_eip" "node" {
  for_each = local.instances

  domain   = "vpc"
  instance = aws_instance.node[each.key].id

  tags = {
    Name = "${var.project}-${each.key}"
  }
}
