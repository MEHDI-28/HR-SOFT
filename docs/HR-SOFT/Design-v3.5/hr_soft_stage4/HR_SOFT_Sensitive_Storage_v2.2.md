# HR-SOFT — حفاظت از اطلاعات حساس و فایل‌های خصوصی
## نسخه 2.2

## 1. طبقه‌بندی داده

| سطح | نمونه | مجوز نمونه | ثبت ممیزی |
|---|---|---|---|
| عمومی سازمانی | نام واحد، عنوان سمت | `org.unit.view` | رویدادهای اصلی تغییر |
| پرسنلی معمولی | نام، شماره پرسنلی، وضعیت اشتغال | `personnel.view` | مشاهده در سطح گزارش‌های حساس/پرخطر |
| هویتی حساس | کد ملی، گذرنامه | `sensitive.identity.view` | هر مشاهده/تغییر |
| بانکی | شبا، شماره حساب | `sensitive.bank.view` | هر مشاهده/تغییر |
| سند محرمانه | اسناد هویتی/قرارداد | `sensitive.documents.view`, `sensitive.documents.download` | مشاهده metadata و هر دانلود |
| خروجی انبوه | ZIP/Excel/PDF | مجوز گزارش/Export + scope | ساخت، دانلود، لغو، انقضا |

## 2. قواعد دسترسی

- مجوز view پرونده پرسنلی، مجوز مشاهده داده هویتی یا بانکی نیست.
- نمایش پیش‌فرض اطلاعات بانکی فقط نام بانک، نام صاحب حساب و چهار رقم انتهایی است؛ شبا/شماره کامل فقط با مجوز جداگانه.
- کد ملی و گذرنامه در جداول حساس ذخیره شوند؛ در جداول عمومی فقط در صورت نیاز fingerprint یک‌طرفه برای جست‌وجوی دقیق.
- ciphertext باید با کلید خارج از DB رمزگذاری شود؛ کلید رمزگشایی در جدول یا کد کلاینت نگهداری نشود.
- عملیات رمزگشایی باید در Edge Function/Backend کنترل‌شده انجام شود و پاسخ فقط به کاربر مجاز برسد.
- رویداد audit نباید ciphertext، مقدار کامل شبا، کد ملی یا متن سند را ذخیره کند.
- دانلود سند یک مجوز مستقل از مشاهده metadata است.
- مجوزها به شکل scope-aware و tenant-aware محاسبه شوند.

## 3. مدل رویداد دسترسی حساس

رویدادهای مورد نیاز:
- `sensitive.identity.view`
- `sensitive.identity.update`
- `sensitive.bank.view`
- `sensitive.bank.update`
- `sensitive.document.metadata_view`
- `sensitive.document.download`
- `sensitive.document.upload`
- `sensitive.document.replace`
- `sensitive.document.archive`
- `export.create`, `export.download`, `export.cancel`, `export.expire`

فیلدهای رویداد:
- actor_app_user_id، tenant_id، event_key
- subject_type و subject_id (مثلاً person یا personnel_record)
- object_id / file_version_id در صورت سند
- occurred_at و request_id
- purpose/reason (برای عملیات پرریسک اجباری)
- outcome (allowed/denied/error)
- policy_version
- source_ip و user_agent در صورت دسترس
- metadata محدود و بدون مقادیر حساس خام

رویداد denied نیز ثبت شود؛ ولی نباید اطلاعاتی افشا کند که کاربر مجاز به دانستن آن نیست.

## 4. معماری فایل خصوصی

- Bucket در Supabase Storage باید `private` باشد.
- مسیر پیشنهادی:
  `tenant/{tenant_uuid}/{owner_type}/{owner_uuid}/file/{file_uuid}/v/{version_no}/{random_object_uuid}.{ext}`
- نام فایل کاربر در مسیر Storage استفاده نشود؛ نام اصلی فقط در metadata نگهداری شود.
- هر نسخه یک object path غیرقابل حدس داشته باشد.
- فایل‌های HR-SOFT نباید از bucket عمومی سرو شوند.
- مسیر فایل فقط پس از کنترل مجوز رکورد مالک قابل resolve باشد.
- دانلود از طریق Backend/Edge Function یا signed URL کوتاه‌عمر انجام شود؛ URL امضاشده فقط پس از احراز مجوز صادر شود.
- RLS در `storage.objects` شرط لازم است اما به‌تنهایی کافی نیست؛ policy باید مالک فایل را از metadata معتبر و جدول `hr_files.file_versions` resolve کند.
- برای فایل‌های متصل به درخواست ظرفیت، مجوز مشاهده درخواست + مجوز فایل باید هر دو برقرار باشد.
- جایگزینی فایل، نسخه جدید می‌سازد؛ نسخه قبلی حفظ و غیرقابل overwrite می‌ماند.
- حذف از Storage فقط در فرایند retention قانونی/پاک‌سازی کنترل‌شده؛ آرشیو معمولی فایل را حذف فیزیکی نمی‌کند.

## 5. محدودیت Storage Policy در وضعیت فعلی

به‌دلیل polymorphic بودن `file_objects.owner_schema/owner_table/owner_id` و نبود registry کامل مالک‌ها، نوشتن یک Storage policy عمومی و قابل اعتماد در این مرحله زودهنگام است. سیاست نهایی باید بعد از ساخت تابع resolve مالک مجاز و allowlist جدول‌های مالک تولید شود. تا آن زمان:
- Bucket خصوصی؛
- دسترسی مستقیم authenticated به Storage ممنوع یا به‌شدت محدود؛
- upload/download فقط از Backend کنترل‌شده؛
- هیچ policy مبتنی بر prefix تنها، مجوز نهایی محسوب نشود.

## 6. retention و نسخه‌ها

- audit و permission history append-only.
- فایل‌های جایگزین‌شده در تاریخچه باقی می‌مانند.
- retention مدت‌دار باید با الزامات حقوقی/قراردادی مشتری تعیین شود؛ فعلاً عددی فرض نشده.
- هر پاک‌سازی فیزیکی باید ثبت درخواست، مجوز، دامنه، دلیل و نتیجه داشته باشد.
