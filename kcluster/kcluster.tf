terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }
  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "eu-central-1"
}

variable "master_instance_count" {
  type    = number
  default = 3
}

variable "worker_instance_count" {
  type    = number
  default = 5
}

variable "my_ip" {
  type    = string
  default = "89.247.166.167"
}

resource "aws_launch_template" "kcluster_masters" {

  name = "kcluster_masters"
  image_id               = "ami-0c9354388bb36c088"
  instance_type          = "t2.medium"
  key_name               = "cks"
  vpc_security_group_ids = ["${aws_security_group.kcluster.id}"]
  user_data              = base64encode(<<-EOT
    #!/bin/bash
    cp /home/ubuntu/.ssh/authorized_keys /root/.ssh/authorized_keys
    systemctl restart sshd
    EOT
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
        Name = "kcluster_master_node"
        Purpose = "kcluster"
        Role = "kcluster_master"
      }
  }
}

resource "aws_autoscaling_group" "kcluster_masters" {
  name = "kcluster_master"
  desired_capacity     = var.master_instance_count
  min_size             = var.master_instance_count
  max_size             = var.master_instance_count

  launch_template {
    id      = aws_launch_template.kcluster_masters.id
    version = "$Latest"
  }

  vpc_zone_identifier = data.aws_subnets.default.ids
  target_group_arns = [aws_lb_target_group.kcluster_masters.arn]
}


resource "aws_launch_template" "kcluster_workers" {

  name = "kcluster_workers"
  image_id               = "ami-0c9354388bb36c088"
  instance_type          = "t2.medium"
  key_name               = "cks"
  vpc_security_group_ids = ["${aws_security_group.kcluster.id}"]
  user_data              = base64encode(<<-EOT
    #!/bin/bash
    cp /home/ubuntu/.ssh/authorized_keys /root/.ssh/authorized_keys
    systemctl restart sshd
    EOT
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
        Name = "kcluster_worker_node"
        Purpose = "kcluster"
        Role = "kcluster_worker"
      }
  }
}

resource "aws_autoscaling_group" "kcluster_workers" {
  name = "kcluster_worker"
  desired_capacity     = var.worker_instance_count
  min_size             = var.worker_instance_count
  max_size             = var.worker_instance_count

  launch_template {
    id      = aws_launch_template.kcluster_workers.id
    version = "$Latest"
  }

  vpc_zone_identifier = data.aws_subnets.default.ids
}

data "aws_instances" "ec2_instances" {
  depends_on = [ aws_autoscaling_group.kcluster_workers, aws_autoscaling_group.kcluster_masters ]

  filter {
    name   = "instance-state-name"
    values = ["running"]
  }
  filter {
    name   = "tag:Purpose"
    values = ["kcluster"]
  }
}

data "aws_vpc" "default" {
  filter {
    name   = "isDefault"
    values = ["true"]
  }
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_lb" "kcluster_masters" {
  name               = "masters-balancer"
  internal           = false
  load_balancer_type = "network"
  subnets            = data.aws_subnets.default.ids

  tags = {
    Name = "kcluster"
    Purpose = "kcluster"
  }
}

resource "aws_lb_listener" "masters" {
  load_balancer_arn = aws_lb.kcluster_masters.arn
  port              = 6443
  protocol          = "TCP"

  default_action {
    target_group_arn = aws_lb_target_group.kcluster_masters.arn
    type  = "forward"
  }

  tags = {
    Name = "kcluster"
    Purpose = "kcluster_master"
  }
}

resource "aws_lb_target_group" "kcluster_masters" {
  name     = "kcluster-masters"
  port     = 6443
  protocol = "TCP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = "/health"
    port                = 80
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 10
    matcher             = "200-499"
  }

  tags = {
    Name = "kcluster"
    Purpose = "kcluster_master"
  }
}

resource "aws_security_group" "kcluster" {
  name = "kcluster"

  tags = {
    Name = "kcluster"
    Purpose = "kcluster"
  }

  ingress {
    from_port         = 0
    to_port           = 65535
    protocol    = "tcp"
    cidr_blocks = data.aws_vpc.default.cidr_block_associations[*].cidr_block
    description = "all VPC IPs"
  }

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = [ "${var.my_ip}/32" ]
    description = "my mac"
  }

  ingress {
    from_port = 6443
    to_port = 6443
    protocol = "tcp"
    cidr_blocks = [ "${var.my_ip}/32" ]
    description = "my mac"
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
      from_port = 0
      to_port = 0
      protocol = -1
      self = true
      description = "all instances"
  }
}

resource "aws_security_group_rule" "ec2_ingress" {
  security_group_id = aws_security_group.kcluster.id
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  cidr_blocks       = [for ip in data.aws_instances.ec2_instances.public_ips : "${ip}/32"] 
  description = "all EC2s on public its addresses"
}