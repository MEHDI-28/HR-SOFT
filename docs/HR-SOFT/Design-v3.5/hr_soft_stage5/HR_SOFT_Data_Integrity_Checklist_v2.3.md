# HR-SOFT — چک‌لیست یکپارچگی داده و کنترل‌های پایگاه داده
## نسخه 2.3

## A. پیش از Migration
- [ ] اجرای baseline و supplemental روی DB توسعه خالی
- [ ] ثبت نسخه PostgreSQL و Supabase
- [ ] بررسی extensionهای `pgcrypto`, `citext`, `btree_gist`
- [ ] شمارش و تهیه snapshot از تمام جداول
- [ ] بررسی duplicateهای storage path
- [ ] بررسی orphanهای کلید خارجی
- [ ] بررسی اختلاف company_id در روابط سازمانی
- [ ] فهرست‌برداری تمام file ownerهای legacy
- [ ] شمارش درخواست‌های باز تکراری برای هر position

## B. قواعدی که باید enforce شوند
- [ ] org_unit parent و layer متعلق به همان company
- [ ] position و superior position متعلق به همان company
- [ ] assignment و position و personnel_record متعلق به همان company
- [ ] position_relationship فقط بین سمت‌های شرکت مجاز
- [ ] scope هدف دقیقاً یک نوع و یک مرجع معتبر داشته باشد
- [ ] file owner از allowlist و FK معتبر
- [ ] storage object path در تمام نسخه‌ها unique
- [ ] capacity request باز برای هر position حداکثر یک مورد
- [ ] revision جدید، approval قبلی را بی‌اعتبار کند
- [ ] تصمیم و تاریخچه و audit append-only
- [ ] اجرای درخواست فقط روی revision تأییدشده

## C. ایمنی هم‌زمانی
تمام فرمان‌های زیر باید در تراکنش سمت سرور اجرا شوند:
- approve capacity request
- revise request / reset approval
- execute capacity request
- cancel approved request
- attach/replace file version
- consume one-time export download token
- add/change group permission
- add/remove group membership

برای requestهای ظرفیت، `SELECT ... FOR UPDATE` روی ردیف درخواست و در صورت نیاز position لازم است. کنترل صرفاً در UI یا بررسی قبل از UPDATE در دو درخواست هم‌زمان کافی نیست.

## D. مدل temporal
- رکوردهای جاری از رویدادهای تغییر جدا باشند.
- تغییر گذشته با correction event ثبت شود.
- query در تاریخ دلخواه باید بر اساس effective time و recorded time قابل بازسازی باشد.
- برای انتساب‌ها و روابط سازمانی، بازه‌های زمانی نباید هم‌پوشانی غیرمجاز داشته باشند.
- هر رویداد باید actor، timestamp ثبت، effective date و reason داشته باشد.

## E. سیاست پشتیبان‌گیری و بازیابی
- backup قبل از هر migration.
- restore test دوره‌ای در محیط جدا.
- کلید رمزنگاری اطلاعات حساس backup جداگانه و تحت کنترل دسترسی محدود.
- آزمون بازیابی باید هم داده و هم objectهای Storage را پوشش دهد.
- log ممیزی پس از restore باید با داده اصلی سازگار باشد.
