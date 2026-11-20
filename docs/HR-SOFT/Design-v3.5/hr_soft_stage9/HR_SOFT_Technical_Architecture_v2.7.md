# HR-SOFT — معماری فنی محصول و محیط‌های اجرا
## نسخه 2.7 | مرحله نهم

- تاریخ: ۱۸ نوامبر ۲۰۲۶
- وضعیت: طرح معماری و برنامه تحویل؛ نه استقرار.
- محدودیت: repository، frontend فعلی، project واقعی Supabase و محیط میزبانی در دسترس/تأییدشده نیستند؛ بنابراین این سند انتخاب قطعی stack یا ادعای وجود deployment نیست.

## 1. معماری هدف

الگوی پیشنهادی: Modular Monolith با مرزهای دامنه روشن؛ نه microservices از روز اول.

لایه‌ها:
1. Web UI: فارسی RTL، responsive، presentation-only.
2. API/domain layer: ورودی محدود، authorization، validation، command handling.
3. PostgreSQL: منبع اصلی حقیقت، constraints، RLS، audit.
4. Supabase Auth: هویت ورود؛ نگاشت به app_users.
5. Private Storage: فایل‌های نسخه‌بندی‌شده.
6. Background workers: outbox، SMS، scheduled assignments، reminders، exports.
7. Observability: application logs، database metrics، audit trail و alerting.

## 2. مرزبندی دامنه‌ها

- Core Identity: tenants, companies, people, personnel records, app users.
- Organization: layers, units, positions, relationships, assignments.
- Security: systems, permissions, groups, memberships, scopes, temporary access.
- Workflow: requests, steps, decisions, capacity requests.
- Files: owner registry, file objects, versions, exports.
- Notifications: preferences, notifications, outbox.
- Audit: immutable event streams.
- Reporting: authorized read models.

هر domain مالک جداول و commandهای خود است؛ domain دیگر نباید مستقیم status آن را تغییر دهد.

## 3. Supabase role strategy

- `anon`: بدون دسترسی به داده HR.
- `authenticated`: فقط wrapper/APIهای لازم؛ نه table-wide access.
- `service_role`: فقط backend trusted/worker، هرگز در browser.
- `postgres`/owner: عملیات migration و maintenance محدود.
- worker role: دسترسی محدود به outbox و صف‌های پردازش؛ نه مجوز عمومی روی کل HR schema.

Schemaهای داخلی `hr_*` از exposed schemas خارج باشند. اگر Supabase Data API برای RPC استفاده شود، فقط wrapperهای عمومی allowlist شوند. توابع internal در schema غیر exposed و بدون EXECUTE عمومی بمانند.

## 4. محیط‌ها

### Development
- داده ساختگی.
- migration قابل reset.
- RLS فعال از روز اول.
- تست دو Tenant.

### Staging
- ساختار نزدیک production.
- داده واقعی فقط در صورت مجوز، minimization و masking.
- اجرای تمام integration/security tests.
- آزمون restore و Storage.

### Production
- deploy فقط از commit/tag تأییدشده.
- migrationهای forward-only و قابل rollback منطقی.
- backup قبل از migration.
- feature flag برای ماژول‌های جدید.
- محدودسازی IP/دسترسی مدیران در صورت نیاز عملیاتی.

هیچ secret یا service key در Git، frontend، screenshot یا log قرار نگیرد.

## 5. CI/CD

Pipeline پیشنهادی:
1. format/lint.
2. static checks برای SQL و migration naming.
3. build frontend/backend.
4. start disposable Postgres/Supabase test environment.
5. apply migrations from empty database.
6. apply upgrade path from previous schema.
7. pgTAP and integration tests.
8. tenant isolation tests.
9. Storage policy tests.
10. build artifact.
11. manual approval for staging/prod.
12. post-deploy smoke tests.

Merge/deploy باید در صورت شکست هر تست امنیتی متوقف شود.

## 6. Migration governance

- هر migration شماره ترتیبی و هدف روشن دارد.
- تغییرات baseline قبلی ویرایش نمی‌شوند؛ migration جدید اضافه می‌شود.
- migration باید idempotency لازم، preflight checks و rollback/forward-fix strategy داشته باشد.
- برای تغییر داده، قبل/بعد و تعداد ردیف تحت تأثیر گزارش شود.
- migrationهای destructive ممنوع مگر با backup، تأیید و برنامه بازیابی.
- schema drift بین dev/staging/prod باید کنترل شود.

## 7. Logging و Monitoring

سه جریان جدا:
- operational logs: خطاهای برنامه، latency، worker failures.
- security audit: actor، resource، action، outcome، timestamp، reason.
- business history: effective date، recorded date، before/after، correction.

Log عمومی نباید شامل کد ملی، شبا، token، password، document bytes یا secrets باشد.

شاخص‌ها:
- login failures و lockouts
- permission denied spike
- RLS errors
- p95 API latency
- DB connection saturation
- outbox backlog/age
- SMS failure rate
- export duration/failure
- Storage access denied
- backup/restore success

## 8. Backup و Disaster Recovery

- backup پایگاه داده و Storage باید با هم برنامه‌ریزی شوند.
- کلیدهای رمزنگاری خارج از DB و backup جداگانه امن.
- restore test در محیط جدا الزامی.
- RPO/RTO باید پیش از production تعیین شود؛ فعلاً عددی فرض نشده.
- tenant export/restore باید جداسازی Tenant را حفظ کند.
- retention و حذف فیزیکی تابع قرارداد/الزامات حقوقی باشد.

## 9. وابستگی‌های بیرونی

- SMS provider هنوز انتخاب نشده؛ integration باید adapter-based باشد.
- email provider و hosting provider قطعی نیستند.
- سرویس پولی جدید انتخاب یا فعال نمی‌شود بدون ارزیابی هزینه و دسترسی.
- معماری باید تا حد امکان portable بماند؛ داده اصلی در PostgreSQL و فایل‌ها در storage خصوصی با metadata قابل انتقال.

## 10. تصمیم‌های باز فنی که بدون اطلاعات پروژه نباید حدس زده شوند

- frontend framework و نسخه فعلی.
- آیا API فقط Supabase RPC/Edge Functions است یا backend جدا لازم است.
- محل میزبانی و region.
- worker runtime.
- domain و TLS.
- SMS provider و محدودیت‌های دسترسی از ایران.
- RPO/RTO و retention.
