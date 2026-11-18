# HR-SOFT — تکمیل امنیت حساب کاربری، IP Policy و تابلو اعلانات
## نسخه 3.1 | مرحله سیزدهم

- تاریخ: ۱۸ نوامبر ۲۰۲۶
- وضعیت: طراحی و Migration پیشنهادی؛ اجرا نشده.
- مبنا: قابلیت‌های ثبت‌شده در Admino_Master_Document_v1.0.md.
- نکته: auth_mode و IP policy در این سند مدل پیشنهادی HR-SOFT هستند؛ پیاده‌سازی واقعی AD یا محدودیت شبکه نیازمند محیط اجرا و بررسی امنیتی است.

## 1. حساب کاربری و روش احراز هویت

فیلدهای مشاهده‌شده:
- شخص مرتبط
- نام کاربری
- نام کاربری Active Directory
- نوع احراز صلاحیت: عادی، Active Directory، هر دو

پیشنهاد مدل:
- `username`: شناسه محلی ورود HR-SOFT.
- `ad_username`: شناسه کاربر در Directory.
- `auth_mode`: `local`, `active_directory`, `both`.
- `auth_user_id`: شناسه هویت Supabase Auth یا identity broker.
- `status`: active/blocked/archived.
- `force_password_change`: فقط در حالت local یا هر دو و در صورت پشتیبانی provider.

**محدودیت:** Supabase Auth به‌تنهایی به معنی پشتیبانی آماده از هر Active Directory نیست. برای AD باید identity provider/SSO سازگار یا backend broker تعریف شود. هیچ integration در این مرحله انتخاب یا اجرا نشده است.

## 2. سیاست IP

مدل پیشنهادی:
- rule می‌تواند برای یک app_user یا کل Tenant تعریف شود.
- rule شامل CIDR، effect allow/deny، بازه اعتبار، دلیل و actor.
- deny صریح بر allow مقدم.
- اگر برای کاربر/tenant حداقل یک allow rule فعال تنظیم شده باشد، ورود فقط از IP مجاز ممکن است.
- اگر هیچ allow rule تعریف نشده، رفتار پیش‌فرض باید از تنظیم امنیتی Tenant تعیین شود؛ پیشنهاد امن برای حساب‌های مدیر سیستم: deny-by-default تا حداقل یک allowlist ثبت شود.
- IP از header قابل جعل کلاینت پذیرفته نشود؛ فقط از trusted proxy chain استخراج شود.
- IPv4 و IPv6 پشتیبانی شوند.
- رویداد ورود موفق/ناموفق با IP و user agent ثبت شود.
- IP policy نباید فقط در UI اعمال شود؛ در لایه احراز هویت/API قبل از دسترسی داده enforce شود.

## 3. گروه پیش‌فرض

- کاربر می‌تواند در چند گروه و چند system عضو باشد.
- گروه پیش‌فرض برای ورود/انتخاب context، مجوز جدید ایجاد نمی‌کند.
- پیشنهاد: یک default group برای هر کاربر در هر system.
- default group باید عضو فعال و گروه فعال همان system باشد.
- اگر گروه پیش‌فرض غیرفعال یا membership منقضی شد، هیچ دسترسی از آن ایجاد نمی‌شود و context پیش‌فرض باید دوباره انتخاب شود.
- حذف گروه باید default mapping را نیز archive/remove کند، اما history حفظ شود.

## 4. گزارش ورود و دسترسی

دو مفهوم جدا:
- login events: ورود موفق، ناموفق، logout، lockout، password reset، AD assertion.
- access events: مشاهده صفحه/منبع، عملیات، permission outcome، scope context، request id.

داده حساس در access log نباید ثبت شود.
گزارش‌ها فقط برای نقش‌های مجاز و با فیلترهای actor، system، date/time، IP، outcome، event type و user قابل مشاهده‌اند.

## 5. تابلو اعلانات

فیلدهای مشاهده‌شده:
- عنوان
- نمایش هنگام ورود
- نمایش در صفحه اصلی
- نمایش در عملکرد ماهانه
- تاریخ شروع اجباری
- تاریخ پایان
- متن خبر
- امکان جلوگیری از نمایش مجدد برای کاربر

پیشنهاد مدل:
- bulletin با تاریخ شروع/پایان و placementهای display.
- acknowledgement per user و per bulletin.
- اگر `prevent_repeat=true` و کاربر acknowledge کرد، همان bulletin دوباره در همان placement نمایش داده نشود.
- اگر prevent_repeat=false، امکان نمایش مجدد در هر بار ورود/بارگذاری طبق policy محصول.
- bulletin منقضی یا هنوز شروع‌نشده نمایش داده نشود.
- متن bulletin sanitize شود؛ HTML/JS خام اجرا نشود.
- فایل ضمیمه در نسخه اول خارج از scope است مگر بعداً اضافه شود.

## 6. امنیت و مجوز

کلیدهای پیشنهادی:
- `security.users.view`, `security.users.add`, `security.users.edit`, `security.users.block`
- `security.ip_rules.view`, `security.ip_rules.manage`
- `security.login_history.view`, `security.access_history.view`, `security.access_history.export`
- `security.default_group.manage`
- `notice.bulletin.view`, `notice.bulletin.add`, `notice.bulletin.edit`, `notice.bulletin.archive`
- `notice.acknowledgement.view`

هر گزارش ورود/دسترسی و تغییر IP policy باید audit شود.
