# K8S People Management

Kubernetes manifests for a 3-tier people management application on AWS EKS.

## Architecture

```
Internet → ALB → Frontend → Backend → MySQL
```

- **Frontend**: Nginx serving static files (port 80)
- **Backend**: REST API (port 8000)
- **Database**: MySQL 8.0 (port 3306)

## Prerequisites

- AWS EKS cluster
- [External Secrets Operator](https://external-secrets.io/) installed
- AWS Secrets Manager secret at `people-mgnt-PeopleManagement/db-pass` with keys:
  - `DB_USER`
  - `DB_PASSWORD`
  - `MYSQL_ROOT_PASSWORD`

## Deployment

```bash
kubectl apply -f namespace.yaml
kubectl apply -f operators/
kubectl apply -f db/
kubectl apply -f backend/
kubectl apply -f frontend/
kubectl apply -f ingress.yaml
```

## Configuration

Database connection is configured via ConfigMap (`app-config`) and Secret (`app-secret`):

- **Host**: `mysql`
- **Port**: `3306`
- **Database**: `peopledb`

Credentials are synced from AWS Secrets Manager every hour.

## Access

The application is exposed via AWS ALB Ingress:

- `/` → Frontend
- `/api` → Backend API

## Database Schema

The `people` table includes:
- `id`, `name`, `role`, `email`, `status`, `join_date`, `department`, `avatar`

Schema is initialized automatically on first deployment.
