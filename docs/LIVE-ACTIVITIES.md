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

## 3.2.5 (26): phone feedback

The compact resident island now uses a 12-point icon and 40-point timer column (previously 60 points), with 12-point timer text and no hours field. The expanded island retains useful content space: one icon/title block on the left and countdown on the right, with no duplicate heading. Content columns clip within their allocated width and use additional horizontal safety padding.

Settings → 小组件 → 实时活动样式测试 uses the shared production card. It supports idle, upcoming, ongoing and ending states, course/task content and a long-title switch. “应用到锁屏与灵动岛” creates or updates one isolated test activity; “模拟开始，启动倒计时” switches upcoming content to a running timer. “结束测试” removes only test activities. The master activity switch and island content preference remain respected. Test payloads never enter the timetable, day-agenda document or course bridge, and foreground reconciliation preserves unexpired tests.

Validation for this follow-up uses the existing core checks and device build, without simulator startup or additional render matrices. Final UI acceptance takes place on the user's phone.

### 3.2.5 verified device delivery

Source `02b1172`: [Test → Build IPA](https://github.com/ddyec/YIClass-iOS/actions/runs/40330236891) succeeded after resolving Settings type-checking complexity and Swift 6 isolation of test activity handles. No simulator run or extra visual scenarios were added. Downloaded IPA verified as 3.2.5 (26), iPhoneOS only, with matching manifest/source commit and SHA-256.

[Download the 3.2.5 (26) phone IPA](https://github.com/ddyec/YIClass-iOS/actions/runs/40330236891/artifacts/12655087272). Re-sign before installation. Artifact container name still carries the prior workflow version; internal IPA version is verified. Final boundary/layout acceptance is on the user's phone using Settings → 小组件 → 实时活动样式测试.


## 3.2.6 (27): expanded regions and small-period progress

Based on the 3.2.5 follow-up in the user's other conversation. The actual expanded widget previously placed the entire card in `.bottom`; it now uses `.leading` for the icon/title, `.trailing` for the bounded whole-course timer and `.bottom` for time/location plus right-aligned progress. Compact/minimal widths remain 12/40 points.

Course payloads carry the real teaching periods from the configured TimeProfile, preserving custom durations and breaks. Each small period has an independent native `ProgressView(timerInterval:countsDown:)`, with its end labelled 休息, 换节 or 下课. Completed bars empty, future bars stay full and the current period drains without a local background timer or boundary-refresh dependency. Tasks use one bar for their actual scheduled work interval. More than four teaching periods use a compact segmented strip to bound the island height. Missing old metadata falls back to one overall bar without inventing a 45-minute lesson.

The phone style-test screen uses the same title/timer/details/progress components, adds a 课间 scenario and sends the period metadata into the real test activity. It is an in-app layout preview, not an emulation of the system camera cutout or a claimed device screenshot. New core tests cover custom 35/40-minute periods with a 7-minute break, window-to-payload propagation, invalid/overlapping periods, task fallback and old JSON. Final phone acceptance uses the existing Settings entry; no simulator or additional render matrix is introduced.


### 3.2.6 verified delivery

Source `3655264b88a6503f851cf95fc904614ed7645530`: [Test → Build IPA](https://github.com/ddyec/YIClass-iOS/actions/runs/40498920610) passed: 65 core tests, PDF/persistence integration, the existing production render suite and device archive. No simulator run or extra render matrix was added. The artifact name now reads its version/build from the packaged manifest, fixing the stale 3.2.3 download label without adding tests after packaging.

[Download 3.2.6 (27) device IPA](https://github.com/ddyec/YIClass-iOS/actions/runs/40498920610/artifacts/12732405213). Re-sign before installation. Use Settings → 小组件 → 实时活动样式测试 → 进行中／课间 → 应用到锁屏与灵动岛 for final phone acceptance. Existing timers/bars are system-managed; view rendering and archive success are not a substitute for physical Dynamic Island/camera layout review.


## 3.2.7 (28): small capsule boundary and very long course names

Phone feedback showed the upper icon/timer and lower location touching the deep corner arcs. Both activity types now set native horizontal contentMargins to 28 points for expanded mode only; no outer frame, vertical margins, minimum height, or compact/minimal size is increased. This follows Apple's concentric-content guidance and public DynamicIsland content-margin API.

The title is bounded to at most 120 points and two 14-point semibold lines with a tail ellipsis, preserving its full accessibility label. Its 14-point icon cannot be squeezed away. Location is one truncated line. More than two small periods use the existing compact segmented strip rather than adding rows and increasing height. In-app acceptance now shows a capsule, using the same horizontal inset and production title/details components instead of a mildly rounded rectangle.

No simulator or additional render matrix is introduced. Phone acceptance: enable the long-title switch, check courses and tasks, verify icon/title/timer/location/end labels remain clear of all four arcs, and verify the small expanded size remains acceptable. System camera/region layout still requires phone review; the in-app preview does not emulate the hardware cutout.
