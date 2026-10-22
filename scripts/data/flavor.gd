class_name BuildFlavor
extends RefCounted

## The clothes an export ships in. The standard build asks its reader which
## tongue its own words speak; a flavoured build is born already speaking
## one -- the Persian APK carries the `persian` feature tag from its export
## preset, and from its first frame the question is already answered: no
## picker on the first run, no language in Settings, the whole chrome --
## boot, loading phases, every page -- in the tongue the build was named
## for. The flavour is read once at the moments that care (the boot's pin,
## the deck's adoption, Settings' tongue row); everything else answers to
## the language the pin already set, the way any reader's choice would.

const PERSIAN := "persian"

## The test door: a headless suite cannot wear an export feature, so the
## suite says the flavour here instead. The word lasts one process -- each
## suite is its own engine run, so nothing leaks between them.
static var _test_flavor := ""


## Does this build carry the Persian feature tag?
static func persian_build() -> bool:
        return _test_flavor == PERSIAN or OS.has_feature(PERSIAN)


## Speak a flavour for the rest of this process -- the suites' door only.
static func force_test(flavor: String) -> void:
        _test_flavor = flavor
