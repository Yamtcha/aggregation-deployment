# FinTrack Deployment

Helm-based Kubernetes deployment for the FinTrack platform. This repo contains four sub-charts deployed into a single `fintrack` namespace.

---

## Architecture Overview

```
                        [ Ingress: fintrack.local ]
                               |           |
                  /api, /swagger-ui    /transaction
                  /v3/api-docs              |
                        |                  |
               [ fintrack-api :8080 ]  [ transaction-aggregator :8083 ]
                        |                  |
                        +--------+---------+
                                 |
                    [ RabbitMQ :5672 ] <-- message bus
                    [ PostgreSQL :5432 ] <-- persistence
                         fintrack_api | fintrack_agg
```

### Services

| Chart | Kubernetes Name | Port | Description |
|---|---|---|---|
| `fintrack-service` | `fintrack-api` | 8080 | Core REST API (Spring Boot). Handles ingestion adapters (CREDIT, DEBIT, LOANS, INVESTMENTS) and exposes Swagger UI. |
| `transaction-aggregator-service` | `transaction-aggregator` | 8083 | Aggregation worker. Consumes transactions from RabbitMQ and persists them to the aggregator DB. |
| `database` | `postgres` | 5432 | PostgreSQL 16. Initialises two databases: `fintrack_api` and `fintrack_agg`. |
| `rabbitmq` | `rabbitmq` | 5672 / 15672 | RabbitMQ 3.13 with management UI. Acts as the message bus between the API and aggregator. |

Secrets (DB credentials, RabbitMQ credentials, API key) are synced from **AWS Secrets Manager** via the External Secrets Operator using the key `fintrack-analyses-secrets`.

---

## Prerequisites

| Tool | Minimum version |
|---|---|
| `kubectl` | 1.28+ |
| `helm` | 3.14+ |
| External Secrets Operator | installed in the cluster |
| NGINX Ingress Controller | installed in the cluster |
| AWS credentials | with read access to Secrets Manager in `eu-west-1` |

---

## Repository Structure

```
fintrack-helm/
  charts/
    fintrack-service/               # Core API chart
    transaction-aggregator-service/ # Aggregator chart
    database/                       # PostgreSQL StatefulSet
    rabbitmq/                       # RabbitMQ StatefulSet
  scripts/
    deploy.sh                       # Full deploy script
    validate.sh                     # Lint + template render check
```

---

## Getting Started

### 1. Validate charts (no cluster required)

Run lint and template rendering against all charts:

```bash
cd fintrack-helm
./scripts/validate.sh
```

If a cluster is reachable, the script will also run Helm dry-runs automatically.

### 2. Deploy to a cluster

Export your AWS credentials, then run the deploy script:

```bash
export AWS_ACCESS_KEY_ID=<your-access-key>
export AWS_SECRET_ACCESS_KEY=<your-secret-key>

cd fintrack-helm
./scripts/deploy.sh
```

The script will:
1. Create the `fintrack` namespace if it does not exist.
2. Create an `aws-credentials` Kubernetes secret used by the External Secrets Operator.
3. Deploy `fintrack-service` and wait for the `ExternalSecret` to become ready (secrets pulled from AWS).
4. Deploy `database` and `rabbitmq`, then wait for both StatefulSets to roll out.
5. Deploy `transaction-aggregator-service`.

Pass `--dry-run` to preview without applying:

```bash
./scripts/deploy.sh --dry-run
```

### 3. Deploy charts individually

Each chart can also be installed on its own with Helm directly.

**Infrastructure first:**

```bash
helm upgrade --install fintrack-database fintrack-helm/charts/database \
  --namespace fintrack --create-namespace

helm upgrade --install fintrack-rabbitmq fintrack-helm/charts/rabbitmq \
  --namespace fintrack
```

**Applications:**

```bash
helm upgrade --install fintrack-service fintrack-helm/charts/fintrack-service \
  --namespace fintrack

helm upgrade --install fintrack-aggregator fintrack-helm/charts/transaction-aggregator-service \
  --namespace fintrack
```

---

## Accessing Services

Add the ingress host to your local `/etc/hosts` (for local clusters such as kind or minikube):

```
127.0.0.1  fintrack.local
```

| Endpoint | URL |
|---|---|
| API | `http://fintrack.local/api` |
| Swagger UI | `http://fintrack.local/swagger-ui` |
| OpenAPI docs | `http://fintrack.local/v3/api-docs` |
| Transaction aggregator | `http://fintrack.local/transaction` |
| RabbitMQ management | Port-forward to pod: `kubectl port-forward svc/rabbitmq 15672:15672 -n fintrack` |

---

## Configuration

All tuneable values live in each chart's `values.yaml`. Key settings:

### fintrack-service

| Key | Default | Description |
|---|---|---|
| `app.image.tag` | `v10.0.0` | Docker image tag |
| `app.replicaCount` | `1` | Number of replicas |
| `app.ingestion.adaptersEnabled` | `CREDIT,DEBIT,LOANS,INVESTMENTS` | Active ingestion adapters |
| `app.jvmOptions` | `-XX:+UseZGC -Xms256m -Xmx512m` | JVM tuning flags |
| `ingress.host` | `fintrack.local` | Ingress hostname |
| `externalSecrets.awsRegion` | `eu-west-1` | AWS region for Secrets Manager |
| `externalSecrets.remoteSecret.key` | `fintrack-analyses-secrets` | AWS secret name |

### transaction-aggregator-service

| Key | Default | Description |
|---|---|---|
| `app.image.tag` | `v7.0.0` | Docker image tag |
| `app.replicaCount` | `1` | Number of replicas |
| `app.jvmOptions` | `-XX:+UseZGC -Xms256m -Xmx512m` | JVM tuning flags |

### database

| Key | Default | Description |
|---|---|---|
| `postgres.tag` | `16-alpine` | PostgreSQL image tag |
| `postgres.storage` | `5Gi` | Persistent volume size |
| `postgres.storageClassName` | `standard` | Storage class |

### rabbitmq

| Key | Default | Description |
|---|---|---|
| `rabbitmq.tag` | `3.13-management-alpine` | RabbitMQ image tag |
| `rabbitmq.storage` | `2Gi` | Persistent volume size |
| `rabbitmq.storageClassName` | `standard` | Storage class |

---

## Health Checks

Both application pods expose Spring Boot Actuator endpoints used for Kubernetes probes:

- **Readiness:** `GET /actuator/health/readiness`
- **Liveness:** `GET /actuator/health/liveness`

Check pod status:

```bash
kubectl get pods -n fintrack
kubectl describe pod <pod-name> -n fintrack
kubectl logs <pod-name> -n fintrack
```

---

## Secrets

Secrets are **not stored in this repo**. They are fetched at deploy time from AWS Secrets Manager by the External Secrets Operator. The following keys are expected in the `fintrack-analyses-secrets` AWS secret:

- `DB_URL`
- `DB_USERNAME`
- `DB_PASSWORD`
- `RABBITMQ_USERNAME`
- `RABBITMQ_PASSWORD`
- `API_KEY`
