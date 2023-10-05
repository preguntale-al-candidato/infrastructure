### ==============
### Segurity group
### ==============
resource "aws_security_group" "db" {
  name        = "${local.name_prefix}-db"
  description = "Traffic to and from DB"
  vpc_id      = aws_vpc.main.id
}

# DB ingress rule from Backend
# etcd:   2379
# minio:  9000 and 9001
# milvus: 9091 and 19530
resource "aws_security_group_rule" "db_from_backend_api" {
  for_each = toset(["2379", "9000", "9001", "9091", "19530"])

  security_group_id        = aws_security_group.db.id
  type                     = "ingress"
  from_port                = each.value
  to_port                  = each.value
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.backend.id
}

# DB egress rule
resource "aws_security_group_rule" "db_all_egress" {
  security_group_id = aws_security_group.db.id
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

### =============
### DB IAM config
### =============
resource "aws_iam_role" "db" {
  name = "${local.name_prefix}-db"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_instance_profile" "db" {
  name = "${local.name_prefix}-db"
  role = aws_iam_role.db.name
}

resource "aws_iam_role_policy_attachment" "milvus_volume_db_policy_attach" {
  role       = aws_iam_role.db.name
  policy_arn = aws_iam_policy.milvus_volume_policy.arn
}

### ============
### Instance AMI
### ============
data "aws_ssm_parameter" "db_amazon_linux_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-minimal-kernel-default-x86_64"
}

### ===========
### DB instance
### ===========

resource "aws_instance" "db" {
  ami                         = data.aws_ssm_parameter.db_amazon_linux_ami.value
  instance_type               = "t3a.small"
  associate_public_ip_address = true
  key_name                    = "jnonino-pac"
  vpc_security_group_ids      = [aws_security_group.db.id]
  iam_instance_profile        = aws_iam_instance_profile.db.name
  user_data                   = base64encode(file("${path.module}/scripts/db-user-data.sh"))
  subnet_id                   = values(aws_subnet.public)[0].id
  root_block_device {
    volume_size           = "30"
    delete_on_termination = true
  }
  tags = {
    Name = "${local.name_prefix}-db"
  }
}

resource "aws_route53_record" "db_internal" {
  zone_id = module.route53.zone_id
  name    = "db-internal"
  type    = "A"
  ttl     = 5
  records = [aws_instance.db.private_ip]
}

resource "aws_route53_record" "db_external" {
  zone_id = module.route53.zone_id
  name    = "db-external"
  type    = "A"
  ttl     = 5
  records = [aws_instance.db.public_ip]
}
