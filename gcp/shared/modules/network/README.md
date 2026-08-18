# gcp/shared/modules/network

A VPC for instances that have **no external IP** and are reached only through
IAP TCP forwarding.

## Why this looks nothing like the AWS module

`aws/shared/modules/vpc` builds public and private subnets because on AWS a
subnet is public when its route table points at an internet gateway. GCP has no
per-subnet internet gateway: an instance is reachable from the internet exactly
when it has an `access_config` block, and unreachable when it does not. So there
is one subnetwork here, and "private" is a property of the instance rather than
of the subnet.

The input names (`project_name`, `environment`, `vpc_cidr`, `labels`) match the
AWS module on purpose, so the call site reads the same on both clouds even though
the resources do not.

## What it creates

| Resource | Why |
|----------|-----|
| `google_compute_network` | `auto_create_subnetworks = false`. Auto-mode VPCs ship a subnet per region and a `default-allow-ssh` rule open to `0.0.0.0/0`. |
| `google_compute_subnetwork` | One private range with `private_ip_google_access = true` and sampled flow logs. |
| `google_compute_router` + `google_compute_router_nat` | Egress for apt, GitHub and registries. Optional via `enable_cloud_nat`. |
| `google_compute_firewall.iap_ssh` | tcp:22 from `35.235.240.0/20` only, scoped to `var.iap_target_tags`. The only ingress rule. |
| `google_compute_firewall.deny_all_ingress` | Explicit deny at priority 65533, for logging and reviewability. |

## The two ranges that matter

- `35.235.240.0/20` — IAP TCP forwarding. Not routable from the internet; traffic
  only appears from it after IAP has authorised the caller against IAM. This is
  the allowed SSH source and the only one.
- `0.0.0.0/0` — appears exactly once, on the *deny* rule. If you ever see it on
  an `allow` rule in this module, that is the bug.

## Costs

Cloud NAT is roughly **$32/month** for the gateway plus data processing, and it
runs whether or not any instance is up. It is the dominant standing cost of this
module. `private_ip_google_access` is free and covers Google APIs, so set
`enable_cloud_nat = false` for a workload that never reaches the public internet.

Flow logs and NAT logs are billed per GB. Defaults here are deliberately
conservative: 50% flow sampling at 10-minute aggregation, and `ERRORS_ONLY` on
NAT (successful translations are noise; dropped ones are how you diagnose port
exhaustion).

## Egress is wide open by design

There is no egress firewall rule, so GCP's implied allow-all egress applies. A
dev box that cannot reach an arbitrary host is a dev box that cannot install
things. Add a scoped egress rule here if this module is ever reused for something
that should not be able to phone home.
