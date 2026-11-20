# HR-SOFT — طرح آزمون پذیرش API امن و Audit تراکنشی
## v0.1 — 2026-11-19

- وضعیت: طراحی و معیار پذیرش؛ هیچ API یا Migration جدیدی ایجاد/منتشر نشده است.
- مرجع: `API-Contract-Org-Admin-v0.1.md`، Resolver v2.4.2 و ساختار فعلی schemaهای `hr_core`، `hr_org`، `hr_security` و `hr_audit`.
- دامنه: تعریف آزمون‌هایی که باید پیش از اتصال UI ساختار سازمانی و پیش از هر عملیات تغییردهنده داده پاس شوند.

## 1. وضعیت فنی تأییدشده

1. تابع داخلی `hr_internal.evaluate_permission_context(...)` وجود دارد و اجرای مستقیم آن برای `authenticated` مجاز نیست.
2. تابع عمومی کسب‌وکاری برای context یا snapshot ساختار سازمانی هنوز وجود ندارد.
3. APIهای نوشتن سازمانی و عملیات دارای Audit هنوز پیاده‌سازی نشده‌اند.
4. جدول `hr_audit.audit_events` در مدل پایه وجود دارد؛ وجود جدول به‌تنهایی تضمین نمی‌کند wrapperها رویداد صحیح را ثبت می‌کنند.
5. آزمون JWT واقعی و اجرای خود Resolver از طریق wrapper موقت آزمایشی موفق شده است؛ این wrapper حذف شده و بخشی از محصول نیست.

## 2. الزامات مرز RPC

هر RPC عمومی باید:
- فقط در schema عمومی expose شود و فقط به نقش `authenticated` مجوز EXECUTE داشته باشد؛ `PUBLIC` و `anon` باید صریحاً رد شوند.
- در صورت استفاده از `SECURITY DEFINER`، دارای `search_path = ''` باشد و همه اشیای دیتابیس را با نام schema کامل فراخوانی کند.
- tenant و app_user را از `auth.uid()` و نگاشت فعال `hr_security.app_users` استخراج کند؛ ورودی tenant از مرورگر نپذیرد.
- وضعیت `status='active'` و `archived_at IS NULL` را کنترل کند.
- شناسه شرکت را فقط به‌عنوان انتخاب resource بپذیرد و تعلق، وضعیت فعال، آرشیو و بازه اعتبار آن را در tenant جاری بررسی کند.
- برای org_unit/personnel context، شناسه منبع را با tenant و company معتبر در سرور تطبیق دهد؛ از UUID ورودی به‌عنوان اثبات مجوز استفاده نکند.
- قبل از خواندن یا تغییر داده، Resolver را با context استخراج‌شده در سرور فراخوانی کند.
- پاسخ‌های خطا را بدون افشای وجود منابع tenant دیگر یکسان‌سازی کند.

## 3. قرارداد پیشنهادی آزمون context

| ID | ورودی/وضعیت | انتظار |
|---|---|---|
| API-CTX-01 | بدون JWT | AUTH_REQUIRED یا رد HTTP 401 |
| API-CTX-02 | JWT معتبر بدون app_user | APP_USER_INACTIVE؛ بدون داده دامنه |
| API-CTX-03 | app_user آرشیوشده با status ناسازگار/active | provision نشود؛ helperها NULL |
| API-CTX-04 | تلاش مرورگر برای ارسال tenant_id | پارامتر پذیرفته نشود؛ tenant فقط از نشست resolve شود |
| API-CTX-05 | company_id ناموجود | RESOURCE_NOT_FOUND |
| API-CTX-06 | company_id متعلق به tenant دیگر | همان RESOURCE_NOT_FOUND؛ بدون افشای وجود |
| API-CTX-07 | org_unit_id متعلق به شرکت دیگر | RESOURCE_NOT_FOUND یا PERMISSION_DENIED مطابق قرارداد ثابت |
| API-CTX-08 | resource خارج از بازه اعتبار یا archived | در snapshot جاری بازنگردد |
| API-CTX-09 | جعل company/org_unit/personnel در payload | context معتبر از DB استخراج شود؛ داده خارج از scope صفر |
| API-CTX-10 | Resolver deny در گروه دیگر در برابر allow | PERMISSION_DENIED |

## 4. قرارداد Audit تراکنشی

برای هر عملیات تغییردهنده داده:
1. احراز هویت، app_user فعال، resource scope و مجوز Resolver پیش از mutation انجام شود.
2. mutation و درج `hr_audit.audit_events` در همان تابع RPC و همان transaction دیتابیس باشند.
3. actor از `hr_security.current_app_user_id()` و tenant از نشست resolve شود؛ هیچ‌کدام از payload مرورگر پذیرفته نشوند.
4. رویداد حداقل شامل tenant، actor، event_type، entity_schema، entity_table، entity_id، occurred_at و reason متناسب با قرارداد باشد.
5. before/after state فقط به اندازه نیاز ممیزی ذخیره شود؛ داده بانکی، رمز، token، کلید یا محتوای حساس غیرضروری در payload ثبت نشود.
6. خطای درج Audit نباید بلعیده شود. اگر Audit الزامی است، خطای آن باید کل RPC را rollback کند.
7. هیچ مسیر جایگزین مستقیمی برای نوشتن جدول دامنه از مرورگر یا roleهای عمومی وجود نداشته باشد.

### آزمون‌های Audit

| ID | سناریو | انتظار |
|---|---|---|
| AUD-01 | عملیات مجاز و موفق | mutation و یک audit event در یک transaction ثبت شوند |
| AUD-02 | Resolver deny | mutation صفر و audit موفقیت صفر؛ در صورت نیاز فقط رویداد امنیتی مستقل و کنترل‌شده |
| AUD-03 | درج Audit عمداً با constraint failure مواجه شود | کل RPC rollback؛ mutation نیز باقی نماند |
| AUD-04 | خطای mutation پس از بررسی مجوز | هیچ audit success ثبت نشود |
| AUD-05 | actor/tenant در payload جعلی باشد | نادیده گرفته شود؛ actor/tenant از نشست تعیین شوند |
| AUD-06 | کاربر tenant A به entity tenant B اشاره کند | RESOURCE_NOT_FOUND؛ هیچ داده یا Audit متعلق به B افشا نشود |
| AUD-07 | تکرار درخواست یا retry | شناسه درخواست/قواعد idempotency مانع ثبت رویداد تکراری ناخواسته شوند |
| AUD-08 | تلاش anon یا دسترسی مستقیم به جدول | رد شود |

## 5. harness و روش اجرای آینده

- harness باید از Supabase محلی disposable و JWT صادرشده از Auth واقعی استفاده کند.
- برای تست رفتار API، wrapper آزمایشی باید همان الگوی امنیتی RPC محصول را داشته باشد؛ wrapper آزمایشی نباید به‌عنوان endpoint محصول باقی بماند.
- fixtureها باید دو tenant، دو شرکت، حداقل دو گروه، scopeهای متفاوت و یک کاربر دارای JWT واقعی داشته باشند.
- در پایان هر اجرا، حساب Auth، tenantها، شرکت‌ها، گروه‌ها، scopeها، permissionها، تابع probe و audit fixtureها باید حذف یا rollback شوند.
- شمارش صفر با query مستقل پس از cleanup الزامی است.
- اجرای تست فقط با API loopback محلی مجاز است؛ script باید در صورت تشخیص URL غیرمحلی متوقف شود.

## 6. دروازه اتصال UI و انتشار

اتصال UI به snapshot فقط پس از PASS شدن API-CTX-01 تا API-CTX-10 و بازبینی پاسخ‌های خروجی مجاز است.

هر API نوشتن یا تغییر داده تا زمان PASS شدن AUD-01 تا AUD-08، آزمون deny-overrides-allow، آزمون tenant isolation و بازبینی ACL نباید به UI متصل شود.

این سند مجوز ساخت یا انتشار Migration نیست. هر Migration یا تغییر API روی پروژه hosted نیازمند بازبینی جداگانه و تأیید صریح پیش از اجرا است.
