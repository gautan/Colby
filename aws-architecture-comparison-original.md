# AWS Architecture Comparison
## Route53 → API Gateway vs Route53 → ALB → Spring Cloud Gateway

---

## Table of Contents
1. [Architecture Diagrams](#architecture-diagrams)
2. [Component Comparison](#component-comparison)
3. [Cost Analysis](#cost-analysis)
4. [Performance](#performance)
5. [Features](#features)
6. [Regional Failover](#regional-failover)
7. [Recommendation](#recommendation)

---

## Architecture Diagrams

### Option 1: API Gateway + VPC Link

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                                 AWS Region                                   │
│                                                                              │
│   ┌──────────────────────────────────────────────────────────────────────┐   │
│   │                              VPC                                     │   │
│   │                                                                      │   │
│   │   ┌───────────────┐         ┌─────────────────────────────────────┐ │   │
│   │   │               │         │              EKS                    │ │   │
│   │   │      NLB      │────────▶│   ┌───────┐  ┌───────┐  ┌───────┐  │ │   │
│   │   │  (VPC Link)   │         │   │  Pod  │  │  Pod  │  │  Pod  │  │ │   │
│   │   │               │         │   └───────┘  └───────┘  └───────┘  │ │   │
│   │   └───────────────┘         └─────────────────────────────────────┘ │   │
│   │           ▲                                                         │   │
│   └───────────│─────────────────────────────────────────────────────────┘   │
│               │                                                              │
│               │ VPC Link                                                     │
│               │                                                              │
│       ┌───────┴───────┐                                                      │
│       │  API Gateway  │                                                      │
│       │    (HTTP)     │                                                      │
│       └───────────────┘                                                      │
│               ▲                                                              │
└───────────────│──────────────────────────────────────────────────────────────┘
                │
        ┌───────┴───────┐
        │   Route 53    │
        └───────────────┘
                ▲
                │
        ┌───────┴───────┐
        │     Users     │
        └───────────────┘
```

**Components:**
- **Route53**: DNS routing and health checks
- **API Gateway**: HTTP API (regional endpoint)
- **VPC Link**: Private connection into VPC
- **NLB**: Network Load Balancer (target for VPC Link)
- **EKS**: Kubernetes pods running microservices

---

### Option 2: ALB + Spring Cloud Gateway

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                                 AWS Region                                   │
│                                                                              │
│   ┌──────────────────────────────────────────────────────────────────────┐   │
│   │                              VPC                                     │   │
│   │                                                                      │   │
│   │   ┌─────────┐    ┌─────────────────────┐    ┌─────────────────────┐ │   │
│   │   │         │    │   EKS (Gateway)     │    │    EKS (Backend)    │ │   │
│   │   │   ALB   │───▶│  ┌───────────────┐  │───▶│  ┌───────┐          │ │   │
│   │   │         │    │  │ Spring Cloud  │  │    │  │  Pod  │          │ │   │
│   │   │         │    │  │   Gateway     │  │    │  └───────┘          │ │   │
│   │   │         │    │  └───────────────┘  │    │  ┌───────┐          │ │   │
│   │   │         │    │  ┌───────────────┐  │    │  │  Pod  │          │ │   │
│   │   │         │    │  │ Spring Cloud  │  │    │  └───────┘          │ │   │
│   │   │         │    │  │   Gateway     │  │    │  ┌───────┐          │ │   │
│   │   │         │    │  └───────────────┘  │    │  │  Pod  │          │ │   │
│   │   └─────────┘    └─────────────────────┘    │  └───────┘          │ │   │
│   │                            │                └─────────────────────┘ │   │
│   │                            │                                        │   │
│   │                            ▼                                        │   │
│   │                    ┌───────────────┐                                │   │
│   │                    │    Lambda     │  (Optional)                    │   │
│   │                    └───────────────┘                                │   │
│   │                                                                      │   │
│   └──────────────────────────────────────────────────────────────────────┘   │
│               ▲                                                              │
└───────────────│──────────────────────────────────────────────────────────────┘
                │
        ┌───────┴───────┐
        │   Route 53    │
        └───────────────┘
                ▲
                │
        ┌───────┴───────┐
        │     Users     │
        └───────────────┘
```

**Components:**
- **Route53**: DNS routing and health checks
- **ALB**: Application Load Balancer (public-facing)
- **Spring Cloud Gateway**: API Gateway running in EKS (2+ replicas)
- **EKS Backend Pods**: Microservices
- **Lambda**: Optional serverless functions

---

## Component Comparison

| Aspect | API Gateway + VPC Link | ALB + Spring Cloud Gateway |
|--------|------------------------|----------------------------|
| **Components** | 2 (APIGW, VPC Link) | 3 (ALB, SCG, VPC Link) |
| **Managed Services** | Fully managed | ALB managed, SCG self-managed |
| **Operational Overhead** | Low | Medium (manage SCG pods) |
| **Infrastructure as Code** | Simple (fewer resources) | More complex |
| **Team Skills Required** | AWS knowledge | AWS + Java + Kubernetes + Spring |

---

## Cost Analysis

### Per-Request Pricing

| Factor | API Gateway | ALB + Spring Gateway |
|--------|-------------|---------------------|
| **Base Cost** | $3.50/million requests | ALB: ~$16/month + LCU charges |
| **Data Transfer** | $0.09/GB | $0.008/GB (significantly cheaper) |

### Monthly Cost Estimates

| Traffic Volume | API Gateway | ALB + Spring Gateway |
|----------------|-------------|---------------------|
| **10M requests/month** | ~$35 | ~$25-40 |
| **100M requests/month** | ~$350 | ~$50-80 |
| **500M requests/month** | ~$1,750 | ~$100-150 |
| **1B requests/month** | ~$3,500 | ~$150-300 |

**Verdict**: API Gateway is cheaper at low volume; ALB + Spring Gateway is significantly cheaper at high volume.

---

## Performance

| Metric | API Gateway | ALB + Spring Gateway |
|--------|-------------|---------------------|
| **Added Latency** | 10-30ms | 5-15ms (ALB) + 5-20ms (SCG) |
| **Cold Start** | None | None (if SCG pods are warmed) |
| **Max Throughput** | 10,000 req/sec (soft limit) | Scales with ALB + pod count |
| **Connection Limits** | Regional limits apply | Higher (ALB scales automatically) |
| **WebSocket Duration** | 2-hour limit | No limit |
| **Max Payload Size** | 10MB | Configurable (can be larger) |
| **HTTP/2 Support** | Yes | Yes |
| **gRPC Support** | HTTP/2 only | Full native support |

---

## Features

### Routing Capabilities

| Routing Type | API Gateway | Spring Cloud Gateway |
|--------------|-------------|---------------------|
| Path-based | Yes | Yes |
| Header-based | Yes (limited) | Yes (full control) |
| Query parameter | Yes | Yes |
| Method-based | Yes | Yes |
| Host-based | Yes | Yes |
| Weighted (A/B testing) | Yes (canary) | Yes |
| Cookie-based | No | Yes |
| Custom predicates | No | Yes (Java code) |
| Regex routes | Limited | Yes |

### Security Features

| Feature | API Gateway | ALB + Spring Gateway |
|---------|-------------|---------------------|
| **WAF Integration** | Yes (Native) | Yes (on ALB) |
| **DDoS Protection** | Shield (automatic) | Shield (on ALB) |
| **Private API** | VPC Endpoints | Private ALB |
| **IAM Authentication** | Yes (Native) | Custom implementation |
| **JWT Validation** | Lambda authorizer | Spring Security (native) |
| **OAuth2/OIDC** | Cognito integration | Spring Security (full control) |
| **API Keys** | Yes (Built-in) | Custom implementation |
| **IP Whitelisting** | Resource policy | ALB + Security Groups |
| **mTLS** | Supported | Supported |

### Resilience Features

| Feature | API Gateway | ALB + Spring Gateway |
|---------|-------------|---------------------|
| **Rate Limiting** | Built-in (usage plans) | Custom (Redis-backed) |
| **Circuit Breaker** | Not built-in | Resilience4j (built-in) |
| **Retry Logic** | Limited | Full control |
| **Timeout Handling** | Configurable | Full control |
| **Bulkhead Pattern** | Not available | Resilience4j |

### Request/Response Handling

| Feature | API Gateway | ALB + Spring Gateway |
|---------|-------------|---------------------|
| **Request Validation** | JSON Schema | Custom (any validation) |
| **Request Transform** | VTL templates (limited) | Full Java control |
| **Response Transform** | VTL templates (limited) | Full Java control |
| **Header Manipulation** | Limited | Full control |
| **Body Manipulation** | VTL (complex) | Java (simple) |

---

## Regional Failover

### Option 1: API Gateway Multi-Region Failover

```
                                         ┌─────────────────────────────────────┐
                                         │           Region A (Primary)        │
                                         │                                     │
                                         │  ┌─────────┐   ┌─────┐   ┌──────┐  │
                                    ┌───▶│  │   API   │──▶│ NLB │──▶│ EKS  │  │
                                    │    │  │ Gateway │   │     │   │ Pods │  │
                                    │    │  └─────────┘   └─────┘   └──────┘  │
┌───────┐    ┌─────────────────┐    │    │                                     │
│       │    │                 │    │    └─────────────────────────────────────┘
│ Users │───▶│    Route 53     │────┤
│       │    │   (Failover/    │    │    ┌─────────────────────────────────────┐
└───────┘    │    Latency)     │    │    │          Region B (Secondary)       │
             └─────────────────┘    │    │                                     │
                                    │    │  ┌─────────┐   ┌─────┐   ┌──────┐  │
                                    └───▶│  │   API   │──▶│ NLB │──▶│ EKS  │  │
                                         │  │ Gateway │   │     │   │ Pods │  │
                                         │  └─────────┘   └─────┘   └──────┘  │
                                         │                                     │
                                         └─────────────────────────────────────┘
```

**Failover Mechanism:**
- Route53 health checks monitor API Gateway endpoints
- Failover or latency-based routing policy
- Each region has independent API Gateway + VPC Link + EKS
- Failover time: 60-120 seconds (DNS TTL dependent)

---

### Option 2: ALB + Spring Gateway Multi-Region Failover

```
                                         ┌─────────────────────────────────────────────┐
                                         │              Region A (Primary)             │
                                         │                                             │
                                         │  ┌─────┐   ┌──────────┐   ┌──────────────┐ │
                                    ┌───▶│  │ ALB │──▶│ Spring   │──▶│ EKS Backend  │ │
                                    │    │  │     │   │ Cloud GW │   │    Pods      │ │
                                    │    │  └─────┘   └──────────┘   └──────────────┘ │
┌───────┐    ┌─────────────────┐    │    │                                             │
│       │    │                 │    │    └─────────────────────────────────────────────┘
│ Users │───▶│    Route 53     │────┤
│       │    │   (Failover/    │    │    ┌─────────────────────────────────────────────┐
└───────┘    │    Latency)     │    │    │             Region B (Secondary)            │
             └─────────────────┘    │    │                                             │
                                    │    │  ┌─────┐   ┌──────────┐   ┌──────────────┐ │
                                    └───▶│  │ ALB │──▶│ Spring   │──▶│ EKS Backend  │ │
                                         │  │     │   │ Cloud GW │   │    Pods      │ │
                                         │  └─────┘   └──────────┘   └──────────────┘ │
                                         │                                             │
                                         └─────────────────────────────────────────────┘
```

**Failover Mechanism:**
- Route53 health checks monitor ALB endpoints
- ALB health checks monitor Spring Gateway pods
- Spring Gateway health checks monitor backend services
- Multiple layers of health detection
- Failover time: 60-120 seconds (DNS TTL dependent)

---

### Option 3: Global Accelerator (Recommended for Fast Failover)

```
                                              ┌────────────────────────────────────┐
                                              │         Region A (Primary)         │
                                              │                                    │
                                         ┌───▶│  ALB ──▶ Spring GW ──▶ EKS Pods   │
                                         │    │                                    │
┌───────┐    ┌────────────────────┐      │    └────────────────────────────────────┘
│       │    │                    │      │
│ Users │───▶│  Global Accelerator│──────┤
│       │    │   (Anycast IPs)    │      │
└───────┘    └────────────────────┘      │    ┌────────────────────────────────────┐
                                         │    │        Region B (Secondary)        │
                                         │    │                                    │
                                         └───▶│  ALB ──▶ Spring GW ──▶ EKS Pods   │
                                              │                                    │
                                              └────────────────────────────────────┘
```

**Benefits:**
- Anycast IPs (static, no DNS propagation delay)
- Automatic failover in <30 seconds
- TCP/UDP optimization over AWS backbone
- Built-in DDoS protection

---

### Regional Failover Comparison

| Aspect | API Gateway | ALB + Spring Gateway |
|--------|-------------|---------------------|
| **Failover Time (Route53)** | 60-120s (DNS TTL) | 60-120s (DNS TTL) |
| **Failover Time (Global Accelerator)** | 10-30s | 10-30s |
| **Health Check Granularity** | API Gateway endpoint only | ALB → SCG → Backend (3 layers) |
| **Custom Health Logic** | Limited | Full control (Spring Actuator) |
| **State Replication** | DynamoDB Global Tables | DynamoDB / ElastiCache Global |
| **Database Failover** | Aurora Global Database | Aurora Global Database |
| **Session Continuity** | Limited | Redis Global Datastore |
| **Active-Active Support** | Yes | Yes |
| **Active-Passive Support** | Yes | Yes |

---

## Recommended Multi-Region Architecture

```
                                    ┌──────────────────┐
                                    │    CloudFront    │  (Optional: caching, WAF)
                                    └────────┬─────────┘
                                             │
                                    ┌────────▼─────────┐
                                    │      Global      │
                                    │   Accelerator    │
                                    └────────┬─────────┘
                           ┌─────────────────┴─────────────────┐
                           │                                   │
              ┌────────────▼────────────┐         ┌────────────▼────────────┐
              │       Region A          │         │       Region B          │
              │                         │         │                         │
              │  ┌─────┐  ┌──────────┐  │         │  ┌─────┐  ┌──────────┐  │
              │  │ ALB │─▶│Spring GW │  │         │  │ ALB │─▶│Spring GW │  │
              │  └─────┘  └────┬─────┘  │         │  └─────┘  └────┬─────┘  │
              │                │        │         │                │        │
              │         ┌──────▼──────┐ │         │         ┌──────▼──────┐ │
              │         │  EKS Pods   │ │         │         │  EKS Pods   │ │
              │         └──────┬──────┘ │         │         └──────┬──────┘ │
              │                │        │         │                │        │
              │         ┌──────▼──────┐ │         │         ┌──────▼──────┐ │
              │         │Aurora Global│◀├─────────┼────────▶│Aurora Global│ │
              │         │  (Writer)   │ │  Sync   │         │  (Reader)   │ │
              │         └─────────────┘ │         │         └─────────────┘ │
              │                         │         │                         │
              │  ┌─────────────────┐    │         │    ┌─────────────────┐  │
              │  │ElastiCache      │◀───┼─────────┼───▶│ElastiCache      │  │
              │  │Global Datastore │    │  Sync   │    │Global Datastore │  │
              │  └─────────────────┘    │         │    └─────────────────┘  │
              └─────────────────────────┘         └─────────────────────────┘
```

**Failover Flow:**
1. Global Accelerator detects ALB health failure (~10 seconds)
2. Traffic automatically routes to healthy region
3. Aurora Global Database promotes reader to writer (if primary region fails)
4. ElastiCache Global Datastore provides session continuity

---

## Recommendation

### Decision Matrix

| Scenario | Recommended Option |
|----------|-------------------|
| Startup / MVP / Low traffic | **API Gateway** |
| High traffic (>100M req/month) | **ALB + Spring Gateway** |
| Simple CRUD APIs | **API Gateway** |
| Complex routing/transformation | **ALB + Spring Gateway** |
| Heavy Lambda usage | **API Gateway** |
| Java/Spring team | **ALB + Spring Gateway** |
| Need circuit breakers | **ALB + Spring Gateway** |
| Minimal operations team | **API Gateway** |
| Multi-cloud strategy | **ALB + Spring Gateway** |
| Strict latency requirements | **ALB + Spring Gateway** |
| AWS-native, serverless-first | **API Gateway** |
| Fast regional failover required | **ALB + Spring Gateway + Global Accelerator** |

### Final Recommendation

**For Regional Failover: ALB + Spring Cloud Gateway + Global Accelerator**

| Factor | Why This Option Wins |
|--------|---------------------|
| **Faster Failover** | Global Accelerator bypasses DNS propagation delays |
| **Health Check Depth** | Multi-layer health checks (ALB → SCG → Backend) |
| **Custom Health Logic** | Spring Actuator can verify DB, cache, and all dependencies |
| **Circuit Breaker** | Resilience4j prevents cascading failures across regions |
| **Session Handling** | ElastiCache Global Datastore enables cross-region sessions |
| **Cost at Scale** | Significantly cheaper for high-traffic multi-region deployments |
| **Observability** | Better distributed tracing across regions |
| **Flexibility** | Full control over routing, transformation, and resilience patterns |

---

## Document Information

- **Created**: February 2026
- **Author**: Architecture Team
- **Version**: 1.0
