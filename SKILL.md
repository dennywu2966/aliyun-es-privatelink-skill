---
name: aliyun-es-privatelink
description: >
  Configure private network connections (PrivateLink) for Aliyun Elasticsearch clusters.
  Covers two scenarios: (1) ES-to-ECS via CLB+PrivateLink for Watcher, LDAP, AD auth,
  custom plugin dictionaries, and cross-cluster reindex from self-managed ES;
  (2) ES-to-ES via NLB+PrivateLink for cross-cluster reindex/migration between two
  Aliyun ES instances. Use when: configuring Aliyun ES private network connectivity,
  setting up PrivateLink for ES, enabling X-Pack Watcher/LDAP/AD behind new network
  architecture, cross-VPC ES communication, ES cluster migration via reindex,
  "configure private connection", "ES privatelink", "ES private network",
  "ES to ECS connectivity", "ES to ES reindex".
---

# Aliyun ES PrivateLink Configuration

## Overview

Aliyun ES instances created after October 2020 use a new network architecture that restricts
certain features (Watcher, reindex, LDAP, AD auth). PrivateLink + Load Balancer is the
**only** solution for private network connectivity under this architecture.

## Prerequisites (all scenarios)

- ES instance created **after October 2020** (new network architecture)
- ES, LB, and target resources must be in the **same region and availability zone**
- Region must support PrivateLink — see [supported regions](https://help.aliyun.com/zh/privatelink/product-overview/regions-and-zones-that-support-privatelink)

## Scenario Selection

| Scenario | LB Type | Reference |
|---|---|---|
| ES accessing ECS services (Watcher, LDAP, AD, plugins, reindex from self-managed) | CLB (private) | [references/clb-es-to-ecs.md](references/clb-es-to-ecs.md) |
| Two Aliyun ES clusters inter-connected (cross-cluster reindex/migration) | NLB (private, IP type) | [references/nlb-es-to-es.md](references/nlb-es-to-es.md) |

Read the appropriate reference file for step-by-step instructions.

## Connectivity Verification

After configuration, use `scripts/test_privatelink_connectivity.sh` to verify:

```bash
bash scripts/test_privatelink_connectivity.sh \
  --endpoint "ep-xxxx.privatelink.aliyuncs.com" \
  --port 9200 \
  --es-host "https://ES1_ENDPOINT:9200" \
  --es-user elastic \
  --es-pass "<password>" \
  --remote-index "source_index" \
  --local-index "dest_index"
```

The script tests TCP connectivity to the PrivateLink endpoint and optionally runs a
reindex operation to verify end-to-end data flow.

## Key Concepts

- **Endpoint Service** — created manually in the target VPC (ECS side or ES_2 side), backed by the LB instance
- **Endpoint** — created automatically by the ES console in the ES VPC when you configure private connection
- **Endpoint Domain** — use this domain in Watcher, LDAP, reindex whitelist configurations

## Common Pitfalls

1. **Region/AZ mismatch** — ES, LB, and target must share the same region AND availability zone
2. **Forgetting "Allow Connection"** — after adding the private connection in ES console, click "Allow Connection" on the endpoint row
3. **Reindex whitelist** — add `endpoint_domain:9200` to `reindex.remote.whitelist` in ES_1 YML config before reindexing
4. **Protocol** — use `http://` or `https://` prefix matching your ES cluster's protocol in reindex host
