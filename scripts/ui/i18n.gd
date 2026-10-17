class_name I18n
extends RefCounted

## The digits each tongue reads its numbers in. English reads the Latin
## digits the app already speaks; Persian and Arabic have their own --
## and a number said in a reader's tongue is said in its own script too.
## The decimal point and the percent sign travel with the digits: ٫ is
## the separator both tongues write inside a number, ٪ the percent that
## stands after one.
const DIGITS := {
        "fa": "۰۱۲۳۴۵۶۷۸۹",
        "ar": "٠١٢٣٤٥٦٧٨٩",
}

## The app's own words, in the reader's own tongue. The verses and their
## Persian translation are the deck's content and never change; this table
## dresses only the chrome -- menus, buttons, messages, the quiet lines a
## page says about itself. English is the key and the fallback: a string
## missing from a language simply reads in English, so a new screen can
## ship before its translations land, and nothing ever renders as a bare
## token. The choice itself travels with the deck (see deck.gd), the way
## the day's pace does -- one reader, one tongue, every device.
##
## The words are plain strings with format tokens (%d, %s) left in place;
## the caller substitutes after t() returns, and every translation keeps
## the argument order the English key established, because GDScript's %
## feeds an array, not named holes.

## The languages the app speaks, in the order the picker shows them. The
## labels are each written in their own tongue and are never translated
## again: a person finds their language by reading it, not by reading
## about it.
const LANGS := ["en", "fa", "ar"]
const LANG_LABELS := {
        "en": "English",
        "fa": "فارسی",
        "ar": "العربية",
}

const Scheduler := preload("res://scripts/data/scheduler.gd")

static var _lang := "en"


## The one door every screen reads through. An unknown language reads as
## English; an unknown string reads as itself (the English key).
static func t(what: String) -> String:
        var entry: Dictionary = STRINGS.get(what, {})
        if entry.has(_lang):
                return str(entry[_lang])
        return what


## A line with numbers in it, said whole: the words in the current tongue
## and the numbers in the tongue's own script. Every %d and %s a
## translated line carries is fed through here, so a Persian page never
## shows a Latin digit standing among Persian words. Care with marked-up
## text: num() converts EVERY digit, including ones inside [color=#B4553F]
## tags and URLs -- dress the number itself, not the line around it.
static func f(what: String, args: Array) -> String:
        return num(t(what) % args)


## A number, said in the current tongue's own script: "100" reads as ۱۰۰
## in Persian and ١٠٠ in Arabic, "1.5" keeps its half as ۱٫۵, "%" keeps
## its place as ٪. English reads every number exactly as it was given.
## Only the digits change, never the words around them.
static func num(what) -> String:
        var text := str(what)
        var table: String = str(DIGITS.get(_lang, ""))
        if table.is_empty():
                return text
        var out := PackedStringArray()
        for i in text.length():
                var ch := text[i]
                if ch >= "0" and ch <= "9":
                        out.append(table[ord(ch) - 48])
                elif ch == ".":
                        # A point between two digits belongs to the number; a
                        # sentence's own full stop never stands between two.
                        var before := i > 0 and text[i - 1] >= "0" and text[i - 1] <= "9"
                        var after := i + 1 < text.length() and text[i + 1] >= "0" and text[i + 1] <= "9"
                        out.append("٫" if before and after else ch)
                elif ch == "%":
                        out.append("٪")
                else:
                        out.append(ch)
        return "".join(out)


## A wait the reader is asked to consider, said in the reader's own tongue
## and script. English keeps Anki's compact arithmetic ("10m", "1d",
## "3.5mo"); every other tongue gets the words with its own digits --
## "۱ دقیقه", "۱ روز" -- because a Persian reader meets a Latin "1d" as
## a foreign word, not a number.
static func wait(seconds: int) -> String:
        var parts := Scheduler.humanize_parts(seconds)
        return num(t(str(parts[0])) % parts[1])


static func lang() -> String:
        return _lang


## A code the app does not speak is not a language choice -- it is a
## corrupted file -- so it lands on English rather than on a table of
## missing keys.
static func set_lang(code: String) -> void:
        _lang = code if LANGS.has(code) else "en"


## The label a picker or a segment shows for a language: its own name in
## its own script, whatever the app is currently speaking.
static func lang_label(code: String) -> String:
        return str(LANG_LABELS.get(code, code))


## Does the tongue being spoken read from the right? A page laid out for a
## left-to-right reader is a page the right-to-left reader has to translate
## twice -- once the words, then where everything stands. The tongues this
## app speaks that run right to left answer here, and every page that has a
## direction asks this one question.
static func is_rtl() -> bool:
        return _lang in ["fa", "ar"]


const STRINGS := {
        # --- home ------------------------------------------------------------------
        "Study": {"fa": "مطالعه", "ar": "دراسة"},
        "Learn new cards": {"fa": "یادگیری کارت‌های تازه", "ar": "تعلّم البطاقات الجديدة"},
        "All caught up": {"fa": "امروز کاری نمانده است", "ar": "لا شيء بانتظارك اليوم"},
        "Browse the cards": {"fa": "همهٔ کارت‌ها", "ar": "تصفّح البطاقات"},
        "Read the whole deck, card by card": {
                "fa": "خواندن کل مجموعه، کارت به کارت",
                "ar": "اقرأ المجموعة كلها، بطاقةً بطاقة",
        },
        "NEXT UP": {"fa": "نوبت بعدی", "ar": "التالي"},
        "Due": {"fa": "سررسید", "ar": "مستحق"},
        "New": {"fa": "تازه", "ar": "جديد"},
        "Learned": {"fa": "آموخته", "ar": "محفوظ"},
        "Not connected": {"fa": "وصل نیست", "ar": "غير متصل"},
        "Settings": {"fa": "تنظیمات", "ar": "الإعدادات"},
        "Install the new version": {"fa": "نصب نسخهٔ تازه", "ar": "تثبيت الإصدار الجديد"},
        "A new version is ready — the gold button up top installs it.": {
                "fa": "نسخهٔ تازه آماده است — دکمهٔ طلایی بالا آن را نصب می‌کند.",
                "ar": "الإصدار الجديد جاهز — الزر الذهبي في الأعلى يثبّته.",
        },
        # --- the sync's own words, on home and under Settings ---------------------
        "Syncing…": {"fa": "همگام‌سازی…", "ar": "مزامنة…"},
        "Not connected — your deck lives on this device only": {
                "fa": "وصل نیست — مجموعهٔ شما تنها روی همین دستگاه است",
                "ar": "غير متصل — مجموعتك على هذا الجهاز فقط",
        },
        "Connection trouble — the app will try again by itself": {
                "fa": "ارتباط برقرار نشد — خودِ برنامه دوباره تلاش می‌کند",
                "ar": "تعذّر الاتصال — سيعيد التطبيق المحاولة من تلقاء نفسه",
        },
        "%d answer waiting to sync": {"fa": "%d پاسخ در انتظار همگام‌سازی", "ar": "إجابة واحدة بانتظار المزامنة"},
        "%d answers waiting to sync": {"fa": "%d پاسخ در انتظار همگام‌سازی", "ar": "%d إجابات بانتظار المزامنة"},
        "Changes waiting to sync": {
                "fa": "تغییرها در انتظار همگام‌سازی‌اند",
                "ar": "تغييرات بانتظار المزامنة",
        },
        "Last synced %s": {"fa": "آخرین همگام‌سازی %s", "ar": "آخر مزامنة %s"},
        "Connected — not synced yet": {"fa": "وصل است — هنوز همگام نشده", "ar": "متصل — لم تتم المزامنة بعد"},
        "Everything in step — synced just now": {
                "fa": "همه چیز همگام است — همین حالا همگام شد",
                "ar": "كل شيء متطابق — تمت المزامنة للتو",
        },
        "Synced just now · %d sent, %d fetched, %d merged": {
                "fa": "همین حالا همگام شد · %d فرستاده، %d گرفته، %d ادغام",
                "ar": "تمت المزامنة للتو · أُرسل %d · جُلب %d · دُمج %d",
        },
        "Sync could not finish — your cards are safe here. Try again.": {
                "fa": "همگام‌سازی کامل نشد — کارت‌های شما همین‌جا در امان‌اند. دوباره تلاش کنید.",
                "ar": "تعذّرت المزامنة — بطاقاتك آمنة هنا. حاول مجددًا.",
        },
        "just now": {"fa": "همین حالا", "ar": "الآن"},
        "%d min ago": {"fa": "%d دقیقه پیش", "ar": "قبل %d دقيقة"},
        "%dh ago": {"fa": "%d ساعت پیش", "ar": "قبل %d ساعة"},
        "%dd ago": {"fa": "%d روز پیش", "ar": "قبل %d يوم"},
        # --- the words a wait is said in, wherever one is named ----------------------
        "%ds": {"fa": "%d ثانیه", "ar": "%d ثانية"},
        "%dm": {"fa": "%d دقیقه", "ar": "%d دقيقة"},
        "%dh": {"fa": "%d ساعت", "ar": "%d ساعة"},
        "%.1fh": {"fa": "%.1f ساعت", "ar": "%.1f ساعة"},
        "%dd": {"fa": "%d روز", "ar": "%d يوم"},
        "%.1fd": {"fa": "%.1f روز", "ar": "%.1f يوم"},
        "%dmo": {"fa": "%d ماه", "ar": "%d شهر"},
        "%.1fmo": {"fa": "%.1f ماه", "ar": "%.1f شهر"},
        "%.1fy": {"fa": "%.1f سال", "ar": "%.1f سنة"},
        # --- study -----------------------------------------------------------------
        "%d of %d": {"fa": "%d از %d", "ar": "%d من %d"},
        "Show answer": {"fa": "نمایش پاسخ", "ar": "إظهار الجواب"},
        "Done": {"fa": "تمام", "ar": "تم"},
        "complete": {"fa": "پایان", "ar": "اكتمل"},
        "Session complete": {"fa": "جلسه کامل شد", "ar": "اكتملت الجلسة"},
        "You answered %d cards in %s. Everything is saved.": {
                "fa": "%d کارت را در %s پاسخ گفتید. همه چیز ذخیره شد.",
                "ar": "أجبت عن %d بطاقة في %s. كل شيء محفوظ.",
        },
        "Rest is part of learning.": {
                "fa": "استراحت نیز بخشی از یادگیری است.",
                "ar": "الراحة جزء من التعلّم.",
        },
        "under a minute": {"fa": "کمتر از یک دقیقه", "ar": "أقل من دقيقة"},
        "1 minute": {"fa": "۱ دقیقه", "ar": "دقيقة واحدة"},
        "%d minutes": {"fa": "%d دقیقه", "ar": "%d دقائق"},
        "Again": {"fa": "دوباره", "ar": "أعد"},
        "again": {"fa": "دوباره", "ar": "إعادة"},
        "Hard": {"fa": "سخت", "ar": "صعب"},
        "hard": {"fa": "سخت", "ar": "صعبة"},
        "Good": {"fa": "خوب", "ar": "جيد"},
        "good": {"fa": "خوب", "ar": "جيدة"},
        "Easy": {"fa": "آسان", "ar": "سهل"},
        "easy": {"fa": "آسان", "ar": "سهلة"},
        "reveal": {"fa": "نمایش", "ar": "إظهار"},
        "answer": {"fa": "پاسخ", "ar": "جواب"},
        "close": {"fa": "بستن", "ar": "إغلاق"},
        # --- shared chrome -----------------------------------------------------------
        "Back to home": {"fa": "بازگشت به خانه", "ar": "العودة إلى الرئيسية"},
        "Edit this card": {"fa": "ویرایش این کارت", "ar": "تعديل هذه البطاقة"},
        "Recitation volume": {"fa": "بلندی تلاوت", "ar": "مستوى التلاوة"},
        "Mute or unmute": {"fa": "قطع یا وصل صدا", "ar": "كتم الصوت أو تشغيله"},
        # --- the card's own voices ---------------------------------------------------
        "Listen": {"fa": "شنیدن", "ar": "استمع"},
        "Persian": {"fa": "فارسی", "ar": "الفارسية"},
        "Listening…": {"fa": "در حال پخش…", "ar": "جارٍ الاستماع…"},
        "Fetching…": {"fa": "در حال گرفتن…", "ar": "جارٍ الجلب…"},
        "Unavailable": {"fa": "در دسترس نیست", "ar": "غير متاح"},
        # --- browse, the library -----------------------------------------------------
        "Browse": {"fa": "کتابخانه", "ar": "المكتبة"},
        "Search the deck — a surah, a verse, 2:1…": {
                "fa": "جست‌وجو در مجموعه — نام سوره، آیه، ۲:۱…",
                "ar": "ابحث في المجموعة — سورة، آية، ٢:١…",
        },
        "In review": {"fa": "در مرور", "ar": "في المراجعة"},
        "All": {"fa": "همه", "ar": "الكل"},
        "What the day is asking for": {
                "fa": "آنچه امروز از تو می‌خواهد",
                "ar": "ما يطلبه اليوم منك",
        },
        "Cards never yet studied": {
                "fa": "کارت‌هایی که هنوز خوانده نشده‌اند",
                "ar": "بطاقات لم تُدرس بعد",
        },
        "Cards resting between reviews": {
                "fa": "کارت‌هایی که میان دو مرور آسوده‌اند",
                "ar": "بطاقات تستريح بين المراجعات",
        },
        "The whole shelf": {"fa": "همهٔ قفسه", "ar": "الرفّ كله"},
        "%d of %d cards": {"fa": "%d از %d کارت", "ar": "%d من %d بطاقة"},
        "No cards answer": {"fa": "هیچ کارتی پاسخ نمی‌دهد", "ar": "لا بطاقات تجيب"},
        "Nothing is due today": {"fa": "امروز چیزی سررسید نیست", "ar": "لا شيء مستحق اليوم"},
        "Every card has been started": {
                "fa": "همهٔ کارت‌ها آغاز شده‌اند",
                "ar": "بدأت كل البطاقات",
        },
        "Nothing rests between reviews yet": {
                "fa": "هنوز کاری میان دو مرور نیست",
                "ar": "لا شيء يستريح بين المراجعات بعد",
        },
        "The shelf is empty": {"fa": "قفسه خالی است", "ar": "الرفّ فارغ"},
        "Try fewer words, or the verse's address — 2:1.": {
                "fa": "کلمات کمتری را بیازما، یا نشانی آیه — ۲:۱.",
                "ar": "جرّب كلمات أقل، أو عنوان الآية — ٢:١.",
        },
        "The deck rests, and so can its reader.": {
                "fa": "مجموعه آسوده است؛ خواننده‌اش هم چنین.",
                "ar": "المجموعة تستريح، وقارئها كذلك.",
        },
        "The whole deck is under way.": {
                "fa": "همهٔ مجموعه در جریان است.",
                "ar": "المجموعة كلها في تقدّم.",
        },
        "Cards land here once reviews carry them.": {
                "fa": "کارت‌ها وقتی مرورها به بار بنشیند این‌جا می‌آیند.",
                "ar": "تصل البطاقات إلى هنا حين تحملها المراجعات.",
        },
        "A deck of folders and files, read from its own shelf.": {
                "fa": "مجموعه‌ای از پوشه‌ها و پرونده‌ها، خوانده از قفسهٔ خودش.",
                "ar": "مجموعة من مجلدات وملفات، تُقرأ من رفّها.",
        },
        "%d card": {"fa": "%d کارت", "ar": "بطاقة واحدة"},
        "%d cards": {"fa": "%d کارت", "ar": "%d بطاقة"},
        "%d in review": {"fa": "%d در مرور", "ar": "%d في المراجعة"},
        "Edit card": {"fa": "ویرایش کارت", "ar": "تعديل البطاقة"},
        "due now": {"fa": "الان", "ar": "الآن"},
        "due today": {"fa": "امروز", "ar": "اليوم"},
        "in %s": {"fa": "تا %s دیگر", "ar": "بعد %s"},
        # --- the editor ---------------------------------------------------------------
        "Back without saving": {"fa": "بازگشت بدون ذخیره", "ar": "العودة دون حفظ"},
        "Write": {"fa": "نوشتن", "ar": "كتابة"},
        "Read": {"fa": "خواندن", "ar": "قراءة"},
        "The words as their author wrote them": {
                "fa": "واژه‌ها همان‌گونه که نویسنده‌اش نوشته است",
                "ar": "الكلمات كما كتبها صاحبها",
        },
        "The card as its reader will see it": {
                "fa": "کارت همان‌گونه که خواننده‌اش خواهد دید",
                "ar": "البطاقة كما سيراها قارئها",
        },
        "QUESTION": {"fa": "پرسش", "ar": "السؤال"},
        "ANSWER": {"fa": "پاسخ", "ar": "الجواب"},
        "leave": {"fa": "خروج", "ar": "خروج"},
        "save": {"fa": "ذخیره", "ar": "حفظ"},
        "·  *stars* lean a word": {
                "fa": "·  *ستاره‌ها* کلمه را خم می‌کنند",
                "ar": "·  *النجوم* تُميل الكلمة",
        },
        "Cancel": {"fa": "لغو", "ar": "إلغاء"},
        "Save": {"fa": "ذخیره", "ar": "حفظ"},
        "The edits are not saved.": {"fa": "تغییرها ذخیره نشده است.", "ar": "التعديلات غير محفوظة."},
        "Keep editing": {"fa": "ادامهٔ ویرایش", "ar": "متابعة التحرير"},
        "Discard": {"fa": "دور انداختن", "ar": "تجاهل"},
        "A card needs both a question and an answer.": {
                "fa": "کارت باید هم پرسش داشته باشد هم پاسخ.",
                "ar": "تحتاج البطاقة إلى سؤال وجواب معًا.",
        },
        "The question could not be saved.": {"fa": "پرسش ذخیره نشد.", "ar": "تعذّر حفظ السؤال."},
        "The answer could not be saved.": {"fa": "پاسخ ذخیره نشد.", "ar": "تعذّر حفظ الجواب."},
        # --- the sync overlay ----------------------------------------------------------
        "Syncing": {"fa": "همگام‌سازی", "ar": "المزامنة"},
        "Signing in to GitHub": {"fa": "ورود به GitHub", "ar": "تسجيل الدخول إلى GitHub"},
        "Reading your repo": {"fa": "خواندن مخزن شما", "ar": "قراءة مستودعك"},
        "Fetching what changed": {"fa": "گرفتن تغییرها", "ar": "جلب ما تغيّر"},
        "Sending your cards": {"fa": "فرستادن کارت‌های شما", "ar": "إرسال بطاقاتك"},
        "Merging your progress": {"fa": "ادغام پیشرفت شما", "ar": "دمج تقدّمك"},
        "Saving to your repo": {"fa": "ذخیره در مخزن شما", "ar": "الحفظ في مستودعك"},
        "Up to date": {"fa": "به‌روز", "ar": "محدَّث"},
        "Sync could not finish": {"fa": "همگام‌سازی کامل نشد", "ar": "تعذّرت المزامنة"},
        "Your cards stay on this device — sync only shares them.": {
                "fa": "کارت‌های شما روی همین دستگاه می‌مانند — همگام‌سازی تنها آن‌ها را به اشتراک می‌گذارد.",
                "ar": "بطاقاتك تبقى على هذا الجهاز — المزامنة تشاركها فقط.",
        },
        # --- settings -------------------------------------------------------------------
        "GitHub sync": {"fa": "همگام‌سازی GitHub", "ar": "مزامنة GitHub"},
        "Connected as @%s": {"fa": "وصل شده به @%s", "ar": "متصل باسم @%s"},
        "Token saved": {"fa": "توکن ذخیره شد", "ar": "حُفظ الرمز"},
        "Not connected. In a browser you sign in with a one-minute token — press Connect GitHub and it walks you through.": {
                "fa": "وصل نیست. در مرورگر با توکنی یک‌دقیقه‌ای وارد می‌شوید — دکمهٔ اتصال GitHub را بزنید تا راهنمایی‌تان کند.",
                "ar": "غير متصل. في المتصفح تسجّل الدخول برمزٍ يُنشأ في دقيقة — اضغط «اتصل بـ GitHub» وسيرشدك.",
        },
        "Not connected. Sync keeps your progress on your own GitHub repo.": {
                "fa": "وصل نیست. همگام‌سازی پیشرفت شما را در مخزن خودِ GitHub نگه می‌دارد.",
                "ar": "غير متصل. تحفظ المزامنة تقدّمك في مستودع GitHub الخاص بك.",
        },
        "Type this code at github.com/login/device, then wait here.": {
                "fa": "این کد را در github.com/login/device بنویسید، سپس این‌جا منتظر بمانید.",
                "ar": "اكتب هذا الرمز في github.com/login/device ثم انتظر هنا.",
        },
        "Open GitHub": {"fa": "گشودن GitHub", "ar": "فتح GitHub"},
        "Copy code": {"fa": "رونوشت کد", "ar": "نسخ الرمز"},
        "Open the sign-in page": {"fa": "گشودن صفحهٔ ورود", "ar": "فتح صفحة تسجيل الدخول"},
        "Copy the code to the clipboard": {
                "fa": "رونوشت کد در کلیپ‌بورد",
                "ar": "نسخ الرمز إلى الحافظة",
        },
        "Connect GitHub": {"fa": "اتصال GitHub", "ar": "اتصل بـ GitHub"},
        "Sign in with GitHub": {"fa": "ورود با GitHub", "ar": "تسجيل الدخول عبر GitHub"},
        "Disconnect": {"fa": "گسستن", "ar": "قطع الاتصال"},
        "Personal access token": {"fa": "توکن دسترسی شخصی", "ar": "رمز الوصول الشخصي"},
        "Paste the token GitHub shows you": {
                "fa": "توکنی را که GitHub نشان‌تان می‌دهد این‌جا بچسبانید",
                "ar": "ألصق الرمز الذي يعرضه GitHub",
        },
        "…or paste a repo token": {"fa": "…یا توکن مخزن را بچسبانید", "ar": "…أو ألصق رمز المستودع"},
        "Show": {"fa": "نمایش", "ar": "إظهار"},
        "Hide": {"fa": "پنهان", "ar": "إخفاء"},
        "Save token": {"fa": "ذخیرهٔ توکن", "ar": "حفظ الرمز"},
        "Show or hide what was typed": {
                "fa": "نمایش یا پنهان‌کردن آنچه نوشته شد",
                "ar": "إظهار ما كُتب أو إخفاؤه",
        },
        "Repository": {"fa": "مخزن", "ar": "المستودع"},
        "Repository name": {"fa": "نام مخزن", "ar": "اسم المستودع"},
        "Where your deck lives on GitHub — created on first sync if it does not exist.": {
                "fa": "مجموعهٔ شما کجا در GitHub زندگی می‌کند — اگر نباشد، در نخستین همگام‌سازی ساخته می‌شود.",
                "ar": "حيث تعيش مجموعتك في GitHub — يُنشأ عند أول مزامنة إن لم يكن موجودًا.",
        },
        "Sync quietly after each session": {
                "fa": "همگام‌سازی آرام پس از هر جلسه",
                "ar": "مزامنة هادئة بعد كل جلسة",
        },
        "Sync now": {"fa": "همگام‌سازی", "ar": "زامِن الآن"},
        "Sync with GitHub": {"fa": "همگام‌سازی با GitHub", "ar": "المزامنة مع GitHub"},
        "New cards each day": {"fa": "کارت‌های تازه در روز", "ar": "بطاقات جديدة كل يوم"},
        "Offer one fewer new card a day": {
                "fa": "یک کارت تازه کمتر در روز",
                "ar": "بطاقة جديدة أقل كل يوم",
        },
        "Offer one more new card a day": {
                "fa": "یک کارت تازه بیشتر در روز",
                "ar": "بطاقة جديدة أكثر كل يوم",
        },
        "How many unseen cards a day offers — 0 studies only reviews. Carried\nwith your deck, so every device paces the day the same.": {
                "fa": "هر روز چند کارت ندیده پیشنهاد می‌شود — صفر یعنی فقط مرور.\nهمراه مجموعهٔ شما می‌آید، تا هر دستگاه هم‌پایِ دیگری گام بردارد.",
                "ar": "كم بطاقة جديدة يعرضها اليوم — صفر يعني المراجعات فقط.\nتُحمل مع مجموعتك، فيسير كل جهاز على الوتيرة نفسها.",
        },
        "Data source": {"fa": "سرچشمهٔ داده", "ar": "مصدر البيانات"},
        "The deck's verses, Persian translation and recitations come from [url=https://quran.makarem.ir/]quran.makarem.ir[/url], carried unchanged from the deck package.": {
                "fa": "آیه‌های مجموعه، ترجمهٔ فارسی و تلاوت‌ها از [url=https://quran.makarem.ir/]quran.makarem.ir[/url] می‌آیند.",
                "ar": "آيات المجموعة وترجمتها الفارسية وتلاواتها من [url=https://quran.makarem.ir/]quran.makarem.ir[/url]، منقولةً دون تغيير من حزمة المجموعة.",
        },
        "Open quran.makarem.ir": {"fa": "گشودن quran.makarem.ir", "ar": "فتح quran.makarem.ir"},
        "QuranTathbit v%s": {"fa": "QuranTathbit نسخهٔ %s", "ar": "QuranTathbit الإصدار %s"},
        "This build has no GitHub app id yet. Add your OAuth app's client id to scripts/net/github_auth.gd, or paste a token below.": {
                "fa": "این ساخت هنوز شناسهٔ برنامهٔ GitHub ندارد. شناسهٔ کلاینت OAuth خود را در scripts/net/github_auth.gd بنویسید، یا توکنی را در پایین بچسبانید.",
                "ar": "لا يحمل هذا البناء معرّف تطبيق GitHub بعد. أضف معرّف عميل OAuth في scripts/net/github_auth.gd، أو ألصق رمزًا أدناه.",
        },
        "Browsers cannot open GitHub's sign-in page (cross-origin rules). Use Connect GitHub for the token steps instead.": {
                "fa": "مرورگرها نمی‌توانند صفحهٔ ورود GitHub را بگشایند (قانون‌های cross-origin). به‌جایش از اتصال GitHub و گام‌های توکن استفاده کنید.",
                "ar": "لا تستطيع المتصفحات فتح صفحة دخول GitHub (قواعد المنشأ المتقاطع). استخدم «اتصل بـ GitHub» لخطوات الرمز بدلًا من ذلك.",
        },
        "Could not reach GitHub. Check your connection and try again.": {
                "fa": "به GitHub نرسید. اتصال خود را ببینید و دوباره تلاش کنید.",
                "ar": "تعذّر الوصول إلى GitHub. تحقّق من اتصالك وحاول مجددًا.",
        },
        "That flow did not complete. Try again when ready.": {
                "fa": "آن روند کامل نشد. آماده که شدید دوباره تلاش کنید.",
                "ar": "لم يكتمل ذلك المسار. حاول مجددًا عندما تكون مستعدًا.",
        },
        "Signing in inside a browser takes a token — GitHub's sign-in page cannot be opened from another site, and no static site can change that. One minute, three steps:": {
                "fa": "ورود در مرورگر توکن می‌خواهد — صفحهٔ ورود GitHub از سایت دیگری باز نمی‌شود، و هیچ سایتی این را نمی‌تواند عوض کند. یک دقیقه، سه گام:",
                "ar": "تسجيل الدخول داخل المتصفح يتطلّب رمزًا — لا يمكن فتح صفحة دخول GitHub من موقع آخر، ولا يستطيع موقع ثابت تغيير ذلك. دقيقة واحدة، ثلاث خطوات:",
        },
        "1. Press the button — GitHub opens with the form filled in: the name and the repo permission are already set.\n2. Generate the token, then copy the string it shows you.\n3. Come back here, paste it into the box below (Ctrl+V, or hold the box on a phone), then press Save.": {
                "fa": "۱. دکمه را بزنید — GitHub با فرمِ پُرشده باز می‌شود: نام و دسترسی مخزن از پیش تنظیم‌اند.\n۲. توکن را بسازید، سپس رشته‌ای را که نشان‌تان می‌دهد رونویسی کنید.\n۳. به این‌جا برگردید، آن را در خانهٔ پایین بچسبانید (Ctrl+V، یا روی گوشی خانه را نگه دارید)، سپس ذخیره را بزنید.",
                "ar": "١. اضغط الزر — يُفتح GitHub والاستمارة مكتملة: الاسم وصلاحية المستودع معدّان سلفًا.\n٢. أنشئ الرمز ثم انسخ السلسلة التي يعرضها.\n٣. ارجع هنا وألصقها في الصندوق أدناه (Ctrl+V، أو اضغط مطوّلًا على الهاتف)، ثم اضغط حفظ.",
        },
        "Create a token on GitHub": {"fa": "ساختن توکن در GitHub", "ar": "إنشاء رمز في GitHub"},
        "Connected, but we could not read your login.": {
                "fa": "وصل است، اما ورود شما خوانده نشد.",
                "ar": "متصل، لكن تعذّر قراءة اسم دخولك.",
        },
        "That token did not work. Check it and try again.": {
                "fa": "آن توکن کار نکرد. آن را ببینید و دوباره تلاش کنید.",
                "ar": "لم يعمل ذلك الرمز. تحقّق منه وحاول مجددًا.",
        },
        "Nothing on the clipboard. Copy the token first, then hold the field to paste.": {
                "fa": "کلیپ‌بورد خالی است. نخست توکن را رونویسی کنید، سپس خانه را نگه دارید تا بچسبد.",
                "ar": "الحافظة فارغة. انسخ الرمز أولًا ثم اضغط الحقل مطوّلًا للّصق.",
        },
        "This build cannot read the clipboard — type the token instead.": {
                "fa": "این ساخت نمی‌تواند کلیپ‌بورد را بخواند — توکن را بنویسید.",
                "ar": "لا يستطيع هذا البناء قراءة الحافظة — اكتب الرمز بدلًا من ذلك.",
        },
        "The clipboard is empty. Copy the token on GitHub, then hold the field to paste.": {
                "fa": "کلیپ‌بورد خالی است. توکن را در GitHub رونویسی کنید، سپس خانه را نگه دارید تا بچسبد.",
                "ar": "الحافظة فارغة. انسخ الرمز من GitHub ثم اضغط الحقل مطوّلًا للّصق.",
        },
        "Pasted — press Save token when it looks right.": {
                "fa": "چسبید — وقتی درست رسید دکمهٔ ذخیرهٔ توکن را بزنید.",
                "ar": "أُلصق — اضغط «حفظ الرمز» عندما يبدو صحيحًا.",
        },
        "This browser would not share its clipboard. Copy the token, tap the field, and use your keyboard's paste.": {
                "fa": "این مرورگر کلیپ‌بوردش را به اشتراک نمی‌گذارد. توکن را رونویسی کنید، خانه را بزنید، و چسباندنِ صفحه‌کلیدتان را به کار ببرید.",
                "ar": "رفض هذا المتصفح مشاركة حافظته. انسخ الرمز، وانقر الحقل، واستخدم لصق لوحة المفاتيح.",
        },
        "The clipboard did not answer. Hold the field again to paste.": {
                "fa": "کلیپ‌بورد پاسخ نداد. برای چسباندن، خانه را دوباره نگه دارید.",
                "ar": "لم تُجب الحافظة. اضغط الحقل مطوّلًا مجددًا للّصق.",
        },
        # --- the backup card -------------------------------------------------------------
        "Backup": {"fa": "پشتیبان", "ar": "نسخة احتياطية"},
        "The whole deck — verses, recitations and your progress — in one zip file. Import joins a backup to this deck; nothing is removed.": {
                "fa": "کل مجموعه — آیه‌ها، تلاوت‌ها و پیشرفت شما — در یک پروندهٔ zip. وارد کردن، پشتیبان را به این مجموعه می‌پیوندد؛ چیزی برداشته نمی‌شود.",
                "ar": "المجموعة كلها — الآيات والتلاوات وتقدّمك — في ملف zip واحد. الاستيراد يضمّ النسخة الاحتياطية إلى هذه المجموعة؛ لا يُحذف شيء.",
        },
        "Export": {"fa": "خروجی", "ar": "تصدير"},
        "Import": {"fa": "وارد کردن", "ar": "استيراد"},
        "Pack the whole deck, with its progress, into one zip": {
                "fa": "کل مجموعه، با پیشرفتش، در یک پروندهٔ zip",
                "ar": "المجموعة كلها مع تقدّمها في ملف zip واحد",
        },
        "Choose a backup zip; its learning joins this deck": {
                "fa": "یک پشتیبان zip را برگزینید؛ یادگیری‌اش به این مجموعه می‌پیوندد",
                "ar": "اختر نسخة احتياطية بصيغة zip؛ يلتحم حفظها به هذه المجموعة",
        },
        "Backup saved — %s": {"fa": "پشتیبان ذخیره شد — %s", "ar": "حُفظت النسخة الاحتياطية — %s"},
        "The backup could not be written — your deck is safe here.": {
                "fa": "پشتیبان نوشته نشد — مجموعهٔ شما همین‌جا در امان است.",
                "ar": "تعذّر حفظ النسخة الاحتياطية — مجموعتك آمنة هنا.",
        },
        "That file is not a QuranTathbit backup.": {
                "fa": "آن پرونده پشتیبانِ QuranTathbit نیست.",
                "ar": "هذا الملف ليس نسخة احتياطية من QuranTathbit.",
        },
        "The backup could not be read.": {
                "fa": "پشتیبان خوانده نشد.",
                "ar": "تعذّرت قراءة النسخة الاحتياطية.",
        },
        "%d new card": {"fa": "%d کارت تازه", "ar": "بطاقة جديدة"},
        "%d new cards": {"fa": "%d کارت تازه", "ar": "%d بطاقات جديدة"},
        "%d card's progress arrived": {"fa": "پیشرفت %d کارت رسید", "ar": "وصل تقدّم بطاقة واحدة"},
        "%d cards' progress arrived": {"fa": "پیشرفت %d کارت رسید", "ar": "وصل تقدّم %d بطاقات"},
        "%d file added": {"fa": "%d پرونده افزوده شد", "ar": "أُضيف ملف واحد"},
        "%d files added": {"fa": "%d پرونده افزوده شد", "ar": "أُضيف %d ملفات"},
        "This deck already holds everything the backup has.": {
                "fa": "این مجموعه همهٔ آنچه این پشتیبان دارد را از پیش دارد.",
                "ar": "تحمل هذه المجموعة بالفعل كل ما في النسخة الاحتياطية.",
        },
        "Backup downloaded — it is in your browser's downloads.": {
                "fa": "پشتیبان بارگیری شد — در دانلودهای مرورگرتان است.",
                "ar": "نُزِّلت النسخة الاحتياطية — إنها في تنزيلات متصفحك.",
        },
        "This build cannot download files — the backup is saved inside the app's storage.": {
                "fa": "این ساخت نمی‌تواند پرونده بارگیری کند — پشتیبان در حافظهٔ خود برنامه ذخیره شد.",
                "ar": "لا يستطيع هذا البناء تنزيل الملفات — حُفظت النسخة الاحتياطية في مساحة التطبيق.",
        },
        "This build cannot open a file picker.": {
                "fa": "این ساخت نمی‌تواند گزینشگر پرونده را بگشاید.",
                "ar": "لا يستطيع هذا البناء فتح منتقي الملفات.",
        },
        "Bring a backup back": {"fa": "بازگرداندن یک پشتیبان", "ar": "إعادة نسخة احتياطية"},
        "No backup files found. Backups this app makes land in your Downloads folder — copy one there first.": {
                "fa": "هیچ پروندهٔ پشتیبانی پیدا نشد. پشتیبان‌هایی که این برنامه می‌سازد در پوشهٔ دانلودها می‌نشینند — نخست یکی را آن‌جا بگذارید.",
                "ar": "لا توجد ملفات احتياطية. النسخ التي ينشئها هذا التطبيق تُحفظ في مجلد التنزيلات — ضع واحدة هناك أولًا.",
        },
        "Downloads": {"fa": "دانلودها", "ar": "التنزيلات"},
        "App storage": {"fa": "حافظهٔ برنامه", "ar": "مساحة التطبيق"},
        # --- the reading card -------------------------------------------------------------
        "Reading": {"fa": "خوانش", "ar": "القراءة"},
        "Ayah font": {"fa": "قلم آیه‌ها", "ar": "خط الآيات"},
        "The face the verses are read in, wherever scripture is shown. Carried with your deck.": {
                "fa": "چهره‌ای که آیه‌ها با آن خوانده می‌شوند، هر جا متنِ وحی نشان داده شود. همراه مجموعهٔ شما می‌آید.",
                "ar": "الوجه الذي تُقرأ به الآيات أينما عُرض النص. يُحمل مع مجموعتك.",
        },
        "App language": {"fa": "زبان برنامه", "ar": "لغة التطبيق"},
        "Menus and messages only — the verses and their translations stay as they are. Carried with your deck.": {
                "fa": "تنها منوها و پیام‌ها — آیه‌ها و ترجمه‌هایشان همان‌گونه می‌مانند. همراه مجموعهٔ شما می‌آید.",
                "ar": "القوائم والرسائل فقط — تبقى الآيات وترجماتها كما هي. يُحمل مع مجموعتك.",
        },
        # --- the display card --------------------------------------------------------------
        "Display": {"fa": "نمایش", "ar": "العرض"},
        "Interface scale": {"fa": "اندازهٔ رابط", "ar": "مقياس الواجهة"},
        "Text scale": {"fa": "اندازهٔ متن", "ar": "مقياس النص"},
        "Shrink the interface one step": {"fa": "رابط یک پله کوچک‌تر شود", "ar": "صغّر الواجهة درجة"},
        "Grow the interface one step": {"fa": "رابط یک پله بزرگ‌تر شود", "ar": "كبّر الواجهة درجة"},
        "Shrink the text one step": {"fa": "متن یک پله کوچک‌تر شود", "ar": "صغّر النص درجة"},
        "Grow the text one step": {"fa": "متن یک پله بزرگ‌تر شود", "ar": "كبّر النص درجة"},
        "Scales the whole interface — cards, pills and words together — the way a phone's display-size setting does.": {
                "fa": "کل رابط را یکجا بزرگ یا کوچک می‌کند — کارت‌ها، قرص‌ها و واژه‌ها با هم — مانند تنظیم اندازهٔ نمایش در گوشی.",
                "ar": "يُكبِّر الواجهة كلها أو يُصغِّرها دفعةً واحدة — البطاقات والأرقام والكلمات معًا — كإعداد حجم العرض في الهاتف.",
        },
        "Scales the words only — verses, translations and messages — leaving the layout where it is.": {
                "fa": "تنها واژه‌ها را بزرگ یا کوچک می‌کند — آیه‌ها، ترجمه‌ها و پیام‌ها — و صفحه را سر جای خود می‌گذارد.",
                "ar": "يُكبِّر الكلمات وحدها — الآيات والترجمات والرسائل — ويترك التخطيط في مكانه.",
        },
        # --- the first-run picker -----------------------------------------------------------
        "Choose your language": {"fa": "زبان خود را انتخاب کنید", "ar": "اختر لغتك"},
}
