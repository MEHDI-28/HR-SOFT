# HR-SOFT — سامانه منابع انسانی و ساختار سازمانی

این مخزن، طراحی و پیاده‌سازی تدریجی HR-SOFT را در کنار رابط اولیه مدیریت ساختار سازمانی (Org-Ch) نگهداری می‌کند.

## وضعیت فعلی

- پایگاه داده توسعه در Supabase با نام **Org-Ch** فعال است.
- شناسه پروژه: `xdjhshktjtevusigqzya` — منطقه: `us-east-2` — PostgreSQL 17.
- ۹ Migration مربوط به HR-SOFT در پروژه اصلی اعمال شده‌اند؛ چهار Migration آخر شامل hardening تقدم deny، API خواندنی ساختار سازمانی، اصلاح redaction ارجاعات و wrapperهای SECURITY INVOKER هستند.
- ۵۷ جدول دامنه HR-SOFT ایجاد شده‌اند؛ داده عملیاتی سازمانی هنوز ایجاد نشده است.
- یک حساب Auth تأییدشده، یک نگاشت کاربر داخلی فعال، یک Tenant و یک شرکت ایجاد شده‌اند.
- کاربر اولیه عضو گروه `tenant_owner` با عنوان «مدیر کل سازمان» است؛ برای این گروه ۶۸ قاعده Allow ثبت شده است. این تعداد به‌تنهایی اثبات‌کننده عبور موفق همه عملیات از Permission Resolver نیست.
- دعوت راه‌اندازی اولیه با موفقیت مصرف شده است.
- همه ۵۷ جدول دامنه RLS فعال و FORCE ROW LEVEL SECURITY دارند؛ سیاست پیش‌فرض داده‌های کسب‌وکار **عدم دسترسی** است.
- `auth.html` ورود، ثبت‌نام، راه‌اندازی مدیر اولیه و بررسی وضعیت نشست را از طریق Supabase انجام می‌دهد.
- `index.html` و `org-structure-manager.html` هنوز رابط legacy با ذخیره‌سازی `localStorage` هستند و عملیات آن‌ها به Supabase متصل نیست. صفحه مستقل `org-structure-readonly.html` برای خواندن مجاز ساختار از RPCهای Supabase اضافه شده است.
- ممیزی امنیتی رابط دو مسیر XSS را در شناسه‌های واردشده از Excel و تاریخچه فیلد شناسایی و در شاخه کاری اصلاح کرده است؛ گزارش در `docs/HR-SOFT/Analysis-v0.1/HR_SOFT_Frontend_Security_Audit_v0.1.md` است.
- دو RPC عمومی فقط‌خواندنی برای context مدیر و snapshot ساختار سازمانی منتشر شده‌اند؛ هیچ API نوشتن کسب‌وکار منتشر نشده است.

## اجرای رابط در ویندوز

از پوشه اصلی مخزن:

```powershell
python -m http.server 8080
```

- رابط ساختار سازمانی: http://localhost:8080/
- ورود و وضعیت حساب: http://localhost:8080/auth.html
- مشاهده ساختار از Supabase (فقط‌خواندنی): http://localhost:8080/org-structure-readonly.html

## تنظیمات Supabase در مرورگر

1. فایل `supabase-config.example.js` را به `supabase-config.js` کپی کنید.
2. URL و Publishable Key پروژه را در فایل محلی قرار دهید.
3. هرگز کلید `service_role`، کلید محرمانه یا گذرواژه دیتابیس را در کد مرورگر قرار ندهید.

## پایگاه داده و Migrationها

پیکربندی CLI در `supabase/config.toml` قرار دارد. Migrationها:

1. `20261118201829_hr_soft_foundation.sql` — مدل پایه و تکمیلی، محدودیت‌های چندشرکتی، تاریخچه، RLS و default-deny.
2. `20261118202031_hr_soft_performance_security_hardening.sql` — انتقال citext به schema داخلی، اصلاح تابع وضعیت نشست، ایندکس FKها و حذف ایندکس‌های تکراری.
3. `20261118202503_hr_soft_api_schema_lockdown.sql` — محدودسازی PostgREST به `public` و `graphql_public`.
4. `20261118203447_hr_soft_bootstrap_permission_resolver.sql` — افزودن Permission Resolver داخلی و راه‌اندازی یک‌باره مدیر اولیه.
5. `20261118203712_hr_soft_bootstrap_internalize.sql` — انتقال پیاده‌سازی ممتاز bootstrap به schema خصوصی؛ wrapper عمومی از نوع SECURITY INVOKER است.

**Migrationهای اعمال‌شده:** چهار Migration جدید در تاریخ 2026-11-20 روی Supabase اصلی اعمال و در تاریخچه ثبت شده‌اند: hardening تقدم deny و وضعیت حساب، انتشار API خواندنی context/snapshot، اصلاح redaction ارجاعات سازمانی، و تبدیل wrapperهای عمومی به SECURITY INVOKER. جزئیات و محدودیت آزمون‌ها در `docs/HR-SOFT/Implementation-v0.1/HR_SOFT_Supabase_Deployment_Report_v0.3.md` ثبت شده است.

برای همگام‌سازی بعدی با Supabase CLI، ابتدا dry-run انجام و فهرست Migrationهای در انتظار بررسی شود:

```powershell
supabase login
supabase link --project-ref xdjhshktjtevusigqzya
supabase db push --remote --dry-run
# فقط پس از بازبینی فهرست دقیق:
supabase db push --remote
```

## مرزهای امنیتی فعلی

- فقط schemaهای `public` و `graphql_public` در Data API قابل مشاهده‌اند؛ schemaهای `hr_*` عمداً expose نشده‌اند.
- جدول‌های حساس، مالی، پرسنلی، فایل، ممیزی و گردش کار مستقیماً از مرورگر قابل خواندن/نوشتن نیستند.
- `public.hr_session_status()` وضعیت احراز هویت و حساب داخلی فعال/غیرآرشیوی را برمی‌گرداند؛ کنترل حساب آرشیوشده در Migration اعمال‌شده تقویت شده است.
- Permission Resolver داخلی از طریق دو RPC محدود خواندنی برای کنترل دسترسی context و snapshot استفاده می‌شود. این موضوع به معنی تأیید همه سناریوهای پذیرش Resolver یا آماده بودن APIهای نوشتن نیست.
- ۵۳ هشدار INFO مربوط به جدول‌های RLS-enabled بدون Policy، رفتار fail-closed عمدی فعلی است؛ برای رفع ظاهری هشدارها Policy باز و عمومی اضافه نکنید.
- رابط اولیه همچنان localStorage دارد؛ اطلاعات هویتی، بانکی، اسناد پرسنلی و سایر داده‌های حساس نباید در آن ذخیره شوند. دو مورد XSS اصلاح شده‌اند، اما آزمون مرورگر واقعی هنوز انجام نشده است.
- گزارش Performance Advisor شامل ایندکس‌های استفاده‌نشده است؛ با توجه به نبود بار عملیاتی واقعی، فعلاً ایندکس‌ها حذف نشوند.

## گام‌های بعدی

1. تکمیل آزمون Permission Resolver با نشست واقعی و تست‌های پذیرش مستقل.
2. تکمیل آزمون مثبت RPCهای خواندنی با نشست واقعی مدیر و آزمون scope/deny/cross-tenant از مرورگر احراز هویت‌شده.
3. طراحی نگاشت مدل legacy به مدل نرمال‌شده و سپس طراحی جداگانه APIهای نوشتن با audit و کنترل مجوز.
4. انتقال handlerهای inline به event listener و حذف تدریجی localStorage از مسیر داده عملیاتی.
5. پیاده‌سازی عملیات نوشتن، Storage خصوصی و سایر ماژول‌ها در مراحل جداگانه.

هیچ Migration جدید، تغییر Production، Merge به `main` یا حذف داده بدون بررسی و تأیید صریح انجام نشود.
