# HR-SOFT — ممیزی امنیت رابط مدیریت سازمانی
## نسخه 0.1 | ۱۹ نوامبر ۲۰۲۶

- مخزن/شاخه: HR-SOFT / docs/hr-soft-design-v3.5
- دامنه: auth.html، index.html، org-structure-manager.html و supabase-config.example.js
- روش: بازبینی ایستای کد و آزمون payloadهای مخرب با Node.js؛ بدون تغییر دیتابیس
- وضعیت: دو مورد XSS اصلاح و آزمون ایستای آن‌ها موفق شده است.

## 1. یافته‌های اصلاح‌شده

### FE-XSS-001 — بالا: تزریق کد از شناسه واردشده در فایل Excel
در صفحه‌های index.html و org-structure-manager.html، شناسه سمت از فایل Excel دریافت و در handlerهای inline مانند editPosition/deletePosition قرار می‌گرفت. تابع قبلی escapeAttr فقط apostrophe و double quote را به‌صورت ناقص مدیریت می‌کرد و backslash/line terminator و سایر کاراکترهای HTML را پوشش نمی‌داد. ترکیب شناسه واردشده با رشته JavaScript داخل صفت HTML می‌توانست به خروج از رشته و اجرای کد منجر شود.

**اصلاح انجام‌شده:**
- شناسه قبل از قرارگیری در handler با JSON.stringify به literal امن JavaScript تبدیل می‌شود.
- سپس مقدار کامل برای صفت HTML با escapeAttr جدید escape می‌شود.
- escapeAttr اکنون &, <, >, double quote و apostrophe را پوشش می‌دهد.
- اصلاح در هر دو صفحه index.html و org-structure-manager.html اعمال شد.

### FE-XSS-002 — متوسط: تاریخچه فیلد با مقدار خام
در renderFieldHistory، اگر h.at تاریخ معتبر نبود، مقدار خام از localStorage به dateStr منتقل و بدون escape وارد innerHTML می‌شد.

**اصلاح انجام‌شده:** dateStr پیش از درج در HTML با escapeHtml عبور داده می‌شود.

## 2. آزمون‌های انجام‌شده

اسکریپت `supabase/tests/validate_frontend_security.cjs` با Node.js اجرا شد و موفق بود:
- payloadهای شامل کوتیشن تکی/دوتایی، backslash، newline، رشته‌های HTML و entityهای HTML در handlerها به‌عنوان داده باقی می‌مانند.
- آزمون VM تأیید کرد payloadها باعث اجرای کد جانبی نمی‌شوند.
- مقادیر متنی قبل از درج در HTML escape می‌شوند.
- الگوی قبلی inline handler دیگر در دو صفحه وجود ندارد.
- در فایل‌های مرورگر هیچ service_role key یا sb_secret key واقعی/مقداردهی‌شده پیدا نشد.

این آزمون ایستا و unit-level است؛ جایگزین آزمون مرورگر واقعی، تست نفوذ یا آزمون با نشست JWT معتبر نیست.

## 3. وضعیت کلیدها و ذخیره‌سازی سمت مرورگر

- supabase-config.example.js فقط placeholder کلید publishable دارد؛ کلید service_role یا secret key در فایل‌های مرورگر یافت نشد.
- auth.html از Supabase Auth با کلید publishable استفاده می‌کند؛ ذخیره‌سازی دستی bootstrap token یا password در کد رابط مشاهده نشد.
- index.html و org-structure-manager.html داده‌های آزمایشی ساختار سازمانی را در localStorage با کلیدهای `org_fields`، `org_positions` و `org_field_history` نگه می‌دارند.
- localStorage قابل‌اعتماد یا محل امن نگهداری اطلاعات پرسنلی/حساس نیست. تا زمان اتصال API امن، داده‌های هویتی، بانکی، اسناد پرسنلی یا اطلاعات حساس نباید در آن ذخیره شوند.

## 4. کارهای باقی‌مانده

1. در مرحله بعد handlerهای inline به addEventListener و data attributes منتقل شوند تا سطح خطر ناشی از رشته‌های JavaScript در HTML حذف شود.
2. import فایل Excel باید علاوه بر escape، اعتبارسنجی طول/قالب شناسه و محدودیت اندازه/تعداد ردیف داشته باشد.
3. پس از آماده‌شدن APIهای امن، تمام داده‌های عملیاتی از localStorage به APIهای tenant-scoped منتقل شوند.
4. تست مرورگر واقعی با نشست معتبر و آزمون مجوزهای سمت سرور انجام شود.

## 5. محدودیت و وضعیت تغییرات

- هیچ migration یا تغییر دیتابیس در این ممیزی اجرا نشده است.
- اصلاحات فقط در working tree شاخه کاری انجام شده‌اند؛ commit، push و merge انجام نشده است.
- رابط مدیریت سازمانی هنوز به داده‌های عملیاتی Supabase متصل نیست.
## 6.1 اصلاح اعتبارسنجی تشخیص کلید محرمانه — ۱۹ نوامبر ۲۰۲۶

در بازبینی مجدد خودِ اسکریپت آزمون مشخص شد الگوی regex برای شناسایی مقداردهی متغیرهای `service_role` و `SUPABASE_SERVICE_ROLE_KEY` بیش از حد escape شده بود و ممکن بود فاصله‌های معمول اطراف `=` یا `:` را به‌درستی تشخیص ندهد.

**اصلاح انجام‌شده در working tree:**
- الگوی regex به `\s*` استاندارد JavaScript اصلاح شد.
- آزمون مثبت برای مقداردهی `SUPABASE_SERVICE_ROLE_KEY = '...'` اضافه شد.
- آزمون مثبت برای `service_role:'...'` اضافه شد.
- آزمون منفی برای متغیر publishable/anon اضافه شد تا false positive ایجاد نشود.

**نتیجه اجرای مجدد:** `validate_frontend_security.cjs` موفق شد و هر سه regression assertion جدید نیز اجرا شدند. این اصلاح فقط در فایل آزمون محلی است؛ هیچ فایل کلید یا تنظیم Supabase تغییر نکرده است.
