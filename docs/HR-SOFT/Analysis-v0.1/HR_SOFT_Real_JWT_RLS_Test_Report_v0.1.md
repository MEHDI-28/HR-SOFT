# HR-SOFT — گزارش آزمون واقعی JWT و RLS
## نسخه 0.1 | محیط محلی Supabase / PostgreSQL 17.11
**تاریخ اجرا:** 2026-11-19  
**نتیجه:** PASS برای دامنه محدود این گزارش؛ این گزارش تأیید پذیرش کامل امنیتی یا مجوز انتشار تولیدی نیست.

## هدف و محیط
آزمون برای بررسی این موارد اجرا شد:
- پذیرش JWT واقعی صادرشده توسط Supabase Auth؛
- ارزیابی توابع هویت و وضعیت نشست در درخواست PostgREST؛
- اجرای RLS با نقش واقعی `authenticated` از مسیر HTTP؛
- جداسازی دو Tenant در جدول‌های `hr_core.tenants` و `hr_security.app_users`؛
- محدودیت مشاهده کاتالوگ سیستم‌ها و مجوزها به رکوردهای فعال؛
- جلوگیری از اجرای probe آزمایشی توسط نقش `anon`.

محیط آزمون، stack مستقل Supabase محلی متصل به PostgreSQL 17.11 بود. همه شش migration مخزن روی این محیط محلی اعمال شده بودند. هیچ درخواست آزمونی به پروژه میزبانی‌شده Org-Ch ارسال نشد.

## روش اجرا
1. چهار حساب موقت از مسیر Admin API محلی Auth ایجاد شدند.
2. برای هر حساب، ورود با ایمیل و رمز عبور از endpoint واقعی Auth انجام شد و access token صادرشده توسط Auth دریافت شد.
3. fixtureهای دو Tenant و mappingهای HR با SQL مدیریتی فقط در دیتابیس محلی ساخته شدند.
4. یک تابع موقت `SECURITY INVOKER` در schema عمومی، صرفاً برای مشاهده نتایج RLS ساخته شد. اجرای آن فقط به `authenticated` اعطا و از `PUBLIC` و `anon` سلب شد.
5. درخواست‌های RPC از طریق PostgREST و با Bearer token واقعی هر کاربر ارسال شدند.
6. پس از آزمون، تابع، fixtureها و حساب‌های Auth موقت حذف شدند.

کلیدهای محلی و رمزهای موقت در خروجی چاپ یا در فایل ذخیره نشدند؛ کلیدهای محلی فقط در حافظه اسکریپت استفاده شدند.

## نتایج

| سناریو | احراز هویت JWT | Provisioned | Tenant قابل مشاهده | app_user قابل مشاهده | رکورد Tenant دیگر | نتیجه |
|---|---:|---:|---:|---:|---:|---|
| کاربر فعال Tenant A | بله | بله | 1 | 1 | 0 | PASS |
| کاربر فعال Tenant B | بله | بله | 1 | 1 | 0 | PASS |
| حساب آرشیوشده | بله | خیر | 0 | 0 | 0 | PASS |
| کاربر بدون mapping سازمانی | بله | خیر | 0 | 0 | 0 | PASS |

نتایج تکمیلی:
- هر چهار JWT واقعی توسط PostgREST پذیرفته شدند.
- `hr_security.current_tenant_id()` و `current_app_user_id()` برای دو کاربر فعال، context مختص همان کاربر را برگرداندند.
- برای حساب آرشیوشده و حساب فاقد mapping، هر دو helper مقدار NULL برگرداندند.
- `public.hr_session_status()` برای هر چهار کاربر، authenticated=true و provisioned مطابق انتظار را برگرداند.
- هر چهار کاربر فقط یک system فعال و یک permission فعال دیدند؛ system و permission غیرفعال قابل مشاهده نبودند.
- اجرای تابع probe با نقش ناشناس `anon` رد شد (HTTP 401 یا 403).

## پاک‌سازی و کنترل اثر
پس از اجرای آزمون، شمارش مجدد دیتابیس محلی نشان داد:
- Tenant آزمایشی: 0
- app_user آزمایشی: 0
- system آزمایشی: 0
- permission آزمایشی: 0
- حساب Auth آزمایشی: 0
- تابع probe موقت: 0

بنابراین داده و تابع آزمایشی در دیتابیس محلی باقی نماندند.

## محدودیت‌ها و آزمون‌های باز
این آزمون فقط سیاست‌های RLS فعلی برای `hr_core.tenants`، `hr_security.app_users`، `hr_security.systems` و `hr_security.permissions` را از مسیر JWT واقعی پوشش می‌دهد. قید `app_users_check` نیز سازگاری `status` و `archived_at` را enforce می‌کند؛ بنابراین وضعیت ناسازگار `status='active'` همراه `archived_at` غیرتهی قابل درج نیست. سناریوی JWT حساب آرشیوشده با `status='archived'` و `archived_at` غیرتهی آزموده شد.

موارد زیر هنوز اثبات نشده‌اند:
- جداسازی Tenant در جدول‌های عملیاتی شرکت، واحد سازمانی، پرونده پرسنلی و گردش‌کار؛
- رفتار CRUD و context derivation در APIهای کسب‌وکاری؛ این APIها هنوز پیاده‌سازی نشده‌اند؛
- اجرای Resolver از طریق wrapper معتبر و آزمون ترکیب کامل role، scope، membership، deny و temporary access با JWT؛
- آزمون‌های ACL-101 تا ACL-128 به‌صورت end-to-end از HTTP؛ آزمون‌های منطقی قبلی جایگزین آزمون end-to-end نیستند؛
- آزمون audit در همان transaction برای خواندن/دانلود داده حساس؛
- آزمون رفتار واقعی با داده و بار عملیاتی.

## فایل آزمون قابل تکرار
از ریشه مخزن و در حالی که Supabase محلی اجراست:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\supabase\tests\run_local_jwt_rls.ps1
```

اسکریپت حساب‌ها و fixtureهای آزمایشی را موقتاً ایجاد و در پایان حذف می‌کند. فقط برای stack محلی و disposable استفاده شود؛ آن را به‌عنوان ابزار آزمون production اجرا نکنید.

## تصمیم انتشار
Migration `20261119090000_hr_soft_resolver_deny_precedence_hardening.sql` همچنان فقط در working tree است و در تاریخ این گزارش در migration history پروژه hosted ثبت نشده است. این آزمون هیچ migrationای را روی پروژه hosted اجرا نکرده و مجوز انتشار محسوب نمی‌شود.


## اجرای مجدد مستقل در 2026-11-19

**نتیجه اجرای مجدد:** PASS — اسکریپت `supabase/tests/run_local_jwt_rls.ps1` روی Supabase محلی اجرا شد و با exit code 0 پایان یافت.

### محیط واقعی اجرا
- API مورد استفاده: Supabase محلی روی `127.0.0.1:54321`؛ اسکریپت از `API_URL`، `ANON_KEY` و `SERVICE_ROLE_KEY` محلی CLI استفاده کرد.
- نسخه واقعی PostgreSQL: **17.11**.
- تاریخچه migration محلی شامل هر شش نسخه، از جمله `20261119090000` بود.
- هیچ درخواست یا تغییری به پروژه hosted Org-Ch انجام نشد.

### نتایج تکرار آزمون JWT/RLS

| سناریو | JWT معتبر | Provisioned | Tenant rows | app_user rows | رکورد Tenant دیگر | نتیجه |
|---|---:|---:|---:|---:|---:|---|
| کاربر فعال Tenant A | بله | بله | 1 | 1 | 0 | PASS |
| کاربر فعال Tenant B | بله | بله | 1 | 1 | 0 | PASS |
| حساب آرشیوشده | بله | خیر | 0 | 0 | 0 | PASS |
| کاربر بدون mapping سازمانی | بله | خیر | 0 | 0 | 0 | PASS |

- هر چهار JWT صادرشده از Auth واقعی توسط PostgREST پذیرفته شدند.
- هر Tenant فقط Tenant و app_user متعلق به خود را دید.
- حساب آرشیوشده و حساب provision نشده، با وجود JWT معتبر، هیچ رکورد HR از tenant/app_user مشاهده نکردند.
- فقط system و permission فعال قابل مشاهده بودند.
- اجرای probe مخصوص نقش authenticated برای anon رد شد.

### کنترل پاک‌سازی پس از اجرا

بلافاصله پس از پایان اسکریپت، شمارش مستقل انجام شد:

| داده یا شیء آزمایشی | باقی‌مانده |
|---|---:|
| Tenant آزمایشی | 0 |
| app_user آزمایشی | 0 |
| حساب Auth آزمایشی | 0 |
| system آزمایشی | 0 |
| permission آزمایشی | 0 |
| تابع probe موقت | 0 |

### دامنه اعتبار نتیجه
این اجرای مجدد، پذیرش JWT واقعی و جداسازی Tenant را فقط برای چهار جدول/سیاست موجود در این گزارش و در محیط محلی تأیید می‌کند. این نتیجه اثبات‌کننده جداسازی تمام جداول عملیاتی یا APIهای کسب‌وکاری نیست؛ زیرا APIهای کسب‌وکاری هنوز پیاده‌سازی نشده‌اند. آزمون end-to-end خود Resolver و audit تراکنشی نیز همچنان باز است.

**وضعیت انتشار:** Migration `20261119090000` فقط در محیط محلی اجرا شده است. این گزارش مجوز انتشار روی پروژه hosted نیست.


## 2026-11-19 — آزمون end-to-end خود Resolver با JWT واقعی

**نتیجه: PASS در محیط محلی Supabase / PostgreSQL 17.11.**

برای رفع فاصله آزمون قبلی، harness مستقل `supabase/tests/run_local_resolver_e2e.ps1` اضافه و اجرا شد. این بار JWT فقط برای آزمون RLS استفاده نشد؛ درخواست RPC با JWT واقعی به یک wrapper موقت و محدود رسید و wrapper تابع واقعی `hr_internal.evaluate_permission_context` را اجرا کرد.

### سناریوها و نتایج

| سناریو | خروجی واقعی | نتیجه |
|---|---|---|
| allow گروه اول + deny گروه دوم، عملیات view | `EXPLICIT_DENY`؛ 1 allow و 1 deny | PASS |
| همان وضعیت برای add با تمام `can_*` در گروه deny خاموش | `EXPLICIT_DENY`؛ 1 allow و 1 deny | PASS |
| همان وضعیت برای edit با تمام `can_*` در گروه deny خاموش | `EXPLICIT_DENY`؛ 1 allow و 1 deny | PASS |
| همان وضعیت برای delete با تمام `can_*` در گروه deny خاموش | `EXPLICIT_DENY`؛ 1 allow و 1 deny | PASS |
| tenant ورودی متفاوت با tenant نشست JWT | `TENANT_MISMATCH` | PASS |
| غیرفعال‌کردن membership گروه deny و باقی‌ماندن allow | `ALLOWED_BY_GROUP`؛ 1 allow و 0 deny | PASS |

### ارزش اثباتی آزمون

- JWT توسط Supabase Auth محلی صادر و توسط PostgREST پذیرفته شد.
- تابع داخلی واقعی Resolver اجرا شد؛ منطق آن در تست بازنویسی یا mock نشد.
- رفتار deny precedence برای هر سه عملیات add/edit/delete با پرچم‌های خاموش deny در runtime تأیید شد.
- مسیر مثبت allow نیز پس از غیرفعال‌شدن عضویت deny تأیید شد.
- mismatch در tenant context به‌صورت fail-closed رد شد.

### مرز آزمون

- wrapper فقط یک harness موقت محلی بود؛ API wrapper محصولی یا endpoint عملیاتی محسوب نمی‌شود.
- این آزمون، جلوگیری از جعل company/org_unit/personnel context توسط APIهای محصول را اثبات نمی‌کند؛ چنین wrapperهای کسب‌وکاری هنوز پیاده‌سازی نشده‌اند.
- ثبت Audit در همان transaction برای عملیات حساس هنوز end-to-end اثبات نشده است.
- آزمون scopeهای company/org_unit/personnel، temporary access و permissionهای حساس در این اجرای JWT-specific پوشش داده نشد؛ پوشش منطقی قبلی آن‌ها در smoke test جداگانه است.
- هیچ شیء آزمایشی در پایان باقی نماند: tenant، Auth user، system، permission و تابع probe همگی شمارش صفر داشتند.

**وضعیت انتشار:** این آزمون فقط در Supabase محلی اجرا شد. Migration `20261119090000` همچنان روی پروژه hosted اجرا نشده است.
