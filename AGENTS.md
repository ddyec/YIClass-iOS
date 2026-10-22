# Project working preferences

- Build and deliver only iPhone/iPad device IPA packages. The user has no simulator and explicitly does not want simulator packages.
- Do not run `scripts/package-build.sh simulator`, generate or upload simulator distribution artifacts, or trigger simulator-only review workflows unless the user explicitly asks for them.
- Keep automatic downloadable builds device-only. Normal core tests and compile checks can still run where appropriate.
- Use the current folded-book product logo for product branding and the app icon. Do not reintroduce the old YC mark. Replace legacy YC branding with the normal current book logo including its original background. Use the existing transparent AssistantLogo for AI-related entry points, including the floating AI button and the AI drawer page, with black strokes in light mode and white strokes in dark mode (follow the effective app color scheme, not the accent color).
- Keep the main navigation floating over scrollable content. Keep the evening expand/collapse control visible above the floating navigation, and give the timetable enough bottom scroll space to reveal its last period. Measure the navigation height rather than assuming a fixed size.
- Main navigation has three destinations (schedule, todos, settings) plus a separate AI button opening a conversation drawer. The empty assistant shows only the logo and “我们应该安排什么？”, with close at top left and history at top right.
- Todo header shows title on the left and current date on the right, without a separate date browsing control. Use urgency-colored task backgrounds with text status labels.
