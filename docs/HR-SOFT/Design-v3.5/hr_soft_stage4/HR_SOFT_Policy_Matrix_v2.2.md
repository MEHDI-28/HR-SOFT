# HR-SOFT — ماتریس سیاست‌های دسترسی و دامنه داده
## نسخه 2.2 | مرحله چهارم

- تاریخ: ۱۸ نوامبر ۲۰۲۶
- وضعیت: سند طراحی و بازبینی؛ هیچ Migration یا Policy روی Supabase اجرا نشده است.
- مبنا: مدل SQL نسخه 0.1، سند مادر 1.9، طراحی امنیت 2.0 و موتور دسترسی 2.1.
- اصل: عدم دسترسی به‌صورت پیش‌فرض؛ Tenant isolation در تمام مسیرها؛ deny بر allow مقدم است.

## 1. قراردادهای امنیتی مشترک

1. احراز هویت با `auth.uid()` فقط شناسه Auth را می‌دهد؛ کاربر HR از `hr_security.app_users` با `auth_user_id` و `status='active'` resolve می‌شود.
2. `tenant_id` از ورودی کلاینت یا `user_metadata` پذیرفته نمی‌شود. Tenant جاری از رکورد فعال `app_users` استخراج می‌شود.
3. RLS لایه دفاع نهایی است، نه جایگزین کنترل مجوز کسب‌وکاری. هر درخواست باید هم Tenant، هم permission key، هم operation و هم data scope را بررسی کند.
4. منطق تصمیم دسترسی باید در سمت سرور و در یک مسیر مرکزی پیاده شود. UI فقط نمایش‌دهنده نتیجه است.
5. `service_role`, مالک پایگاه داده و نقش‌های دارای `BYPASSRLS` نباید در مرورگر/موبایل قرار گیرند.
6. جداول داخلی `hr_*` از فهرست exposed schemas در Supabase Data API خارج بمانند؛ دسترسی از API کنترل‌شده/توابع محدود انجام شود.
7. سیاست‌های `SELECT`, `INSERT`, `UPDATE`, `DELETE` جدا هستند. مجوز view عمومی به معنی مجوز دیدن ستون‌های حساس نیست.
8. هر دسترسی به داده حساس باید رویداد ممیزی مستقل ثبت کند؛ رویدادهای view/download نیز ثبت می‌شوند.

## 2. ماتریس سیاست در سطح جدول

علامت‌ها: `T` = tenant جاری؛ `P` = permission key متناظر؛ `S` = scope مؤثر؛ `A` = فقط حساب خودش؛ `SYS` = کاتالوگ سراسری؛ `ADM` = دسترسی مدیریتی محدود.

| جدول | SELECT | INSERT | UPDATE | DELETE | قیدهای ویژه |
|---|---|---|---|---|---|
| `hr_core.tenants` | `T`، حداقل فیلد | فقط provisioning کنترل‌شده | فقط فرایند مدیریت Tenant | ممنوع | tenant از auth mapping |
| `hr_core.companies` | `T+P+S` | `T+P` | `T+P+S` | ممنوع؛ archive | روابط والد در همان Tenant |
| `hr_core.people` | `T+P+S`؛ ستون‌های حساس جدا | `T+P` | `T+P+S` | ممنوع؛ archive | شناسه ملی از این جدول خارج |
| `hr_core.personnel_records` | `T+P+S` | `T+P` | `T+P+S` | ممنوع؛ archive | شخص دقیقاً در شرکت/پرونده معتبر |
| `hr_security.app_users` | `A` برای پروفایل محدود؛ `ADM+T` برای مدیریت | دعوت/Provisioning کنترل‌شده | `ADM+T`؛ کاربر فقط تنظیمات مجاز خودش | ممنوع؛ block/archive | هر Auth identity به رکورد HR فعال مشخص |
| `hr_org.org_layers` | `T+P+S` | `T+P` | `T+P+S` | ممنوع؛ archive | شرکت در همان Tenant |
| `hr_org.org_units` | `T+P+S` | `T+P` | `T+P+S` | ممنوع؛ archive | parent/layer باید با company_id سازگار باشد |
| `hr_org.positions` | `T+P+S` | `T+P` | `T+P+S` | ممنوع؛ archive | ظرفیت فقط از مسیر درخواست ظرفیت |
| `hr_org.position_relationships` | `T+P+S` | `T+P` | اصلاح با تاریخچه | ممنوع | نوع رابطه و بازه اعتبار |
| `hr_org.position_assignments` | `T+P+S` | `T+P` | فقط فرمان کنترل‌شده | ممنوع؛ cancel/end | تغییر گذشته با correction append-only |
| `hr_security.systems` | `SYS` فقط کاتالوگ فعال | عملیات انتشار نسخه | عملیات انتشار نسخه | ممنوع | جدول سراسری |
| `hr_security.user_groups` | `T+P` | `T+P` | `T+P` | archive/حذف منطقی گروه | گروه متعلق به یک system |
| `hr_security.group_memberships` | `T+P` | `T+P` | `T+P` | پایان عضویت/غیرفعال | تاریخچه عضویت حفظ شود |
| `hr_security.permissions` | `SYS` فقط کاتالوگ | انتشار نسخه | انتشار نسخه | ممنوع | مجوزهای system-scoped |
| `hr_security.group_permission_rules` | فقط مدیر سیستم مجاز | فقط مدیر سیستم | فقط مدیر سیستم | ممنوع؛ غیرفعال‌سازی/نسخه جدید | تغییرات در permission_change_history |
| `hr_security.data_scopes` | فقط مدیر سیستم مجاز | فقط مدیر سیستم | فقط مدیر سیستم | ممنوع؛ غیرفعال‌سازی | نوع scope باید دقیقاً یک هدف معتبر داشته باشد |
| `hr_security.group_scope_assignments` | فقط مدیر سیستم مجاز | فقط مدیر سیستم | فقط مدیر سیستم | پایان اعتبار | deny هر گروه بر allow گروه دیگر مقدم |
| `hr_security.temporary_access` | کاربر مربوطه محدود؛ مدیر مجاز | مدیر مجاز/گردش تأیید | لغو/تمدید کنترل‌شده | ممنوع | starts_at/ends_at و دلیل اجباری |
| `hr_audit.audit_events` | `ADM` و مالک رویداد در دامنه محدود | فقط مسیر سرور | ممنوع | ممنوع | append-only |
| `hr_audit.permission_change_history` | فقط مدیر سیستم | فقط مسیر سرور | ممنوع | ممنوع | export هم تابع همین permission |
| `hr_workflow.requests` | درخواست‌کننده/مراجعین مجاز `T+P+S` | درخواست‌کننده `T+P` | فرمان گردش کار | ممنوع | وضعیت با transition کنترل‌شده |
| `hr_workflow.steps` | اعضای مجاز همان گردش | فقط موتور workflow | فقط موتور workflow | ممنوع | approver فرد یا گروه معتبر |
| `hr_workflow.decisions` | مشارکت‌کنندگان مجاز | فقط تصمیم‌گیرنده مجاز | ممنوع | ممنوع | تصمیم‌ها immutable |
| `hr_workflow.capacity_change_requests` | `T+P+S` و مدیران تعیین‌شده | درخواست‌کننده مجاز | فرمان‌های دامنه‌ای | ممنوع | یک درخواست باز برای هر position |
| `hr_workflow.capacity_request_revisions` | مدیران/درخواست‌کننده مجاز | فقط فرمان ویرایش کنترل‌شده | ممنوع | ممنوع | snapshot قبل/بعد immutable |
| `hr_workflow.capacity_request_notes` | فقط مدیر سیستم | فقط مدیر سیستم | ممنوع | ممنوع | یادداشت داخلی immutable |
| `hr_files.file_objects` | مجوز رکورد مالک + مجوز فایل | آپلود کنترل‌شده | metadata کنترل‌شده | archive | `owner_schema/table/id` باید allowlist شود |
| `hr_files.file_versions` | مجوز فایل + نسخه | آپلود/جایگزینی کنترل‌شده | ممنوع | ممنوع | مسیر Storage خصوصی؛ نسخه قبلی حفظ |
| `hr_workflow.capacity_request_files` | مجوز درخواست ظرفیت و فایل | مدیر سیستم مجاز | ممنوع | detach فقط با archive/audit | اتصال فایل به درخواست |
| `hr_notify.user_preferences` | `A` | `A` | `A` فقط فیلدهای مجاز | ممنوع | SMS opt-out؛ in-app غیرقابل خاموشی |
| `hr_notify.notifications` | گیرنده خودش؛ مدیر سامانه فقط نظارت محدود | فقط سرویس اعلان | read-state توسط گیرنده؛ status توسط worker | ممنوع | payload نباید اطلاعات حساس غیرضروری داشته باشد |
| `hr_files.export_jobs` | همه مدیران برای فهرست محدود؛ جزئیات creator/ADM | فقط مدیر سیستم | worker و creator برای cancel محدود | ممنوع | فقط creator حق دریافت خروجی |
| `hr_files.export_job_items` | فقط مدیر مجاز/creator | worker | ممنوع | ممنوع | اقلام خروجی snapshot هستند |
| `hr_sensitive.identity_data` | مجوز مستقل `sensitive.identity.view` + `T+S` | مجوز مستقل update | مجوز مستقل update | ممنوع؛ نسخه/اصلاحیه | هر مشاهده/تغییر audit |
| `hr_sensitive.bank_accounts` | `sensitive.bank.view` + `T+S` | `sensitive.bank.add` | `sensitive.bank.edit` | ممنوع؛ پایان اعتبار | نمایش ماسک‌شده در حالت عادی |

## 3. دامنه داده (Scope)

ترتیب بررسی:
1. اعتبار هویت و فعال بودن `app_users`.
2. تطبیق tenant رکورد با tenant کاربر.
3. فعال بودن system، group، membership و بازه اعتبار.
4. جمع‌آوری تمام قواعد مجوز از گروه‌های فعال و دسترسی موقت معتبر.
5. اگر برای همان permission/operation/scope حداقل یک deny معتبر وجود داشت، نتیجه رد است.
6. در غیر این صورت، حداقل یک allow معتبر لازم است.
7. scope باید با رکورد هدف تطبیق داده شود؛ صرف داشتن permission key کافی نیست.

Scopeهای پشتیبانی‌شده:
- `tenant`: تمام داده‌های Tenant.
- `company`: شرکت مشخص.
- `org_unit`: واحد مشخص؛ در صورت `include_descendants=true` تمام زیرواحدهای فعال/تاریخی طبق تاریخ ارزیابی.
- `personnel`: پرونده پرسنلی مشخص.

**نکته:** ساختار فعلی `data_scopes` برای scope نوع `org_unit` و `personnel` کنترل سازگاری شرکت را کامل enforce نمی‌کند. باید trigger/constraint سمت دیتابیس اضافه شود. scopeها باید با زمان ارزیابی و تاریخ مؤثر داده سازگار شوند.

## 4. بازبینی ناسازگاری‌های SQL نسخه 0.1

| مورد | ریسک | اصلاح پیشنهادی |
|---|---|---|
| `app_users` فقط `unique(tenant_id,id)` دارد و `auth_user_id` در کل DB unique است | یک حساب Auth را نمی‌توان به چند Tenant نگاشت کرد؛ با معماری یک Tenant برای هر مشتری سازگار است اما جابجایی/چندعضویتی را محدود می‌کند | تصمیم فعلی را صریحاً حفظ کنیم: یک Auth identity = یک app_user = یک Tenant |
| `org_units.parent_unit_id` فقط Tenant را enforce می‌کند | امکان اتصال parent از شرکت دیگر در همان Tenant | FK مرکب `(tenant_id, company_id, parent_unit_id)` به کلید مناسب یا trigger سازگاری |
| `positions.org_unit_id` و `superior_position_id` فقط Tenant را enforce می‌کنند | اتصال سمت به واحد/مافوق شرکت دیگر در همان Tenant | کنترل company_id با FK مرکب/trigger |
| `position_assignments` سه رابطه Tenant را enforce می‌کند ولی تطبیق company_id بین position و personnel_record کامل نیست | انتساب فرد شرکت A به سمت شرکت B | trigger/command validation برای تطبیق شرکت |
| `position_relationships` فاقد company_id است | رابطه بین سمت‌های دو شرکت در همان Tenant ممکن است ناخواسته باشد | افزودن company_id یا trigger با سیاست مجاز بودن cross-company |
| `data_scopes` check برای org_unit/personnel همه ستون‌های نامربوط را NULL نمی‌کند | scope مبهم یا چندهدفه | CHECK کامل برای هر چهار نوع scope |
| `file_objects.owner_schema/table/id` polymorphic است و FK واقعی ندارد | اتصال فایل به رکورد اشتباه/حذف‌شده | registry مالک‌های مجاز + trigger اعتبارسنجی + permission resolver |
| `file_versions.storage_object_path` قید یکتا ندارد | مسیر تکراری یا نسبت دادن یک object به چند نسخه | unique روی `(storage_bucket, storage_object_path)` |
| `capacity_change_requests.status` و `execution_mode` وضعیت‌های هم‌پوشان دارند | `scheduled`, `approved_awaiting_execution`, `overdue` می‌توانند هم‌زمان معنی بدهند | وضعیت فرایندی را از زمان‌بندی/تاخیر جدا کنیم؛ جزئیات در سند ظرفیت |
| جداول تاریخچه‌ای بدون trigger append-only | UPDATE/DELETE با نقش دارای مجوز ممکن است | trigger منع UPDATE/DELETE + محدودیت grants |
| `systems` و `permissions` global هستند اما نسخه‌بندی ندارند | تغییر کاتالوگ می‌تواند رفتار موجود را تغییر دهد | کاتالوگ versioned/immutable release |
| `export_jobs` مسیر موقت و توکن دانلود ندارد | کنترل دانلود تک‌بار و creator-only مبهم است | توکن تصادفی hash‌شده، creator-bound، expiry، consume atomic |

## 5. الگوی API امن

- کلاینت نباید مستقیماً به جداول داخلی `hr_*` دسترسی نوشتن داشته باشد.
- عملیات حساس از RPC/Edge Functionهای مشخص عبور کند.
- هر تابع SECURITY DEFINER:
  - `search_path=''`
  - نام schema و objectها fully-qualified
  - `EXECUTE` از `PUBLIC` revoke شود
  - فقط به نقش لازم grant شود
  - ورودی tenant/user از کلاینت را مرجع اعتماد قرار ندهد
  - خودش actor و tenant را از Auth context resolve کند.
- توابع نباید داده خام حساس را به لاگ عمومی یا خطای API بنویسند.

## 6. آزمون‌های پذیرش اجباری

- کاربر Tenant A با UUID رکورد Tenant B نمی‌تواند SELECT/UPDATE/DELETE کند.
- عضویت در گروه غیرفعال هیچ مجوزی نمی‌دهد.
- allow از گروه اول + deny از گروه دوم = deny.
- پایان بازه دسترسی موقت، دسترسی را قطع می‌کند.
- scope شرکت A نمی‌تواند داده شرکت B را بخواند.
- scope واحد با descendants فقط زیرواحدهای همان شرکت را می‌پوشاند.
- permission عادی personnel.view به تنهایی identity_data یا bank_accounts را نمایش نمی‌دهد.
- download فایل نیازمند permission جداگانه و اجازه رکورد مالک است.
- فایل private با URL حدس‌زدنی/دانستن path قابل دانلود نیست.
- تصمیم گردش کار، تاریخچه مجوز و audit event قابل UPDATE/DELETE نیست.
- export job فقط توسط سازنده قابل دانلود است؛ مدیران دیگر فقط metadata مجاز را می‌بینند.

## 7. وضعیت اجرا

این سند سیاست نهایی اجرایی نیست. برای نهایی کردن آن لازم است:
- مدل SQL در محیط توسعه اجرا شود.
- نام دقیق permission keyها و scope resolver نهایی شود.
- RPC/Edge Functionها پیاده‌سازی شوند.
- تست‌های pgTAP در محیط staging اجرا شوند.
- آزمون نفوذ Tenant A/B و Storage انجام شود.
