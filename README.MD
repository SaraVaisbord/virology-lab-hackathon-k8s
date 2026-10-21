# Kubernetes – מערכת אימות טפסי התחייבות (המעבדה המרכזית לנגיפים)

קובצי Kubernetes להרצת [virology-lab-hackathon-app](https://github.com/SaraVaisbord/virology-lab-hackathon-app) על אשכול EKS שמוקם ב-[virology-lab-hackathon-infra](https://github.com/SaraVaisbord/virology-lab-hackathon-infra).

## ארכיטקטורה

```
אינטרנט (רק מכתובות מורשות) → ALB
   ├── /api/*  → backend (FastAPI: OCR, ברקודים, Gemini, תור עיבוד)
   │              ├── RDS PostgreSQL – שרת מסד נתונים נפרד, גיבוי יומי + שחזור לכל רגע ב-7 הימים האחרונים
   │              └── S3 – באקט פרטי ומוצפן לקבצים ולתמונות העמודים (לא במסד הנתונים)
   └── /       → frontend (nginx + React)

סודות (חיבור למסד, מפתחות Gemini) → AWS Secrets Manager → External Secrets → Secret ב-Kubernetes
גישת ה-backend ל-S3 → IAM role (IRSA) שמורשה רק לבאקט הזה
```

ה-backend לא שומר שום דבר על הדיסק שלו: אם הוא נופל או מופעל מחדש, שום נתון לא הולך לאיבוד.

## קבצים

```
namespace.yaml                  virology-lab
operators/                      SecretStore + ExternalSecret (מסד נתונים + מפתחות Gemini)
backend/                        ServiceAccount (IRSA), ConfigMap, Deployment, Service
frontend/                       Deployment, Service
ingress.yaml                    ALB: /api → backend, / → frontend, גישה רק מכתובות מורשות
deploy.ps1                      בנייה, דחיפה ל-ECR ופריסה
```

ערכים שנקבעים רק אחרי הקמת התשתית מופיעים בקבצים כ-`${...}` (למשל `${FILES_BUCKET}`), ו-`deploy.ps1` ממלא אותם מתוך `terraform output`.

## פריסה

אחרי `aws sso login` ו-`terraform apply` ב-[infra](https://github.com/SaraVaisbord/virology-lab-hackathon-infra), ואחרי הכנסת מפתחות Gemini לסוד `<prefix>/gemini`:

```powershell
.\deploy.ps1 -InfraDir ..\virology-lab-hackathon-infra -AppDir <תיקיית האפליקציה>
```

הסקריפט:
1. קורא מ-Terraform את כתובות ה-ECR, שם הבאקט, ה-IAM role והאזור
2. בונה את שתי התמונות ודוחף אותן ל-ECR (אפשר לדלג עם `-SkipBuild`)
3. ממלא את הערכים בקבצים, מחיל אותם ומחכה שהכול יעלה
4. מדפיס את כתובת המערכת

ברירת המחדל: הגישה פתוחה רק לכתובת האינטרנט של המחשב שמריץ את הסקריפט. כתובות נוספות: `-AllowedCidrs "1.2.3.4/32,5.6.7.8/32"`.

## לפני שימוש עם נתונים אמיתיים

- [ ] מסך כניסה למערכת (כרגע הגישה מוגבלת רק לפי כתובת).
- [ ] HTTPS – תעודה ב-ACM ו-listener על פורט 443 ב-ingress.
