# Contributing to BeTracky Background Location Service

Thank you for your interest in contributing! This document explains how to get set up, what the branch and PR workflow looks like, and what we expect from contributions.

## How contributions work

- The `master` branch is protected — no one pushes to it directly.
- To contribute, **fork the repo**, make your changes on a branch, and open a pull request.
- Only the maintainer (@DineshWayaman) reviews and merges PRs.

## Getting started

```bash
# 1. Fork the repo on GitHub, then clone your fork
git clone https://github.com/<your-username>/BeTracky-Background-Location-Service.git
cd BeTracky-Background-Location-Service

# 2. Install dependencies
flutter pub get

# 3. Run the tests to make sure everything is working
flutter test

# 4. Lint
dart analyze lib/ test/
```

## Branch naming

| Type | Pattern | Example |
|------|---------|---------|
| New feature | `feature/<short-description>` | `feature/trip-detection` |
| Bug fix | `fix/<short-description>` | `fix/offline-store-without-url` |
| Docs only | `docs/<short-description>` | `docs/improve-geofence-example` |
| Refactor | `refactor/<short-description>` | `refactor/database-helper` |

## Before opening a PR

- [ ] `flutter test` passes with no failures
- [ ] `dart analyze lib/ test/` reports no issues
- [ ] If you added a new feature or fixed a bug, add an entry to `CHANGELOG.md` under a new `## Unreleased` section at the top
- [ ] If the public API changed, update `README.md`
- [ ] Keep PRs focused — one feature or fix per PR

## Commit messages

Use plain, lowercase present-tense summaries:

```
fix: offline mode now stores locations when no url is set
feat: add trip detection auto-start/stop
docs: add geofencing example to README
```

## Reporting bugs

Use the **Bug Report** issue template. Include your Flutter version (`flutter --version`), the platform (Android/iOS), and the package version.

## Requesting features

Use the **Feature Request** issue template. Explain the problem you are trying to solve, not just the solution you have in mind.

## Code style

- Follow standard Dart/Flutter conventions (enforced by `flutter_lints`)
- No `print()` in library code — use `debugPrint()` if logging is genuinely needed
- No new public APIs without a doc comment

## Questions

Open a GitHub Discussion or an issue — we are happy to help.
