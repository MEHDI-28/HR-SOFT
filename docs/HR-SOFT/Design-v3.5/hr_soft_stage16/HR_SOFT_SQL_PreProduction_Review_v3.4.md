# HR-SOFT — فهرست خطاها و ریسک‌های SQL برای pre-production
## نسخه 3.4

| موضوع | فایل/نسخه | یافته | اصلاح |
|---|---|---|---|
| پایه مصوب/موقت | organization v0.3 | احتمال اشتباه با ظرفیت headcount | نام‌گذاری base_value در v0.3.1 |
| Bulletin composite FK | user security v0.4 | missing unique(tenant_id,id) | index در v0.6 |
| default group system | user security v0.4 | system_id و group_id هم‌بستگی enforce نشده | composite FK |
| file owner NULL | migration v0.2 | CHECK ممکن است NULL را قبول کند | owner_type IS NOT NULL |
| SECURITY DEFINER trigger functions | proposals v2.2/v0.2/v2.5 | revoke EXECUTE کامل در همه proposalها یکدست نبود | revoke snippet |
| capacity cancelled backfill | migration v0.2 | cancelled به rejected نگاشت شده | بازنگری قبل از اجرا |
| birth_date duplicate | personnel v0.5 | legacy + private details | backfill و deprecate مرحله‌ای |

## نتیجه
پیش از هر اجرای واقعی باید این اصلاحات با schema واقعی تطبیق داده شوند. این مرحله static review است، نه اجرای SQL parser یا پایگاه داده؛ بنابراین ادعای compile/pass مطرح نیست.
