# HR-SOFT — گزارش تطبیق Migration سخت‌سازی Resolver با دیتابیس فعال
## v0.1 — 2026-11-19

- وضعیت: بررسی فقط‌خواندنی؛ هیچ تغییر دیتابیسی اعمال نشده است.
- پروژه Supabase: Org-Ch
- Project ID: `xdjhshktjtevusigqzya`
- PostgreSQL فعال: 17.11
- شاخه محلی: `docs/hr-soft-design-v3.5`
- Migration مورد بررسی: `20261119090000_hr_soft_resolver_deny_precedence_hardening.sql`

## 1. نتیجه اجرایی

Migration محلی هنوز روی دیتابیس فعال اعمال نشده است. فهرست migrationهای ثبت‌شده در Supabase شامل پنج migration تا نسخه `20261118203712` است و migration با نسخه `20261119090000` در آن وجود ندارد.

تطبیق تعریف تابع فعال با Migration محلی نشان داد دو ایراد اصلی RES-001 و RES-003 هنوز در دیتابیس فعال وجود دارند، اما در فایل پیشنهادی اصلاح شده‌اند. دو قید یکپارچگی RES-005 نیز در دیتابیس فعال وجود ندارند و در Migration محلی اضافه و validate شده‌اند.

## 2. تطبیق Resolver — RES-001

**وضعیت دیتابیس فعال: ایراد تأیید شد.**

در تابع فعال `hr_internal.evaluate_permission_context`، بلوک `v_group_deny` همچنان شرط `CASE p_operation` را دارد. بنابراین برای عملیات add/edit/delete، deny صریح ممکن است در صورت خاموش بودن پرچم متناظر `can_add/can_edit/can_delete` از شمارش حذف شود.

**وضعیت Migration محلی: اصلاح پیشنهادی درست اعمال شده است.**

در بلوک `v_group_deny` فایل محلی، شرط `CASE p_operation` وجود ندارد؛ اثر deny مستقل از پرچم‌های مجازکننده عملیات شمرده می‌شود. دو شرط operation-gate در مسیرهای allow باقی مانده‌اند.

آزمون دودویی محلی نیز سناریوی ACL-101/118 را با deny در یک گروه و allow در گروه دیگر، در حالی که تمام پرچم‌های deny خاموش‌اند، پاس کرده است. این آزمون شبیه‌سازی PostgreSQL است و جایگزین آزمون JWT واقعی نیست.

## 3. تطبیق هویت فعال — RES-003

**وضعیت دیتابیس فعال: ناهمسانی تأیید شد.**

در دو تابع فعال زیر، شرط `archived_at IS NULL` وجود ندارد:
- `hr_security.current_app_user_id()`
- `hr_security.current_tenant_id()`

همچنین تابع فعال `public.hr_session_status()` نیز فقط `status = 'active'` را بررسی می‌کند و شرط آرشیو را ندارد.

**وضعیت Migration محلی: اصلاح پیشنهادی موجود است.**

هر سه تابع کمکی/وضعیت نشست در Migration محلی شرط `archived_at IS NULL` را دارند؛ Resolver نیز همین شرط را دارد.

## 4. قیود temporary_access — RES-005

در دیتابیس فعال، دو قید زیر یافت نشدند:
- `ck_temporary_access_approval_pair_v18`
- `ck_temporary_access_global_scope_approval_v18`

Migration محلی هر دو قید را با `NOT VALID` اضافه و سپس صریحاً `VALIDATE CONSTRAINT` می‌کند. آزمون محلی وجود و اعتبار هر دو قید را تأیید کرده است.

## 5. فراداده امنیتی توابع فعال

فراداده ثبت‌شده در دیتابیس فعال هنگام بررسی:

| تابع | مالک | SECURITY DEFINER | search_path | ACL مشاهده‌شده |
|---|---|---:|---|---|
| `hr_internal.evaluate_permission_context(...)` | postgres | بله | خالی | postgres |
| `hr_security.current_app_user_id()` | postgres | بله | خالی | postgres, authenticated |
| `hr_security.current_tenant_id()` | postgres | بله | خالی | postgres, authenticated |
| `public.hr_session_status()` | postgres | خیر | خالی | postgres, authenticated, service_role |

Migration از `CREATE OR REPLACE FUNCTION` با همان امضاها استفاده می‌کند و دستور تغییر ACL یا GRANT/REVOKE در آن وجود ندارد. با این حال، بعد از هر انتشار باید ACL و فراداده دوباره از دیتابیس خوانده و تطبیق داده شوند.

## 6. آزمون‌های اجراشده در این نوبت

1. `validate_resolver_hardening.ps1`: PASS
2. `validate_frontend_security.cjs`: PASS
3. `run_resolver_migration_smoke.ps1`: PASS
4. `git diff --check`: PASS؛ فقط هشدار معمول LF/CRLF دیده شد.

Smoke test روی کانتینر موقت PostgreSQL 16 اجرا شد و در پایان تراکنش را rollback و کانتینر آزمایشی را حذف کرد. سناریوهای گزارش‌شده شامل AUTH_REQUIRED، حساب آرشیوشده، ACL-101/118، مرزهای Scope، عضویت منقضی، temporary allow/deny و SEC-404/405 است.

این تست‌ها موارد زیر را اثبات نمی‌کنند:
- رفتار با JWT و نشست واقعی Supabase؛
- RLS با نقش‌های واقعی `authenticated` و `anon`؛
- جداسازی واقعی دو tenant در محیط فعال؛
- اجرای Migration روی PostgreSQL 17 فعال.

## 7. وضعیت انتشار و محدودیت اقدام

- Migration محلی روی دیتابیس فعال اجرا نشده است.
- هیچ policy جدیدی ساخته نشده است.
- هیچ grant/revoke جدیدی اعمال نشده است.
- هیچ داده عملیاتی تغییر نکرده است.
- هیچ commit، push یا merge انجام نشده است.
- PR شماره ۱ همچنان نباید بدون تأیید صریح کاربر merge شود.

## 8. گام‌های بعدی پیشنهادی

1. پیش از انتشار، بازبینی نهایی Migration و تأیید سازگاری قیود با وضعیت واقعی داده انجام شود.
2. برای اثبات کامل، harness پذیرش با JWT واقعی و حداقل دو tenant آزمایشی آماده شود.
3. آزمون روی نسخه PostgreSQL 17 در محیط جداگانه/مجاز اجرا شود؛ بدون ایجاد محیط پولی جدید مگر با تأیید کاربر.
4. پس از تکمیل آزمون‌ها، اجرای Migration روی پروژه فعال فقط با تأیید صریح و مستقل کاربر انجام شود.
5. پس از انتشار، تعریف توابع، ACL، قیود و Security Advisor دوباره بررسی شوند.


## 9. بررسی تکمیلی سطح API و RLS — 2026-11-19

### 9.1 توابع و نقاط ورود API

بررسی read-only فهرست توابع schema عمومی نشان داد فقط دو تابع عمومی وجود دارد:
- `public.hr_bootstrap_first_admin(...)`
- `public.hr_session_status()`

برای هیچ‌یک از APIهای کسب‌وکاری قراردادشده در `API-Contract-Org-Admin-v0.1.md`، تابع عمومی متناظر هنوز وجود ندارد. همچنین فهرست Edge Functions پروژه خالی است.

نتیجه: Resolver فعلی هنوز از مسیر API کسب‌وکاری فراخوانی نمی‌شود و UI ساختار سازمانی هنوز مسیر خواندن امن از API ندارد. بنابراین این مرحله صرفاً اصلاح موتور مجوز و آماده‌سازی زیرساخت است، نه تکمیل اتصال واقعی UI.

### 9.2 سیاست‌های RLS مشاهده‌شده

در schemaهای `hr_*` چهار policy مشاهده شد:
- `hr_core.tenants`: خواندن tenant جاری با `hr_security.current_tenant_id()`.
- `hr_security.app_users`: خواندن رکورد خود کاربر با `auth.uid()` و `current_app_user_id()` و status فعال.
- `hr_security.permissions`: خواندن کاتالوگ permission فعال.
- `hr_security.systems`: خواندن سیستم فعال.

هیچ policy جدیدی ساخته نشد. سایر جدول‌های HR-SOFT همچنان بدون policy و به‌صورت fail-closed هستند؛ هشدار INFO مربوط به RLS بدون policy نباید با policy عمومی یا دسترسی باز برطرف شود.

نکته: پس از اعمال اصلاح RES-003، policyهای مبتنی بر `current_app_user_id()` و `current_tenant_id()` باید با حساب آرشیوشده و نشست واقعی دوباره آزموده شوند؛ انتظار می‌رود helperها برای حساب آرشیوشده NULL بدهند و policy دسترسی ندهد.

### 9.3 وضعیت تازه Security و Performance Advisor

در بررسی 2026-11-19:
- Security Advisor: یک هشدار WARN درباره غیرفعال بودن Leaked Password Protection.
- Security Advisor: 53 مورد INFO از نوع RLS Enabled No Policy؛ با توجه به طراحی fail-closed، این موارد به‌خودی‌خود مجوز افزودن policy عمومی نیستند.
- Performance Advisor: تعداد 103 مورد INFO از نوع Unused Index.
- تعداد Edge Functionهای مستقرشده: صفر.

اقدام پیشنهادی:
1. فعال‌سازی Leaked Password Protection از Auth Settings پس از بررسی اثر آن بر سیاست رمز عبور؛ این تغییر در این مرحله انجام نشد.
2. حذف ایندکس‌های unused انجام نشود؛ پایگاه داده هنوز بار عملیاتی کافی برای نتیجه‌گیری ندارد.
3. تا آماده‌شدن API wrapperهای امن و آزمون JWT/RLS، هیچ policy عمومی یا دسترسی مستقیم به جدول‌های عملیاتی اضافه نشود.

## 10. اولویت‌های اجرایی باز

| اولویت | مورد | وضعیت |
|---|---|---|
| P0 | اجرای آزمون پذیرش با JWT واقعی و roleهای authenticated/anon | باز |
| P0 | اثبات deny-overrides-allow با نشست واقعی و دو گروه | باز |
| P0 | اثبات جداسازی tenant و جلوگیری از جعل company/org/personnel context | باز؛ API wrapper هنوز وجود ندارد |
| P1 | اجرای Migration اصلاحی روی PostgreSQL 17 در محیط مجاز | آماده‌سازی‌شده؛ انتشار نشده |
| P1 | تصمیم و طراحی command امن برای تأییدکننده دسترسی موقت (SEC-414) | باز |
| P1 | اتصال UI ساختار سازمانی به API خواندنی امن | قرارداد طراحی شده؛ پیاده‌سازی نشده |
| P2 | بازبینی Leaked Password Protection | هشدار فعال؛ تغییر لازم دارد |
| P2 | بازبینی ایندکس‌های unused پس از ورود بار عملیاتی | فعلاً تعویق |


## 11. تطبیق قرارداد Snapshot با ساختار واقعی hr_org

بر اساس `information_schema.columns` در دیتابیس فعال، ساختار ستون‌های پنج جدول اصلی به شرح زیر است. این بررسی فقط خواندنی بوده است.

| جدول | ستون‌های اصلی تأییدشده | ملاحظات قرارداد |
|---|---|---|
| `hr_org.org_layers` | id, tenant_id, company_id, layer_code, title, sort_order, is_active | ترتیب نمایش از `sort_order` می‌آید؛ ستون valid_from/valid_to در این جدول وجود ندارد. |
| `hr_org.org_units` | id, tenant_id, company_id, layer_id, parent_unit_id, unit_code, title, unit_type_code, is_visible, is_active, valid_from, valid_to, archived_at | تاریخ اعتبار و آرشیو باید در snapshot اعمال شوند؛ `layer_id` nullable است. |
| `hr_org.organizational_positions` | id, tenant_id, company_id, position_key, title, priority, level_code, is_visible, is_active, valid_from, valid_to | ترتیب/اولویت از `priority` است؛ عنوان سطح و شناسه آن باید با مدل UI تطبیق داده شود. |
| `hr_org.positions` | id, tenant_id, company_id, org_unit_id, position_code, title, superior_position_id, approved_capacity, is_active, valid_from, valid_to, archived_at, organizational_position_id | قرارداد باید فقط از این ستون‌های واقعی استفاده کند؛ هیچ فیلد legacy مانند پایه سمت یا ماهیت شغل در این جدول وجود ندارد. |
| `hr_org.position_relationships` | id, tenant_id, company_id, from_position_id, to_position_id, relationship_type, valid_from, valid_to, description | این جدول company_id دارد؛ هر دو سمت رابطه باید در همان tenant/company و بازه معتبر کنترل شوند. |

در بررسی قبلی شمارش داده‌ها، پنج جدول بالا خالی بودند؛ بنابراین صحت ساختار و کلیدها قابل بررسی است، اما صحت رفتار snapshot روی داده واقعی سازمانی هنوز قابل اثبات نیست.

### نکات لازم برای پیاده‌سازی امن snapshot

1. ابتدا شرکت انتخابی از `hr_core.companies` با tenant استخراج‌شده از نشست، `archived_at IS NULL`، `status='active'` و بازه اعتبار کنترل شود.
2. هر query به جدول‌های سازمانی باید هم‌زمان tenant_id و company_id را محدود کند؛ اتکا به UUID ورودی کافی نیست.
3. برای `org_units` و `positions` علاوه بر بازه اعتبار، وضعیت فعال و archived_at کنترل شود.
4. برای `organizational_positions`، `is_visible`, `is_active` و بازه اعتبار اعمال شود؛ وضعیت آرشیو در ستون‌های فهرست‌شده وجود ندارد.
5. `org_layers` فاقد بازه اعتبار و archived_at است؛ فقط is_active و company/tenant scope در فاز اول قابل اعمال است.
6. برای `position_relationships` بازه اعتبار و company/tenant scope اعمال شود؛ ستون وضعیت فعال/آرشیو در فهرست ستون‌ها وجود ندارد.
7. در قرارداد خروجی، فیلدهای UI باید نام‌های مشتق‌شده و مستند داشته باشند؛ نباید وجود ستون‌هایی را القا کرد که در DB نیستند.
8. تا زمان وجود داده آزمایشی معتبر، تست خروجی snapshot باید با fixtureهای جداگانه و tenantهای ساختگی انجام شود، نه با تغییر داده‌های عملیاتی پروژه فعال.


## 12. اصلاح کیفیت آزمون امنیت فرانت‌اند

در بازبینی خود اسکریپت `validate_frontend_security.cjs` مشخص شد regex تشخیص مقداردهی کلیدهای `service_role` بیش از حد escape شده بود. این نقص می‌توانست یک false negative در خود آزمون امنیتی ایجاد کند.

الگو اصلاح شد و سه regression assertion افزوده شد:
- تشخیص `SUPABASE_SERVICE_ROLE_KEY = '...'` با فاصله.
- تشخیص `service_role:'...'` بدون فاصله.
- عدم تشخیص اشتباه متغیر `SUPABASE_ANON_KEY`.

پس از اصلاح، اسکریپت دوباره اجرا شد و تمام آزمون‌ها PASS شدند. این مورد نشان می‌دهد نتیجه PASS قبلی به‌تنهایی کافی نبود؛ نسخه فعلی آزمون پوشش دقیق‌تری برای این الگو دارد.
