# HR-SOFT — آزمون مدل سازمانی تکمیلی
## نسخه 3.0 | اجرا نشده

| ID | آزمون | انتظار |
|---|---|---|
| ORG-201 | position به organizational_position همان شرکت متصل شود | قبول |
| ORG-202 | اتصال موقعیت سازمانی شرکت دیگر | رد |
| ORG-203 | profile با position و company سازگار | قبول |
| ORG-204 | superior_position از شرکت دیگر | رد |
| ORG-205 | دو profile version یکسان برای position | unique رد |
| ORG-206 | profile effective_to قبل از effective_from | CHECK رد |
| ORG-207 | چند duty برای یک position | قبول |
| ORG-208 | duty متعلق به Tenant دیگر | FK رد |
| ORG-209 | چند office برای یک position در بازه‌های معتبر | قبول |
| ORG-210 | office متعلق به شرکت دیگر | FK رد |
| ORG-211 | چند candidate succession با priority متفاوت | قبول |
| ORG-212 | candidate پرسنلی از شرکت دیگر | FK رد |
| ORG-213 | succession منقضی‌شده در نمای جاری | نمایش داده نشود |
| ORG-214 | position خالی بدون assignment | در چارت باقی بماند |
| ORG-215 | تغییر profile سمت | assignmentهای افراد بازنویسی نشوند |

نکته: آزمون هم‌پوشانی بازه‌های profile، duties، offices و succession باید بعد از تصمیم قواعد هم‌پوشانی به exclusion constraint یا trigger تبدیل شود.
