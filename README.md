# actions

GitHub Actions shared by the [rewse](https://github.com/rewse) repositories.

## dependabot-review

Rates the risk of a Dependabot PR with [Kiro CLI](https://kiro.dev/docs/cli/headless) in headless mode and rebase-merges the PR when every condition holds:

- Every updated dependency is a patch or minor update, or a Docker image whose tag stays the same and whose digest changes, which the diff must confirm. A major update or an unknown update type anywhere in a grouped PR rates the whole PR high without asking Kiro.
- Kiro rates the risk low after reading the changelog, the diff, and how the repository uses the dependency.
- Every check outside the calling workflow passes within 30 minutes.

Each run posts its rating as a new PR comment, which it updates with the merge outcome, so the PR keeps the history of earlier ratings. The action also labels the PR `risk:low`, `risk:medium`, or `risk:high`. Kiro runs on its V3 engine with an agent whose only tools read and search files, and receives no credential besides its API key, because the PR body and diff come from upstream. The agent's permission rules let those tools read only a copy of the checkout without `.git` and `.kiro`, which is Kiro's working directory, and the PR body, diff, and metadata, and Kiro gets a `KIRO_HOME` of its own, so no other agent, hook, or MCP server loads. Kiro's verdict counts only when it carries the random nonce that the run puts in the prompt, so a verdict planted in the PR text does not. The action also discards a verdict whose text holds the API key, even split up or encoded in base64 or hex, or anything shaped like a GitHub token or a PEM block, and caps the length of what it posts. The merge uses a GitHub App token so that the push to the default branch starts its workflows, which a merge with `GITHUB_TOKEN` would not. When GitHub refuses the merge because the base branch moved, as it does when several Dependabot PRs in one repository merge at the same moment, the action tries again up to three more times, 15 seconds apart.

```yaml
name: Dependabot Review

on:
  pull_request:
    types: [opened, synchronize, reopened]

permissions:
  contents: read

concurrency:
  group: dependabot-review-${{ github.event.pull_request.number }}
  cancel-in-progress: true

jobs:
  review:
    name: Review
    if: github.event.pull_request.user.login == 'dependabot[bot]'
    runs-on: ubuntu-latest
    timeout-minutes: 50
    permissions:
      actions: read
      checks: read
      contents: read
      issues: write
      pull-requests: write
      statuses: read
    steps:
      - name: Review the Dependabot PR
        uses: rewse/actions/dependabot-review@<commit SHA>  # vX.Y.Z
        with:
          app-client-id: ${{ secrets.DEPENDABOT_APP_CLIENT_ID }}
          app-private-key: ${{ secrets.DEPENDABOT_APP_PRIVATE_KEY }}
          kiro-api-key: ${{ secrets.KIRO_API_KEY }}
```

| Input | Default | Description |
|---|---|---|
| `app-client-id` | | Client ID of the GitHub App that merges the PR |
| `app-private-key` | | Private key of the GitHub App that merges the PR |
| `dry-run` | `false` | When `true`, rate and comment but never merge; any value other than `true` or `false` fails the run |
| `kiro-api-key` | | Kiro API key for headless mode |
| `kiro-model` | | Model for Kiro to use; empty uses the Kiro default |

| Output | Description |
|---|---|
| `outcome` | What happened to the PR, as written in the comment |
| `risk` | The risk rating: `low`, `medium`, or `high`, or `skipped` when someone other than Dependabot started the run |

Workflows started by Dependabot read only Dependabot secrets, so register `DEPENDABOT_APP_CLIENT_ID`, `DEPENDABOT_APP_PRIVATE_KEY`, and `KIRO_API_KEY` under Settings → Secrets and variables → Dependabot in each repository. The App needs Contents: Read and write, Pull requests: Read and write, and Metadata: Read-only, and must be installed on the repository. Kiro API keys require a Kiro Pro, Pro+, or Power subscription.

The action rates and merges only when Dependabot opened the PR and started the run, whatever the caller's job condition says. A push by anyone else to a Dependabot PR, or a PR that someone else opened, makes the action skip Kiro, remove the risk labels, post `Risk: skipped`, and leave the PR for manual review without failing. An empty key in a run that Dependabot started is a misconfiguration and fails the job.

The App private key and the Kiro API key have no expiry. Rotate them when someone who could read them leaves or when a leak is suspected: generate a new App private key and delete the old one in the App settings, issue a new Kiro API key and revoke the old one, then update the Dependabot secrets in every repository.

## setup-safe-chain

Installs [Aikido Safe Chain](https://github.com/AikidoSec/safe-chain) from the newest release that is published, stable, immutable, and at least `cooldown-hours` old. The installer comes from that release's assets, so the binary is checked against the SHA256 embedded in it, and a new Safe Chain release is picked up on its own once the cooldown passes.

```yaml
- name: Setup Aikido Safe Chain
  uses: rewse/actions/setup-safe-chain@<commit SHA>  # vX.Y.Z
```

| Input | Default | Description |
|---|---|---|
| `cooldown-hours` | `96` | Minimum age in hours of the release to install |

| Output | Description |
|---|---|
| `version` | The installed Safe Chain version |

The step fails when no release meets the conditions or when the GitHub API cannot be reached.

## trufflehog

Scans the whole history of `main` for secrets with the [TruffleHog](https://github.com/trufflesecurity/trufflehog) image pinned by tag and digest in `trufflehog/Dockerfile`. Dependabot updates the tag and the digest together, and an image update with nothing else to release is tagged as a patch release automatically, so callers follow new TruffleHog releases through their own Dependabot updates of this action. The action runs `trufflehog git` with `--branch main --fail --fail-on-scan-errors --no-update --github-actions` and fails when it finds a secret or cannot scan. Check out the full history with a local `main` branch first, which a scheduled or manual run on `main` has.

```yaml
- uses: actions/checkout@<commit SHA>  # vX.Y.Z
  with:
    fetch-depth: 0
    persist-credentials: false

- uses: rewse/actions/trufflehog@<commit SHA>  # vX.Y.Z
  with:
    extra-args: --exclude-detectors=lob --results=verified,unknown
```

| Input | Default | Description |
|---|---|---|
| `extra-args` | `""` | Extra TruffleHog arguments, separated by spaces |

## Development

Run the unit tests with `for t in tests/test_*.sh; do "$t" || exit 1; done`. Tag releases as `vX.Y.Z` so Dependabot can update callers that pin a commit SHA; the tag push publishes the release with notes from git-cliff. A TruffleHog image update is tagged automatically under the conditions in [AGENTS.md](AGENTS.md#releases).

## License

[MIT](LICENSE)
