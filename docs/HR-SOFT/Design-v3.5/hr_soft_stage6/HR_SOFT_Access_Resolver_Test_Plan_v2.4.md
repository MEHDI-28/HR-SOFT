# HR-SOFT — آزمون‌های موتور مجوز مؤثر
## نسخه 2.4 | اجرا نشده

| ID | سناریو | نتیجه مورد انتظار |
|---|---|---|
| ACL-101 | گروه A allow + گروه B deny برای همان permission و scope | deny |
| ACL-102 | گروه B غیرفعال دارای deny | نادیده گرفته شود |
| ACL-103 | membership منقضی‌شده | نادیده گرفته شود |
| ACL-104 | permission system متفاوت از group.system_id | deny |
| ACL-105 | rule allow بدون scope allow | deny |
| ACL-106 | scope deny در یک گروه و scope allow در گروه دیگر | deny |
| ACL-107 | scope company A و resource company B | deny |
| ACL-108 | scope org_unit با descendants | زیرواحد مجاز؛ خارج درخت deny |
| ACL-109 | org hierarchy در تاریخ گذشته | براساس effective_at |
| ACL-110 | temporary allow خارج بازه | deny |
| ACL-111 | temporary deny همزمان با group allow | deny |
| ACL-112 | temporary access با scope null | فقط مطابق policy محدود، نه tenant-wide خودکار |
| ACL-113 | کاربر context جعلی company_id می‌فرستد | wrapper آن را نادیده می‌گیرد و context واقعی resolve می‌کند |
| ACL-114 | permission تغییر می‌کند و درخواست بعدی می‌آید | نتیجه جدید بلافاصله اعمال |
| ACL-115 | personnel.view بدون sensitive.identity.view | اطلاعات هویتی افشا نشود |
| ACL-116 | sensitive.documents.view بدون download | metadata مجاز، bytes ممنوع |
| ACL-117 | system admin بدون sensitive.bank.view | اطلاعات کامل بانکی ممنوع |
| ACL-118 | deny rule با تمام can_* false | deny همچنان مقدم است |
| ACL-119 | allow rule فقط can_edit=true و operation=view | view طبق تصمیم محصول از rule فعال و scope معتبر؛ semantics باید در seed/contract یکنواخت باشد |
| ACL-120 | هیچ group membership فعال نیست | deny |

## معیارهای قبولی
- تمام تست‌های deny اولویت و جعل context باید pass شوند.
- تغییر permission در همان درخواست بعدی اثر کند.
- هیچ wrapper عمومی اجازه ارسال tenant/company/org/personnel context دلخواه ندهد.
- خروجی عمومی جزئیات policy یا نام گروه‌ها را افشا نکند.
