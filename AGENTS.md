# Repository rules

## Kiro CLI Installer

`dependabot-review` installs Kiro CLI with the official installer, `curl -fsSL https://cli.kiro.dev/install | bash`, although `~/git/AGENTS.md` forbids piping an installer into `sh`. The repository owner allowed this exception. The installer verifies the SHA256 of the archive it downloads.

## Validation

Before pushing, run `uvx pre-commit run --all-files` and `for t in tests/test_*.sh; do "$t" || exit 1; done`, and commit any files the hooks reformat. Stage new files first, because `--all-files` skips untracked files. CI runs the same hooks, and `core.hooksPath` points at git-defender, so `pre-commit install` cannot run them at commit time. Add each new test script as its own `run:` step in `.github/workflows/test.yml`, because CI lists the scripts one by one.
