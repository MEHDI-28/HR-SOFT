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
`bulletin_acknowledgements` به `(tenant_id, bulletin_id)` ارجاع می‌دهد؛ پس `bulletins` باید `UNIQUE(tenant_id,id)` داشته باشد. این unique در proposal اولیه وجود نداشت و باید اضافه شود.

### 2.2. Default group/system consistency
`user_default_groups` در نسخه اولیه فقط tenant و group را enforce می‌کرد و تضمین نمی‌کرد `group_id` متعلق به همان `system_id` باشد. باید unique composite روی `user_groups(tenant_id, system_id, id)` و FK مرکب استفاده شود.

### 2.3. IP policy semantics
باید قاعده allowlist فعال، deny precedence، trusted proxy و حالت بدون allowlist در سطح Tenant صریح و آزمون‌پذیر باشد. صرف ذخیره CIDR، enforcement ایجاد نمی‌کند.

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
