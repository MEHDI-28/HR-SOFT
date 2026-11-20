# HR-SOFT — آزمون داده‌های شخص و پرونده پرسنلی
## نسخه 3.2 | اجرا نشده

| ID | سناریو | انتظار |
|---|---|---|
| PER-401 | person بدون personnel record | مجاز |
| PER-402 | app_user بدون person link | طبق سیاست حساب، مجاز/محدود |
| PER-403 | یک personnel record با شرکت دیگر از همان Tenant | رابطه قدیمی تغییر نکند؛ انتقال با event |
| PER-404 | کد ملی در جدول people | ممنوع؛ فقط identity_data |
| PER-405 | مشاهده birth/private details بدون permission | رد |
| PER-406 | مشاهده موبایل کامل بدون مجوز تماس | رد |
| PER-407 | ارسال SMS با opt-out | ارسال نشود |
| PER-408 | mobile ciphertext ذخیره شود | plaintext در DB/log نباشد |
| PER-409 | country alpha2 تکراری | unique رد |
| PER-410 | city به country نامعتبر | FK رد |
| PER-411 | تغییر employment status | personnel_record_event ایجاد شود |
| PER-412 | correction بدون reason | رد |
| PER-413 | UPDATE/DELETE روی employment event | رد |
| PER-414 | گزارش پرسنلی عادی | داده حساس mask/omit |

هیچ آزمونی اجرا نشده است.
