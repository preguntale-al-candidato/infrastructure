#####
# VPC
#####
resource "aws_vpc" "main" {
  cidr_block = local.vpc_cidr_block
}

##################
# Internet gateway
##################
resource "aws_internet_gateway" "internet_gw" {
  vpc_id = aws_vpc.main.id
}

################
# Public subnets
################

# Subnets
resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id     = aws_vpc.main.id
  availability_zone = each.value.availability_zone
  cidr_block = each.value.cidr_block

  tags = {
    Name = each.key
  }
}

# Route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id
}

# Route to access internet
resource "aws_route" "public_access_to_internet" {
  route_table_id         =  aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gw.id
}

# Association of Route Table to Subnets
resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# # Elastic IPs for NAT
# resource "aws_eip" "nat" {
#   domain = "vpc"
# }

# # NAT gateways
# resource "aws_nat_gateway" "nat" {
#   allocation_id = aws_eip.nat.id
#   subnet_id     = values(aws_subnet.public)[0].id
# }

#################
# Private subnets
#################

# # Subnets
# resource "aws_subnet" "private" {
#   for_each = local.private_subnets

#   vpc_id     = aws_vpc.main.id
#   availability_zone = each.value.availability_zone
#   cidr_block = each.value.cidr_block

#   tags = {
#     Name = each.key
#   }
# }

# # Route table
# resource "aws_route_table" "private" {
#   vpc_id = aws_vpc.vpc.id
# }

# # Route to access internet
# resource "aws_route" "private_access_to_internet" {
#   route_table_id         =  aws_route_table.public.id
#   destination_cidr_block = "0.0.0.0/0"
#   gateway_id             = aws_nat_gateway.nat.id
# }

# # Association of Route Table to Subnets
# resource "aws_route_table_association" "public" {
#   for_each = aws_subnet.private

#   subnet_id      = each.value.id
#   route_table_id = aws_route_table.private.id
# }
