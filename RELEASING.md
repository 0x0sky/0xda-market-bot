# Releasing 0xda Market Bot

The project uses Semantic Versioning. Stable tags have the form `vMAJOR.MINOR.PATCH`;
for example, release `0.1.0` is tagged `v0.1.0` rather than `release_0.1`.

## Release flow

1. Update `VERSION`, move curated entries from `Unreleased` in `CHANGELOG.md`,
   and add `docs/releases/vX.Y.Z.md` on `master`.
2. Require green tests and verify the `master` deployment with the test core
   and test Telegram bot.
3. Promote and verify the matching 0xda Market core version first, including
   its migrations and production health check.
4. Promote this repository with a pull request from `master` to `release`.
   Wait for release-branch CI and the Render production deployment, then verify
   `/start`, `/buy`, `/apply_prices` and one controlled price update.
5. Run **Prepare GitHub release** with `vX.Y.Z`. The workflow retests the exact
   `release` HEAD, builds the image, creates an annotated tag and saves a draft
   GitHub Release.
6. Review the draft and publish it after the matching core release is public.

Tags are immutable release coordinates: never move or reuse a published tag.
GitHub's immutable-releases setting should be enabled after the draft workflow
has been validated for both repositories.

## Rollback

Prefer a revert pull request or forward fix on `release`; do not force-push the
production branch. Keep the core and bot compatibility pair together. If only
the bot is reverted, verify `/buy`, `/apply_prices` and `premium_12m` against the
currently deployed core before restoring Telegram traffic.
