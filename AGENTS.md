# Repository instructions

## Sources of truth

- Active delivery work lives in `docs/task-specs/`.
- Implemented behavior is documented in `docs/system-specs/`.
- Task specs describe proposed work and must not be presented as current behavior.
- Source code remains authoritative when implemented behavior and a system spec disagree; update the affected system spec as part of the change.

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

- Work on the currently checked-out branch.
- Do not create or switch branches unless the user explicitly requests it.
- Do not open pull requests unless the user explicitly requests one.
- When asked to commit and push, commit directly to the current branch.
- If the current branch is protected or cannot be pushed, stop and report the blocker.
- Before editing, verify that the local branch is synchronized with its remote.
- After a pull request is merged, switch to `main` and update it with `git pull --ff-only`.
- Never force-push `main`.

## Deployment approval

- Do not deploy or publish changes until the user explicitly approves the specific deployment.
- Approval to design, implement, test, commit, or push is not deployment approval.
- Deployment includes publishing a GitHub release, uploading distributable artifacts, notarizing for distribution, changing production hosting, or running any release/deployment command against an external service.
