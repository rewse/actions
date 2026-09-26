# actions

GitHub Actions shared by the [rewse](https://github.com/rewse) repositories.

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

Run the unit tests with `tests/test_resolve_version.sh`. Tag releases as `vX.Y.Z` so Dependabot can update callers that pin a commit SHA.

## License

[MIT](LICENSE)
