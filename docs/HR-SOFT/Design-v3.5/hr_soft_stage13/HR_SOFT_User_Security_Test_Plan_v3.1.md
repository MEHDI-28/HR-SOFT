# HR-SOFT — آزمون امنیت حساب، IP، ورود و تابلو اعلانات
## نسخه 3.1 | اجرا نشده

| ID | آزمون | انتظار |
|---|---|---|
| USR-301 | auth_mode=local | فقط مسیر محلی مجاز |
| USR-302 | auth_mode=active_directory بدون AD broker معتبر | ورود رد |
| USR-303 | auth_mode=both | provider مجاز مطابق account config |
| USR-304 | AD username تکراری در یک Tenant | unique رد |
| IP-301 | IP در allow CIDR | مجاز در صورت نبود deny |
| IP-302 | IP در deny و allow همزمان | deny |
| IP-303 | IP خارج allowlist فعال | deny |
| IP-304 | header جعلی X-Forwarded-For از client | نادیده گرفته شود |
| IP-305 | IPv6 معتبر | CIDR match صحیح |
| GRP-301 | default group خارج system کاربر | FK/command رد |
| GRP-302 | default group غیرفعال | دسترسی ایجاد نکند |
| LOG-301 | login failure | login event ثبت شود |
| LOG-302 | access denied | access event ثبت شود |
| LOG-303 | log update/delete | رد |
| BUL-301 | bulletin قبل از starts_at | نمایش داده نشود |
| BUL-302 | bulletin پس از ends_at | نمایش داده نشود |
| BUL-303 | prevent_repeat و acknowledgement | در همان placement دوباره نمایش نشود |
| BUL-304 | acknowledgement در home | مانع نمایش login نشود، مگر policy صریحاً global شود |
| BUL-305 | متن HTML/JS خطرناک | sanitize و اجرا نشود |

هیچ آزمونی در این بسته اجرا نشده است.
