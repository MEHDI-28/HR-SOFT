# HR-SOFT — برنامه آزمون اصلاحات امنیتی مرحله ۱۸
## نسخه 0.1 | طرح آزمون؛ اجرا نشده

## 1. پیش‌نیاز محیط

- پایگاه داده disposable/staging مستقل؛ هرگز production نباشد.
- schema پایه و supplemental به ترتیب migration مستقر شده باشند.
- اصلاح ترتیب FK مربوط به bulletin در Migration v0.4 اعمال شده باشد.
- Stage 16 correction snippets و Stage 18 corrections در محیط آزمایشی اعمال شده باشند.
- Tenant A و Tenant B، دو system، دو group و دو permission با داده ساختگی ساخته شوند.

## 2. آزمون‌های پذیرش

| شناسه | سناریو | انتظار |
|---|---|---|
| SEC-401 | اتصال group و permission متعلق به یک system | قبول |
| SEC-402 | اتصال group سیستم A به permission سیستم B | FK رد کند |
| SEC-403 | تغییر system_id یک rule به system دیگر | FK رد کند |
| SEC-404 | temporary_access با scope خالی و بدون approved_by | CHECK رد کند |
| SEC-405 | temporary_access با scope خالی و بدون approved_at | CHECK رد کند |
| SEC-406 | approved_by متعلق به Tenant دیگر | FK رد کند |
| SEC-407 | temporary_access با scope مشخص و بدون approval metadata | از نظر این قید پذیرفته؛ authorization همچنان تابع command/policy است |
| SEC-408 | UPDATE روی user_login_events | trigger رد کند |
| SEC-409 | DELETE روی user_login_events | trigger رد کند |
| SEC-410 | UPDATE روی user_access_events | trigger رد کند |
| SEC-411 | DELETE روی user_access_events | trigger رد کند |
| SEC-412 | ایجاد bulletin_acknowledgements با FK مرکب | migration و FK باید بدون خطا ساخته شوند |
| SEC-413 | کاربر authenticated بدون resolver کامل به داده HR دسترسی بگیرد | رد؛ هیچ policy permissive موقت مجاز نیست |
| SEC-414 | approver در command سمت سرور مدیر مجاز همان Tenant نباشد | فرمان رد و audit ثبت شود |

## 3. آزمون‌های preflight

پیش از VALIDATE کردن FKهای group-permission:
```sql
select r.id, r.system_id, p.system_id as permission_system_id
from hr_security.group_permission_rules r
join hr_security.permissions p on p.id = r.permission_id
where r.system_id <> p.system_id;
```

انتظار: صفر ردیف.

پیش از VALIDATE کردن قید تأیید دسترسی موقت:
```sql
select id, tenant_id
from hr_security.temporary_access
where (approved_by is null) <> (approved_at is null)
   or (scope_id is null and (approved_by is null or approved_at is null));
```

انتظار: صفر ردیف؛ موارد ناسازگار باید با تصمیم مدیر و حفظ audit اصلاح شوند، نه با پرکردن حدسی approver.

## 4. نکات امنیتی

- وجود approved_by در دیتابیس فقط رابطه هویتی را ثابت می‌کند؛ مجاز بودن approver باید در command سمت سرور با permission مستقل بررسی شود.
- این migration به‌تنهایی موتور دسترسی را پیاده‌سازی نمی‌کند.
- هیچ RLS policy مجازکننده‌ای تا زمان تکمیل resolver و آزمون‌های Tenant isolation اضافه نشود.
- تمام تست‌ها با داده ساختگی و roleهای واقعی PostgreSQL اجرا شوند؛ تست صرفاً با owner/postgres برای اثبات RLS کافی نیست.

## 5. وضعیت

این سند برنامه آزمون است. هیچ Migration، pgTAP یا تست integration در این مرحله اجرا نشده است.
