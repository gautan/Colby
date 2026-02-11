# Redis High Availability with Amazon ElastiCache Global Datastore

## Overview

Amazon ElastiCache Global Datastore provides fully managed cross-region replication for Redis. It enables low-latency reads in multiple AWS regions and disaster recovery with promotion of a secondary region to primary in under two minutes.

Key capabilities:

- **Cross-region replication** — Asynchronous replication from a primary region to up to two secondary regions
- **Sub-millisecond reads** — Each region serves reads from local replicas
- **Disaster recovery** — A secondary region can be promoted to primary if the primary region becomes unavailable
- **Encryption** — In-transit and at-rest encryption across regions

## Architecture

```
                        Async Replication
   Primary Region ──────────────────────────► Secondary Region
   (us-east-1)                                (us-west-2)

 ┌──────────────────┐                      ┌──────────────────┐
 │  ElastiCache     │                      │  ElastiCache     │
 │  Replication     │                      │  Replication     │
 │  Group           │                      │  Group           │
 │                  │                      │                  │
 │  ┌────────────┐  │                      │  ┌────────────┐  │
 │  │  Primary   │  │   ── async rep ──►   │  │  Replica    │  │
 │  │  (R/W)     │  │                      │  │  (R/O)      │  │
 │  └────────────┘  │                      │  └────────────┘  │
 │  ┌────────────┐  │                      │  ┌────────────┐  │
 │  │  Replica   │  │                      │  │  Replica    │  │
 │  │  (R/O)     │  │                      │  │  (R/O)      │  │
 │  └────────────┘  │                      │  └────────────┘  │
 └──────────────────┘                      └──────────────────┘
         │                                          │
         ▼                                          ▼
 ┌──────────────────┐                      ┌──────────────────┐
 │  Route 53        │                      │  Route 53        │
 │  Failover Primary│                      │  Failover        │
 │  redis.internal  │                      │  Secondary       │
 └──────────────────┘                      └──────────────────┘
```

Applications connect to `redis.internal` (a Route 53 private hosted zone record). Under normal operation this resolves to the primary region endpoint. On failure, Route 53 fails over to the secondary region endpoint.

## Setup

### Prerequisites

- AWS CLI v2 configured with appropriate credentials
- Two VPCs (one per region) with private subnets
- Subnet groups created in each region for ElastiCache

### 1. Create the Primary Replication Group

```bash
aws elasticache create-replication-group \
  --replication-group-id redis-primary \
  --replication-group-description "Primary Redis cluster" \
  --engine redis \
  --engine-version 7.0 \
  --cache-node-type cache.r7g.large \
  --num-cache-clusters 2 \
  --automatic-failover-enabled \
  --multi-az-enabled \
  --at-rest-encryption-enabled \
  --transit-encryption-enabled \
  --cache-subnet-group-name redis-subnet-group \
  --security-group-ids sg-xxxxxxxx \
  --region us-east-1
```

Wait for the replication group to become `available`:

```bash
aws elasticache describe-replication-groups \
  --replication-group-id redis-primary \
  --region us-east-1 \
  --query "ReplicationGroups[0].Status"
```

### 2. Create the Global Datastore

```bash
aws elasticache create-global-replication-group \
  --global-replication-group-id-suffix my-global-redis \
  --primary-replication-group-id redis-primary \
  --region us-east-1
```

### 3. Add the Secondary Region

```bash
aws elasticache create-replication-group \
  --replication-group-id redis-secondary \
  --replication-group-description "Secondary Redis cluster" \
  --global-replication-group-id ldgnf-my-global-redis \
  --num-cache-clusters 2 \
  --cache-node-type cache.r7g.large \
  --cache-subnet-group-name redis-subnet-group \
  --security-group-ids sg-yyyyyyyy \
  --region us-west-2
```

> **Note:** The `global-replication-group-id` is prefixed by a region identifier (e.g., `ldgnf-`). Retrieve it from `describe-global-replication-groups`.

## HA Layers

| Failure Scenario | Recovery Mechanism | Expected Downtime |
|---|---|---|
| **Node failure** | ElastiCache automatic failover promotes a read replica within the same AZ or another AZ | ~30 seconds |
| **AZ failure** | Multi-AZ enabled; replica in another AZ is promoted automatically | ~30 seconds |
| **Region failure** | Global Datastore promotion of secondary region + Route 53 DNS failover | ~1-2 minutes |

## Route 53 DNS-Based Failover

ElastiCache endpoints are inside a VPC and cannot be health-checked directly by Route 53. The solution uses a Lambda function as a health probe, publishing results to CloudWatch, which Route 53 can evaluate.

### Architecture

```
Lambda (runs every 30s)
   │
   ├──► Connect to ElastiCache primary endpoint
   │    Run PING + SET/GET test
   │
   └──► Publish custom CloudWatch metric
        Namespace: Custom/Redis
        Metric: HealthCheckStatus (1 = healthy, 0 = unhealthy)
              │
              ▼
        CloudWatch Alarm
        (threshold: < 1 for 2 consecutive periods)
              │
              ▼
        Route 53 Health Check
        (type: CLOUDWATCH_METRIC)
              │
              ▼
        Route 53 Failover Record Set
        redis.internal → primary or secondary endpoint
```

### 1. Create the Private Hosted Zone

```bash
aws route53 create-hosted-zone \
  --name internal \
  --vpc VPCRegion=us-east-1,VPCId=vpc-xxxxxxxx \
  --caller-reference "$(date +%s)" \
  --hosted-zone-config PrivateZone=true
```

Associate the secondary region VPC with the same hosted zone:

```bash
aws route53 associate-vpc-with-hosted-zone \
  --hosted-zone-id Z1234567890 \
  --vpc VPCRegion=us-west-2,VPCId=vpc-yyyyyyyy
```

### 2. Deploy the Lambda Health Checker

Create a Lambda function in the primary region VPC that connects to the ElastiCache primary endpoint and publishes a custom CloudWatch metric.

```python
# lambda_function.py
import boto3
import redis
import os
import time

cloudwatch = boto3.client("cloudwatch")

REDIS_HOST = os.environ["REDIS_HOST"]
REDIS_PORT = int(os.environ.get("REDIS_PORT", 6379))
NAMESPACE = "Custom/Redis"
METRIC_NAME = "HealthCheckStatus"


def lambda_handler(event, context):
    healthy = 0
    try:
        r = redis.Redis(
            host=REDIS_HOST,
            port=REDIS_PORT,
            ssl=True,
            socket_connect_timeout=5,
            socket_timeout=5,
        )
        # PING test
        if not r.ping():
            raise Exception("PING failed")

        # Write/read test
        test_key = f"healthcheck:{int(time.time())}"
        r.set(test_key, "ok", ex=60)
        val = r.get(test_key)
        if val != b"ok":
            raise Exception("SET/GET verification failed")

        healthy = 1
    except Exception as e:
        print(f"Health check failed: {e}")

    cloudwatch.put_metric_data(
        Namespace=NAMESPACE,
        MetricData=[
            {
                "MetricName": METRIC_NAME,
                "Value": healthy,
                "Unit": "None",
            }
        ],
    )

    return {"healthy": healthy}
```

Schedule this Lambda to run every 30 seconds using an EventBridge rule (or two rules at 1-minute intervals offset by 30 seconds, since EventBridge minimum interval is 1 minute):

```bash
# Rule 1: every minute
aws events put-rule \
  --name redis-health-check \
  --schedule-expression "rate(1 minute)" \
  --region us-east-1

aws events put-targets \
  --rule redis-health-check \
  --targets "Id"="1","Arn"="arn:aws:lambda:us-east-1:123456789012:function:redis-health-check"
```

> **Tip:** For sub-minute resolution, use an EventBridge rule that invokes a Step Functions state machine with a 30-second Wait state, calling Lambda twice per minute.

### 3. Create the CloudWatch Alarm

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name redis-primary-unhealthy \
  --namespace Custom/Redis \
  --metric-name HealthCheckStatus \
  --statistic Minimum \
  --period 60 \
  --evaluation-periods 2 \
  --threshold 1 \
  --comparison-operator LessThanThreshold \
  --treat-missing-data breaching \
  --region us-east-1
```

This alarm enters `ALARM` state if the health check metric is below 1 for two consecutive 60-second periods (~2 minutes of unhealthy state).

### 4. Create the Route 53 Health Check

```bash
aws route53 create-health-check \
  --caller-reference "redis-cw-$(date +%s)" \
  --health-check-config '{
    "Type": "CLOUDWATCH_METRIC",
    "Inverted": false,
    "CloudWatchAlarmConfiguration": {
      "EvaluationPeriods": 2,
      "Threshold": 1,
      "ComparisonOperator": "LessThanThreshold",
      "Period": 60,
      "MetricName": "HealthCheckStatus",
      "Namespace": "Custom/Redis",
      "Statistic": "Minimum"
    },
    "InsufficientDataHealthStatus": "Unhealthy"
  }'
```

> **Note:** The Route 53 health check must be created in `us-east-1` regardless of the alarm's region, since Route 53 is a global service that reads CloudWatch alarms from `us-east-1`.

### 5. Create the Failover DNS Records

```bash
# Primary record (active when health check passes)
aws route53 change-resource-record-sets \
  --hosted-zone-id Z1234567890 \
  --change-batch '{
    "Changes": [{
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "redis.internal",
        "Type": "CNAME",
        "SetIdentifier": "primary",
        "Failover": "PRIMARY",
        "TTL": 10,
        "ResourceRecords": [{"Value": "redis-primary.xxxxxx.use1.cache.amazonaws.com"}],
        "HealthCheckId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
      }
    }]
  }'

# Secondary record (used when primary health check fails)
aws route53 change-resource-record-sets \
  --hosted-zone-id Z1234567890 \
  --change-batch '{
    "Changes": [{
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "redis.internal",
        "Type": "CNAME",
        "SetIdentifier": "secondary",
        "Failover": "SECONDARY",
        "TTL": 10,
        "ResourceRecords": [{"Value": "redis-secondary.xxxxxx.usw2.cache.amazonaws.com"}]
      }
    }]
  }'
```

The TTL is set to 10 seconds to minimize stale DNS cache entries during failover.

## Failover Procedure

When a region-level failure is detected:

### 1. Promote the Secondary Region

```bash
aws elasticache failover-global-replication-group \
  --global-replication-group-id ldgnf-my-global-redis \
  --primary-region us-west-2 \
  --primary-replication-group-id redis-secondary \
  --region us-east-1
```

This makes the secondary cluster the new primary (read/write). The operation typically completes in under 1 minute.

### 2. DNS Failover

If the Route 53 health check is configured as described above, DNS failover happens automatically when the CloudWatch alarm enters `ALARM` state. No manual DNS changes are needed.

### Expected Timeline

| Step | Time |
|---|---|
| Failure occurs | T+0 |
| Lambda detects failure (next invocation) | T+0 to T+30s |
| CloudWatch alarm triggers (2 evaluation periods) | T+~2 min |
| Route 53 detects unhealthy health check | T+~2.5 min |
| DNS propagation (TTL = 10s) | T+~2.5 min |
| Applications reconnect to secondary | T+~2.5-3 min |

## Reducing Failover Time

| Knob | Default | Aggressive | Impact |
|---|---|---|---|
| Lambda invocation interval | 60s | 30s (via Step Functions) | Faster detection |
| CloudWatch alarm evaluation periods | 2 | 1 | Faster alarm, higher false-positive risk |
| CloudWatch alarm period | 60s | 30s (requires high-resolution metrics) | Faster alarm |
| Route 53 DNS TTL | 10s | 5s | Faster DNS propagation, more DNS queries |
| Application connection timeout | varies | 3-5s | Faster reconnect after failover |

With aggressive settings, total failover time can be reduced to approximately **60-90 seconds**. Weigh this against the increased risk of false positives triggering unnecessary failovers.

## Application Integration

### Connecting via DNS

Applications should connect to the Route 53 DNS name rather than directly to ElastiCache endpoints:

```
redis.internal:6379
```

### Retry Logic

Applications must handle transient connection errors during failover:

```python
import redis
from redis.backoff import ExponentialBackoff
from redis.retry import Retry

retry = Retry(ExponentialBackoff(cap=10, base=0.5), retries=5)

client = redis.Redis(
    host="redis.internal",
    port=6379,
    ssl=True,
    retry=retry,
    retry_on_error=[
        redis.exceptions.ConnectionError,
        redis.exceptions.TimeoutError,
    ],
    socket_connect_timeout=5,
    socket_timeout=5,
)
```

### Eventual Consistency

Global Datastore uses asynchronous replication. During normal operation, replication lag is typically under 1 second but can increase under heavy write load or network issues. After failover to a secondary region:

- Recently written data may not be present on the promoted secondary
- Applications should tolerate missing keys gracefully (cache-miss pattern)
- Check `ReplicationLag` CloudWatch metric to monitor lag during normal operation

## Kubernetes (EKS) Integration

### Option 1: ExternalName Service

Create a Kubernetes Service that resolves to the Route 53 DNS name:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: default
spec:
  type: ExternalName
  externalName: redis.internal
```

Applications use `redis.default.svc.cluster.local` (or just `redis`) which resolves to the Route 53 failover record.

> **Note:** ExternalName services use a CNAME redirect. Some Redis clients may not follow CNAME chains correctly. Test with your specific client library. If there are issues, use Option 2.

### Option 2: ConfigMap with Endpoint

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: redis-config
  namespace: default
data:
  REDIS_HOST: "redis.internal"
  REDIS_PORT: "6379"
  REDIS_SSL: "true"
```

Reference from a deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
        - name: app
          image: my-app:latest
          envFrom:
            - configMapRef:
                name: redis-config
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 256Mi
```

### DNS Resolution in EKS

Ensure the EKS cluster VPC is associated with the Route 53 private hosted zone so that pods can resolve `redis.internal`:

```bash
aws route53 associate-vpc-with-hosted-zone \
  --hosted-zone-id Z1234567890 \
  --vpc VPCRegion=us-east-1,VPCId=vpc-eks-xxxxxxxx
```

Also verify that `enableDnsSupport` and `enableDnsHostnames` are enabled on the VPC.

## Monitoring

### Key CloudWatch Metrics

| Metric | Namespace | Description | Alert Threshold |
|---|---|---|---|
| `ReplicationLag` | AWS/ElastiCache | Async replication lag to secondary (seconds) | > 5s |
| `EngineCPUUtilization` | AWS/ElastiCache | Redis engine CPU usage | > 80% |
| `DatabaseMemoryUsagePercentage` | AWS/ElastiCache | Memory usage as % of max | > 80% |
| `CurrConnections` | AWS/ElastiCache | Current client connections | > 80% of `maxclients` |
| `HealthCheckStatus` | Custom/Redis | Lambda health checker result | < 1 |
| `Evictions` | AWS/ElastiCache | Keys evicted due to memory pressure | > 0 sustained |

### Alerting Example

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name redis-replication-lag-high \
  --namespace AWS/ElastiCache \
  --metric-name ReplicationLag \
  --dimensions Name=CacheClusterId,Value=redis-secondary-001 \
  --statistic Maximum \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 5 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions arn:aws:sns:us-east-1:123456789012:redis-alerts
```

## Terraform Examples

### ElastiCache Global Datastore

```hcl
resource "aws_elasticache_global_replication_group" "this" {
  global_replication_group_id_suffix = "my-global-redis"
  primary_replication_group_id       = aws_elasticache_replication_group.primary.id
}

resource "aws_elasticache_replication_group" "primary" {
  provider                   = aws.us_east_1
  replication_group_id       = "redis-primary"
  description                = "Primary Redis cluster"
  engine                     = "redis"
  engine_version             = "7.0"
  node_type                  = "cache.r7g.large"
  num_cache_clusters         = 2
  automatic_failover_enabled = true
  multi_az_enabled           = true
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  subnet_group_name          = aws_elasticache_subnet_group.primary.name
  security_group_ids         = [aws_security_group.redis_primary.id]
}

resource "aws_elasticache_replication_group" "secondary" {
  provider                       = aws.us_west_2
  replication_group_id           = "redis-secondary"
  description                    = "Secondary Redis cluster"
  global_replication_group_id    = aws_elasticache_global_replication_group.this.global_replication_group_id
  num_cache_clusters             = 2
  node_type                      = "cache.r7g.large"
  subnet_group_name              = aws_elasticache_subnet_group.secondary.name
  security_group_ids             = [aws_security_group.redis_secondary.id]
}
```

### Route 53 Failover with Health Check

```hcl
resource "aws_route53_zone" "internal" {
  name = "internal"

  vpc {
    vpc_id     = var.primary_vpc_id
    vpc_region = "us-east-1"
  }
}

resource "aws_route53_zone_association" "secondary" {
  zone_id = aws_route53_zone.internal.zone_id
  vpc_id  = var.secondary_vpc_id
  vpc_region = "us-west-2"
}

resource "aws_cloudwatch_metric_alarm" "redis_health" {
  provider            = aws.us_east_1
  alarm_name          = "redis-primary-unhealthy"
  namespace           = "Custom/Redis"
  metric_name         = "HealthCheckStatus"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
}

resource "aws_route53_health_check" "redis_primary" {
  type                            = "CLOUDWATCH_METRIC"
  cloudwatch_alarm_name           = aws_cloudwatch_metric_alarm.redis_health.alarm_name
  cloudwatch_alarm_region         = "us-east-1"
  insufficient_data_health_status = "Unhealthy"
}

resource "aws_route53_record" "redis_primary" {
  zone_id = aws_route53_zone.internal.zone_id
  name    = "redis.internal"
  type    = "CNAME"
  ttl     = 10

  failover_routing_policy {
    type = "PRIMARY"
  }

  set_identifier  = "primary"
  records         = [aws_elasticache_replication_group.primary.primary_endpoint_address]
  health_check_id = aws_route53_health_check.redis_primary.id
}

resource "aws_route53_record" "redis_secondary" {
  zone_id = aws_route53_zone.internal.zone_id
  name    = "redis.internal"
  type    = "CNAME"
  ttl     = 10

  failover_routing_policy {
    type = "SECONDARY"
  }

  set_identifier = "secondary"
  records        = [aws_elasticache_replication_group.secondary.primary_endpoint_address]
}
```

### Lambda Health Checker

```hcl
resource "aws_lambda_function" "redis_health_check" {
  provider      = aws.us_east_1
  function_name = "redis-health-check"
  runtime       = "python3.12"
  handler       = "lambda_function.lambda_handler"
  timeout       = 30
  filename      = data.archive_file.lambda.output_path

  vpc_config {
    subnet_ids         = var.primary_private_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      REDIS_HOST = aws_elasticache_replication_group.primary.primary_endpoint_address
      REDIS_PORT = "6379"
    }
  }

  role = aws_iam_role.lambda_health_check.arn
}

resource "aws_cloudwatch_event_rule" "redis_health_check" {
  provider            = aws.us_east_1
  name                = "redis-health-check"
  schedule_expression = "rate(1 minute)"
}

resource "aws_cloudwatch_event_target" "redis_health_check" {
  provider = aws.us_east_1
  rule     = aws_cloudwatch_event_rule.redis_health_check.name
  arn      = aws_lambda_function.redis_health_check.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  provider      = aws.us_east_1
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.redis_health_check.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.redis_health_check.arn
}
```
