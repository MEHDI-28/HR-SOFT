# HR-SOFT — Git Sync Package v3.5

این بسته برای افزودن مستندات طراحی HR-SOFT به مخزن GitHub زیر آماده شده است:

`https://github.com/mehdi-28/HR-SOFT`

## محتویات
- اسناد مرحله‌های طراحی موجود در آرشیو نسخه ۳.۵
- اسناد Gate 0 و SQL فقط‌خواندنی مرحله ۱۷
- نسخه‌های مرجع فعلی در مسیر `LATEST`
- بدون سورس اصلی Admino، بدون فایل‌های محیطی، بدون secrets و بدون تغییر در کد اجرایی برنامه

## نکته مهم
این بسته هنوز در GitHub ثبت نشده است. اتصال GitHub از محیط اجرایی در این نوبت خطای داخلی داد و اتصال شبکه مستقیم نیز برقرار نشد. بنابراین این فایل یک بسته آماده ورود به مخزن است، نه Commit یا Push انجام‌شده.

## روش پیشنهادی ثبت در Git (PowerShell)

1. ابتدا مخزن را روی سیستم خود به‌روز کنید و مطمئن شوید تغییرات محلی مهمی ندارید.
2. ZIP را در یک مسیر دلخواه دانلود کنید.
3. PowerShell را در ریشه مخزن `HR-SOFT` باز کنید و دستورات زیر را اجرا کنید.

```powershell
git status --short
git switch -c docs/hr-soft-design-v3.5
Expand-Archive -Path "$env:USERPROFILE\Downloads\HR_SOFT_Git_Sync_Package_v3.5.zip" -DestinationPath "." -Force
git status --short
git add docs/HR-SOFT/Design-v3.5 HR_SOFT_GIT_SYNC_README_v3.5.md
git diff --cached --stat
git commit -m "docs(hr-soft): add design archive v3.5 and Gate 0 pack"
git push -u origin docs/hr-soft-design-v3.5
```

> اگر ZIP در پوشه Downloads نیست، فقط مسیر فایل را در دستور `Expand-Archive` اصلاح کنید.

## بازبینی پیش از Commit
- اگر `git status --short` پیش از شروع، تغییرات محلی نشان داد، آن‌ها را حذف یا reset نکنید؛ ابتدا باید بررسی شوند.
- پس از استخراج، `git diff --cached --stat` را بررسی کنید.
- این Commit فقط مستندات را اضافه می‌کند؛ هیچ migration، تغییر schema، policy یا تنظیمات Supabase اجرا نمی‌کند.
- شاخه اصلی (`main`/`master`) مستقیماً تغییر داده نمی‌شود؛ تغییرات در شاخه مستقل قرار می‌گیرند تا از طریق Pull Request بررسی شوند.
