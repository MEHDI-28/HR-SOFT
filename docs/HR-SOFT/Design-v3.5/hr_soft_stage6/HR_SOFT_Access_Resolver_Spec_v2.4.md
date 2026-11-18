# HR-SOFT — طراحی موتور محاسبه مجوز مؤثر
## نسخه 2.4 | مرحله ششم

- تاریخ: ۱۸ نوامبر ۲۰۲۶
- وضعیت: طراحی اجرایی سطح قرارداد؛ پیاده‌سازی و اجرا نشده.
- مبنا: تصمیم‌های امنیتی ثبت‌شده در نسخه‌های 1.9 تا 2.3 و SQL پایه 0.1.
- اصل: یک موتور تصمیم‌گیری سمت سرور؛ RLS لایه enforcement؛ UI مرجع امنیت نیست.

## 1. هدف و محدوده

موتور دسترسی باید برای هر درخواست مشخص کند:
- چه کاربری درخواست می‌دهد؟
- روی کدام Tenant و منبع واقعی؟
- کدام permission key لازم است؟
- عملیات چیست؟
- محدوده داده مجاز چیست؟
- آیا دسترسی موقت، عضویت غیرفعال، deny یا تاریخ اعتبار نتیجه را تغییر می‌دهد؟

موتور نباید به `tenant_id`, `company_id`, `org_unit_id` یا `personnel_record_id` ارسالی مستقیم کلاینت اعتماد کند. این مقادیر باید از رکورد واقعی یا wrapper سمت سرور استخراج شوند.

## 2. قرارداد تصمیم

خروجی موتور:
- `allowed boolean`
- `reason_code text` با مقادیر کنترل‌شده
- `policy_version text`
- `evaluated_at timestamptz`
- `matched_allow_count integer`
- `matched_deny_count integer`

Reason codes:
- `AUTH_REQUIRED`
- `APP_USER_INACTIVE`
- `TENANT_MISMATCH`
- `SYSTEM_INACTIVE`
- `NO_ACTIVE_MEMBERSHIP`
- `PERMISSION_NOT_GRANTED`
- `EXPLICIT_DENY`
- `SCOPE_NOT_GRANTED`
- `TEMPORARY_ACCESS_EXPIRED`
- `RESOURCE_NOT_FOUND`
- `ALLOWED_BY_GROUP`
- `ALLOWED_BY_TEMPORARY_ACCESS`

در API عمومی فقط `allowed` و پیام بی‌خطر برگردد؛ جزئیات reason_code در audit داخلی باقی بماند تا اطلاعات گروه‌ها و سیاست‌های امنیتی افشا نشود.

## 3. عملیات استاندارد

| Operation | معنا | منبع مجوز |
|---|---|---|
| `view` | مشاهده عادی | وجود rule مؤثر allow برای permission key و نبود deny؛ بدون ستون جداگانه can_view، مطابق تصمیم کاربر |
| `add` | ایجاد رکورد | `can_add=true` |
| `edit` | ویرایش رکورد | `can_edit=true` |
| `delete` | حذف منطقی/آرشیو | `can_delete=true` |
| `download` | دریافت بایت فایل | permission مستقل download |
| `view_sensitive` | مشاهده داده حساس | permission مستقل حساس |
| `correct_history` | اصلاح گذشته با رویداد اصلاحی | permission ویژه |
| `approve` | تصمیم گردش کار | permission + approver assignment |
| `execute` | اجرای تغییر تأییدشده | permission اجرایی مستقل |

برای `view` ستون `can_view` اضافه نمی‌شود، چون تصمیم محصول این بوده که مشاهده به‌صورت پیش‌فرض در چارچوب permission فعال باشد و ستون جداگانه نداشته باشد. با این حال، بدون permission key و scope مجاز، مشاهده آزاد نیست.

## 4. الگوریتم تصمیم‌گیری

ترتیب قطعی:
1. `auth.uid()` باید وجود داشته باشد.
2. یک `app_users` فعال و یکتا برای Auth identity پیدا شود.
3. Tenant کاربر از app_users استخراج شود.
4. منبع هدف از DB خوانده شود؛ tenant و company واقعی آن resolve شود.
5. اگر tenant منبع با tenant کاربر متفاوت است، رد فوری.
6. permission key باید در system درست تعریف و فعال باشد.
7. group membership باید فعال و در بازه زمانی معتبر باشد؛ گروه و system نیز فعال باشند.
8. ruleهای گروه‌های فعال برای permission key جمع‌آوری شوند.
9. rule با `effect='deny'` در هر گروه، در همان operation و scope معتبر، بر تمام allowها مقدم است.
10. برای allow گروهی، هم permission rule و هم scope allow معتبر لازم است.
11. temporary access در بازه `[starts_at, ends_at)` بررسی شود؛ temporary deny بر همه allowها مقدم است.
12. دسترسی موقت با scope null به معنی کل Tenant نیست؛ فقط در صورت تأیید مدیر و ثبت دلیل می‌تواند در Tenant جاری اعمال شود و باید محدودیت policy داشته باشد.
13. اگر هیچ allow معتبر باقی نماند، رد.
14. هر view/download حساس، event ممیزی ثبت کند.

## 5. جمع چندگروهی

- allowها از گروه‌های فعال کاربر جمع می‌شوند.
- deny صریح در هر گروه، allow گروه دیگر را خنثی می‌کند.
- گروه غیرفعال، عضویت غیرفعال یا منقضی‌شده در محاسبه شرکت نمی‌کند.
- reactivation گروه، مجوزهای قدیمی را خودکار فعال نمی‌کند؛ مطابق تصمیم ثبت‌شده باید عضویت و مجوزها دوباره تنظیم شوند.
- temporary access با عضویت گروهی یکسان نیست و باید در مسیر جداگانه و با دلیل/تأیید بررسی شود.

## 6. ارزیابی Scope

### ورودی Scope Resolver
- tenant_id واقعی
- company_id واقعی (در صورت وجود)
- org_unit_id واقعی (در صورت وجود)
- personnel_record_id واقعی (در صورت وجود)
- effective_at برای داده‌های زمانی
- evaluated_at برای اعتبار دسترسی

### تطبیق
- tenant scope: تمام منابع همان Tenant.
- company scope: منابع همان شرکت.
- org_unit scope: همان واحد؛ در صورت include_descendants، تمام descendants در همان شرکت.
- personnel scope: همان پرونده پرسنلی.
- scopeهای تاریخی باید براساس وضعیت سازمان در تاریخ effective_at ارزیابی شوند، نه فقط درخت فعلی.

### قاعده deny
deny scope از هر گروه در صورت تطبیق با رکورد هدف، کل دسترسی را رد می‌کند؛ حتی اگر گروه دیگری scope گسترده‌تر allow داشته باشد.

## 7. نکته مهم درباره ساختار فعلی

`group_permission_rules` دارای `can_add`, `can_edit`, `can_delete`, `effect` است و ستون `can_view` ندارد. `group_scope_assignments` جداگانه scope و effect را نگه می‌دارد.

برای جلوگیری از ambiguity:
- rule allow بدون scope allow نباید دسترسی داده ایجاد کند.
- rule deny در صورت تطبیق permission و scope deny، دسترسی را قطع کند.
- اگر هیچ scope assignment برای گروه وجود ندارد، گروه هیچ داده‌ای را نمی‌بیند؛ مگر اینکه یک scope tenant-wide صریحاً ثبت شده باشد.
- عملیات download باید permission key مجزا داشته باشد، نه اینکه از view استنتاج شود.

## 8. جلوگیری از جعل context

تابع resolver داخلی نباید به authenticated به‌صورت عمومی grant شود، چون کاربر می‌تواند context جعلی ارسال کند.
الگوی امن:
1. API/RPC عمومی مثل `hr_api.get_personnel_record(id)` فقط `record_id` دریافت کند.
2. تابع wrapper رکورد واقعی را با context Auth بخواند.
3. wrapper context واقعی را به resolver داخلی بدهد.
4. resolver داخلی `EXECUTE` عمومی نداشته باشد و فقط مالک توابع کنترل‌شده آن را اجرا کند.
5. خروجی wrapper فقط فیلدهای مجاز را برگرداند.
6. برای داده حساس wrapper جداگانه و audit اجباری باشد.

## 9. کلیدهای مجوز پیشنهادی

### مدیریت سامانه و امنیت
- `system.dashboard.view`
- `system.settings.view`, `system.settings.edit`
- `security.users.view`, `security.users.add`, `security.users.edit`, `security.users.block`
- `security.groups.view`, `security.groups.add`, `security.groups.edit`, `security.groups.archive`
- `security.memberships.view`, `security.memberships.add`, `security.memberships.edit`
- `security.permissions.view`, `security.permissions.edit`
- `security.permission_history.view`, `security.permission_history.export`
- `security.temporary_access.add`, `security.temporary_access.revoke`

### ساختار سازمانی
- `org.company.view`, `org.company.add`, `org.company.edit`
- `org.unit.view`, `org.unit.add`, `org.unit.edit`, `org.unit.archive`
- `org.position.view`, `org.position.add`, `org.position.edit`, `org.position.archive`
- `org.relationship.view`, `org.relationship.add`, `org.relationship.edit`
- `org.chart.view`, `org.chart.export`

### پرسنلی
- `personnel.view`, `personnel.add`, `personnel.edit`, `personnel.archive`
- `personnel.assignment.view`, `personnel.assignment.add`, `personnel.assignment.edit`
- `personnel.assignment.history.view`
- `personnel.history.correct`
- `sensitive.identity.view`, `sensitive.identity.edit`
- `sensitive.bank.view`, `sensitive.bank.add`, `sensitive.bank.edit`
- `sensitive.documents.view`, `sensitive.documents.upload`, `sensitive.documents.replace`, `sensitive.documents.download`

### گردش کار و ظرفیت
- `workflow.inbox.view`
- `workflow.request.submit`
- `workflow.request.view`
- `workflow.request.approve`, `workflow.request.reject`
- `capacity.request.add`, `capacity.request.view`, `capacity.request.edit`
- `capacity.request.approve`, `capacity.request.reject`
- `capacity.request.execute`, `capacity.request.cancel`
- `capacity.request.notes.view`, `capacity.request.notes.add`
- `capacity.request.files.view`, `capacity.request.files.manage`
- `capacity.request.export.create`, `capacity.request.export.download`

### اعلان و گزارش
- `notification.view`, `notification.preferences.edit`
- `report.personnel.view`, `report.personnel.export`
- `report.organization.view`, `report.organization.export`
- `report.security.view`, `report.security.export`

کلیدها پیشنهادی‌اند و قبل از seed باید به کاتالوگ system/permission نسخه‌بندی‌شده تبدیل شوند. کلید نهایی باید پایدار و یکتا باشد.

## 10. مجوزهای حساس و separation of duties

- کاربر مجاز به مشاهده اطلاعات بانکی الزاماً مجاز به ویرایش آن نیست.
- مشاهده، ویرایش و دانلود اسناد سه مجوز مستقل‌اند.
- ثبت تصمیم approve و اجرای نهایی capacity دو permission مستقل‌اند.
- مدیر سیستم بودن به‌تنهایی نباید به معنی مجوز مشاهده تمام داده‌های حساس باشد؛ مجوز حساس مستقل لازم است.
- permission history فقط برای مدیر سیستم و با audit بازدید/خروجی.
- export داده حساس باید permission export مستقل و scope برابر یا محدودتر از view داشته باشد.

## 11. Cache و اثر تغییر مجوز

- تغییر مجوز باید بلافاصله اثر کند.
- در نسخه اول تصمیم‌های دسترسی در cache بلندمدت ذخیره نشوند.
- اگر cache کوتاه‌مدت در آینده اضافه شد، باید با permission_version و invalidation تراکنشی باطل شود.
- signed URLهای Storage باید کوتاه‌عمر باشند؛ لغو permission نمی‌تواند URL صادرشده را پیش از انقضای آن لزوماً باطل کند، بنابراین مدت اعتبار باید بسیار محدود و حساسیت فایل لحاظ شود.

## 12. شرط پذیرش

- deny در هر گروه بر allow تمام گروه‌ها مقدم.
- کاربر نمی‌تواند context شرکت/واحد/پرسنل را جعل کند.
- هیچ دسترسی cross-tenant.
- scope خالی به معنی allow نیست.
- view فقط با permission key فعال + scope معتبر.
- download مستقل از view.
- داده حساس audit کامل دارد.
- تغییر مجوز در همان درخواست بعدی اثر کند.
