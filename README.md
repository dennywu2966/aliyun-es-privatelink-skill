# aliyun-es-privatelink-skill

Claude Code skill for configuring Aliyun Elasticsearch PrivateLink connections.

## What it does

Guides you through setting up private network connectivity for Aliyun ES instances
created after October 2020, which use a new network architecture that restricts
Watcher, reindex, LDAP, and AD auth features.

## Scenarios

| Scenario | LB Type | Use Cases |
|---|---|---|
| ES → ECS | CLB (private) | Watcher webhooks, LDAP/AD auth, custom plugin dictionaries, reindex from self-managed ES |
| ES → ES | NLB (private, IP type) | Cross-cluster reindex, ES migration between Aliyun instances |

## Installation

### As a shared skill (recommended)

```bash
# Clone into your Claude Code skills directory
git clone https://github.com/dennywu2966/aliyun-es-privatelink-skill.git \
  ~/.claude/skills/aliyun-es-privatelink
```

### As a project skill

```bash
# Clone into your project's .claude/skills directory
git clone https://github.com/dennywu2966/aliyun-es-privatelink-skill.git \
  .claude/skills/aliyun-es-privatelink
```

## Usage

Once installed, trigger the skill in Claude Code with natural language:

- "configure ES privatelink"
- "set up private connection for ES"
- "ES to ECS connectivity via PrivateLink"
- "cross-cluster reindex between two Aliyun ES instances"

## Structure

```
├── SKILL.md                              # Main skill file (overview, inputs, steps, verification)
├── references/
│   ├── clb-es-to-ecs.md                  # ES→ECS step-by-step (CLB + PrivateLink)
│   └── nlb-es-to-es.md                   # ES→ES step-by-step (NLB + PrivateLink)
└── scripts/
    └── test_privatelink_connectivity.sh  # Connectivity verification (DNS, TCP, HTTP, reindex)
```

## Verification Script

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

Run `--help` for all options.
