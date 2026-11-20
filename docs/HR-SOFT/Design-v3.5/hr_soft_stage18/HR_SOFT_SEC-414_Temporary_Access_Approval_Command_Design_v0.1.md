# HR-SOFT — یادداشت طراحی کنترل تأیید دسترسی موقت (SEC-414)
## نسخه 0.1 — 2026-11-19

- وضعیت: پیشنهاد طراحی مبتنی بر بررسی read-only؛ هیچ Migration یا API منتشر نشده است.
- هدف: جلوگیری از ثبت دسترسی موقت با approver دلخواه یا غیرمجاز.
- مرجع: Stage 18، Resolver v2.4.1 فعال، Migration پیشنهادی Resolver v2.4.2، قرارداد API Org Admin v0.1.

## 1. یافته قطعی از دیتابیس فعال

جدول `hr_security.temporary_access` شامل ستون‌های زیر است:
- `tenant_id`, `app_user_id`, `system_id`, `permission_id`
- `scope_id` nullable
- `effect`, `starts_at`, `ends_at`, `reason`
- `approved_by` nullable, `approved_at` nullable
- `created_at`, `created_by`

قیود موجود:
- `ends_at > starts_at`
- دسترسی allow فقط با `scope_id`, `approved_by`, `approved_at` غیرتهی مجاز است.
- FK مرکب `(tenant_id, approved_by)` تضمین می‌کند approver در همان tenant وجود داشته باشد؛ اما فعال بودن حساب، عضویت مدیریتی یا داشتن مجوز approve را اثبات نمی‌کند.
- FK مرکب tenant برای target user و scope نیز وجود دارد.

کاتالوگ مجوزهای فعال و قواعد گروه `tenant_owner` بررسی شد. در حال حاضر permission key اختصاصی برای تأیید دسترسی موقت مشاهده نشد. مجوزهایی مانند `security.users.edit` جایگزین دقیق و امنی برای `security.temporary_access.approve` نیستند.

## 2. شکاف امنیتی SEC-414

قیود دیتابیس فعلی فقط صحت ارجاع tenant و جفت بودن metadata را تضمین می‌کنند. کاربری که بتواند مسیر نوشتن مستقیم یا یک wrapper ضعیف را فراخوانی کند، از نظر constraint به‌تنهایی اثبات نمی‌کند که:
- approver همان کاربر احراز‌شده است؛
- حساب approver فعال و آرشیو نشده است؛
- approver مجوز اختصاصی تأیید در همان tenant و scope را دارد؛
- approver نمی‌خواهد دسترسی خودش را تأیید کند.

در حال حاضر API کسب‌وکاری برای نوشتن temporary_access وجود ندارد؛ بنابراین این یادداشت طراحی مسیر آینده است، نه گزارش سوءاستفاده جاری از API.

## 3. طرح پیشنهادی کنترل سمت سرور

### 3.1 Permission مستقل

افزودن permission key مستقل:
`security.temporary_access.approve`

- فقط از طریق migration و seed کنترل‌شده به کاتالوگ همان system اضافه شود.
- هیچ دسترسی پیش‌فرض عمومی یا مجوز ضمنی از `tenant_owner` صرفاً به‌خاطر نام گروه فرض نشود.
- قواعد allow برای approverها صریحاً در group_permission_rules و scope assignment ثبت شوند.
- operation Resolver برابر `approve` باشد؛ Resolver باید deny صریح را مقدم بداند.

### 3.2 Command امن و اتمیک

نام پیشنهادی:
`public.hr_security_grant_temporary_access_v1(...)`

ورودی‌های قابل بررسی:
- `p_target_app_user_id`
- `p_permission_key`
- `p_scope_id`
- `p_effect`
- `p_starts_at`
- `p_ends_at`
- `p_reason`

ورودی‌های ممنوع:
- `tenant_id`
- `approved_by`
- `approved_at`
- `created_by`

این مقادیر باید در سرور از `auth.uid()`، `hr_security.current_app_user_id()` و `hr_security.current_tenant_id()` استخراج شوند.

ترتیب اجباری اجرای command:
1. رد درخواست بدون `auth.uid()`.
2. resolve کردن app_user و tenant جاری؛ حساب status غیرفعال یا archived رد شود.
3. خواندن target و scope با tenant جاری؛ ورودی متعلق به tenant دیگر به‌صورت `RESOURCE_NOT_FOUND` پاسخ داده شود.
4. رد scope خالی؛ scope tenant-wide فقط با یک رکورد صریح `data_scopes.scope_type='tenant'` قابل استفاده باشد.
5. اعتبارسنجی effect، بازه زمانی، reason و فعال بودن permission.
6. ارزیابی `security.temporary_access.approve` با Resolver برای همان tenant و scope مؤثر.
7. اعمال deny-overrides-allow؛ هر deny صریح باید عملیات را متوقف کند.
8. در صورت سیاست separation-of-duties، رد target برابر approver؛ پیشنهاد پیش‌فرض این سند: self-approval ممنوع.
9. درج رکورد در همان transaction با `approved_by = current_app_user_id` و `approved_at = clock_timestamp()` و `created_by = current_app_user_id`.
10. ثبت audit event در همان transaction؛ اگر audit insert شکست خورد، کل عملیات rollback شود.
11. خروجی حداقلی شامل شناسه رکورد، effect، scope و بازه؛ بدون افشای ruleها یا گروه‌های approver.

### 3.3 Scope و محدوده دسترسی approver

صرف اینکه approver برای یک رکورد در scope خود مجوز دارد، به معنی مجاز بودن او برای اعطای scope گسترده‌تر نیست.

قبل از پیاده‌سازی باید رابطه subset بین scope مجاز approver و scope اعطاشونده دقیق تعریف و تست شود:
- tenant → tenant/company/unit/personnel طبق قواعد صریح محصول؛
- company → فقط همان شرکت و فرزندان مجاز؛
- org_unit → همان واحد و در صورت include_descendants، زیرواحدهای مجاز؛
- personnel_record → فقط همان پرونده.

تا زمان پیاده‌سازی و آزمون subset، command باید fail-closed باشد و فقط scopeهایی را بپذیرد که containment آن‌ها با منطق قابل اثبات است.

## 4. نکات سازگاری با جدول فعلی

- FK same-tenant approver حفظ شود.
- قیود approval pair و global-scope approval در Migration v2.4.2 تکمیل می‌شوند، اما به‌تنهایی جایگزین command نیستند.
- Resolver فعلی temporary access با `scope_id IS NULL` را به‌صورت دسترسی tenant-wide تفسیر نمی‌کند. این رفتار fail-closed باید حفظ شود.
- برای effect=allow، constraint موجود تأییدکننده و scope را اجباری می‌کند.
- برای effect=deny با scope خالی، حتی اگر metadata تأیید موجود باشد، Resolver فعلی آن را به‌عنوان deny سراسری اعمال نمی‌کند؛ command باید scope خالی را رد کند تا این تفاوت موجب ابهام عملیاتی نشود.

## 5. آزمون‌های پذیرش الزامی

| ID | سناریو | نتیجه |
|---|---|---|
| SEC-414-A | کاربر بدون نشست command را فراخوانی کند | AUTH_REQUIRED |
| SEC-414-B | app_user غیرفعال یا archived | APP_USER_INACTIVE |
| SEC-414-C | target یا scope متعلق به tenant دیگر | RESOURCE_NOT_FOUND |
| SEC-414-D | approver فاقد permission اختصاصی | PERMISSION_DENIED |
| SEC-414-E | deny صریح برای approver در scope | PERMISSION_DENIED |
| SEC-414-F | approver scope محدودتر از scope درخواستی | رد؛ عدم امکان گسترش scope |
| SEC-414-G | self-approval | رد |
| SEC-414-H | scope_id خالی یا scope tenant-wide ضمنی | INVALID_ARGUMENT |
| SEC-414-I | بازه نامعتبر یا پایان قبل از شروع | INVALID_ARGUMENT |
| SEC-414-J | audit insert شکست بخورد | rollback کامل |
| SEC-414-K | approver مجاز و scope subset معتبر | درج اتمیک با approver استخراج‌شده از نشست |
| SEC-414-L | مرورگر approved_by یا tenant_id جعلی ارسال کند | مقادیر ورودی نادیده گرفته شوند؛ actor و tenant فقط از نشست استخراج شوند |

تمام آزمون‌های امنیتی باید با JWT واقعی، roleهای واقعی و حداقل دو tenant آزمایشی در محیط disposable/staging اجرا شوند؛ fake JWT claims در SQL Editor قابل قبول نیست.

## 6. تصمیم‌های باز پیش از Migration

1. تأیید نام permission key و گروه‌های مجاز به آن.
2. تأیید ممنوعیت self-approval.
3. تأیید ماتریس دقیق scope-subset و اینکه چه کسی می‌تواند دسترسی tenant-wide اعطا کند.
4. تعیین اینکه درخواست‌کننده و approver دو actor مستقل‌اند یا ثبت دسترسی یک‌مرحله‌ای توسط approver کفایت می‌کند.
5. تعیین event type و payload حداقلی audit.

تا زمان تصمیم درباره موارد بالا، هیچ permission seed، RPC، trigger یا policy جدیدی ایجاد نشود.
