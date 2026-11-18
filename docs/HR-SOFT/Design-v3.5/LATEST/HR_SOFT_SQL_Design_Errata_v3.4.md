# HR-SOFT — گزارش اصلاحات فنی و بازبینی ایستای SQL
## نسخه 3.4 | مرحله شانزدهم

- تاریخ: ۱۸ نوامبر ۲۰۲۶
- هدف: ثبت خطاها/ابهام‌های کشف‌شده در proposalهای SQL قبل از هر اجرا.
- وضعیت: اصلاحات پیشنهادی؛ هیچ‌کدام اجرا نشده‌اند.

## 1. اصلاح معنای فیلد پایه سازمانی

در proposal اولیه v0.3، عبارت منبع «تاریخ اجرای پایه، پایه مصوب، پایه موقت» به‌اشتباه با نام‌های `approved_capacity` و `temporary_capacity` مدل شده بود. این عبارت لزوماً ظرفیت تعداد نیروی انسانی نیست و نباید با `positions.approved_capacity` یا workflow تغییر ظرفیت یکی گرفته شود.

نسخه اصلاح‌شده `HR_SOFT_Organization_Extension_v0.3.1.sql` نام‌های زیر را به‌کار می‌برد:
- `approved_base_value`
- `temporary_base_value`
- `base_effective_date`
- `base_notes`

نوع دقیق و واحد اندازه‌گیری همچنان نیازمند بررسی فرم مرجع است؛ `numeric(14,3)` صرفاً انتخاب پیشنهادی و قابل تغییر است.

## 2. خطاهای ساختاری در proposal v0.4 (امنیت کاربر)

### 2.1. Bulletin FK
`bulletin_acknowledgements` به `(tenant_id, bulletin_id)` ارجاع می‌دهد؛ پس `bulletins` باید `UNIQUE(tenant_id,id)` داشته باشد. این unique در proposal اولیه وجود نداشت. در شاخه جاری، قید در تعریف جدول `bulletins` و پیش از ایجاد جدول acknowledgement اضافه شد. ایندکس متناظر در correction v0.6 اکنون redundant است، اما در صورت حفظ باید با نام و وضعیت schema مقصد تطبیق داده شود. اجرای واقعی Migration v0.4 هنوز لازم است.

### 2.2. Default group/system consistency
`user_default_groups` در نسخه اولیه فقط tenant و group را enforce می‌کرد و تضمین نمی‌کرد `group_id` متعلق به همان `system_id` باشد. باید unique composite روی `user_groups(tenant_id, system_id, id)` و FK مرکب استفاده شود.

### 2.3. IP policy semantics
باید قاعده allowlist فعال، deny precedence، trusted proxy و حالت بدون allowlist در سطح Tenant صریح و آزمون‌پذیر باشد. صرف ذخیره CIDR، enforcement ایجاد نمی‌کند.

### 2.4. Group permission/system consistency
در baseline، `group_permission_rules` گروه و permission را جداگانه reference می‌کند و هم‌سیستمی بودن آن‌ها enforce نمی‌شود. Stage 18 proposal، `system_id` را از گروه backfill می‌کند و FK مرکب به گروه و permission همان system می‌افزاید. پیش از VALIDATE باید query ناسازگاری صفر ردیف برگرداند.

### 2.5. Temporary access approval
در baseline، `temporary_access.scope_id` و `approved_by` nullable هستند و `approved_at` وجود ندارد. Stage 18 proposal برای دسترسی tenant-wide با scope خالی، ثبت جفت approver/approval time را اجباری می‌کند. مجاز بودن approver همچنان باید در command سمت سرور کنترل شود.

### 2.6. Login/access event immutability
Migration مرحله 13 append-only trigger برای `user_login_events` و `user_access_events` را به TODO واگذار کرده بود. Stage 18 proposal triggerهای جلوگیری از UPDATE/DELETE را با تابع موجود Stage 5 اضافه می‌کند؛ این تغییر باید با roleهای واقعی و RLS در محیط آزمایشی آزمون شود.

## 3. Trigger function grants

توابع trigger از نوع SECURITY DEFINER باید:
- مالکیت کنترل‌شده داشته باشند؛
- `search_path=''` داشته باشند؛
- EXECUTE از PUBLIC/anon/authenticated لغو شود، مگر مسیر مشخصی واقعاً نیازمند آن باشد؛
- schema/table/function fully-qualified باشند.

حتی اگر trigger در جدول اجرا می‌شود، تابع نباید به‌عنوان API عمومی قابل فراخوانی باشد.

## 4. File owner check

در proposal v0.2، CHECKهایی که `owner_type` را NULL می‌گذاشتند ممکن بود به‌علت semantics سه‌حالته CHECK در PostgreSQL، NULL را pass کنند. شرط اصلاحی باید `owner_type IS NOT NULL` را صریحاً enforce کند و دقیقاً یک FK مالک معتبر داشته باشد.

## 5. Cancellation status mapping

مهاجرت status قدیمی `cancelled` به `approval_status='rejected'` فقط یک نگاشت موقت است و از نظر معنایی دقیق نیست. در نسخه بعد باید وضعیت cancellation به‌صورت مستقل یا به‌عنوان execution_status حفظ شود و approval history از decisions/revisions استخراج شود. تا قبل از بررسی داده‌های واقعی، این نگاشت نباید اجرا شود.

## 6. Duplicate/constraint preflight

پیش از unique index و FK validation:
- duplicate storage paths = صفر
- duplicate open capacity requests = صفر
- company mismatch در assignments = صفر
- cross-company parent/position relations = صفر
- file owners خارج allowlist باید migrate شوند
- malformed scopes باید اصلاح شوند

## 7. سایر ملاحظات

- Stage 14 birth_date هم در `people` و هم در private details دیده می‌شود؛ migration باید backfill و سپس deprecate کند، نه اینکه دو منبع حقیقت مستقل باقی بمانند.
- default group فقط context انتخابی است و نباید permission اضافی ایجاد کند.
- `user_login_events` برای loginهای ناموفق پیش از resolve Tenant ممکن است tenant_id نداشته باشد؛ گزارش global باید دسترسی و privacy جداگانه داشته باشد.
- event tables و outbox باید retention، partitioning و role grants مشخص داشته باشند.
