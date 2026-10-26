# Adaptive Live Activities (3.2.4 / 25)

Based on `fix/glass-rest-scroll-todos`, preserving the day agenda and native navigation work.

- One-item lock-screen cards separate title and countdown into bounded columns. Titles truncate at two lines; two-course cards use equal columns with no competing countdown. No forced minimum height, progress bar, outline, or action row.
- Compact presentations show one title, work time and course location. Expanded Dynamic Island uses system leading/trailing regions for type and timer, with details below. Compact/minimal islands use SF Symbols instead of clipped title fragments.
- Courses use a cyan book; scheduled tasks use a mint checklist. With a foreground refresh during the final five minutes, the card icon becomes orange. The label/time remains readable without relying on color.
- Scheduled tasks are read from canonical `DayAgendaDocument` placements. Deadlines do not create work sessions. Completed, deleted, unscheduled and expired tasks are removed on reconciliation. At most two task requests are retained, prioritizing active tasks, within a rolling 24-hour planning horizon.
- The master switch ends both activity types. The task switch and island visibility switch are independent. Course bridge records remain course-only so tasks never suppress timetable widgets.
- System timer text continues counting while the app is backgrounded. New data, completion, warning color and later course selection reconcile while the app is active. End dates mark stale content, which is hidden; this does not claim to terminate the ActivityKit shell or advance activities in the background. Scheduled starts are best effort and depend on system authorization/budget. Placements over eight hours display only during their final eight-hour window.

## Validation

Portable project validation checks new source membership and deterministic project generation. Core tests cover exact phase boundaries, deadline-only tasks, completion, expiration, overlapping requests, stable payload encoding, rescheduling and the eight-hour lifetime limit.

The existing Test -> Build IPA pipeline compiles the device app after all tests and production SwiftUI rendering pass. Production `AgendaActivityCard` renders cover widths 320/375/408, long titles/locations, single/two-course cards, active/upcoming tasks and a 160 x 62 compact card. Accessibility environment render variants are included. These are macOS SwiftUI ImageRenderer images, not iOS device screenshots.

On-device review: check lock screen and all island presentations; rename/reschedule/complete an active task; toggle tasks/master/island; background across a scheduled start and end; try large system text and a 12-hour time locale. Verify no text crosses the card edge and expired names disappear. No simulator package is produced.

## Verified delivery

Commit `863ba46`: [Test → Build IPA](https://github.com/ddyec/YIClass-iOS/actions/runs/40322434883) passed, including 62 core tests, PDF/persistence integration, production SwiftUI renders and the device archive. Inspected 320-point standard/accessibility and 62-point constrained-height renders. The downloaded IPA reports 3.2.4 (25), iPhoneOS only; manifest and SHA-256 match.

[Download 3.2.4 (25) device IPA](https://github.com/ddyec/YIClass-iOS/actions/runs/40322434883/artifacts/12649942338). Re-sign before installation. The artifact container retains the previous workflow's 3.2.3 label because the available OAuth credential cannot change workflow files; the verified IPA internal version is 3.2.4 (25). [Production render images](https://github.com/ddyec/YIClass-iOS/actions/runs/40322434883/artifacts/12650445363). These are layout evidence, not iOS device screenshots.
