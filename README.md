# HR-SOFT — سامانه منابع انسانی و ساختار سازمانی

این مخزن، طراحی و پیاده‌سازی تدریجی HR-SOFT را در کنار رابط اولیه مدیریت ساختار سازمانی (Org-Ch) نگهداری می‌کند.

## وضعیت فعلی

- پایگاه داده توسعه در Supabase با نام **Org-Ch** آماده شده است.
- شناسه پروژه: `xdjhshktjtevusigqzya` — منطقه: `us-east-2` — PostgreSQL 17.
- Five Supabase migrations have been applied to the Org-Ch development project.
- 57 HR-SOFT domain tables have been created; they currently contain no operational data.
- همه جدول‌های دامنه RLS فعال و اجباری دارند. سیاست پیش‌فرض برای داده‌های کسب‌وکار **عدم دسترسی** است.
- هیچ Tenant، شرکت، کاربر HR، گروه یا مجوزی به‌صورت حدسی ساخته نشده است.
- `index.html` هنوز رابط اولیه Org-Ch با ذخیره‌سازی `localStorage` است و هنوز به API داده‌ای HR-SOFT متصل نشده است.
- auth.html supports Supabase sign-in/sign-up and the one-time first-admin bootstrap; signup alone grants no HR data access.

## اجرای رابط در ویندوز

از پوشه اصلی مخزن:

```powershell
python -m http.server 8080
```

- رابط ساختار سازمانی: http://localhost:8080/

## تنظیمات Supabase در مرورگر

1. فایل `supabase-config.example.js` را به `supabase-config.js` کپی کنید.
2. URL و Publishable Key پروژه را در فایل محلی قرار دهید.

## پایگاه داده و Migrationها

پیکربندی CLI در `supabase/config.toml` قرار دارد. Migrationها:

1. `20261118201829_hr_soft_foundation.sql` — مدل پایه و تکمیلی، محدودیت‌های چندشرکتی، تاریخچه، RLS و default-deny.
2. `20261118202031_hr_soft_performance_security_hardening.sql` — انتقال citext به schema داخلی، اصلاح تابع وضعیت نشست، ایندکس FKها و حذف ایندکس‌های تکراری.
3. `20261118202503_hr_soft_api_schema_lockdown.sql` - Restricts PostgREST to public and graphql_public.
4. `20261118203447_hr_soft_bootstrap_permission_resolver.sql` - Adds the internal permission resolver and one-time first-admin bootstrap.
5. `20261118203712_hr_soft_bootstrap_internalize.sql` - Moves privileged bootstrap implementation to the private schema; public wrapper is SECURITY INVOKER.

برای همگام‌سازی بعدی با Supabase CLI:

```powershell
supabase login
supabase link --project-ref xdjhshktjtevusigqzya
supabase db push --remote --dry-run
# After reviewing the exact pending migration list:
supabase db push --remote
```

## مرزهای امنیتی فعلی

- فقط schemaهای `public` و `graphql_public` در Data API قابل مشاهده‌اند؛ schemaهای `hr_*` عمداً expose نشده‌اند.
- جدول‌های حساس، مالی، پرسنلی، فایل، ممیزی و گردش کار مستقیماً از مرورگر قابل خواندن/نوشتن نیستند.
- تابع `public.hr_session_status()` فقط وضعیت احراز هویت و وجود حساب داخلی فعال را برمی‌گرداند.
- The internal permission resolver v2.4.1 and one-time first-admin bootstrap are installed; business-data RPCs and private Storage remain pending.
- Supabase reports 53 RLS-enabled tables without policies. This is intentional fail-closed behavior until permission-aware business APIs are complete.

## اسناد طراحی

اسناد معماری، ERD، امنیت، تصمیم‌ها و مراحل طراحی در `docs/HR-SOFT/` قرار دارند. فایل‌های SQL طراحی تاریخی، به‌تنهایی مجوز اجرا نیستند؛ Migrationهای قابل استقرار فقط در `supabase/migrations/` نگهداری می‌شوند.
