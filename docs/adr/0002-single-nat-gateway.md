# ADR 0002: One NAT gateway by default

**Status:** Accepted

## Context

Tasks in the private app subnets need outbound HTTPS (image pulls, WordPress
updates, AWS APIs). AWS's high-availability pattern is one NAT gateway per AZ,
so an AZ failure never removes another AZ's egress. Each NAT gateway is billed
per hour plus per GB, which is the largest fixed cost in this stack.

## Decision

Default `single_nat_gateway = true`, with per-AZ NAT one variable away. Each AZ
already has its own app route table, so switching only changes the route targets.

## Consequences

- If the NAT gateway's AZ fails, tasks in other AZs keep **serving traffic**
  (inbound comes through the ALB), but lose **outbound** calls until the AZ recovers.
- Cross-AZ data charges apply for egress from the other two AZs.
- The free S3 gateway endpoint takes S3 traffic off the NAT path entirely.
- Production setting: `single_nat_gateway = false`, and consider
  `enable_interface_endpoints = true` to keep AWS API traffic private.
