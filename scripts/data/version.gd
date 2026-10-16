class_name AppVersion
extends RefCounted

## One place that knows the app's version. The number is read at runtime
## (Settings → About shows it; the About line in Settings carries it) so a
## user never has to wonder which build is in front of them. Bump this in
## lockstep with export_presets.cfg (product_version, version/name) and the
## package.json that publishes the web build to npm.

const VERSION := "1.0.22"
