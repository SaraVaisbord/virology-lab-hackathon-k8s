# Kubernetes – מערכת אימות טפסי התחייבות (המעבדה המרכזית לנגיפים)

קובצי Kubernetes להרצת [virology-lab-hackathon-app](https://github.com/SaraVaisbord/virology-lab-hackathon-app) על אשכול EKS שמוקם ב-[virology-lab-hackathon-infra](https://github.com/SaraVaisbord/virology-lab-hackathon-infra).

> **סטטוס:** הקבצים הועתקו מאפליקציה קודמת ועדיין **מותאמים** – ראו "מה נשאר להתאים" למטה. לא לפרוס לפני כן.

## ארכיטקטורה מתוכננת

```
אינטרנט → ALB → /      → frontend (nginx, קבצי React)
              → /api   → backend (FastAPI: OCR, ברקודים, Gemini, תור עיבוד)
                              └─ דיסק קבוע (EBS gp3): מסד הנתונים + תמונות העמודים
```

- **frontend** – nginx שמגיש את הממשק (פורט 80).
- **backend** – FastAPI (פורט 8000), עותק אחד: תור העיבוד רץ בתוך התהליך, והמסד הוא SQLite על הדיסק הקבוע.
- **סודות** – מפתחות Gemini מ-AWS Secrets Manager דרך External Secrets.

## מבנה

```
namespace.yaml
ingress.yaml           ALB: / → frontend, /api → backend
backend/               Deployment, Service, ConfigMap, kustomization (תמונת ECR)
frontend/              Deployment, Service, kustomization (תמונת ECR)
operators/             SecretStore + ExternalSecret (AWS Secrets Manager)
db/                    MySQL של האפליקציה הקודמת – יוסר
```

## פריסה (אחרי ההתאמות)

```bash
kubectl apply -f namespace.yaml
kubectl apply -f operators/
kubectl apply -k backend/
kubectl apply -k frontend/
kubectl apply -f ingress.yaml
```

## מה נשאר להתאים

- [ ] **דיסק קבוע ל-backend** – PersistentVolumeClaim (gp3) שמחובר ל-`/app/data`; בלעדיו הנתונים נמחקים בכל הפעלה מחדש.
- [ ] **הסרת `db/`** (MySQL והטבלה `people` שייכים לאפליקציה הקודמת).
- [ ] **ConfigMap ו-Secret** – `APP_DATA_DIR`, `LLM_ENABLED`, `WORKER_ENABLED`, `CORS_ORIGINS` ומפתחות `GEMINI_API_KEY*` במקום פרטי MySQL.
- [ ] **משאבים** – ל-backend לפחות 1.5–2Gi זיכרון ומעבד אחד (כרגע 256Mi / 0.2).
- [ ] **בדיקת תקינות** – `/api/health` במקום `/api`.
- [ ] **נתיבים** – קידומת `/api` ב-backend, ובניית ה-frontend עם `VITE_API_BASE_URL=/api`.
- [ ] **תמונות ECR** – שמות ותגיות של האפליקציה הזו ב-`kustomization.yaml`.
- [ ] **הגבלת גישה ל-ALB** – `alb.ingress.kubernetes.io/inbound-cidrs` (אין עדיין מסך כניסה במערכת).
