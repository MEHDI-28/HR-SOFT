# HR-SOFT — بازطراحی مدل داده و نقشه Migration
## نسخه 2.3 | مرحله پنجم

- تاریخ: ۱۸ نوامبر ۲۰۲۶
- وضعیت: طراحی فنی و Migration پیشنهادی؛ اجرا نشده.
- مبنا: اسناد مادر 1.9 و 2.2، SQL پایه 0.1، SQL تکمیلی 0.1، RLS lockdown 0.1 و یافته‌های مرحله چهارم.
- محدودیت: هیچ اتصال فعال به پروژه Supabase در این مرحله تأیید نشده است؛ بنابراین schema واقعی remote با این طرح تطبیق داده نشده.

## 1. هدف مرحله

هدف این مرحله تبدیل یافته‌های امنیتی به تغییرات مشخص در مدل داده است؛ با حفظ داده‌ها و تاریخچه و بدون اجرای تغییر روی محیط واقعی.

## 2. تصمیمات معماری حفظ‌شده

- هر مشتری مستقل یک Tenant؛ شرکت‌های مادر/زیرمجموعه داخل همان Tenant.
- هر پرونده پرسنلی در نسخه اول به یک شرکت تعلق دارد.
- حذف عادی فیزیکی نیست؛ archive/deactivate.
- اصلاح گذشته با رکورد اصلاحی و حفظ سابقه اصلی.
- داده هویتی، بانکی و اسناد دارای permission مستقل.
- deny در هر گروه بر allow گروه دیگر مقدم است.
- هر گروه متعلق به یک system؛ کاربر می‌تواند عضو چند گروه باشد.
- تاریخ اعتبار کسب‌وکاری از زمان ثبت سیستمی مستقل است.

## 3. اصلاح روابط شرکت و سازمان

### 3.1 شرکت در تمام روابط سازمانی
کلیدهای خارجی Tenant-only مانع cross-tenant هستند، اما cross-company درون یک Tenant را متوقف نمی‌کنند. برای این روابط، کلید مرکب `(tenant_id, company_id, id)` باید unique و در FK استفاده شود:
- org_units: والد و لایه باید در همان شرکت باشند.
- positions: واحد سازمانی و سمت مافوق باید در همان شرکت باشند.
- position_assignments: سمت و پرونده پرسنلی باید در همان شرکت باشند.
- position_relationships: رابطه دو سمت در یک شرکت؛ این نسخه به‌عنوان پیش‌فرض همین محدودیت را اعمال می‌کند.

### 3.2 قاعده سازگاری انتساب
هر assignment باید:
- tenant_id و company_id یکسان با position داشته باشد.
- tenant_id و company_id یکسان با personnel_record داشته باشد.
- تاریخ اعتبار معتبر داشته باشد.
- برای assignment اصلی، هم‌پوشانی غیرمجاز با assignment اصلی دیگر همان پرونده/سمت را نداشته باشد.

هم‌پوشانی دقیق باید با exclusion constraint و `btree_gist` یا trigger تراکنشی پیاده شود. چون نیازمندی‌های acting/temporary و ظرفیت چندنفره متفاوت‌اند، قید عمومی روی همه انواع assignment مناسب نیست. مرحله بعدی باید قواعد overlap را برای primary/acting/temporary مجزا پیاده کند.

## 4. اصلاح مدل مالکیت فایل

مدل polymorphic خام `owner_schema + owner_table + owner_id` به‌تنهایی FK واقعی ندارد و امکان اشاره به جدول غیرمجاز ایجاد می‌کند.

در نسخه اصلاحی:
- `owner_type` از فهرست بسته و کنترل‌شده انتخاب می‌شود.
- برای هر نوع مالک، یک ستون FK nullable مستقل اضافه می‌شود.
- دقیقاً یکی از ستون‌های مالک باید پر باشد.
- در این مرحله `capacity_request` مالک فعال است؛ انواع دیگر هنگام اضافه شدن ماژول‌ها migration جدا خواهند داشت.
- ستون‌های legacy برای دوره انتقال حفظ می‌شوند و بعد از backfill/validation حذف خواهند شد.
- file version با object path یکتا و immutable ثبت می‌شود.

## 5. اصلاح گردش کار ظرفیت

وضعیت تأیید از وضعیت اجرا جدا می‌شود:

`approval_status`:
- `pending_approval`
- `approved`
- `rejected`
- `awaiting_reapproval`

`execution_status`:
- `blocked`
- `scheduled`
- `due`
- `overdue`
- `executed`
- `cancelled`

قواعد:
- اجرا فقط در حالت `approval_status='approved'`.
- revision جدید پس از تأیید، `awaiting_reapproval` می‌سازد و اجرای نسخه قبلی را ممنوع می‌کند.
- اجرای موفق فقط اگر `current_revision_no = last_approved_revision_no`.
- موعد گذشته بدون اجرا → `overdue`؛ ظرفیت فعلی بدون تغییر.
- رد/لغو/اجراشده درخواست باز محسوب نمی‌شوند.
- یک درخواست باز برای هر position با partial unique index enforce می‌شود.
- عملیات approve/revise/execute باید در توابع تراکنشی و با قفل ردیف انجام شود؛ نه با چند update مستقل از UI.

## 6. اصلاح مدل تاریخچه و audit

جداول زیر باید append-only باشند:
- audit_events
- permission_change_history
- workflow.decisions
- capacity_request_revisions
- capacity_request_notes
- file_versions
- sensitive_access_events

هر تغییر جاری باید رویداد before/after یا revision متناظر ایجاد کند. trigger منع UPDATE/DELETE، دفاع تکمیلی است؛ grants و API design هم باید نوشتن مستقیم را مسدود کنند.

## 7. کلیدهای زمانی

- `valid_from/valid_to`: زمان اعتبار کسب‌وکاری.
- `created_at/recorded_at`: زمان ورود به سیستم.
- `effective_at`: زمان اثر واقعی تغییر.
- زمان‌های اجرای زمان‌بندی‌شده باید timezone-aware باشند؛ ذخیره به‌صورت `timestamptz` و نمایش با timezone شرکت/کاربر.
- برای تاریخ‌های صرفاً تقویمی استخدام/اعتبار، `date` مناسب است.
- در مدل فعلی تاریخ‌های شمسی نباید به شکل متن ذخیره شوند؛ تبدیل UI باید به نوع تاریخ استاندارد پایگاه داده انجام شود.

## 8. Migration strategy

1. snapshot/backup و ساخت محیط توسعه مجزا.
2. baseline و supplemental در DB آزمایشی اجرا و تمام objectها استخراج شوند.
3. Migration 0.2: unique indexes و FKهای شرکت‌محور.
4. Migration 0.3: file owner registry/columns و انتقال metadata.
5. Migration 0.4: capacity status dual-write/backfill، بعد تغییر API و سپس قید یکتایی.
6. Migration 0.5: append-only triggers و audit grants.
7. Migration 0.6: permission resolver و RLS policyها.
8. Storage policy فقط پس از file resolver و تست owner permission.
9. pgTAP + آزمون end-to-end دو Tenant.
10. deploy با feature flags و rollback plan.

## 9. شروط توقف انتشار

- هر تست cross-tenant موفق شود.
- رکوردی به شرکت اشتباه وصل باشد.
- file object فاقد مالک معتبر باشد.
- capacity request باز تکراری برای یک position وجود داشته باشد.
- history/audit قابل UPDATE/DELETE باشد.
- RLS policy با SECURITY DEFINER ناامن یا search_path mutable داشته باشد.
- هر endpoint از tenant_id ارسالی کلاینت اعتماد کند.

## 10. خارج از دامنه

- اجرای SQL در Supabase.
- ساخت bucket واقعی یا تنظیم Storage.
- تغییر Auth provider.
- اتصال به دیتابیس واقعی.
- وارد کردن اطلاعات کارکنان واقعی.
- توسعه UI در این مرحله.
