# ES-to-ECS Private Connection via CLB + PrivateLink

Connect an Aliyun ES instance (VPC_1) to an ECS instance (VPC_2) for Watcher, LDAP, AD auth,
custom plugin dictionaries, or reindex from self-managed ES.

## Architecture

```
ES (VPC_1) → [Endpoint] ←PrivateLink→ [Endpoint Service] → CLB → ECS (VPC_2)
```

## Prerequisites

- Aliyun ES instance in VPC_1 (created after Oct 2020)
- ECS instance in VPC_2 with the target service deployed
- Same region and availability zone for ES, ECS, and CLB

## Step 1: Create and Configure CLB Instance

1. Open [CLB Console](https://slb.console.aliyun.com/slb/) (select your region in the top nav)
2. Click **Create CLB** (传统型负载均衡)
3. Configure:
   - **Region**: same as ES instance
   - **Instance Type**: **Private** (私网)
   - **Availability Zone**: same as ES and ECS
4. Purchase the CLB instance
5. Configure listener:
   - Click **Listener Configuration Wizard** on the instance
   - Set listening port (e.g., 9200 for ES, 389 for LDAP, 636 for LDAPS)
   - Add ECS as backend server
   - Configure health check

> Reference: [Create CLB](https://help.aliyun.com/zh/slb/classic-load-balancer/user-guide/create-and-manage-a-clb-instance)

## Step 2: Create Endpoint Service

1. Open [PrivateLink Endpoint Service Console](https://vpc.console.aliyun.com/privatelink/) (select your region)
2. Click **Create Endpoint Service**
3. Select the CLB instance as the service resource
4. Configure other parameters and click **Confirm**

> Reference: [Create Endpoint Service](https://help.aliyun.com/zh/privatelink/user-guide/create-and-manage-an-endpoint-service)

## Step 3: Configure ES Private Connection

1. Open [ES Console](https://elasticsearch.console.aliyun.com/)
2. Navigate to target ES instance
3. Left sidebar → **Network and Security** (网络与安全)
4. In **Cluster Network Settings**, click **Modify** next to **Configure Private Connection**
5. Click **Add Private Connection**
6. Select the endpoint service created in Step 2, choose target availability zone
7. Confirm the dialog
8. Click **Allow Connection** on the endpoint row
9. Wait for **Connection Status** to become **Connected** (已连接)

## Step 4: Get Endpoint Domain

1. In the private connection panel, click the **Endpoint ID**
2. Expand the endpoint to view its domain name
3. Use this domain in your service configuration (see use cases below)

## Use Cases After Connection

### Watcher Webhook

```json
{
  "actions": {
    "webhook": {
      "webhook": {
        "host": "<endpoint_domain>",
        "port": 8080,
        "path": "/alert",
        "method": "post"
      }
    }
  }
}
```

### LDAP Configuration

```yaml
xpack.security.authc.realms.ldap.ldap1:
  order: 2
  url: "ldap://<endpoint_domain>:389"
  bind_dn: "cn=admin,dc=example,dc=com"
  user_search:
    base_dn: "ou=users,dc=example,dc=com"
    filter: "(uid={0})"
  group_search:
    base_dn: "ou=groups,dc=example,dc=com"
  unmapped_groups_as_roles: false
```

### AD (Active Directory) Configuration

```yaml
xpack.security.authc.realms.active_directory.ad1:
  order: 3
  url: "ldaps://<endpoint_domain>:636"
  domain_name: "example.com"
  unmapped_groups_as_roles: false
```

> Note: For AD over LDAPS (port 636), ensure the CLB listener is configured on port 636
> and the AD server's SSL certificate is valid.

### Reindex from Self-managed ES

First add whitelist in ES YML config (requires cluster restart):

```
reindex.remote.whitelist: ["<endpoint_domain>:9200"]
```

Then run:

```json
POST _reindex
{
  "source": {
    "remote": {
      "host": "http://<endpoint_domain>:9200",
      "username": "elastic",
      "password": "<password>"
    },
    "index": "source_index"
  },
  "dest": {
    "index": "dest_index"
  }
}
```

> Use `https://` if the self-managed ES on ECS has TLS enabled.
