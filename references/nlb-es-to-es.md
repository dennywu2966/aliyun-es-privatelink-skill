# ES-to-ES Private Connection via NLB + PrivateLink

Connect two Aliyun ES instances across VPCs for cross-cluster reindex/migration.
ES_1 initiates the connection; ES_2 is the data source.

## Architecture

```
ES_1 (VPC_1) → [Endpoint] ←PrivateLink→ [Endpoint Service] → NLB → ES_2 (VPC_2)
```

## Prerequisites

- Two Aliyun ES instances in the same region (created after Oct 2020)
- Region/AZ must support PrivateLink

## Step 1: Create NLB Instance

1. Open [NLB Console](https://slb.console.aliyun.com/nlb) (select your region in the top nav)
2. Click **Create NLB**
3. Configure:
   - **Region**: same as ES_2
   - **Network Type**: **Private** (私网)
   - **Availability Zone**: same as ES_2
4. Purchase the NLB instance

> Reference: [Create NLB](https://help.aliyun.com/zh/slb/network-load-balancer/user-guide/create-and-manage-an-nlb-instance)

## Step 2: Create NLB Server Group

1. Go to NLB **Server Groups** page
2. Click **Create Server Group**
3. Configure:
   - **Type**: **IP Type** (IP 类型) — this is critical, do NOT use Instance type
   - **VPC**: select ES_2's VPC
   - Custom name

## Step 3: Add ES_2 as Backend

1. Get ES_2 private IP using one of these methods:
   - **From ES Console**: check the instance's **Basic Information** page for private network address
   - **Via ping**: `ping <ES_2_private_domain>` (works if DNS resolves from your environment)
   - **Via nslookup**: `nslookup <ES_2_private_domain>` (more reliable across environments)
   - **Via API**: `aliyun elasticsearch DescribeInstance --InstanceId <id>` and check `networkConfig`
2. In the server group, click **Edit Backend Servers**
3. Click **Add IP**
4. Enter ES_2's private IP
5. Set port to **9200**
6. Confirm

## Step 4: Add NLB Listener

1. On the NLB instance, click **Create Listener**
2. Protocol: **TCP**
3. Listening port: **9200**
4. Server group: select the IP-type group from Step 2
5. Submit

## Step 5: Create Endpoint Service

1. Open [PrivateLink Endpoint Service Console](https://vpc.console.aliyun.com/privatelink/) (select your region)
2. Click **Create Endpoint Service**
3. Configure:
   - **Region**: same as ES
   - **Service Resource Type**: **NLB** (网络型负载均衡)
   - **Service Resource**: select the NLB instance
4. Confirm

## Step 6: Configure ES_1 Private Connection

1. Open [ES Console](https://elasticsearch.console.aliyun.com/)
2. Navigate to **ES_1** instance
3. Left sidebar → **Network and Security**
4. Click **Modify** next to **Configure Private Connection**
5. Click **Add Private Connection**
6. Select the endpoint service from Step 5
7. Confirm
8. Click **Allow Connection** on the endpoint row
9. Wait for status **Connected**

## Step 7: Get Endpoint Domain

1. Click the **Endpoint ID** in the private connection panel
2. Copy the endpoint domain for use in reindex configuration

## Step 8: Test with Reindex

### Configure reindex whitelist on ES_1

In ES_1 instance → **Cluster Configuration** → **YML Config** → **Modify**:

```
reindex.remote.whitelist: ["<endpoint_domain>:9200"]
```

Save and wait for the cluster to restart.

### Run reindex

Use `http://` or `https://` matching ES_2's protocol configuration:

```json
POST _reindex
{
  "source": {
    "remote": {
      "host": "http://<endpoint_domain>:9200",
      "username": "elastic",
      "password": "<ES_2_password>"
    },
    "index": "source_index"
  },
  "dest": {
    "index": "dest_index"
  }
}
```

> If ES_2 has HTTPS enabled, use `"host": "https://<endpoint_domain>:9200"` instead.

### Verify

```json
GET dest_index/_count
```

Compare document count with ES_2's source index.

### Large index migration tips

For large indices, use sliced scroll for parallelism:

```json
POST _reindex?slices=5&wait_for_completion=false
{
  "source": {
    "remote": {
      "host": "http://<endpoint_domain>:9200",
      "username": "elastic",
      "password": "<ES_2_password>"
    },
    "index": "source_index"
  },
  "dest": {
    "index": "dest_index"
  }
}
```

Monitor progress with:

```json
GET _tasks?detailed=true&actions=*reindex
```
