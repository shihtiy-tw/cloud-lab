# Module: vpc

Two-tier VPC — public subnets for the NAT gateway, private subnets for workloads
that must not be reachable from the internet.

Its first consumer is [`aws/compute/dev-vm`](../../../compute/dev-vm/), whose
entire connectivity model is "private subnet, no public IP, no inbound rules,
outbound only". That is the shape this module is built for.

## Usage

```hcl
module "vpc" {
  source = "../../../shared/modules/vpc"

  project_name = "cloud-lab"
  environment  = "dev"
  vpc_cidr     = "10.20.0.0/16"
  az_count     = 2

  tags = local.common_tags
}
```

The module declares no `provider` block, so it inherits the caller's. Configure
the region in the root module from a real variable — never
`provider "aws" { region = terraform.workspace }`, which is what
`aws/compute/ecs/infrastructure/vpc` does and why `--env dev` cannot select a
workspace anywhere in this repo. A workspace names an environment, not a region.

## Layout

With the default `vpc_cidr = "10.0.0.0/16"` and `az_count = 2`:

| Subnet | CIDR | Route to 0.0.0.0/0 |
|--------|------|--------------------|
| public a | 10.0.0.0/24 | internet gateway |
| public b | 10.0.1.0/24 | internet gateway |
| private a | 10.0.8.0/24 | NAT gateway |
| private b | 10.0.9.0/24 | NAT gateway |

Private subnets start at a fixed offset of 8 rather than at `length(public)`, so
adding a third AZ later does not renumber the existing private subnets.
Renumbering replaces a subnet, and the dev VM's persistent EBS home is pinned to
one.

## Cost

Subnets, route tables and the internet gateway are free. The NAT gateway is not:
roughly **$32/month** per gateway plus $0.045/GB processed. `single_nat_gateway`
defaults to `true` for that reason — per-AZ NAT buys AZ-failure isolation that a
lab does not need and triples the standing bill.

If a workload only needs AWS APIs and no general internet, VPC interface
endpoints (`ssm`, `ssmmessages`, `ec2messages`, plus an S3 gateway endpoint) are
the NAT-free alternative at ~$7/month per endpoint. That does not work for the
dev VM, which has to reach apt repositories and GitHub, but it is the right answer
for private ECS tasks and Lambdas.

## Inputs

| Name | Type | Default | Purpose |
|------|------|---------|---------|
| `project_name` | string | — | Name and tag prefix. |
| `environment` | string | — | `dev`/`staging`/`test`/`prod`/`sandbox`/`demo`. |
| `vpc_cidr` | string | `10.0.0.0/16` | Must be `/20` or larger. |
| `tags` | map(string) | `{}` | Merged last, so it can override the common tags. |
| `az_count` | number | `2` | AZs to span, capped at what the region offers. |
| `enable_nat_gateway` | bool | `true` | Private egress. |
| `single_nat_gateway` | bool | `true` | One NAT for all AZs instead of one each. |
| `map_public_ip_on_launch` | bool | `false` | Off by default on purpose. |

## Outputs

`vpc_id`, `vpc_cidr`, `private_subnet_ids`, `public_subnet_ids` are the contract
asserted by [`aws/tests/vpc_test.go`](../../../tests/vpc_test.go); renaming them
breaks that test. Also exported: `availability_zones` (index-aligned with the
subnet lists — needed to place a zonal resource such as an EBS volume in the same
AZ as its subnet), `internet_gateway_id`, `nat_gateway_ids`, `nat_public_ips`,
`private_route_table_ids`, `public_route_table_id`.

## Tests

```bash
cd aws/tests
go test -v -short -run TestVPCValidate   # no credentials needed
go test -v -run TestVPCIntegration       # creates real resources, costs money
```
