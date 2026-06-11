# Stage 1b placeholder

`mob_notify_nif.m` lands here in Stage 1b — extracted from mob
`ios/mob_nif.m:3238-3319` (nif_notify_schedule / nif_notify_cancel /
nif_notify_register_push), with the delegate setup replaced by a call to core's
(new) `mob_notify_set_screen_pid` export. See ../../../EXTRACTION.md.
