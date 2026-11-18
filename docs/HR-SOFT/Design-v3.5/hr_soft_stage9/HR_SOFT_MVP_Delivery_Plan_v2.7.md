# HR-SOFT — برنامه تحویل MVP و معیار پذیرش
## نسخه 2.7

## 1. MVP قابل استفاده
MVP باید چرخه پایه زیر را end-to-end اجرا کند:
1. ایجاد Tenant و شرکت‌ها.
2. تعریف ساختار سازمانی و سمت‌ها.
3. ایجاد شخص و پرونده پرسنلی.
4. ساخت حساب و اتصال به شخص.
5. ساخت سیستم، گروه، مجوز و scope.
6. انتساب کاربران به گروه‌ها.
7. مشاهده چارت سازمانی.
8. ثبت انتساب سمت آتی و اجرای خودکار در تاریخ مؤثر.
9. ثبت تاریخچه و اصلاح گذشته با مجوز ویژه.
10. ثبت درخواست تغییر ظرفیت، تأیید، revision و اجرای جداگانه.
11. اعلان in-app؛ SMS بعد از انتخاب provider.
12. گزارش فهرست پرسنل و ساختار سازمانی.
13. فایل خصوصی و نسخه‌بندی.
14. audit و export کنترل‌شده.

## 2. معیار پذیرش سراسری
- Tenant A هیچ داده‌ای از Tenant B نمی‌بیند یا تغییر نمی‌دهد.
- company scope بین شرکت‌های یک Tenant enforce می‌شود.
- deny بر allow مقدم است.
- تمام عملیات نوشتن از command/API کنترل‌شده انجام می‌شوند.
- تمام تغییرات مهم audit/history دارند.
- sensitive view/download permission مستقل دارد.
- فایل‌ها private هستند و URL عمومی ندارند.
- history append-only است.
- درخواست ظرفیت فقط پس از approval و برای revision تأییدشده اجرا می‌شود.
- assignment آینده قبل از effective date در چارت جاری ظاهر نمی‌شود.
- پیام‌ها idempotent هستند.
- خروجی گزارش همان scope صفحه را رعایت می‌کند.
- UI فارسی RTL و قابل استفاده با صفحه‌کلید است.

## 3. فازبندی تحویل

### Gate 0 — دسترسی و موجودی پروژه
- repository و branch
- schema واقعی Supabase
- frontend/backend موجود
- environments/secrets ownership
- وضعیت deployment

### Gate 1 — Data Foundation
- migrations
- company-safe FKs
- file owner registry
- capacity status model
- audit append-only

### Gate 2 — Security Foundation
- Auth mapping
- permission seed
- resolver
- RLS
- Storage policies
- pgTAP two-tenant

### Gate 3 — Core HR
- company/org/position/personnel
- assignment temporal history
- executive chart

### Gate 4 — Workflow
- inbox
- capacity approvals/revisions/execution
- notes/files
- outbox

### Gate 5 — Reports/UI hardening
- dashboard
- report catalogue
- exports
- accessibility/RTL
- performance

## 4. Definition of Ready برای شروع توسعه
- source repository قابل دسترس.
- schema واقعی استخراج شده.
- نسخه PostgreSQL/Supabase مشخص.
- محیط توسعه جدا.
- migration ownership مشخص.
- user stories و screen captures کافی.
- no-go list و deferred modules ثبت‌شده.

## 5. Definition of Done برای هر release
- migrations applied in disposable env
- rollback/forward fix documented
- tests pass
- security review complete
- audit verified
- documentation updated
- backup/restore strategy verified
- no unresolved critical/high issue
