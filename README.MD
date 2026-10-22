# Kubernetes Deployment — Commitment Form Validation

Kubernetes manifests and a deployment script that run
[virology-lab-hackathon-app](https://github.com/SaraVaisbord/virology-lab-hackathon-app) on the EKS cluster
provisioned by [virology-lab-hackathon-infra](https://github.com/SaraVaisbord/virology-lab-hackathon-infra).

## Architecture

```
https://virolab.site  (Route 53 ALIAS → ALB; ACM certificate, HTTP redirected to HTTPS, TLS 1.2+)
   ├── /api/*  → backend   FastAPI — login, extraction queue, OCR, barcodes, Claude / Gemini
   │                ├── Amazon RDS PostgreSQL — dedicated, private, backed up
   │                └── Amazon S3 — private bucket for uploads and page images (never in the database)
   └── /       → frontend  nginx serving the React build

Secrets   AWS Secrets Manager → External Secrets Operator → Kubernetes Secret → backend environment
S3 access IAM role for the backend's service account (IRSA), scoped to the files bucket only
```

The backend keeps no state on its own disk: if the pod restarts, nothing is lost.

## Repository layout

```
namespace.yaml        the virology-lab namespace
operators/            SecretStore + ExternalSecret (database connection and application keys)
backend/              ServiceAccount (IRSA), ConfigMap, Deployment, Service
frontend/             Deployment, Service
ingress.yaml          ALB: HTTPS (ACM), /api → backend, / → frontend, optional source-address allow-list
deploy.ps1            build, push to ECR, render and apply the manifests, point the domain at the ALB
```

Values known only after the infrastructure exists appear as `${...}` placeholders (for example `${FILES_BUCKET}`,
`${CERTIFICATE_ARN}`); `deploy.ps1` fills them from `terraform output`.

## Deployment

Prerequisites: `aws sso login`, a completed `terraform apply` in the infra repository, the application keys stored in
the `<prefix>/gemini` secret (see the infra README), Docker running, and `kubectl`.

```powershell
.\deploy.ps1 -InfraDir ..\virology-lab-hackathon-infra -AppDir <path to the app repository>
```

The script:

1. reads the ECR repositories, bucket, IAM role, region, domain and certificate from `terraform output`;
2. builds both images and pushes them to ECR (`-SkipBuild` to reuse existing images);
3. renders the manifests, applies them and waits for the rollout;
4. points the domain and `www` at the ALB with Route 53 ALIAS records and prints the address.

| Parameter | Default | Purpose |
|---|---|---|
| `-AllowedCidrs` | this computer's public IP | Source addresses allowed through the ALB, comma-separated (`0.0.0.0/0` = everyone, behind the login screen) |
| `-LlmEnabled` | `true` | `false` runs only the local extraction stages (no AI tokens) |
| `-Tag` | current date and time | Image tag |
| `-SkipBuild` | off | Deploy without rebuilding the images |

## Production readiness

- [x] HTTPS on a custom domain with an auto-renewing ACM certificate; HTTP redirected to HTTPS
- [x] Login screen with a one-time code; every API call requires a session
- [x] Secrets only in AWS Secrets Manager; least-privilege IAM for S3
- [x] Private, backed-up database; versioned, encrypted file storage
- [ ] Mail delivery for login codes configured (SMTP) and `AUTH_DEMO_CODE` removed
- [ ] `AUTH_COOKIE_SECURE=true` once the site is served over HTTPS only
- [ ] Data-processing review for page images sent to the AI providers
