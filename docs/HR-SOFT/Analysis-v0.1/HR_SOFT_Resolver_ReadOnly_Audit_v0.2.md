# HR-SOFT — الحاقیه ممیزی فقط‌خواندنی موتور مجوز
## نسخه 0.2 | ۱۹ نوامبر ۲۰۲۶

- محیط بررسی: Supabase Org-Ch / HR-SOFT
- Project ID: xdjhshktjtevusigqzya
- روش: مشاهده وضعیت دیتابیس، تعریف توابع، مجوزهای EXECUTE، قیود و برنامه‌های آزمون؛ بدون تغییر دیتابیس
- وضعیت: ممیزی ایستا تکمیل شد؛ آزمون پذیرش با JWT واقعی هنوز انجام نشده است.

## 1. شواهد وضعیت فعلی

- پروژه Supabase در وضعیت ACTIVE_HEALTHY و PostgreSQL 17.11 است.
- پنج migration در تاریخچه ثبت شده‌اند: foundation، performance/security hardening، API schema lockdown، bootstrap/permission resolver و internalize کردن bootstrap.
- 57 از 57 جدول HR در schemaهای hr_* دارای RLS و FORCE ROW LEVEL SECURITY هستند.
- توابع hr_internal.evaluate_permission_context و hr_internal.scope_matches برای anon و authenticated مجوز EXECUTE ندارند.
- تابع داخلی evaluate_permission_context از SECURITY DEFINER و search_path خالی استفاده می‌کند.
- public.hr_session_status و public.hr_bootstrap_first_admin برای authenticated مجاز و برای anon غیرمجاز هستند.
- Security Advisor مورد بحرانی گزارش نکرد؛ هشدار Leaked Password Protection همچنان فعال است.
- 53 هشدار INFO مربوط به جدول‌های RLS بدون policy مشاهده شد. با توجه به طراحی fail-closed، برای رفع ظاهری این هشدارها policy عمومی اضافه نشود.
- Performance Advisor ایندکس‌های استفاده‌نشده را گزارش می‌کند؛ تا زمان وجود بار عملیاتی و شواهد، حذف ایندکس توصیه نمی‌شود.

- قیدهای هم‌سیستمی group_permission_rules و triggerهای append-only برای user_login_events و user_access_events در دیتابیس فعال مشاهده شدند.
- در temporary_access ستون approved_at و FK مرکب approver در همان tenant وجود دارد؛ اما قید approval pair و قید الزام approval برای scope خالی وجود ندارند. جدول در زمان بررسی صفر ردیف داشت.

## 2. یافته‌های منطق Resolver

### RES-001 — بالا: تقدم deny در عملیات add/edit/delete به‌درستی تضمین نشده
**وضعیت: ایراد ایستا تأیید شد؛ اصلاح در migration شاخه کاری آماده شده و هنوز deploy نشده است.**

در نسخه مستقر Resolver (v2.4.1)، در هر دو شمارش v_group_allow و v_group_deny شرط CASE مربوط به can_add/can_edit/can_delete اعمال شده بود. در شمارش deny همین شرط باعث می‌شد deny با پرچم عملیات خاموش از شمارش خارج شود. migration پیشنهادی v2.4.2 این شرط را فقط از مسیر deny حذف می‌کند.

در نتیجه سناریوی ACL-118 برنامه آزمون (deny rule با تمام can_* خاموش باید همچنان deny باشد) در عملیات add/edit/delete با کد فعلی تضمین نمی‌شود. همچنین اگر effect در group_scope_assignments برابر deny باشد، شرط پرچم عملیات می‌تواند مانع شمارش آن شود.

**اصلاح آماده‌شده در migration پیشنهادی:** شرط can_* از مسیر v_group_deny حذف شده و در مسیر allow حفظ شده است؛ بنابراین deny پس از احراز membership معتبر و تطبیق scope مستقل از پرچم‌های can_* شمارش می‌شود. ACL-118، ACL-121 و ACL-124 برای آزمون این رفتار افزوده شده‌اند. migration هنوز اجرا نشده است.

### RES-002 — متوسط: semantics scope خالی؛ تصمیم طراحی ثبت شد
در شمارش temporary deny شرط ta.scope_id IS NOT NULL وجود دارد؛ بنابراین temporary deny با scope خالی وارد deny count نمی‌شود. برنامه آزمون ACL-112 نیز می‌گوید scope خالی نباید خودکار به معنی tenant-wide باشد، اما رفتار مجاز دقیق را به policy واگذار کرده است.

**تصمیم طراحی برای این فاز:** scope خالی هرگز tenant-wide فرض نمی‌شود؛ Resolver آن را fail-closed نگه می‌دارد و write wrapper باید آن را با INVALID_ARGUMENT رد کند. دسترسی tenant-wide فقط با data_scope صریح از نوع tenant تعریف می‌شود. این سیاست در قرارداد API و ACL-127 ثبت شده است؛ فعال‌سازی هر نوع temporary access سراسری همچنان به command امن و کنترل SEC-414 وابسته است.

### RES-003 — متوسط: یکسان‌سازی تشخیص کاربر فعال
Resolver علاوه بر status='active'، archived_at IS NULL را بررسی می‌کند؛ اما توابع hr_security.current_app_user_id و current_tenant_id و نیز public.hr_session_status فقط status='active' را بررسی می‌کردند. بنابراین حسابی که archived_at دارد اما status آن هنوز active است، در این مسیرها فعال تلقی می‌شد.

**اصلاح آماده‌شده در migration پیشنهادی:** شرط archived_at IS NULL به هر سه تابع افزوده شده است. ACL-123 برای آزمون رفتار همسان اضافه شده؛ migration هنوز deploy نشده است.

### RES-004 — باز: مجاز بودن approver دسترسی موقت
قیدهای فعلی، برای temporary allow وجود scope، approved_by و approved_at را الزام می‌کنند و Resolver نیز وجود metadata تأیید را بررسی می‌کند. اما این موارد به‌تنهایی اثبات نمی‌کنند approver مدیر مجاز همان tenant بوده است.

آزمون SEC-414 صراحتاً بررسی مجوز approver را در command سمت سرور لازم می‌داند. چون command/API نوشتن هنوز طراحی و مستقر نشده، این کنترل هنوز قابل تأیید نیست.

### RES-005 — متوسط: قیود یکپارچگی تأیید temporary_access ناقص‌اند
در دیتابیس فعال ستون approved_at و FK مرکب (tenant_id, approved_by) وجود دارد؛ اما دو قید Stage 18 در جدول دیده نشدند:
- approval pair: approved_by و approved_at باید هر دو NULL یا هر دو غیر NULL باشند.
- global-scope approval: اگر scope_id خالی باشد، هر دو metadata تأیید باید وجود داشته باشند.

قید موجود فعلی فقط برای effect='allow'، scope و هر دو metadata را الزام می‌کند؛ برای effect='deny' این دو قاعده را کامل پوشش نمی‌دهد. جدول temporary_access در زمان بررسی صفر ردیف داشت.

**اصلاح آماده‌شده در migration پیشنهادی:** دو CHECK constraint از Stage 18 اضافه و پس از preflight/بررسی خالی بودن جدول validate شده‌اند. FK approver تکرار نشده چون در دیتابیس فعال موجود است. scope خالی در Resolver همچنان خودکار tenant-wide تفسیر نمی‌شود؛ فعال‌سازی دسترسی سراسری منوط به semantics روشن و command سمت سرور با کنترل SEC-414 است.

## 3. مواردی که هنوز اثبات نشده‌اند

- deny precedence در چند عضویتی با JWT واقعی.
- انقضای membership و temporary access در زمان واقعی.
- مرزهای tenant، company، org unit و personnel با دو tenant آزمایشی.
- تطبیق context استخراج‌شده در wrapper سمت سرور با resource واقعی.
- رفتار scopeهای تاریخی و hierarchy در تاریخ گذشته.
- ثبت audit در همان transaction برای read/download حساس.
- آزمون‌های SEC-401 تا SEC-414 و ACL-101 تا ACL-127 با roleهای واقعی.

تست با postgres/owner یا جعل claim در SQL editor جایگزین آزمون با نشست معتبر کاربر نیست.

## 4. تصمیم اجرایی

1. فعلاً هیچ API کسب‌وکاری و هیچ policy permissive به RLS متصل نشود.
2. migration پیشنهادی RES-001، RES-003 و RES-005 در شاخه کاری آماده شده؛ بازبینی ایستا انجام شده و تا آزمون در محیط disposable روی دیتابیس فعال اجرا نشود.
3. RES-002: scope خالی tenant-wide نیست؛ write wrapper باید آن را رد کند و tenant-wide فقط با scope صریح تعریف شود.
4. ACL-118 و ACL-121 تا ACL-127 در برنامه آزمون v2.5 ثبت شده‌اند.
5. SEC-414 تا طراحی command امن، باز بماند.
6. پس از آماده شدن harness معتبر، تست‌های پذیرش با JWT واقعی و tenantهای آزمایشی اجرا شوند.
7. فعال‌سازی Leaked Password Protection از تنظیمات Auth در یک گام جداگانه بررسی شود.

## 5. وضعیت Git

- شاخه: docs/hr-soft-design-v3.5
- تغییرات محلی قبلی حفظ شده‌اند: README.md، supabase/README.md و API-Contract-Org-Admin-v0.1.md
- git diff --check بدون خطای whitespace/conflict marker بود؛ فقط هشدار تبدیل LF به CRLF دیده شد.
- فایل migration پیشنهادی `20261119090000_hr_soft_resolver_deny_precedence_hardening.sql` ایجاد شده است. Supabase CLI هنوز نصب نیست؛ فایل با الگوی timestamp migration ساخته شد.
- اسکریپت `supabase/tests/validate_resolver_hardening.ps1` با موفقیت اجرا شد.
- اسکریپت تکرارپذیر `supabase/tests/run_resolver_migration_smoke.ps1` ایجاد و اجرا شد؛ migration در کانتینر موقت PostgreSQL 16 اعمال شد؛ مسیرهای AUTH_REQUIRED و APP_USER_INACTIVE، عدم provision برای حساب archived، helperهای null و قیود SEC-404/405 موفق بودند. در unit simulation با auth.uid ساختگی و پیاده‌سازی واقعی scope_matches از migration منبع، ACL-101، ACL-102، ACL-103، ACL-104، ACL-105، ACL-106، ACL-107، ACL-108، ACL-109، ACL-110، ACL-111، ACL-114، ACL-115، ACL-116، ACL-117، ACL-118، ACL-120، ACL-121، ACL-123، ACL-124، ACL-127 و ACL-128 پاس شدند؛ قیود SEC-404/405 نیز آزموده شدند؛ این نتایج آزمون JWT واقعی یا RLS نیستند. کانتینر پس از آزمون حذف شد.
- این آزمون جایگزین تست کامل Resolver با JWT واقعی، tenant isolation یا آزمون روی PostgreSQL 17 نیست؛ migration روی Supabase فعال اجرا نشده است.
- برنامه آزمون `HR_SOFT_Access_Resolver_Test_Plan_v2.5.md` ایجاد شده است.
- commit، push، PR merge و تغییر دیتابیس انجام نشده است.
