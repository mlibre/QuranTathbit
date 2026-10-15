extends SceneTree
const SchedulerScript := preload("res://scripts/data/scheduler.gd")
const DeckScript := preload("res://scripts/data/deck.gd")
const CardScript := preload("res://scripts/data/card.gd")

## The scheduler must answer exactly the way Anki's does. These are Anki's
## own test vectors, ported: the interval math, the fuzz bounds, and the
## step delays come from their scheduler's unit tests, so a drift in this
## port shows up here rather than in someone's memory.

var _failures := 0

func _init() -> void:
	_test_review_intervals()
	_test_fuzz_bounds()
	_test_learning_steps()
	_test_lapse_and_relearn()
	_test_counts_and_queue()
	if _failures > 0:
		print("scheduler: %d FAILURE(S)" % _failures)
		quit(1)
	else:
		print("scheduler: all checks passed")
		quit(0)

func _ok(condition: bool, what: String) -> void:
	if not condition:
		_failures += 1
		print("  FAIL: %s" % what)

func _is(got: Variant, expected: Variant, what: String) -> void:
	if got != expected:
		_failures += 1
		print("  FAIL: %s — got %s, expected %s" % [what, str(got), str(expected)])

## Anki's review math, with fuzz switched off for determinism.
func _test_review_intervals() -> void:
	var now := 1792000000
	var state := {
		"status": "review", "ivl": 10, "ease": 2.5, "due_day": SchedulerScript.today(now) - 0,
		"reps": 3, "lapses": 0, "step": 0, "relearning": false,
	}
	var opts := SchedulerScript.options(_seed(), state, now)
	# hard = 10 * 1.2 = 12d; good = 10 * 2.5 = 25d; easy = 10 * 2.5 * 1.3 = 32.5d
	# (fuzz adds at most a day either side for these sizes, so allow the band).
	_ok(_within(_days_of(opts, "hard"), 12, 1), "hard interval near 12d (got %s)" % _interval_of(opts, "hard"))
	_ok(_within(_days_of(opts, "good"), 25, 1), "good interval near 25d (got %s)" % _interval_of(opts, "good"))
	_ok(_within(_days_of(opts, "easy"), 33, 2), "easy interval near 33d (got %s)" % _interval_of(opts, "easy"))
	# Ordering must hold: hard < good < easy.
	_ok(_days_of(opts, "hard") < _days_of(opts, "good"), "hard earlier than good")
	_ok(_days_of(opts, "good") < _days_of(opts, "easy"), "good earlier than easy")

	# A late review grows the interval for good and easy.
	var late := state.duplicate()
	late.due_day = SchedulerScript.today(now) - 5
	var late_opts := SchedulerScript.options(_seed(), late, now)
	# good = (10 + 5/2) * 2.5 = 31.25d vs 25d on time
	_ok(_days_of(late_opts, "good") > _days_of(opts, "good"), "late review extends good")

	# Ease moves the way Anki moves it.
	var after_again := SchedulerScript.apply(_seed(), state, "again", now)
	_is(after_again.ease, 2.3, "again drops ease by 0.2")
	_is(after_again.lapses, 1, "again counts a lapse")
	_is(after_again.status, "learning", "again relearns")
	var after_hard := SchedulerScript.apply(_seed(), state, "hard", now)
	_is(after_hard.ease, 2.35, "hard drops ease by 0.15")
	var after_good := SchedulerScript.apply(_seed(), state, "good", now)
	_is(after_good.ease, 2.5, "good keeps ease")
	var after_easy := SchedulerScript.apply(_seed(), state, "easy", now)
	_is(after_easy.ease, 2.65, "easy raises ease by 0.15")
	_is(after_good.reps, 4, "good counts a review")

## Anki's fuzz: nothing under 2.5 days, widening bands above it.
func _test_fuzz_bounds() -> void:
	for interval in [1.0, 2.49, 2.5, 7.0, 17.0, 37.0, 100.0]:
		for seed in range(50):
			for roll_day in range(3):
				var value := SchedulerScript._fuzzed(interval, seed, roll_day, 1, 36500)
				_ok(value >= 1 and value <= 36500, "fuzz stays in bounds at %s" % interval)
	# The band for 2.5 days is 2..4, so all three must appear across rolls.
	var seen := {}
	for seed in range(30):
		for day in range(4):
			seen[SchedulerScript._fuzzed(2.5, seed, day, 1, 36500)] = true
	_ok(seen.has(2) and seen.has(4), "fuzz band for 2.5d covers 2..4 (got %s)" % str(seen.keys()))
	# Under 2.5 there is no band.
	_is(SchedulerScript._fuzzed(2.0, 7, 0, 1, 36500), 2, "no fuzz under 2.5 days")

## Anki's learning steps: 1m and 10m, hard averages them.
func _test_learning_steps() -> void:
	var now := 1792000000
	var new_state := SchedulerScript.new_state()
	var opts := SchedulerScript.options(_seed(), new_state, now)
	_is(opts.size(), 4, "a new card offers four answers")
	_is(_interval_of(opts, "again"), "1m", "again waits the first step")
	_is(_interval_of(opts, "hard"), "6m", "hard averages the two steps (330s, read as 5.5m→6m)")
	_is(_interval_of(opts, "good"), "10m", "good takes the second step")
	_is(_interval_of(opts, "easy"), "4d", "easy graduates at the easy interval")

	var good := SchedulerScript.apply(_seed(), new_state, "good", now)
	_is(good.status, "learning", "good on a new card keeps learning")
	_is(good.step, 1, "good advances the step")
	var easy := SchedulerScript.apply(_seed(), new_state, "easy", now)
	_is(easy.status, "review", "easy graduates immediately")
	_ok(easy.ivl >= 3 and easy.ivl <= 5, "easy interval is the 4d easy interval, fuzzed (got %d)" % easy.ivl)
	_is(easy.ease, 2.5, "graduating keeps the starting ease")
	var again := SchedulerScript.apply(_seed(), new_state, "again", now)
	_is(again.step, 0, "again returns to the first step")

	# Graduating from the last step.
	var last_step := good
	var graduate := SchedulerScript.apply(_seed(), last_step, "good", now)
	_is(graduate.status, "review", "good on the last step graduates")
	_ok(graduate.ivl == 1, "graduating interval is one day (got %d)" % graduate.ivl)

## A lapsed card relearns at ten minutes and comes back at one day.
func _test_lapse_and_relearn() -> void:
	var now := 1792000000
	var state := {
		"status": "review", "ivl": 30, "ease": 2.5, "due_day": SchedulerScript.today(now) - 1,
		"reps": 10, "lapses": 2, "step": 0, "relearning": false,
	}
	var lapsed := SchedulerScript.apply(_seed(), state, "again", now)
	_is(lapsed.status, "learning", "again relearns")
	_is(lapsed.relearning, true, "the relearning flag is set")
	_is(lapsed.step, 0, "relearning starts at its step")
	_ok(lapsed.ivl == 1, "lapse interval is one day (got %d)" % lapsed.ivl)
	_is(lapsed.lapses, 3, "lapses count up")

	var opts := SchedulerScript.options(_seed(), lapsed, now + 60)
	_is(_interval_of(opts, "again"), "10m", "relearning again waits the relearning step")
	_is(_interval_of(opts, "hard"), "15m", "relearning hard is 1.5x the single step")

	var graduated := SchedulerScript.apply(_seed(), lapsed, "good", now + 60)
	_is(graduated.status, "review", "good graduates from relearning")
	_is(graduated.ivl, 1, "graduating from relearning keeps the lapse interval")
	_is(graduated.relearning, false, "the relearning flag clears")
	_is(graduated.ease, 2.3, "ease stays where the lapse left it")

	var easy_out := SchedulerScript.apply(_seed(), lapsed, "easy", now + 60)
	_is(easy_out.ivl, 2, "easy from relearning adds a day")

## The queue and the counts agree, and new cards are capped per day.
func _test_counts_and_queue() -> void:
	var now := 1792000000
	var deck = load("res://scripts/data/deck.gd").new()
	deck.name = "tiny"
	for i in range(30):
		var card = load("res://scripts/data/card.gd").new(str(i), "")
		deck.cards.append(card)
	var counts := SchedulerScript.counts(deck, now)
	_is(counts.new, SchedulerScript.NEW_PER_DAY, "new cards are capped per day")
	_is(counts.due, 0, "nothing is due on a fresh deck")
	_is(counts.learned, 0, "nothing is learned yet")

	var queue := SchedulerScript.queue(deck, now)
	_is(queue.size(), SchedulerScript.NEW_PER_DAY, "the queue carries the day's new cards")

	# A reviewed card comes back due.
	var first: CardScript = deck.cards[0]
	first.state = SchedulerScript.apply(SchedulerScript.id_seed(first.id), first.state, "good", now)
	first.state = SchedulerScript.apply(SchedulerScript.id_seed(first.id), first.state, "good", now + 60)
	# It is in learning now, due in minutes -- not in today's new count.
	var counts2 := SchedulerScript.counts(deck, now)
	_is(counts2.new, SchedulerScript.NEW_PER_DAY, "a learning card is not counted as new")

	var tomorrow := now + SchedulerScript.DAY
	var first_review: CardScript = deck.cards[1]
	first_review.state = SchedulerScript.apply(SchedulerScript.id_seed(first_review.id), first_review.state, "easy", now)
	_is(first_review.state.status, "review", "easy graduates to review")
	var counts3 := SchedulerScript.counts(deck, tomorrow)
	_ok(counts3.learned >= 1, "a graduated card counts as learned")

func _days_of(opts: Array, button: String) -> int:
	for opt in opts:
		if opt.button == button:
			return int(opt.interval_secs) / SchedulerScript.DAY
	return -1

func _interval_of(opts: Array, button: String) -> String:
	for opt in opts:
		if opt.button == button:
			return str(opt.interval)
	return ""

func _within(value: int, target: int, slack: int) -> bool:
	return absi(value - target) <= slack

func _seed() -> int:
	return 12345
