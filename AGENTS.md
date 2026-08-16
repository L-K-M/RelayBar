# Repository instructions

## Sources of truth

- Active delivery work lives in `docs/task-specs/`.
- Implemented behavior is documented in `docs/system-specs/`.
- Task specs describe proposed work and must not be presented as current behavior.
- Source code remains authoritative when implemented behavior and a system spec disagree; update the affected system spec as part of the change.

## Toolchain and commands

- Requirements: macOS 13 or newer, Xcode (CI pins 16.4), and — for packaged builds — a Developer ID Application certificate.
- `swift test` runs the package tests. The SwiftPM manifest deliberately omits Sparkle so unit tests can never initialize an updater or touch the network; CI runs `swift test -Xswiftc -warnings-as-errors` plus an unsigned `xcodebuild` Release build.
- `./scripts/build.sh` is the family entry point: a thin stub over the shared build engine from <https://github.com/L-K-M/release-tool> (`--clean/--debug/--run/--install/--zip/--dmg`), delegating to `./scripts/build-app.sh`, which owns the build and the inside-out Developer ID signing of Sparkle's nested components.
- `./scripts/release.sh X.Y.Z [--push]` cuts a release (same shared engine): bumps `MARKETING_VERSION`, the Sparkle build number (`scripts/bump-build-number.sh`), and the README version marker in one commit, then tags `vX.Y.Z`; `--push` triggers `.github/workflows/release.yml` (test → build → notarize → publish). The tag must match the committed version.
- Release machinery beyond that — `package-release.sh`, `notarize-release.sh`, `update-appcast.sh`, `verify-update-feed.sh`, `stage-private-update.sh`, `verify-private-update-feed.sh`, `prune-renderer-resources.sh`, `check-task-spec-registry.sh` — is documented in `docs/system-specs/operations/build-and-release.md`, the authoritative runbook.

## Task-spec writing

- Keep task specs concise and non-redundant.
- Use `Outcome` for the result, `Delivery Boundary` for scope, `Work` for required changes, and `Acceptance` for observable completion checks.
- Put active task specs directly in `docs/task-specs/` and move accepted specs to `docs/task-specs/archive/`.
- Number tasks with three digits (`001`, `002`, and so on).
- Omit empty, speculative, or repetitive sections.

## Task-spec completion

Before marking a task `Complete`:

1. verify every acceptance criterion against current evidence;
2. update the relevant files under `docs/system-specs/` to describe the implemented behavior;
3. run the checks relevant to the change and `git diff --check`;
4. record any required manual, visual, security, or live-SSH evidence;
5. move the accepted spec to `docs/task-specs/archive/`.

Do not commit or push merely because a task is complete; follow the Git workflow below.

## Git workflow

- Do implementation work on a feature branch, not directly on `main`.
- Create or switch to a feature branch before editing. Codex-created branches use the `codex/` prefix unless the user requests another name.
- Do not open pull requests unless the user explicitly requests one.
- When asked to commit and push, commit directly to the current feature branch.
- If the current branch is protected or cannot be pushed, stop and report the blocker.
- Before editing, fetch remotes. If the current branch has an upstream, verify that it is synchronized; if it is new, record its base and any divergence from that base's remote.
- After a pull request is merged, switch to `main` and update it with `git pull --ff-only`.
- Never commit directly to or force-push `main`.
- Never add agent self-attribution to commits, pull requests, or code comments. No `Co-Authored-By` trailers naming an agent, no "Generated with" or "Created by" lines, and no tool or model names in commit messages or PR bodies.

## Deployment approval

- Do not deploy or publish changes until the user explicitly approves the specific deployment.
- Approval to design, implement, test, commit, or push is not deployment approval.
- Deployment includes publishing a GitHub release, uploading distributable artifacts, notarizing for distribution, changing production hosting, or running any release/deployment command against an external service.
