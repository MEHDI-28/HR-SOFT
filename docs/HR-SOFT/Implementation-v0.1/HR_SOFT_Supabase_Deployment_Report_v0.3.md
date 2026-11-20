# HR-SOFT — گزارش استقرار Supabase و اتصال رابط خواندنی
## نسخه 0.3 | 2026-11-20

### 1. محیط هدف
- پروژه: Org-Ch
- Project Ref: `xdjhshktjtevusigqzya`
- وضعیت سرویس هنگام اجرا: `ACTIVE_HEALTHY`
- PostgreSQL: `17.11.0.019`
- روش اجرا: Supabase MCP مستقیم روی دیتابیس اصلی؛ هیچ تستی در محیط محلی اجرا نشد.

### 2. Migrationهای ثبت‌شده روی دیتابیس اصلی

پنج Migration پایه قبلی حفظ شدند. چهار Migration جدید زیر با موفقیت ثبت و اجرا شدند:

| Version | Migration | وضعیت |
|---|---|---|
| 20261120063245 | hr_soft_resolver_deny_precedence_hardening_20261119 | موفق |
| 20261120063501 | hr_soft_org_admin_read_api_v1 | موفق |
| 20261120063528 | hr_soft_org_snapshot_reference_redaction_fix | موفق |
| 20261120063557 | hr_soft_org_api_invoker_wrappers | موفق |

### 3. اصلاح Resolver نسخه 2.4.2
- Deny مستقل از پرچم‌های can_add/can_edit/can_delete ارزیابی می‌شود.
- Allow همچنان به پرچم عملیات مربوطه وابسته است.
- app_user آرشیوشده از توابع current_app_user_id/current_tenant_id حذف می‌شود.
- hr_session_status حساب آرشیوشده را provisioned اعلام نمی‌کند.
- دو Constraint مربوط به جفت تأییدکننده/زمان تأیید و الزام تأیید برای دسترسی بدون scope اضافه و Validate شدند.
- پیش از Migration، تعداد رکوردهای temporary_access برابر صفر و تعداد نقض هر دو شرط برابر صفر بود.

### 4. APIهای خواندنی منتشرشده

#### 4.1 `public.hr_admin_get_context_v1()`
- ورودی ندارد.
- app_user و tenant را از `auth.uid()` استخراج می‌کند.
- tenant باید active و غیرآرشیوشده باشد.
- شرکت‌ها فقط در صورت تعلق به tenant جاری، active بودن، معتبر بودن در تاریخ جاری و داشتن مجوز `org.company.view` بازگردانده می‌شوند.
- capabilityهای company/chart/unit/position/relationship با Resolver محاسبه می‌شوند.

#### 4.2 `public.hr_org_get_admin_snapshot_v1(p_company_id uuid, p_effective_at date)`
- فقط خواندنی است.
- `company_id` فقط selector است؛ tenant از نشست احراز هویت‌شده استخراج می‌شود.
- شرکت باید active، غیرآرشیوشده و در تاریخ مؤثر معتبر باشد.
- دروازه endpoint: `org.company.view` و `org.chart.view`.
- مجوز unit برای هر org_unit و مجوز position برای هر position در scope واحد واقعی ارزیابی می‌شود.
- relationship فقط وقتی بازمی‌گردد که هر دو سمت قابل مشاهده باشند و مجوز رابطه برای هر دو واحد برقرار باشد.
- parent_unit_id، superior_position_id و organizational_position_id فقط در صورت قابل مشاهده بودن مرجع بازگردانده می‌شوند.
- فقط داده‌های پایه ساختار سازمانی بازمی‌گردند؛ داده پرسنلی/هویتی/بانکی/تماس خصوصی در پاسخ نیست.
- فیلترهای active/visible/archive/validity مطابق ستون‌های واقعی هر جدول اعمال می‌شوند.

### 5. مرز امنیتی و ACL
- wrapperهای public از نوع `SECURITY INVOKER` هستند.
- منطق اصلی در `hr_internal` و با `SECURITY DEFINER`، `search_path = ''` و schema-qualified references اجرا می‌شود.
- EXECUTE روی wrapperهای public فقط برای `authenticated` است.
- `anon` و `PUBLIC` روی wrapperها EXECUTE ندارند.
- اجرای مستقیم جدول‌های `hr_org` برای anon/authenticated همچنان بسته است.
- schemaهای `hr_*` به Data API اضافه نشده‌اند.
- توابع داخلی برای اجرای wrapper توسط authenticated مجازند، اما schema داخلی در فهرست exposed schemas نیست.
- هیچ service_role یا secret key به مرورگر داده نشده است.
- هیچ policy باز یا عمومی اضافه نشده است.

### 6. آزمون‌های اجراشده روی دیتابیس اصلی

| آزمون | نتیجه |
|---|---|
| Migration history پس از اجرا | PASS؛ هر چهار نسخه جدید ثبت شدند |
| preflight Constraintهای temporary_access | PASS؛ صفر رکورد و صفر نقض |
| Validate دو Constraint جدید | PASS |
| Resolver بدون نشست | PASS؛ `AUTH_REQUIRED` |
| hr_session_status بدون نشست | PASS؛ authenticated=false و provisioned=false |
| context RPC بدون نشست | PASS؛ `AUTH_REQUIRED` |
| snapshot RPC بدون نشست | PASS؛ `AUTH_REQUIRED` |
| ACL wrapperهای public | PASS؛ authenticated=true، anon=false، PUBLIC=false |
| ACL توابع داخلی برای anon | PASS؛ false |
| دسترسی مستقیم SELECT به org_units | PASS؛ anon=false و authenticated=false |
| Supabase Security Advisor پس از اصلاح wrapperها | PASS بدون هشدار SECURITY DEFINER روی wrapperهای public |
| تعداد RLS Enabled No Policy | 53 مورد INFO؛ fail-closed و عمدی، بدون افزودن policy |
| Leaked Password Protection | یک هشدار WARN قبلی همچنان برقرار است؛ تنظیم Auth تغییر داده نشد |

### 7. آزمون‌هایی که هنوز انجام نشده‌اند
به دلیل اینکه SQL/MCP database connection نشست واقعی کاربر مرورگر را در اختیار این اجرا نمی‌گذارد، آزمون مثبت با JWT واقعی کاربر در hosted database انجام نشده است. از جعل JWT claims در SQL Editor استفاده نشده است.

بنابراین موارد زیر هنوز نیازمند آزمون از یک نشست واقعی authenticated هستند:
- خروجی موفق context برای مدیر واردشده.
- snapshot موفق برای شرکت Org-Ch.
- deny-overrides-allow با داده واقعی و fixture کنترل‌شده.
- cross-tenant و scopeهای company/org_unit.
- عدم افشای parent/superior/relationship با fixture چندواحدی.
- رفتار historical effective date.

آزمون JWT واقعی قبلی در Supabase محلی PostgreSQL 17 شش سناریوی Resolver را PASS کرده بود؛ این نتیجه جایگزین آزمون مثبت hosted نیست.

### 8. وضعیت داده
در زمان پس از استقرار:
- org_layers = 0
- org_units = 0
- organizational_positions = 0
- positions = 0
- position_relationships = 0
- audit_events = 1 (همان رخداد bootstrap قبلی)

Migrationها هیچ داده عملیاتی سازمانی ایجاد نکردند و هیچ داده‌ای پاک یا تغییر داده نشد.

### 9. اتصال رابط خواندنی — 2026-11-20
- صفحه جدید `org-structure-readonly.html` ایجاد شد.
- صفحه با Supabase JS و تنظیمات publishable موجود، نشست واقعی را بررسی می‌کند؛ در نبود نشست به `auth.html` هدایت می‌شود.
- پس از ورود، ابتدا `hr_admin_get_context_v1()` اجرا می‌شود و فقط شرکت‌هایی که capability مشاهده چارت دارند در انتخاب‌گر نمایش داده می‌شوند.
- پس از انتخاب شرکت، `hr_org_get_admin_snapshot_v1()` اجرا می‌شود.
- نمایش شامل خلاصه شمارش، لایه‌ها، درخت واحدها، سمت‌های قابل مشاهده و روابط مجاز است.
- صفحه فقط‌خواندنی است؛ هیچ INSERT/UPDATE/DELETE، import، ذخیره‌سازی localStorage یا دسترسی مستقیم به جداول دامنه ندارد.
- تمام متن‌های دریافتی با `textContent` به DOM افزوده می‌شوند و به‌عنوان HTML اجرا نمی‌شوند.
- لینک صفحه خواندنی به `index.html`، `org-structure-manager.html` و پس از provision شدن حساب به `auth.html` اضافه شد.
- در هر دو صفحه قدیمی هشدار داده شد که فرم‌ها و ذخیره‌سازی آن‌ها محلی/آزمایشی‌اند و در Supabase ذخیره نمی‌شوند.
- فرم legacy به جدول positions متصل نشده است؛ نگاشت مدل همچنان نیازمند کار جداگانه است.

### 10. وضعیت Git و آزمون
- تغییرات قبلی working tree حفظ شدند و روی آن‌ها overwrite یا reset انجام نشد.
- هیچ Commit، Push یا Merge انجام نشده است.
- PR #1 همچنان مستقل باقی می‌ماند.
- سرور یا اپلیکیشن محلی اجرا نشد؛ فقط بررسی ایستای کد انجام شد.
- `node --check` برای اسکریپت‌های inline صفحه ورود و صفحه خواندنی موفق بود.
- `supabase/tests/validate_frontend_security.cjs` پس از اضافه‌شدن کنترل‌های صفحه خواندنی اجرا شد و همه آزمون‌ها PASS شدند؛ این آزمون نبود دسترسی مستقیم جدول، نبود عملیات نوشتن و نبود innerHTML در صفحه خواندنی را نیز بررسی می‌کند.
- `git diff --check` بدون خطای whitespace پایان یافت.
- فایل محلی `supabase-config.js` به پروژه صحیح اشاره می‌کند، Publishable Key تنظیم شده و فایل به‌درستی از Git مستثنا است؛ مقدار کلید در گزارش چاپ نشده است.
- در مخزن، تنظیم یا workflow مشخصی برای GitHub Pages، Vercel یا Netlify پیدا نشد؛ بنابراین انتشار وب از این شاخه هنوز انجام نشده است.
- آزمون مثبت صفحه با نشست واقعی مدیر هنوز انجام نشده؛ تا زمان ورود مدیر و اجرای RPCها از مرورگر، صحت عملیاتی خروجی مثبت اعلام نمی‌شود.

### 11. گام بعدی
1. باز کردن صفحه ورود و ورود با حساب مدیر.
2. بازکردن `org-structure-readonly.html` و ثبت نتیجه context و snapshot.
3. اگر داده سازمانی هنوز خالی باشد، پیام خالی بودن ساختار نمایش داده می‌شود؛ این با شکست API اشتباه گرفته نمی‌شود.
4. پس از تأیید آزمون خواندنی، طراحی APIهای نوشتن، audit و نگاشت مدل به‌صورت مرحله‌ای و جداگانه انجام شود.
