# Repository rename transition: Phoenix Launch Silo to Warp Drive

## Objective

Rename the canonical GitHub repository from
`magtools/phoenix-launch-silo` to `magtools/warp-drive` without interrupting
existing Warp installations or their `warp update` and automatic version-check
flows.

## Implemented compatibility change

`warp.sh` now resolves update artifacts in this order:

1. `https://raw.githubusercontent.com/magtools/warp-drive/refs/heads/master/dist`
2. `https://raw.githubusercontent.com/magtools/phoenix-launch-silo/refs/heads/master/dist`

The first source that returns a non-empty `version.md` becomes the source for the
whole operation. `sha256sum.md` and `warp` are downloaded from that same source,
then the existing SHA-256 validation runs before `./warp` is replaced. This avoids
mixing a version, checksum, and binary published from different repositories.

The fallback applies to both `warp update` and the seven-day automatic version
check. It also treats a 404 from the future repository as an expected reason to
try the legacy source, making it safe to publish this change before the GitHub
rename occurs.

`warp update self` and `warp update --self` are unchanged: they only apply the
payload embedded in the local `./warp` and never use either remote source.

## Rollout

1. Release a `dist/warp` containing this compatibility change while the current
   repository remains `phoenix-launch-silo`.
2. Keep publishing the three `dist` artifacts there for one or two months. New
   binaries will transparently fall back after the primary URL returns 404.
3. Rename the GitHub repository to `warp-drive`.
4. Publish a release from the renamed repository and verify both the automatic
   check and `warp update` resolve the primary source.

## Pending work after the GitHub rename

- Change canonical repository links in `README.md`, `mkdocs.yml`, `wiki_docs/`,
  `release/landing/`, `features/`, `LICENSE`, and `AGENTS.md` to
  `magtools/warp-drive`.
- Regenerate `docs/` from `wiki_docs/`; do not hand-edit generated documentation.
- Confirm installation commands download `dist/warp` from the new raw URL.
- Test update compatibility with a pre-transition `warp` binary, the transition
  binary, and a newly published binary.
- Decide a retirement date for the legacy fallback. Keeping it for at least
  6–12 months is recommended; it is intentionally safe to retain longer.
