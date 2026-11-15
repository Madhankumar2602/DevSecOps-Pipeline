resource "aws_security_group" "jenkins" {
  name        = "${var.project}-jenkins"
  #checkov:skip=CKV2_AWS_5:Attached to aws_instance.node["jenkins"] via for_each (graph check cannot resolve it)
  description = "Jenkins + SonarQube CI server"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.project}-jenkins-sg" }
}

resource "aws_security_group" "k8s" {
  name        = "${var.project}-k8s"
  #checkov:skip=CKV2_AWS_5:Attached to aws_instance.node["k8s"] via for_each (graph check cannot resolve it)
  description = "Single-node k3s cluster"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.project}-k8s-sg" }
}

# ---------- Jenkins ingress (your IP only) ----------
resource "aws_vpc_security_group_ingress_rule" "jenkins_ssh" {
  security_group_id = aws_security_group.jenkins.id
  description       = "SSH from my IP"
  cidr_ipv4         = var.my_ip_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

resource "aws_vpc_security_group_ingress_rule" "jenkins_ui" {
  security_group_id = aws_security_group.jenkins.id
  description       = "Jenkins UI from my IP"
  cidr_ipv4         = var.my_ip_cidr
  ip_protocol       = "tcp"
  from_port         = 8080
  to_port           = 8080
}

resource "aws_vpc_security_group_ingress_rule" "sonar_ui" {
  security_group_id = aws_security_group.jenkins.id
  description       = "SonarQube UI from my IP"
  cidr_ipv4         = var.my_ip_cidr
  ip_protocol       = "tcp"
  from_port         = 9000
  to_port           = 9000
}

# ---------- k8s ingress ----------
resource "aws_vpc_security_group_ingress_rule" "k8s_ssh" {
  security_group_id = aws_security_group.k8s.id
  description       = "SSH from my IP"
  cidr_ipv4         = var.my_ip_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

resource "aws_vpc_security_group_ingress_rule" "k8s_app_me" {
  security_group_id = aws_security_group.k8s.id
  description       = "ShipGuard NodePort from my IP"
  cidr_ipv4         = var.my_ip_cidr
  ip_protocol       = "tcp"
  from_port         = 30080
  to_port           = 30080
}

resource "aws_vpc_security_group_ingress_rule" "k8s_app_jenkins" {
  security_group_id            = aws_security_group.k8s.id
  description                  = "Smoke tests from Jenkins"
  referenced_security_group_id = aws_security_group.jenkins.id
  ip_protocol                  = "tcp"
  from_port                    = 30080
  to_port                      = 30080
}

resource "aws_vpc_security_group_ingress_rule" "k8s_api_jenkins" {
  security_group_id            = aws_security_group.k8s.id
  description                  = "Kubernetes API from Jenkins"
  referenced_security_group_id = aws_security_group.jenkins.id
  ip_protocol                  = "tcp"
  from_port                    = 6443
  to_port                      = 6443
}

# ---------- egress: instances need the internet for packages, images and AWS APIs ----------
#tfsec:ignore:aws-ec2-no-public-egress-sgr
resource "aws_vpc_security_group_egress_rule" "jenkins_all" {
  #checkov:skip=CKV_AWS_382:CI server must download packages, images and call AWS APIs
  security_group_id = aws_security_group.jenkins.id
  description       = "Outbound internet"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

#tfsec:ignore:aws-ec2-no-public-egress-sgr
resource "aws_vpc_security_group_egress_rule" "k8s_all" {
  #checkov:skip=CKV_AWS_382:Node must pull images from ECR and send logs to CloudWatch
  security_group_id = aws_security_group.k8s.id
  description       = "Outbound internet"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
