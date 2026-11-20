# HR-SOFT — کاتالوگ گزارش‌ها، داشبورد و خروجی‌ها
## نسخه 2.6 | مرحله هشتم

- تاریخ: ۱۸ نوامبر ۲۰۲۶
- وضعیت: طراحی محصول بر اساس نیازمندی‌های ثبت‌شده؛ نه پیاده‌سازی.
- مبنا: گزارش‌های مشاهده‌شده در Admino و نیازهای HR-SOFT.
- نکته: عنوان‌های گزارش Admino در این سند به‌عنوان شواهد نام‌گذاری آمده‌اند؛ منطق محاسبه و ستون‌های دقیق آن‌ها در منبع موجود تأیید نشده‌اند.

## 1. اصول گزارش‌گیری

1. گزارش‌ها باید با permission key و scope مؤثر فیلتر شوند؛ فیلتر UI مرز امنیت نیست.
2. هر گزارش دارای metadata ثابت است: report_key، عنوان، توضیح، dataset، permission، فیلترها، ستون‌ها، export formats، نسخه.
3. داده‌های حساس فقط با مجوز مستقل و در خروجی هم mask/omit می‌شوند.
4. خروجی Excel/PDF دقیقاً همان scope و permission صفحه را رعایت می‌کند.
5. export job باید actor، زمان، فیلترها، policy version و وضعیت را ثبت کند.
6. خروجی انبوه حساس نیازمند permission جداگانه export است.
7. گزارش تاریخی باید `effective_at` را پشتیبانی کند.
8. همه گزارش‌ها pagination و محدودیت حجم دارند؛ export حجیم از worker انجام می‌شود.

## 2. فهرست گزارش‌های مشاهده‌شده در Admino

این عنوان‌ها از فهرست HR report ثبت شده‌اند؛ جزئیات ستون/فرمول آن‌ها هنوز مستند نشده است:
- لایه‌های سازمانی
- مدیریت پرسنلی
- پرسنل
- نوع استخدام
- نوع ارتقاء
- وابستگان و مزایا
- نوع مزایا
- خوداظهاری
- وضعیت مسکن
- وضعیت سکونت
- پرسنل غیرفعال
- ارزیابی‌های ثبت‌شده
- وضعیت خانواده وابستگان
- جزئیات پرسنل/وابستگان
- نتیجه ارزیابی
- وضعیت پرسنل
- سوابق کار در شرکت/خارج شرکت

در HR-SOFT این موارد به‌صورت کاتالوگ گزارش تعریف می‌شوند و فیلدهای دقیق پس از طراحی فرم‌های داده متناظر نهایی خواهند شد.

## 3. کاتالوگ پیشنهادی نسخه اول

| Report Key | عنوان | Dataset | مجوز مشاهده | خروجی |
|---|---|---|---|---|
| `org.layers` | لایه‌های سازمانی | org_layers | `report.organization.view` | Excel/PDF |
| `org.units` | واحدهای سازمانی | org_units | `org.unit.view` | Excel/PDF |
| `org.chart` | نمودار سازمانی | units/positions/relationships/assignments | `org.chart.view` | PDF/Excel |
| `personnel.directory` | فهرست پرسنل | personnel_records + people | `personnel.view` | Excel/PDF |
| `personnel.status` | وضعیت پرسنل | personnel_records | `report.personnel.view` | Excel/PDF |
| `personnel.inactive` | پرسنل غیرفعال | personnel_records | `report.personnel.view` | Excel |
| `personnel.employment_type` | نوع استخدام | personnel_records | `report.personnel.view` | Excel |
| `personnel.promotion_type` | نوع ارتقاء | future promotion domain | `report.personnel.view` | بعد از تعریف ماژول |
| `personnel.work_history` | سوابق کار داخل/خارج شرکت | employment history | `report.personnel.view` | Excel/PDF |
| `personnel.dependents` | وابستگان و وضعیت خانواده | deferred dependent domain | `report.personnel.view` | بعد از تعریف ماژول |
| `personnel.evaluations` | ارزیابی‌های ثبت‌شده/نتیجه ارزیابی | deferred evaluation domain | `report.personnel.view` | بعد از تعریف ماژول |
| `security.permission_history` | تاریخچه تغییر مجوز | permission_change_history | `security.permission_history.view` | Excel/PDF |
| `workflow.inbox` | کارتابل گردش کار | requests/steps | `workflow.inbox.view` | محدود |
| `capacity.overdue` | درخواست‌های ظرفیت معوق | capacity_change_requests | `capacity.request.view` | Excel |
| `audit.sensitive_access` | مشاهده/دانلود داده حساس | sensitive_access_events | مجوز ممیزی حساس | محدود/کنترل‌شده |

### دامنه نسخه اول
- گزارش‌های مرتبط با جداول موجود و قطعی قابل پیاده‌سازی‌اند.
- گزارش وابستگان، مزایا، ارتقاء و ارزیابی تا زمانی که ماژول داده متناظر طراحی نشده، فقط در roadmap می‌مانند.
- ماژول‌های deferred مثل حضور و غیاب، رستوران، انبار، لباس، آموزش، مهمانسرا، حمل‌ونقل و رفاه وارد این بسته نمی‌شوند.

## 4. فیلترهای استاندارد

- شرکت (در صورت دسترسی چندشرکتی)
- واحد سازمانی و زیرواحدها
- وضعیت فعال/غیرفعال/آرشیو
- بازه تاریخ ثبت
- بازه تاریخ مؤثر
- نوع استخدام (در صورت وجود)
- سمت/عنوان شغلی
- جست‌وجوی متنی با حداقل طول و محدودیت query

فیلترها باید بر اساس scope کاربر محدود شوند؛ کاربر نباید بتواند با تغییر query parameter دامنه را گسترش دهد.

## 5. داشبورد نسخه اول

### کارت‌های پیشنهادی
- تعداد کل پرونده‌های پرسنلی قابل مشاهده
- تعداد پرسنل فعال/غیرفعال
- تعداد شرکت‌ها و واحدهای سازمانی قابل مشاهده
- تعداد سمت‌های مصوب و ظرفیت
- سمت‌های دارای vacancy (در صورت تعریف قاعده ظرفیت)
- درخواست‌های در انتظار اقدام کاربر
- درخواست‌های ظرفیت معوق (برای مدیران مجاز)
- انتصاب‌های آتی نزدیک به اجرا

هر کارت باید:
- permission مستقل یا permission dataset متناظر داشته باشد.
- از scope همان کاربر استفاده کند.
- در صورت نبود permission مخفی شود، نه اینکه صفر نشان دهد و وجود داده را لو دهد.
- لینک drill-down به فهرست مجاز داشته باشد.

## 6. خروجی Excel/PDF

- فایل خروجی باید generated_at، generated_by، report_key، فیلترهای اعمال‌شده و policy_version را در metadata/صفحه اول ثبت کند.
- داده‌های حساس به‌صورت پیش‌فرض حذف یا mask می‌شوند.
- خروجی نباید شامل ستون‌های پنهان UI باشد.
- export به‌صورت asynchronous برای داده‌های حجیم.
- download نیازمند permission مستقل export.
- فایل خروجی در private storage و با TTL نگهداری می‌شود.
- لینک دانلود creator-bound و کوتاه‌عمر.
- همه exportها audit می‌شوند.

## 7. Performance / Read Models

- dashboard از queryهای محدود/aggregate استفاده کند.
- گزارش‌های پرتکرار می‌توانند read model یا materialized view داشته باشند، ولی scope/tenant باید در لایه query امن اعمال شود.
- materialized view مشترک بدون tenant partition/filter ممنوع.
- refresh داده‌های حساس نباید آن‌ها را در cache عمومی کپی کند.
- indexها بر اساس queryهای واقعی و `EXPLAIN ANALYZE` طراحی شوند، نه حدس.
