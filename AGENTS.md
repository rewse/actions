# Repository rules

## Kiro CLI Installer

`dependabot-review` installs Kiro CLI with the official installer, `curl -fsSL https://cli.kiro.dev/install | bash`, although `~/git/AGENTS.md` forbids piping an installer into `sh`. The repository owner allowed this exception. The installer verifies the SHA256 of the archive it downloads.

## Validation

Before pushing, run `uvx pre-commit run --all-files` and `for t in tests/test_*.sh; do "$t" || exit 1; done`, and commit any files the hooks reformat. Stage new files first, because `--all-files` skips untracked files. CI runs the same hooks, and `core.hooksPath` points at git-defender, so `pre-commit install` cannot run them at commit time. Add each new test script as its own `run:` step in `.github/workflows/test.yml`, because CI lists the scripts one by one.

## Releases

Pushing a `vX.Y.Z` tag starts `release.yml`, which creates the GitHub Release with notes that git-cliff builds from the Conventional Commits since the previous tag, so a manual release is only `git tag vX.Y.Z && git push origin vX.Y.Z`. The ruleset `Protect release tags` restricts creating, updating, and deleting `v*` tags to the repository admin role and the release-only GitHub App, whose key lives in the `auto-tag` environment. Do not give that App's permissions to any other workflow.

`trufflehog-auto-tag.yml` tags the next patch release on its own after Dependabot updates `trufflehog/Dockerfile`, but only when every commit since the latest tag is by Dependabot and every changed path is `trufflehog/Dockerfile`, `.pre-commit-config.yaml`, or under `.github/`, `tests/`, or `docs/`. Any other change, or any commit by a person, waits for a manual release. `.github/scripts/next-auto-tag.sh` makes that decision and also requires the Dockerfile to stay a single `FROM ghcr.io/trufflesecurity/trufflehog:X.Y.Z@sha256:...` line, because git author names can be forged; keep its allowed paths limited to files that callers never run. The workflow runs the copy of the script in the latest release tag, so a change to the script takes effect only after a manual release.
