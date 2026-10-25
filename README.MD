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
kustomization.yaml    the list of manifests, the deployed image tags, and how cluster.env fills the manifests
cluster.env           the cluster's values: region, cluster, bucket, IAM role, domain, certificate, allowed addresses
namespace.yaml        the virology-lab namespace
operators/            SecretStore + ExternalSecret (database connection and application keys)
backend/              ServiceAccount (IRSA), ConfigMap, Deployment, Service
frontend/             Deployment, Service
ingress.yaml          ALB: HTTPS (ACM), /api → backend, / → frontend, optional source-address allow-list
deploy.ps1            apply by hand and point the domain at the ALB
```

Values known only after the infrastructure exists live once, in `cluster.env` (taken from `terraform output`). The
manifests name them in capitals (for example `FILES_BUCKET`, `CERTIFICATE_ARN`) and Kustomize replaces them while
building; `kubectl kustomize .` shows the result without applying it.

## Deployment

### Automatic (every release)

A merge to `master` in the app repository runs its CI/CD: tests, a version tag (`v1.2.3`), both images pushed to ECR
under that tag, then a commit here setting the tag in `kustomization.yaml` (`deploy v1.2.3`), `kubectl apply -k .` and
a wait for the rollout. The history of this repository is therefore the history of what ran in the cluster; going
back to an earlier release means setting its tag here and applying.

### By hand

For the first deployment, the DNS records, or a change made here (for example in `cluster.env`).
Prerequisites: `aws sso login`, a completed `terraform apply` in the infra repository, the application keys stored in
the `<prefix>/gemini` secret (see the infra README), and `kubectl`.

```powershell
.\deploy.ps1 -InfraDir ..\virology-lab-hackathon-infra
```

The script applies the manifests, waits for the rollout, then points the domain and `www` at the ALB with Route 53
ALIAS records and prints the address.

## Production readiness

- [x] HTTPS on a custom domain with an auto-renewing ACM certificate; HTTP redirected to HTTPS
- [x] Login screen with a one-time code; every API call requires a session
- [x] Secrets only in AWS Secrets Manager; least-privilege IAM for S3
- [x] Private, backed-up database; versioned, encrypted file storage
- [ ] Mail delivery for login codes configured (SMTP) and `AUTH_DEMO_CODE` removed
- [ ] `AUTH_COOKIE_SECURE=true` once the site is served over HTTPS only
- [ ] Data-processing review for page images sent to the AI providers
