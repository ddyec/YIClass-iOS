# Project working preferences

- Build and deliver only iPhone/iPad device IPA packages. The user has no simulator and explicitly does not want simulator packages.
- Do not run `scripts/package-build.sh simulator`, generate or upload simulator distribution artifacts, or trigger simulator-only review workflows unless the user explicitly asks for them.
- Keep automatic downloadable builds device-only. Normal core tests and compile checks can still run where appropriate.
