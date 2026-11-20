# HR-SOFT — ترتیب نهایی مهاجرت‌ها و Gateهای کیفیت
## نسخه 3.3

| ترتیب | Migration/بخش | وابستگی | Gate |
|---|---|---|---|
| 0 | استخراج schema و baseline | دسترسی dev DB | schema snapshot |
| 1 | اصلاح company-safe FK | baseline | mismatch queries = 0 |
| 2 | position profile/org position/duties/offices/succession | migration 1 | FK and temporal tests |
| 3 | private person details/contact/country/city | baseline | PII access tests |
| 4 | user auth mode/IP/default group/login logs/bulletin | auth architecture | login/IP tests |
| 5 | capacity approval/execution split | workflow baseline | concurrency tests |
| 6 | file owner registry + private Storage | file schema | owner and storage tests |
| 7 | permission catalogue and resolver | all scope tables | ACL test suite |
| 8 | RLS and grants | resolver | cross-tenant pgTAP |
| 9 | temporal events/outbox/workers | domain commands | idempotency and schedule tests |
| 10 | reports/read models/exports | permissions | export scope tests |
| 11 | UI and release | all above | end-to-end acceptance |

**اصل:** Migration بعدی تا قبولی Gate قبلی وارد production نمی‌شود.
