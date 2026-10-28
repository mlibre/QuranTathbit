class_name Scheduler
extends RefCounted

## The scheduling math, ported from Anki's SM-2 scheduler (deck defaults, no
## FSRS). A card lives in one of three states -- new, learning, review -- and
## each answer moves it to the next one with Anki's exact numbers: starting
## ease 2.5, again -0.2, hard -0.15, easy +0.15, hard factor 1.2, easy bonus
## 1.3, learning steps 1m/10m, graduating interval 1d, easy interval 4d,
## relearning step 10m, lapse multiplier 0, maximum interval 36500 days. A
## lapsed card relearns at 10m and returns at one day; easy skips a day
## further still.
##
## A card the reader is not ready for can be taken out of the day and put
## back in the initial basket -- deferred, not answered (deferred_state
## below). It waits out the rest of its day as a new card the queue will
## not offer, and the next day it is simply new again, offered among the
## day's own fresh cards as though nothing had happened. Deferring is the
## reader's own move, never the algorithm's: no ease moves, no interval
## grows.
##
## Days are counted with a rollover: a day flips at 04:00, so a session after
## midnight still belongs to the evening before. The index is measured from
## the Unix epoch, which keeps it identical on every platform and timezone --
## a card due "today" is due today wherever the deck is opened.
##
## Intervals are fuzzed the way Anki fuzzes them, so a dozen cards answered
## "Good" do not all come back on the same day. The fuzz is drawn per card
## per day, deterministically: the same card on the same day gets the same
## interval on every device, which keeps a synced deck consistent without
## coordinating devices.

const MINUTE := 60
const HOUR := 3600
const DAY := 86400

# Deck parameters, in Anki's defaults.
const LEARNING_STEPS := [1 * MINUTE, 10 * MINUTE]  # seconds
const RELEARNING_STEPS := [10 * MINUTE]
const GRADUATING_IVL := 1  # days
const EASY_IVL := 4  # days
const INITIAL_EASE := 2.5
const MIN_EASE := 1.3
const EASE_AGAIN := -0.2
const EASE_HARD := -0.15
const EASE_EASY := 0.15
const HARD_FACTOR := 1.2
const EASY_BONUS := 1.3
const LAPSE_MULT := 0.0
const MAX_IVL := 36500
## Anki's deck default, worn to this deck's own size: how many unseen cards a
## day offers. The starting point of the app's own setting, and the fallback
## wherever a caller does not bring a number of its own. A scripture deck is
## learned a couple of verses a day, not crammed twenty.
const NEW_PER_DAY := 2
const ROLLOVER := 4 * HOUR

const AGAIN := "again"
const HARD := "hard"
const GOOD := "good"
const EASY := "easy"

## A stable seed for a card id string (FNV-1a). String.hash() is not promised
## stable across engine versions; fuzz must not shift when the app updates.
static func id_seed(id: String) -> int:
        var hash := 2166136261
        for byte in id.to_utf8_buffer():
                hash = (hash ^ byte) * 16777619
                hash &= 0x7FFFFFFF
        return hash

static func today(now: int) -> int:
        return int(floor(float(now - ROLLOVER) / float(DAY)))

static func new_state() -> Dictionary:
        return {
                "status": "new",
                "step": 0,
                "relearning": false,
                "due_ts": 0,
                "due_day": 0,
                "ivl": 0,
                "ease": INITIAL_EASE,
                "reps": 0,
                "lapses": 0,
                "mod": 0,
                "defer_day": 0,  # the day a defer is waiting out; 0 never waited
                "suspended": false,  # out of the schedule for good; see suspended_state
        }


## The initial basket, put back for a day: everything a new card starts
## with, stamped with the day whose remaining offer it is waiting out. A
## card carried to this state today is invisible to today's queue and
## today's counts; tomorrow the day has moved past the stamp and the card
## is new again, offered with the day's own fresh cards. Whatever the card
## had learned before is given back -- the reader asked for the initial
## basket, not a shorter version of the old one. The moment is stamped too:
## a defer is a deliberate act, later than any answer before it, and the
## merges that compare card states must be able to see that.
static func deferred_state(now: int) -> Dictionary:
        var state := new_state()
        state["defer_day"] = today(now)
        state["mod"] = now
        return state


## Out of the schedule for good: the initial basket with the door closed
## behind it. Nothing is due, nothing is offered, nothing is counted -- the
## card is a page in the deck's book and never a card in its queue, as
## though the reader never started studying it at all. The moment is
## stamped the way a defer's is, so the merges can see the act.
static func suspended_state(now: int) -> Dictionary:
        var state := new_state()
        state["suspended"] = true
        state["mod"] = now
        return state


## Is this state a card the queue never offers, whatever its status? A
## suspended card stands outside the schedule entirely: not due, not new,
## not learned -- simply not asked.
static func is_suspended(state: Dictionary) -> bool:
        return bool(state.get("suspended", false))


## Is this state a card today's offer passes over? Only a new card can be
## waiting out a defer, and only while its day has not yet passed.
static func is_deferred(state: Dictionary, now: int) -> bool:
        return (
                str(state.get("status", "new")) == "new"
                and int(state.get("defer_day", 0)) >= today(now)
        )

# --- the queue -----------------------------------------------------------------

static func queue(deck, now: int, new_per_day := NEW_PER_DAY) -> Array:
        """Due cards first (oldest due first), then today's new cards.

        `new_per_day` is the day's own offer of unseen cards -- the reader's
        choice, carried in from Settings; a 0 asks for reviews only.
        """
        var today_idx := today(now)
        var due: Array = []
        var fresh: Array = []
        var new_left := maxi(new_per_day, 0)
        for card in deck.cards:
                var state: Dictionary = card.state
                # A suspended card is not the day's to ask, whatever it was:
                # not due, not new, not learned -- outside the schedule.
                if is_suspended(state):
                        continue
                match state["status"]:
                        "learning":
                                if int(state["due_ts"]) <= now:
                                        due.append(card)
                        "review":
                                if int(state["due_day"]) <= today_idx:
                                        due.append(card)
                        _:
                                # A card deferred today is not the day's to
                                # offer: it stands aside without spending the
                                # day's own count, so the next unseen card
                                # takes its place.
                                if new_left > 0 and not is_deferred(state, now):
                                        fresh.append(card)
                                        new_left -= 1
        due.sort_custom(func(a, b) -> bool:
                var da: int = a.state["due_day"] if a.state["status"] == "review" else -1
                var db: int = b.state["due_day"] if b.state["status"] == "review" else -1
                if da != db:
                        return da < db
                return a.id < b.id
        )
        var out: Array = []
        for card in due:
                out.append(card)
        for card in fresh:
                out.append(card)
        return out

## The first card a larger offer would bring: new, not suspended, not
## waiting out a defer -- the queue's own rule, read past the day's cap.
## The day's offer may be spent or set to reviews alone, while the deck
## still holds an unseen card; this is that card, or null when every card
## has been started or set aside. A card the reader deferred or suspended
## is never offered back the same day by a bigger cap -- the defer was the
## reader's own word about today.
static func first_fresh(deck, now: int):
        for card in deck.cards:
                var state: Dictionary = card.state
                if is_suspended(state):
                        continue
                if str(state.get("status", "new")) == "new" and not is_deferred(state, now):
                        return card
        return null

static func counts(deck, now: int, new_per_day := NEW_PER_DAY) -> Dictionary:
        var today_idx := today(now)
        var due := 0
        var fresh := 0
        var learned := 0
        var new_left := maxi(new_per_day, 0)
        for card in deck.cards:
                var state: Dictionary = card.state
                # The counts agree with the queue: a suspended card is
                # nowhere among them, whatever it was before the door closed.
                if is_suspended(state):
                        continue
                match state["status"]:
                        "learning":
                                if int(state["due_ts"]) <= now:
                                        due += 1
                        "review":
                                # Learned is what the reader has, not what
                                # happens to be waiting: a card in review
                                # counts as learned whether its day has come
                                # or not. The day it comes due it speaks in
                                # the Due pill as well -- the two numbers
                                # overlap on purpose, each answering its own
                                # question -- so a few quiet days never drain
                                # the Learned count the reader remembers.
                                # Only an answer moves it: a lapse sends the
                                # card back to relearning, and it returns the
                                # hour it graduates again.
                                if int(state["due_day"]) <= today_idx:
                                        due += 1
                                learned += 1
                        _:
                                # The queue and the counts agree on what the
                                # day offers: a deferred card is not among it.
                                if new_left > 0 and not is_deferred(state, now):
                                        fresh += 1
                                        new_left -= 1
        # The cap rides along for the callers that fill the queue the same way
        # (home's "next up" reads it from these counts) -- the offer itself,
        # not the remainder the counting loop has been eating.
        return {
                "due": due,
                "new": fresh,
                "learned": learned,
                "new_per_day": maxi(new_per_day, 0),
        }

# --- answering -----------------------------------------------------------------

static func options(card_id: int, state: Dictionary, now: int) -> Array:
        """The four ways the card can be answered right now.

        Each option: {button, interval, next} where interval is the humanized wait
        and next is the resulting state (with mod unset -- apply() stamps it).
        """
        match state["status"]:
                "new":
                        return _learning_options(card_id, state, false, now)
                "learning":
                        return _learning_options(card_id, state, true, now)
                "review":
                        return _review_options(card_id, state, now)
        push_error("Scheduler.options: unknown status %s" % state["status"])
        return []

static func apply(card_id: int, state: Dictionary, button: String, now: int) -> Dictionary:
        var next: Dictionary = state
        for opt in options(card_id, state, now):
                if opt.button == button:
                        next = (opt.next as Dictionary).duplicate(true)
                        break
        if next == state:
                push_error("Scheduler.apply: no option %s for status %s" % [button, state["status"]])
                return state
        next.mod = now
        next.reps = int(state.get("reps", 0)) + 1
        return next

# --- new and learning cards ----------------------------------------------------

static func _learning_options(card_id: int, state: Dictionary, is_learning: bool, now: int) -> Array:
        var relearning: bool = is_learning and bool(state.get("relearning", false))
        var steps: Array = RELEARNING_STEPS if relearning else LEARNING_STEPS
        var step_idx: int = int(state["step"]) if is_learning else 0
        var today_idx := today(now)
        var out: Array = []

        # Again: back to the first step, in one minute (ten, when relearning).
        var again_secs: int = int(steps[0])
        out.append(_option(AGAIN, again_secs, _change(state, {
                "status": "learning",
                "step": 0,
                "relearning": relearning or bool(state.get("relearning", false)),
                "due_ts": now + again_secs,
        })))

        # Hard: the average of the first and second step (Anki avoids equalling
        # the again delay), or 1.5x the step when no step follows.
        var hard_secs: int = _hard_step_secs(steps, step_idx)
        out.append(_option(HARD, hard_secs, _change(state, {
                "status": "learning",
                "step": step_idx,
                "relearning": relearning,
                "due_ts": now + hard_secs,
        })))

        # Good: a step forward, or graduate.
        var has_next: bool = step_idx + 1 < steps.size()
        if has_next:
                var good_secs: int = int(steps[step_idx + 1])
                out.append(_option(GOOD, good_secs, _change(state, {
                        "status": "learning",
                        "step": step_idx + 1,
                        "relearning": relearning,
                        "due_ts": now + good_secs,
                })))
        else:
                var grad_days: int = 0
                if relearning:
                        grad_days = int(state["ivl"])  # the lapse interval, set when it lapsed
                else:
                        grad_days = _fuzzed(GRADUATING_IVL, card_id, today_idx, 1, MAX_IVL)
                out.append(_option(GOOD, grad_days * DAY, _change(state, {
                        "status": "review",
                        "step": 0,
                        "relearning": false,
                        "due_ts": 0,
                        "due_day": today_idx + grad_days,
                        "ivl": grad_days,
                        "ease": float(state["ease"]) if relearning else INITIAL_EASE,
                })))

        # Easy: graduate to the easy interval (lapse interval + 1 when relearning).
        var easy_days: int = 0
        if relearning:
                easy_days = int(state["ivl"]) + 1
        else:
                easy_days = _fuzzed(EASY_IVL, card_id, today_idx, 1, MAX_IVL)
        out.append(_option(EASY, easy_days * DAY, _change(state, {
                "status": "review",
                "step": 0,
                "relearning": false,
                "due_ts": 0,
                "due_day": today_idx + easy_days,
                "ivl": easy_days,
                "ease": float(state["ease"]) if relearning else INITIAL_EASE,
        })))
        return out

static func _hard_step_secs(steps: Array, step_idx: int) -> int:
        if step_idx == 0 and steps.size() > 1:
                var secs: int = (int(steps[0]) + int(steps[1])) / 2
                return _round_days_if_long(secs)
        if steps.size() == 1:
                var single: int = mini(int(steps[0]) * 3 / 2, int(steps[0]) + DAY)
                return _round_days_if_long(single)
        return _round_days_if_long(int(steps[step_idx]))

static func _round_days_if_long(secs: int) -> int:
        if secs > DAY:
                return int(round(float(secs) / float(DAY))) * DAY
        return secs

# --- review cards --------------------------------------------------------------

static func _review_options(card_id: int, state: Dictionary, now: int) -> Array:
        var scheduled: int = int(state["ivl"])
        var days_late: int = maxi(today(now) - int(state["due_day"]), 0)
        var cur: float = maxf(float(scheduled), 1.0)
        var ease: float = float(state["ease"])
        var today_idx := today(now)

        # Passing intervals, each at least one day past the previous option's.
        var hard_min: int = scheduled + 1
        var hard_days: int = _fuzzed(cur * HARD_FACTOR, card_id, today_idx, hard_min, MAX_IVL)
        var good_days: int = _fuzzed(
                (cur + float(days_late) / 2.0) * ease, card_id, today_idx, hard_days + 1, MAX_IVL
        )
        var easy_days: int = _fuzzed(
                (cur + float(days_late)) * ease * EASY_BONUS, card_id, today_idx, good_days + 1, MAX_IVL
        )

        # Failing: a lapse relearns the card and returns it at the lapse interval
        # (0% of the old interval, floored at one day).
        var lapse_days: int = _fuzzed(cur * LAPSE_MULT, card_id, today_idx, 1, MAX_IVL)

        var out: Array = []
        out.append(_option(AGAIN, int(RELEARNING_STEPS[0]), _change(state, {
                "status": "learning",
                "relearning": true,
                "step": 0,
                "due_ts": now + int(RELEARNING_STEPS[0]),
                "lapses": int(state["lapses"]) + 1,
                "ease": maxf(ease + EASE_AGAIN, MIN_EASE),
                "ivl": lapse_days,
        })))
        out.append(_option(HARD, hard_days * DAY, _change(state, {
                "status": "review",
                "due_day": today_idx + hard_days,
                "ivl": hard_days,
                "ease": maxf(ease + EASE_HARD, MIN_EASE),
        })))
        out.append(_option(GOOD, good_days * DAY, _change(state, {
                "status": "review",
                "due_day": today_idx + good_days,
                "ivl": good_days,
        })))
        out.append(_option(EASY, easy_days * DAY, _change(state, {
                "status": "review",
                "due_day": today_idx + easy_days,
                "ivl": easy_days,
                "ease": ease + EASE_EASY,
        })))
        return out

# --- helpers -------------------------------------------------------------------

static func _option(button: String, interval_secs: int, next: Dictionary) -> Dictionary:
        return {
                "button": button,
                "interval_secs": interval_secs,
                "interval": humanize(interval_secs),
                "next": next,
        }

static func _change(state: Dictionary, changes: Dictionary) -> Dictionary:
        var next: Dictionary = state.duplicate(true)
        next.merge(changes, true)
        return next

## Anki's fuzz: intervals of 2.5 days or more get a small, seeded nudge so
## due dates spread out instead of stacking. Returns whole days.
static func _fuzzed(interval_days: float, card_id: int, day: int, minimum: int, maximum: int) -> int:
        var lo: int = 0
        var hi: int = 0
        if interval_days < 2.5:
                lo = int(round(interval_days))
                hi = lo
        else:
                var delta: float = 1.0
                delta += 0.15 * maxf(minf(interval_days, 7.0) - 2.5, 0.0)
                delta += 0.1 * maxf(minf(interval_days, 20.0) - 7.0, 0.0)
                delta += 0.05 * maxf(interval_days - 20.0, 0.0)
                lo = int(round(interval_days - delta))
                hi = int(round(interval_days + delta))
        lo = clampi(lo, minimum, maximum)
        hi = clampi(hi, minimum, maximum)
        if hi == lo and hi > 2 and hi < maximum:
                hi = lo + 1
        var roll := _card_day_roll(card_id, day)
        return lo + int(floor(roll * float(1 + hi - lo)))

## A stable pseudo-random roll in [0, 1) for this card on the given day: the
## same card on the same day gets the same fuzz on every device, so a deck
## synced between two devices agrees on every interval it shares.
static func _card_day_roll(card_id: int, day: int) -> float:
        var rng := RandomNumberGenerator.new()
        rng.seed = hash([card_id, day])
        return rng.randf_range(0.0, 1.0)

## "10m", "3d", "1.2mo", "2.4y" -- the way Anki reads its intervals back.
static func humanize(seconds: int) -> String:
        var parts := humanize_parts(seconds)
        return str(parts[0]) % parts[1]


## The parts of a humanized wait -- the pattern and the number that fills
## it -- so a tongue other than English can say the same wait in its own
## words and its own digits (see i18n.wait). The pattern is the STRINGS
## key; the number is exactly what the pattern expects, int or float.
static func humanize_parts(seconds: int) -> Array:
        if seconds < MINUTE:
                return ["%ds", seconds]
        if seconds < HOUR:
                return ["%dm", int(round(float(seconds) / 60.0))]
        if seconds < DAY:
                var hours := float(seconds) / 3600.0
                if hours == floor(hours):
                        return ["%dh", int(hours)]
                return ["%.1fh", hours]
        var days := float(seconds) / float(DAY)
        if days < 30:
                if days == floor(days):
                        return ["%dd", int(days)]
                return ["%.1fd", days]
        var months := days / 30.0
        if months < 12:
                if months == floor(months):
                        return ["%dmo", int(months)]
                return ["%.1fmo", months]
        return ["%.1fy", days / 365.0]
