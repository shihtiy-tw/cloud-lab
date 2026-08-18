# Two-tier VPC: public subnets for the NAT gateway and anything internet-facing,
# private subnets for workloads that must not be reachable from the internet.
#
# The dev VM (aws/compute/dev-vm) is the reason the private tier exists at all:
# it has no public IP and no inbound rules, and reaches AWS only outbound through
# the NAT gateway, so "private subnet + egress" is the whole network contract.

locals {
  name = "${var.project_name}-${var.environment}"

  # Required tags per aws/docs/standards/TAGGING_STANDARDS.md. var.tags comes
  # last so a caller (or a test) can override any of them.
  common_tags = merge(
    {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
      Component   = "networking"
    },
    var.tags
  )

  # Never ask for more AZs than the region actually has; us-west-1 and a handful
  # of others expose two.
  az_names = slice(
    data.aws_availability_zones.available.names,
    0,
    min(var.az_count, length(data.aws_availability_zones.available.names))
  )

  # Private subnets start at a fixed offset rather than at length(public), so
  # adding an AZ later never renumbers an existing private subnet. Renumbering
  # replaces the subnet, and the dev VM's persistent EBS home is pinned to one.
  private_subnet_offset = 8

  # One NAT gateway shared by every private subnet, or one per AZ. See the
  # single_nat_gateway variable for the cost trade.
  nat_gateway_count = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : length(local.az_names)) : 0
}

# opt-in-not-required filters out AZs in regions the account has not enabled;
# they appear in the list but no subnet can be created in them.
data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  # DNS support and hostnames are both prerequisites for VPC interface endpoints
  # (and therefore for ever dropping the NAT gateway), so they are not optional.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "${local.name}-vpc"
  })
}

resource "aws_subnet" "public" {
  count = length(local.az_names)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = local.az_names[count.index]
  map_public_ip_on_launch = var.map_public_ip_on_launch

  tags = merge(local.common_tags, {
    Name = "${local.name}-public-${local.az_names[count.index]}"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  count = length(local.az_names)

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + local.private_subnet_offset)
  availability_zone = local.az_names[count.index]

  # Explicit even though false is the default: an instance in here must never
  # acquire a public IP, and stating it makes that reviewable.
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "${local.name}-private-${local.az_names[count.index]}"
    Tier = "private"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.name}-igw"
  })
}

resource "aws_eip" "nat" {
  count = local.nat_gateway_count

  domain = "vpc"

  # An EIP allocated before the IGW exists cannot be associated with the NAT
  # gateway, and Terraform has no way to infer that ordering on its own.
  depends_on = [aws_internet_gateway.main]

  tags = merge(local.common_tags, {
    Name = "${local.name}-nat-eip-${count.index}"
  })
}

resource "aws_nat_gateway" "main" {
  count = local.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  depends_on = [aws_internet_gateway.main]

  tags = merge(local.common_tags, {
    Name = "${local.name}-nat-${count.index}"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.name}-public-rt"
  })
}

# Routes as separate resources, not inline `route` blocks: inline routes are
# authoritative for the whole table, so anything added out-of-band (a VPN, a peer)
# is silently deleted on the next apply.
resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# One private route table per AZ regardless of NAT count, so flipping
# single_nat_gateway to false is a route change rather than a table rebuild.
resource "aws_route_table" "private" {
  count = length(local.az_names)

  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.name}-private-rt-${local.az_names[count.index]}"
  })
}

resource "aws_route" "private_nat" {
  count = var.enable_nat_gateway ? length(aws_route_table.private) : 0

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[var.single_nat_gateway ? 0 : count.index].id
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# The default security group allows all traffic between anything that lands in
# it. Nothing here uses it, so strip it to nothing rather than leave a permissive
# group attached to the VPC.
resource "aws_default_security_group" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.name}-default-do-not-use"
  })
}
