# Project working preferences

- Build and deliver only iPhone/iPad device IPA packages. The user has no simulator and explicitly does not want simulator packages.
- Do not run `scripts/package-build.sh simulator`, generate or upload simulator distribution artifacts, or trigger simulator-only review workflows unless the user explicitly asks for them.
- Keep automatic downloadable builds device-only. Normal core tests and compile checks can still run where appropriate.
- Use the current folded-book product logo throughout the app. Do not reintroduce the old YC mark. Replace legacy YC branding with the normal current book logo including its original background. Use the transparent line-art logo only inside the AI drawer page; never substitute it for the global product logo or app icon.
- Main navigation has three destinations (schedule, todos, settings) plus a separate AI button opening a conversation drawer. The empty assistant shows only the logo and “我们应该安排什么？”, with close at top left and history at top right.
- Todo header shows title on the left and current date on the right, without a separate date browsing control. Use urgency-colored task backgrounds with text status labels.
