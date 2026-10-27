# Host-key recovery verification

Verified locally on 2026-10-27.

- Before the fix, both address-edit and changed-key integration regressions
  failed because the profile entered the retry ladder instead of failing.
- The fixed address-edit test verifies the new SSH target, immediate failure,
  no retry deadline or network-change restart, and explicit restart recovery.
- Changed-key coverage retains the diagnostic after a verbose stderr preamble
  and cancels a pending browser launch.
- An inherited-stderr regression reproduced a three-second UI stall before
  nonblocking capture and passes with the corrected reader.
- Real `/usr/bin/ssh -G` evaluates the copied shell command offline against
  conflicting SSH configuration. It verifies interactive strict checking,
  connection arguments and shell escaping, with no forwards, remote shell,
  control reuse, or local command execution.
- The full Swift suite passed with warnings treated as errors: 452 tests,
  17 opt-in tests skipped. After the final UI and queued-stderr changes,
  62 relevant tests passed, including the new snapshot test; two live SSH
  tests were skipped.
- The unsigned Xcode Release build, task-spec registry, and `git diff --check`
  passed.
- Four rendered list snapshots were visually inspected in light and dark
  appearances at 380 × 440 and 480 × 720 points. The recovery button remains
  visible and reachable without horizontal overflow.

Live fingerprint verification against the reported server and interaction
with the recovery alert remain manual checks. Stop retries, choose
**Verify SSH Host Key…**, copy the verification command, and run it in
Terminal. Verify the fingerprint independently before accepting a new key
or updating the indicated saved entry. Press Control-C and explicitly start
the profile again.
