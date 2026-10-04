# Exceptions

## Kiro CLI Installer

`dependabot-review` installs Kiro CLI with the official installer, `curl -fsSL https://cli.kiro.dev/install | bash`, although `~/git/AGENTS.md` forbids piping an installer into `sh`. The repository owner allowed this exception. The installer verifies the SHA256 of the archive it downloads.
