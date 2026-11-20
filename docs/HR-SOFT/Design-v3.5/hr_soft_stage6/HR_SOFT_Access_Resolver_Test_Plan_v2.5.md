# HR-SOFT — آزمون‌های موتور مجوز مؤثر
## نسخه 2.5 | برنامه آزمون اصلاح deny precedence و هویت فعال
?????: **????????? ????? ? ????? Migration ?? PostgreSQL 16.15? 17.12 ? Supabase ???? PostgreSQL 17.11 ???? ????????? JWT/RLS ????? ? ????? ??? Resolver ???? deny-overrides-allow ?? view/add/edit/delete ? tenant mismatch ??? ?? ???? ???? PASS ??? ???. ????? API??? ?????????? ??????? context ???? company/org_unit/personnel ? audit ??????? ?????? ??? ???.**

| ID | سناریو | نتیجه مورد انتظار |
|---|---|---|
| ACL-101 | گروه A allow + گروه B deny برای همان permission و scope | deny |
| ACL-102 | گروه B غیرفعال دارای deny | نادیده گرفته شود |
| ACL-103 | membership منقضی‌شده | نادیده گرفته شود |
| ACL-104 | permission system متفاوت از group.system_id | deny |
| ACL-105 | rule allow بدون scope allow | deny |
| ACL-106 | scope deny در یک گروه و scope allow در گروه دیگر | deny |
| ACL-107 | scope company A و resource company B | deny |
| ACL-108 | scope org_unit با descendants | زیرواحد مجاز؛ خارج درخت deny |
| ACL-109 | org hierarchy در تاریخ گذشته | براساس effective_at؛ تا وجود تاریخچه سلسله‌مراتب، fail-closed |
| ACL-110 | temporary allow خارج بازه | deny |
| ACL-111 | temporary deny همزمان با group allow | deny |
| ACL-112 | temporary access با scope null | فقط مطابق policy محدود، نه tenant-wide خودکار |
| ACL-113 | کاربر context جعلی company_id می‌فرستد | wrapper آن را نادیده می‌گیرد و context واقعی resolve می‌کند |
| ACL-114 | permission تغییر می‌کند و درخواست بعدی می‌آید | نتیجه جدید بلافاصله اعمال |
| ACL-115 | personnel.view بدون sensitive.identity.view | اطلاعات هویتی افشا نشود |
| ACL-116 | sensitive.documents.view بدون download | metadata مجاز، bytes ممنوع |
| ACL-117 | system admin بدون sensitive.bank.view | اطلاعات کامل بانکی ممنوع |
| ACL-118 | deny rule با تمام can_* false و scope منطبق | deny برای add/edit/delete همچنان مقدم است |
| ACL-119 | allow rule فقط can_edit=true و operation=view | view طبق تصمیم محصول از rule فعال و scope معتبر؛ semantics باید در seed/contract یکنواخت باشد |
| ACL-120 | هیچ group membership فعال نیست | deny |
| ACL-121 | group_scope_assignments.effect=deny با rule اثر allow و پرچم عملیات خاموش | deny در صورت تطبیق membership و scope |
| ACL-122 | deny در یک گروه و allow در گروه دیگر برای همان عملیات و scope | deny |
| ACL-123 | app_user آرشیوشده با status=archived و archived_at غیرخالی؛ حالت ناسازگار status=active همراه archived_at باید توسط CHECK رد شود | helperهای current_app_user_id/current_tenant_id مقدار null بدهند؛ hr_session_status.is_provisioned=false |
| ACL-124 | allow rule با can_add/can_edit/can_delete خاموش برای همان عملیات | allow نشود؛ اصلاح deny نباید gate مسیر allow را حذف کند |
| ACL-125 | approved_by و approved_at فقط یکی مقدار داشته باشند | قید approval pair رد کند |
| ACL-126 | temporary_access با scope_id خالی و بدون approval metadata | قید global-scope approval رد کند |
| ACL-127 | temporary_access با scope خالی حتی با metadata تأیید | Resolver هیچ allow یا deny ضمنی اعمال نکند؛ write wrapper با INVALID_ARGUMENT رد کند؛ رفتار fail-closed بماند |
| ACL-128 | tenant_id ورودی Resolver با tenant کاربر احراز‌شده متفاوت باشد | TENANT_MISMATCH و عدم ادامه ارزیابی scope/resource |

## معیارهای قبولی
- تمام تست‌های deny precedence و جعل context باید pass شوند.
- ACL-118 و ACL-121 باید با پرچم‌های خاموش و scope منطبق، deny را ثابت کنند.
- ACL-124 باید ثابت کند پرچم‌های can_* همچنان در مسیر allow اعمال می‌شوند.
- ACL-125 و ACL-126 باید قیود approval metadata را تأیید کنند.
- ACL-127 باید ثابت کند scope خالی بدون policy و command امن، tenant-wide تفسیر نمی‌شود.
- تغییر permission در درخواست بعدی اثر کند.
- هیچ wrapper عمومی اجازه ارسال tenant/company/org/personnel context دلخواه ندهد.
- خروجی عمومی جزئیات policy یا نام گروه‌ها را افشا نکند.
- ACL-123 با JWT معتبر و role واقعی authenticated اجرا شود؛ تست صرفاً با postgres برای این مورد کافی نیست.

## پیش‌نیاز اجرا
- محیط disposable/staging مستقل؛ هرگز production نباشد.
- Tenant A و Tenant B، دو system، دو group، permission و scopeهای ساختگی.
- اجرای تست‌ها با roleهای واقعی PostgreSQL و JWT معتبر Supabase.
- داده‌های تست و membershipها باید در transaction یا fixture قابل پاکسازی باشند.

## وضعیت
این فایل برنامه آزمون است و به معنی اجرای آزمون‌ها یا تأیید امنیتی نیست.

## اجرای فعلی — تفکیک از آزمون پذیرش
- اسکریپت ایستای `supabase/tests/validate_resolver_hardening.ps1`: موفق.
- اسکریپت تکرارپذیر `supabase/tests/run_resolver_migration_smoke.ps1`: موفق؛ کانتینرهای موقت PostgreSQL 16.15 و 17.12 ایجاد شدند، migration روی هر دو نسخه اعمال شد، مسیرهای AUTH_REQUIRED و APP_USER_INACTIVE، عدم provision برای حساب archived، helperهای null و قیود CHECK آزموده شدند و هر دو کانتینر حذف شدند. اسکریپت اکنون با متغیر اختیاری `HR_SOFT_POSTGRES_IMAGE` قابل اجرا روی imageهای مختلف است.
- در unit simulation محلی PostgreSQL 16، با `auth.uid()` ساختگی و پیاده‌سازی واقعی `scope_matches()` از migration منبع به‌همراه fixtureها، مسیرهای AUTH_REQUIRED، APP_USER_INACTIVE و ACL-101، ACL-102، ACL-103، ACL-104، ACL-105، ACL-106، ACL-107، ACL-108، ACL-109، ACL-110، ACL-111، ACL-114، ACL-115، ACL-116، ACL-117، ACL-118، ACL-120، ACL-121، ACL-123، ACL-124، ACL-127 و ACL-128 پاس شدند؛ قیود SEC-404/405 نیز پاس شدند.
- محیط کامل محلی Supabase با PostgreSQL 17.11 نیز بالا آمد و هر شش Migration مخزن به‌ترتیب روی آن اعمال شد. در این محیط 57/57 جدول HR دارای RLS و FORCE RLS بودند؛ دو قید جدید validated بودند؛ ACL و فراداده چهار تابع Resolver/identity/session با مقادیر مورد انتظار تطبیق داشتند.
- آزمون واقعی JWT/RLS با `supabase/tests/run_local_jwt_rls.ps1` از مسیر Auth و PostgREST محلی PostgreSQL 17.11 اجرا شد. چهار حساب موقت با JWT واقعی آزموده شدند: دو کاربر فعال در دو Tenant مستقل، یک حساب آرشیوشده و یک کاربر احراز‌شده فاقد mapping HR. همه چهار JWT توسط PostgREST پذیرفته شدند.
- برای Tenant A و Tenant B، هر کاربر دقیقاً یک Tenant و یک app_user متعلق به خود دید و تعداد ردیف‌های Tenant دیگر صفر بود. برای حساب آرشیوشده و کاربر فاقد mapping، `current_tenant_id()` و `current_app_user_id()` تهی، `is_authenticated=true` و `is_provisioned=false` و تعداد ردیف‌های Tenant/app_user قابل مشاهده صفر بود.
- هر چهار کاربر فقط یک system فعال و یک permission فعال دیدند؛ رکوردهای غیرفعال کاتالوگ قابل مشاهده نبودند. اجرای probe موقت با نقش `anon` رد شد.
- تابع probe با `SECURITY INVOKER` و فقط در محیط محلی ساخته و پس از آزمون حذف شد. شمارش نهایی صفر بودن Tenant/app_user/system/permission/Auth user آزمایشی و نبود تابع probe را تأیید کرد.
- گزارش جزئی آزمون: `docs/HR-SOFT/Analysis-v0.1/HR_SOFT_Real_JWT_RLS_Test_Report_v0.1.md`. اسکریپت قابل تکرار: `supabase/tests/run_local_jwt_rls.ps1`.
- دامنه اثبات‌شده محدود به RLS فعلی جدول‌های tenants، app_users، systems و permissions است. جداسازی tenant در داده‌های عملیاتی، CRUD، APIهای کسب‌وکاری، Resolver از مسیر wrapper معتبر و آزمون end-to-end ماتریس کامل ACL/SEC هنوز اثبات نشده‌اند.
- stack محلی پس از آزمون متوقف می‌شود و volume آن حفظ می‌شود. هیچ تغییری در Supabase فعال انجام نشده است.


## نتیجه اجرای Resolver با JWT واقعی — 2026-11-19

- harness جدید: `supabase/tests/run_local_resolver_e2e.ps1`.
- اجرای تابع واقعی `hr_internal.evaluate_permission_context` از RPC موقت با JWT صادرشده توسط Auth محلی: PASS.
- deny در برابر allow برای view/add/edit/delete، شامل `can_*` خاموش در rule deny: PASS.
- tenant mismatch: PASS؛ خروجی `TENANT_MISMATCH`.
- allow پس از غیرفعال‌شدن membership deny: PASS.
- این آزمون API محصولی، استخراج context سمت سرور برای منابع واقعی یا ثبت audit تراکنشی را پوشش نمی‌دهد؛ این موارد باز می‌مانند.
