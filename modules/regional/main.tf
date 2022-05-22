data "aws_availability_zones" "all" {}
data "aws_caller_identity" "current" {}
data "aws_elb_service_account" "main" {}
data "aws_region" "current" {}

locals {
  name               = "demo"
  is_non_prod        = var.env == "prod" ? false : true
  availability_zones = slice(sort(data.aws_availability_zones.all.zone_ids), 0, var.number_of_azs)
  account            = data.aws_caller_identity.current.account_id
  region             = data.aws_region.current.name
  tags = {
    Environment                                   = var.env
    Name                                          = local.name
  }
}

module "vpc" {
  source = "./vpc"

  vpc_name                 = local.name
  vpc_azs                  = local.availability_zones
  vpc_single_nat_gateway   = local.is_non_prod
  vpc_enable_nat_gateway   = true
  vpc_enable_dns_hostnames = true
  vpc_tags                 = local.tags
}

// external facing load balancer
resource "aws_lb" "ext_lb" {
  name_prefix        = local.name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.external_facing_web_sg.id]
  subnets            = module.vpc.vpc_public_subnet_ids
  drop_invalid_header_fields = true
  enable_deletion_protection = false

  tags = {
    Environment = var.env
  }
}

data "aws_iam_role" "myrole" {
  name = "0b1-wan-ken0be"
}

resource "aws_lb_listener" "ext_lb" {
  load_balancer_arn = aws_lb.ext_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = format("\"These aren't the Dr01ds you're looking for.\", said %s in %s", data.aws_iam_role.myrole.id, local.region )
      status_code  = "404"
    }
  }
}
// external facing load balancer security group allowing inbound http
resource "aws_security_group" "external_facing_web_sg" {
  name        = "external-facing-web-sg"
  description = "Allow inbound HTTP"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Allow ingress access to port 80"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow egress access"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "external-facing-web-sg"
  }
}
