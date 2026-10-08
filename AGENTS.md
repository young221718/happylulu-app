# HappyLulu Agent Guide

## Scope

HappyLulu is a native Swift macOS menu bar utility. Source, tests, packaging,
and Korean user documentation belong to this repository.

## Working rules

- Read the current Git status and checkout identity before editing. Preserve
  unrelated changes and user attendance data.
- When used inside Hive, `develop/` is the baseline directory on `main`.
  New manually managed feature checkouts use direct sibling `<task>/` directories
  and `codex/` branches; preserve existing checkout and branch names. Compare
  their common Git directory before reuse.
- Use the smallest useful workflow. Material behavior changes require an
  independent review after relevant checks; simple docs need no extra agents.
- Keep attendance on the local Mac. Do not add network collection or accounts
  without an explicit feature request.
- Preserve the existing `AfterSix` storage path and bundle identifier unless
  a migration is deliberately implemented and verified.
- Do not count wake or session activation as an unlock event. Do not fabricate
  historical attendance when the app was not running.
- Never lock, log out, or reboot the user's Mac to run validation without
  explicit authorization.
- Keep `.build/`, `dist/`, app bundles, credentials, and personal state out of
  Git. `Resources/HappyLuluIcon.png` is the reviewed application source asset.
- Require an explicit user request for this repository and publication action
  before pushing, creating or updating a PR, releasing, or deploying. A request
  for local changes or successful checks alone does not authorize publication.
- User documentation and reports are normally Korean; keep this guide English.

## Checks

```sh
swift run --build-system native AfterSixChecks
bash scripts/build-app.sh
bash -n scripts/build-app.sh
plutil -lint Resources/Info.plist
git diff --check
```

Use the existing macOS Command Line Tools; do not install dependencies merely
to run checks. Unit checks, build/signature validation, actual unlock detection,
and login-after-reboot behavior are separate evidence. Record their limits.

## Safe personal maintenance

- Keep attention on the requested repository and demonstrated defects. Use small,
  testable changes; preserve the operator's data and unfinished work.
- Reproduce a defect with a failing check before fixing it. Run relevant regression
  checks and obtain independent review for behavior changes before claiming done.
- Inspect branch ancestry, dirty/ignored files, and active work before integration.
  Preserve unique commits and unfinished checkouts. Clean up only confirmed merged,
  clean, inactive task branches within explicit cleanup authorization.
- Report executed checks, review findings, commit/merge evidence, and remaining
  blockers. Completion requires verified results. Deployment needs its own request.
