# HR-SOFT — Migration Dependency Graph
## نسخه 0.1 — ترتیب وابستگی، نه مجوز اجرا

```mermaid
flowchart TD
    G0[Gate 0: snapshot واقعی DEV + repo + backup] --> G1[1. تطبیق baseline و company-safe keys]
    G1 --> G2[2. مدل سازمانی و روابط سمت]
    G1 --> G3[3. اطلاعات خصوصی فرد و تماس]
    G1 --> G4[4. حساب کاربری، گروه، IP و اعلان]
    G1 --> G5[5. گردش درخواست و ظرفیت]
    G2 --> G6[6. انتساب سمت و تاریخچه]
    G3 --> G7[7. دسترسی داده حساس و ممیزی]
    G4 --> G8[8. کاتالوگ مجوز و resolver]
    G5 --> G8
    G6 --> G8
    G7 --> G8
    G8 --> G9[9. RLS، grants و Storage policies]
    G9 --> G10[10. آزمون tenant isolation و ACL]
    G10 --> G11[11. رویدادهای زمانی، outbox و worker]
    G11 --> G12[12. گزارش‌ها، export و read models]
    G12 --> G13[13. UI، پذیرش و release]
```

## قواعد مسیر بحرانی
1. Gate 0 مقدم بر تمام migrationها است.
2. company-safe FKها باید پیش از افزودن روابط سازمانی/پرسنلی اجرا و آزمون شوند.
3. Access resolver باید قبل از سیاست‌های نهایی RLS و Storage تثبیت شود.
4. هیچ policy permissive گسترده‌ای نباید جایگزین resolver و scope check شود.
5. آزمون دو tenant و سناریوهای explicit deny پیش‌نیاز فعال‌سازی محیط واقعی است.
6. migrationهای داده‌ای باید preflight، backfill، validation و rollback plan داشته باشند.
7. مرحله UI تنها پس از تثبیت قرارداد API و permissionها وارد پذیرش می‌شود.

## مواردی که هنوز باید از schema واقعی تعیین شوند
- نام و نسخه migrationهای واقعی؛
- وجود/عدم وجود جدول‌ها و constraintهای متناظر؛
- سازگاری کلیدها و داده‌های موجود؛
- ترتیب دقیق فایل‌های migration با توجه به وابستگی‌های واقعی؛
- امکان rollback هر تغییر و حجم backfill.
