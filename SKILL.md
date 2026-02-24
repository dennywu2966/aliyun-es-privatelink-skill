---
name: aliyun-es-privatelink
description: >
  Configure private network connections (PrivateLink) for Aliyun Elasticsearch clusters.
  Covers two scenarios: (1) ES-to-ECS via CLB+PrivateLink for Watcher, LDAP, AD auth,
  custom plugin dictionaries, and cross-cluster reindex from self-managed ES;
  (2) ES-to-ES via NLB+PrivateLink for cross-cluster reindex/migration between two
  Aliyun ES instances.
  Use when: configuring Aliyun ES private network connectivity, setting up PrivateLink
  for ES, enabling X-Pack Watcher/LDAP/AD behind new network architecture, cross-VPC
  ES communication, ES cluster migration via reindex.
  Trigger phrases: "configure private connection", "ES privatelink", "ES private network",
  "ES to ECS connectivity", "ES to ES reindex", "privatelink setup", "ES watcher webhook",
  "ES LDAP configuration", "cross-VPC elasticsearch", "aliyun ES migration",
  "ES reindex remote whitelist", "endpoint service for ES".
---

# Aliyun ES PrivateLink Configuration

## Overview

Aliyun ES instances created after October 2020 use a new network architecture that restricts
certain features (Watcher, reindex, LDAP, AD auth). PrivateLink + Load Balancer is the
**only** solution for private network connectivity under this architecture.

## Input

| Parameter | Required | Description |
|---|---|---|
| Scenario | Yes | `es-to-ecs` (Watcher/LDAP/AD/reindex from self-managed) or `es-to-es` (cross-cluster reindex/migration) |
| Region | Yes | Aliyun region (e.g., cn-hangzhou, cn-shanghai) — must be same for all resources |
| Availability Zone | Yes | Must match across ES, LB, and target |
| ES Instance ID | Yes | The ES instance initiating the connection |
| Target | Yes | ECS IP/service (scenario 1) or ES_2 instance (scenario 2) |
| Target Port | No | Default: 9200 (ES), 389 (LDAP), 636 (LDAPS), 8080 (webhook) |
| Protocol | No | `http` or `https` — must match target ES cluster config |

## Prerequisites

- ES instance created **after October 2020** (new network architecture)
- ES, LB, and target resources must be in the **same region and availability zone**
- Region must support PrivateLink — see [supported regions](https://help.aliyun.com/zh/privatelink/product-overview/regions-and-zones-that-support-privatelink)

## Steps

### 1. Select scenario and follow the reference guide

| Scenario | LB Type | Reference |
|---|---|---|
| ES → ECS (Watcher, LDAP, AD, plugins, reindex from self-managed) | CLB (private) | [references/clb-es-to-ecs.md](references/clb-es-to-ecs.md) |
| ES → ES (cross-cluster reindex/migration) | NLB (private, IP type) | [references/nlb-es-to-es.md](references/nlb-es-to-es.md) |

### 2. Create Load Balancer → Endpoint Service → ES Private Connection

Each reference guide covers the full step-by-step. The high-level flow is:

```
Create LB (CLB or NLB) → Add backend servers → Create Endpoint Service
→ Add Private Connection in ES Console → Allow Connection → Get Endpoint Domain
```

### 3. Configure ES to use the endpoint

Depending on the use case:
- **Reindex**: add endpoint to `reindex.remote.whitelist` in ES YML config
- **Watcher**: use endpoint domain in webhook action `host`
- **LDAP/AD**: use endpoint domain in realm `url`

## Verification

After completing the steps, verify connectivity:

```bash
bash scripts/test_privatelink_connectivity.sh \
  --endpoint "ep-xxxx.privatelink.aliyuncs.com" \
  --port 9200 \
  --protocol http \
  --es-host "https://ES1_ENDPOINT:9200" \
  --es-user elastic \
  --es-pass "<password>" \
  --remote-index "source_index" \
  --local-index "dest_index" \
  --cleanup
```

The script runs 4 checks:
1. **DNS resolution** — endpoint domain resolves
2. **TCP connectivity** — port is reachable
3. **HTTP probe** — ES responds on the endpoint
4. **Reindex test** (optional) — end-to-end data flow verification

**Success criteria**: All 4 checks pass. For reindex, compare `dest_index/_count` with source.

## Key Concepts

- **Endpoint Service** — created manually in the target VPC (ECS side or ES_2 side), backed by the LB instance
- **Endpoint** — created automatically by the ES console in the ES VPC when you configure private connection
- **Endpoint Domain** — use this domain in Watcher, LDAP, reindex whitelist configurations

## Troubleshooting

### Connection status stuck on "Connecting"

1. Verify **region and AZ match** between ES, LB, and target
2. Check that the Endpoint Service status is **Available** in PrivateLink console
3. Ensure you clicked **"Allow Connection"** on the endpoint row in ES console
4. Check PrivateLink quotas — you may have hit the max endpoints per VPC

### TCP connectivity fails (test step 2)

1. Check LB listener is configured on the correct port
2. Verify backend server health check is passing (green) in LB console
3. Check ECS/ES_2 security group allows inbound traffic from the LB's VPC CIDR
4. For NLB: ensure server group type is **IP type**, not Instance type

### HTTP probe returns 000 or connection refused

1. The backend service may not be running — SSH into ECS and verify
2. Port mismatch between LB listener and backend service
3. For HTTPS endpoints, ensure the certificate is valid or use `--protocol https`

### Reindex fails with "connection refused" or "host not found"

1. Confirm `reindex.remote.whitelist` includes `<endpoint_domain>:9200` (restart required)
2. Verify protocol matches: use `http://` if ES_2 doesn't have TLS, `https://` if it does
3. Check ES_2 credentials are correct
4. If ES_2 requires client certificates, PrivateLink reindex won't work — use snapshot/restore instead

### LDAP/AD connection timeout

1. Verify CLB listener port matches LDAP port (389 for LDAP, 636 for LDAPS)
2. Check CLB health check is using TCP on the correct port
3. Ensure the LDAP/AD server on ECS is bound to `0.0.0.0`, not `127.0.0.1`

## Common Pitfalls

1. **Region/AZ mismatch** — ES, LB, and target must share the same region AND availability zone
2. **Forgetting "Allow Connection"** — after adding the private connection in ES console, click "Allow Connection" on the endpoint row
3. **Reindex whitelist** — add `endpoint_domain:9200` to `reindex.remote.whitelist` in ES_1 YML config before reindexing; cluster restart is required
4. **Protocol** — use `http://` or `https://` prefix matching your ES cluster's protocol in reindex host
5. **NLB server group type** — for ES-to-ES, the NLB server group must be **IP type**, not Instance type
6. **CLB vs NLB** — ES-to-ECS uses CLB; ES-to-ES uses NLB. Using the wrong type will fail
