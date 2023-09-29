################
# Load Balancing
################
# Load Balancer security group
resource "aws_security_group" "lb_sg" {
  name        = "${local.name_prefix}-lb"
  description = "Allow HTTPS to ALB"
  vpc_id      = aws_vpc.main.id
}

# LB HTTPS Ingress rule
resource "aws_security_group_rule" "lb_https_ingress" {
  security_group_id = aws_security_group.lb_sg.id

  type        = "ingress"
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
}

# LB Egress rule
resource "aws_security_group_rule" "lb_all_egress" {
  security_group_id = aws_security_group.lb_sg.id

  type        = "egress"
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]
}

# Application Load Balancer
resource "aws_lb" "lb" {
  name               = local.name_prefix
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_sg.id]
  subnets            = [for subnet in aws_subnet.public : subnet.id]

  enable_deletion_protection = false
}

# HTTPS ALB listener
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.lb.arn
  port              = "443"
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate.cert.arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Default response not implemented"
      status_code  = "501"
    }
  }
}
