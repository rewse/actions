# actions

GitHub Actions shared by the [rewse](https://github.com/rewse) repositories.

## dependabot-review

Rates the risk of a Dependabot PR with [Kiro CLI](https://kiro.dev/docs/cli/headless) in headless mode and rebase-merges the PR when every condition holds:

- Every updated dependency is a patch or minor update. A major update or an unknown update type anywhere in a grouped PR rates the whole PR high without asking Kiro.
- Kiro rates the risk low after reading the changelog, the diff, and how the repository uses the dependency.
- Every check outside the calling workflow passes within 30 minutes.

The action posts its rating as one PR comment, updated on each run, and labels the PR `risk:low`, `risk:medium`, or `risk:high`. Kiro runs with the read and grep tools only and receives no credential besides its API key, because the PR body and diff come from upstream. Those tools can read files outside the workspace, so the action discards a verdict that quotes the API key and caps the length of what it posts. The merge uses a GitHub App token so that the push to the default branch starts its workflows, which a merge with `GITHUB_TOKEN` would not.

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
    if: github.actor == 'dependabot[bot]'
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
| `dry-run` | `false` | When `true`, rate and comment but never merge |
| `kiro-api-key` | | Kiro API key for headless mode |
| `kiro-model` | | Model for Kiro to use; empty uses the Kiro default |

| Output | Description |
|---|---|
| `outcome` | What happened to the PR, as written in the comment |
| `risk` | The risk rating: `low`, `medium`, or `high` |

Workflows started by Dependabot read only Dependabot secrets, so register `DEPENDABOT_APP_CLIENT_ID`, `DEPENDABOT_APP_PRIVATE_KEY`, and `KIRO_API_KEY` under Settings → Secrets and variables → Dependabot in each repository. The App needs Contents: Read and write, Pull requests: Read and write, and Metadata: Read-only, and must be installed on the repository. Kiro API keys require a Kiro Pro, Pro+, or Power subscription.

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

## Development

Run the unit tests with `for t in tests/test_*.sh; do "$t" || exit 1; done`. Tag releases as `vX.Y.Z` so Dependabot can update callers that pin a commit SHA.

## License

[MIT](LICENSE)
