# HR-SOFT — Gate 0: استخراج وضعیت واقعی پایگاه داده
## بسته ممیزی فقط‌خواندنی — نسخه 0.1

### هدف
پیش از هر پیاده‌سازی، باید وضعیت واقعی محیط توسعه (DEV) ثبت شود: schema، جدول‌ها، ستون‌ها، کلیدها، indexها، RLS، policyها، grantها، roleها، routineها، triggerها، extensionها و Storage. این بسته جایگزین بررسی repository، تنظیمات Auth یا تست عملی نیست.

### وضعیت ایمنی
- فایل SQL فقط شامل پرس‌وجوهای `SELECT` و یک تراکنش `READ ONLY` است.
- هیچ `CREATE`، `ALTER`، `DROP`، `INSERT`، `UPDATE`، `DELETE`، `GRANT` یا `REVOKE` ندارد.
- اجرای پیشنهادی فقط روی محیط توسعه است؛ خروجی‌ها را قبل از اشتراک‌گذاری از نظر داده شخصی/محرمانه بازبینی کنید.
- پرس‌وجوی Storage فقط نام bucket و policy metadata را می‌خواند؛ محتوای فایل‌ها، signed URLها و رکوردهای کاربران Auth را استخراج نمی‌کند.
- اسکریپت اصلی فقط وجود جدول‌های schema مربوط به Storage و policyهای آن را فهرست می‌کند. برای خواندن مشخصات bucketها، فقط اگر جدول `storage.buckets` در خروجی فهرست جدول‌ها وجود داشت، این پرس‌وجوی اختیاری را جداگانه اجرا کنید: `SELECT id, name, public, file_size_limit, allowed_mime_types, created_at, updated_at FROM storage.buckets ORDER BY name;`
- جدول migration ledger نیز فقط وجود جدول را پیدا می‌کند؛ نسخه‌ها را حدس نمی‌زند.

### روش اجرای پیشنهادی
1. مطمئن شوید اتصال به پروژه و محیط `DEV` است، نه `PROD`.
2. از داشبورد Supabase یا ابزار SQL مورد تأیید تیم، فایل `HR_SOFT_Gate0_ReadOnly_Inventory_v0.1.sql` را باز کنید.
3. اگر کل فایل در SQL editor به علت multi-result محدودیت داشت، هر بخش شماره‌دار را جداگانه اجرا کنید. `BEGIN ... ROLLBACK` را برای اجرای تکه‌ای حذف کنید؛ پرس‌وجوها همچنان فقط‌خواندنی‌اند.
4. خروجی هر بخش را با نام شماره آن به CSV ذخیره کنید؛ بخش‌های حساس را فقط در فضای امن تیم نگه دارید.
5. همراه خروجی‌ها این اطلاعات غیرمحرمانه را ثبت کنید: شناسه پروژه به شکل کوتاه‌شده، نام محیط، زمان snapshot با timezone، نسخه PostgreSQL، نقش اجراکننده، commit/branch برنامه.
6. snapshot را با baseline طراحی HR-SOFT مقایسه کنید؛ هیچ migration را صرفاً به دلیل وجود فایل SQL اجرا نکنید.

### خروجی‌هایی که باید تحویل شوند
| شناسه | خروجی | برای چه تصمیمی لازم است |
|---|---|---|
| G0-01 | نسخه PostgreSQL، نقش و search_path | سازگاری و محدوده دسترسی |
| G0-02 | extensionها | وابستگی‌های واقعی |
| G0-03/04 | schemaها و relationها | تفکیک موجود/غایب و اشیای خارج از طرح |
| G0-05 | ستون‌ها و نوع داده | mapping دقیق مدل |
| G0-06 | constraintها و FKها | صحت ارجاع‌ها و ترتیب migration |
| G0-07 | indexها | کارایی و قیود یکتا |
| G0-08 | policyهای RLS | ممیزی مرز tenant و دسترسی |
| G0-09/10 | ACL و role membership | کمینه‌سازی مجوزها |
| G0-11/12 | routineها و triggerها | بررسی SECURITY DEFINER، search_path و side effects |
| G0-13/14 | enumها و sequenceها | تطبیق نوع‌ها و کلیدها |
| G0-15 | Storage buckets/policies | حفاظت اسناد HR |
| G0-16 | وجود migration ledger | تشخیص تاریخچه مهاجرت |
| G0-17 | شمارش کلی اشیا | کنترل کامل بودن snapshot |

### محدودیت مهم
SQL نمی‌تواند تنظیمات Auth provider، OAuth redirect URLs، SMTP/SMS provider، Edge Functions deployment، secrets، تنظیمات شبکه، تنظیمات پروژه در داشبورد یا کد برنامه را کامل استخراج کند. این موارد باید از پنل/فایل‌های پیکربندی و repository بررسی شوند؛ هرگز secret یا کلید API را در گزارش یا چت قرار ندهید.

### معیار قبولی Gate 0
Gate 0 فقط زمانی قبول است که:
- پروژه و محیط دقیقاً شناسایی شده باشند؛
- snapshot کامل و تاریخ‌دار از DEV موجود باشد؛
- repository و branch متناظر مشخص باشد؛
- وضعیت backup/restore قابل اتکا بررسی شده باشد؛
- schema snapshot با baseline طراحی تطبیق داده شده باشد؛
- اختلاف‌ها به فهرست `existing / missing / drifted / unknown` تبدیل شده باشند؛
- هیچ داده حساس یا secret در بسته تحویلی وجود نداشته باشد.

### توقف‌های اجباری
در صورت هر یک از موارد زیر migration متوقف می‌شود:
- محیط یا پروژه نامشخص؛
- backup یا روش بازگشت تأیید نشده؛
- وجود تغییرات دستی ناشناخته در DB؛
- اختلاف بین migration history و schema واقعی؛
- RLS فعال/غیرفعال غیرمنتظره؛
- policy یا grant ناشناخته؛
- داده ناسازگار در کلیدهای خارجی؛
- migration پیشنهادی دارای `DROP`، بازنویسی داده یا تغییر مخرب بدون برنامه بازگشت.

### فایل‌های مرتبط
- `HR_SOFT_Master_v3.4.md`
- `HR_SOFT_SQL_PreProduction_Review_v3.4.md`
- `HR_SOFT_SQL_Design_Errata_v3.4.md`
- `HR_SOFT_Migration_Sequence_v3.3.md`
- `HR_SOFT_Gate0_ReadOnly_Inventory_v0.1.sql`

این بسته فقط ابزار جمع‌آوری شواهد است؛ هیچ تغییری در پایگاه داده ایجاد نمی‌کند.
