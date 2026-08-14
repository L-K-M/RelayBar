# Task 035 - Add GLM 5.3 PR Review

**Status:** Complete

## Outcome

RelayBar pull requests can receive automatic GLM 5.3 code-review feedback
without exposing repository secrets to fork pull requests or executing
untrusted pull-request code.

## Delivery Boundary

Add repository automation and its operational documentation. Configuring the
repository's `ZAI_API_KEY` secret and running the workflow on GitHub remain
repository-administration and live-verification steps.

## Work

- Trigger reviews for non-draft same-repository pull requests.
- Pin the review action to an immutable commit and select `glm-5.3` explicitly.
- Grant only the read and review-comment permissions required by the action.
- Cancel superseded reviews and skip cleanly when the API key is unavailable.
- Document the workflow's security and trigger boundaries.

## Acceptance

- The workflow parses as YAML and selects `glm-5.3`.
- Fork and draft pull requests cannot run the privileged review job.
- The workflow neither checks out nor executes pull-request code.
- The action reference is an immutable commit SHA.
- `git diff --check` passes.

## Evidence

- Local YAML parsing and static workflow assertions passed on 2026-08-14.
- `git diff --check` passed on 2026-08-14.
- A live review requires `ZAI_API_KEY` and a GitHub pull-request event.
