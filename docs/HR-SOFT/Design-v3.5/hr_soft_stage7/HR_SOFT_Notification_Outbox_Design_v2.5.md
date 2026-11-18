# HR-SOFT — اعلان‌ها، Outbox و اجرای رویدادهای زمان‌بندی‌شده
## نسخه 2.5

## 1. معماری اعلان

تغییر کسب‌وکاری و ایجاد پیام باید در یک transaction ثبت شوند:
- تغییر assignment/capacity
- درج `outbox_events`
- commit
- worker مستقل پیام‌ها را مصرف و ارسال می‌کند.

ارسال SMS یا تماس با provider داخل transaction پایگاه داده انجام نمی‌شود.

## 2. اعلان انتساب سمت

هنگام اجرای assignment در تاریخ مؤثر:
- کارمند دریافت‌کننده انتساب: in-app و SMS (در صورت فعال بودن SMS).
- پیام شامل عنوان سمت، واحد سازمانی، تاریخ شروع و مافوق مستقیم.
- مدیر مستقیم جدید و مدیر مستقیم قبلی و اولین مدیر بالاتر مطلع می‌شوند.
- اگر مدیر بالاتر موجود نباشد، تمام مدیران سیستم دریافت می‌کنند.
- گیرندگان تکراری deduplicate می‌شوند.
- زنجیره مدیران در لحظه اجرای انتساب محاسبه می‌شود.
- اعلان in-app همیشه فعال است؛ SMS می‌تواند توسط گیرنده غیرفعال شود.

در زمان لغو انتساب آتی یا تغییر تاریخ پیش از اجرا، برای کارمند اعلان ارسال نمی‌شود.

## 3. اعلان ظرفیت

- یک روز قبل و روز اجرای برنامه‌ریزی‌شده: in-app به مدیران سیستم.
- اگر موعد گذشت و اجرا نشده: status `overdue` و ظرفیت قبلی باقی می‌ماند.
- پس از overdue: اعلان in-app روزانه به مدیران سیستم تا حل درخواست.
- یادآورها باید idempotent باشند؛ برای یک request و event_date فقط یک پیام ایجاد شود.

## 4. Outbox event contract

فیلدها:
- id UUID
- tenant_id
- event_key
- aggregate_type / aggregate_id
- payload JSONB (بدون داده حساس غیرضروری)
- occurred_at
- available_at
- attempts
- locked_at / locked_by
- processed_at
- last_error
- idempotency_key

Unique:
- `(tenant_id, idempotency_key)`

## 5. Worker lifecycle

- انتخاب batch با `FOR UPDATE SKIP LOCKED`.
- قفل کوتاه و ثبت locked_at/locked_by.
- ارسال بیرون transaction.
- ثبت نتیجه و provider_message_id.
- retry با backoff و حداکثر تعداد تلاش قابل تنظیم.
- پس از سقف retry، failed و قابل مشاهده برای مدیر سامانه.
- هر event در اثر retry نباید اعلان تکراری بسازد.

## 6. ساعت و timezone

- تمام timestampها در DB به `timestamptz` و UTC ذخیره شوند.
- تاریخ‌های تقویمی صرف مانند تاریخ استخدام در `date`.
- زمان‌بندی سازمانی باید timezone شرکت داشته باشد؛ در نسخه اول مقدار timezone در company settings نگهداری شود.
- اگر timezone شرکت تنظیم نشده باشد، worker نباید موعدهای حساس را حدس بزند؛ رویداد در وضعیت نیازمند پیکربندی بماند.

## 7. امنیت پیام

- متن SMS نباید شامل کد ملی، شبا، اطلاعات بانکی یا سند باشد.
- payload outbox حداقل داده لازم را داشته باشد.
- دسترسی worker به صف و secrets provider محدود باشد.
- خطای provider نباید متن کامل اطلاعات حساس را ثبت کند.
