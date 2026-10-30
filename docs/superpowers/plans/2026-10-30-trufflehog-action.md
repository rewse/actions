# TruffleHog の自前アクション化とイメージ更新の自動リリース 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `rewse/actions/trufflehog` を作り、Dependabot による TruffleHog イメージ更新を自動でパッチリリースまで進め、13 リポジトリの週次スイープをそのアクションに切り替える。

**Architecture:** `trufflehog/` は Dockerfile 1 行でイメージを固定する Docker コンテナアクション。`.github/scripts/next-auto-tag.sh` が「最新タグから HEAD までがイメージ更新と呼び出し側が実行しないパスへの Dependabot の変更だけか」を判定して次のタグを出し、`trufflehog-auto-tag.yml` がリリース専用 App のトークンでタグを作る。タグの push で `release.yml` が git-cliff のノートで GitHub Release を作る。

**Tech Stack:** bash、git、gh CLI、GitHub Actions（Docker コンテナアクション）、Dependabot（`docker` エコシステム）、git-cliff、`actions/create-github-app-token`

**Spec:** `docs/superpowers/specs/2026-10-30-trufflehog-action-design.md`

## Global Constraints

- `rewse/actions` の作業は `git pull` 後のブランチ `feat/trufflehog-action` で行う。ほかのリポジトリはそれぞれ `git pull` してから作業する。
- `uses:` はフル SHA と `# vX.Y.Z` で固定する。使う値: `actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1`、`actions/create-github-app-token@bcd2ba49218906704ab6c1aa796996da409d3eb1  # v3.2.0`、`orhun/git-cliff-action@a9a95522b26fe6403f7bb24031f21fb573d0f5ff  # v4.9.1`。同一リポジトリ内のアクションは `uses: ./trufflehog  # zizmor: ignore[self-repository]` と書く（`test.yml` の `./setup-safe-chain` と同じ理由のコメントを付ける）。
- イメージの初期値: `FROM ghcr.io/trufflesecurity/trufflehog:3.99.7@sha256:0d003fc3abc4e1565eca8462b992001314de51451e96e3c44de80d116794d5d1`（2026-10-24 公開、96 時間以上経過済み）。
- checkout には `persist-credentials: false` を付け、全ジョブに `name` を付け、最上位の `permissions` は `contents: read` にする。
- 自動タグ付けを許すパス: `trufflehog/Dockerfile`（必須）、`.pre-commit-config.yaml`、`.github/` 配下、`tests/` 配下、`docs/` 配下。Dependabot の author は名前 `dependabot[bot]`、メール `49699333+dependabot[bot]@users.noreply.github.com`。
- 対象タグは `^v[0-9]+\.[0-9]+\.[0-9]+$` に一致するものだけ。
- リリース専用 App の資格情報: Environment `auto-tag` の secret `AUTO_TAG_APP_PRIVATE_KEY`、リポジトリの Actions variable `AUTO_TAG_APP_CLIENT_ID`。
- スクリプトは `#!/usr/bin/env bash` と `set -euo pipefail`、先頭に用途のコメントを置く。テストは `tests/test_*.sh` の既存の書き方（`expect` 関数、`ok`/`FAIL` 出力、失敗数で終了コード）に合わせ、`.github/workflows/test.yml` に 1 スクリプト 1 `run:` ステップで足す。
- コミット前に `uvx --with pre-commit-uv==4.3.0 pre-commit@4.6.2 run --all-files` とテスト一式（`for t in tests/test_*.sh; do "$t" || exit 1; done`）を通す。新規ファイルは先に stage する。コミットメッセージは Conventional Commits、英語。
- push、タグ、PR 作成、PR へのコメント、GitHub の設定変更は外部への書き込みなので、実行前にユーザーの確認を取る。

## Review Focus

- タグが 1 つもない、または最新タグが HEAD を指していて差分がない: タグを作らず理由を出す（Task 2 の `blocks_without_tag`, `blocks_no_commits`）。
- 許可パスに似た別パス（`.github-extra/x`、`docs.md`、`trufflehog/action.yml`）: 許可パス扱いせず止める（Task 2 の `blocks_lookalike_paths`, `blocks_other_trufflehog_file`）。
- 人のコミットが Dependabot のコミットの間に 1 つだけ混ざる: 止める（Task 2 の `blocks_mixed_authors`）。
- `v1.2.0-rc1` のような前リリース用タグや、HEAD の祖先でないタグがある: 無視して正しい最新の安定タグから数える（Task 2 の `ignores_prerelease_and_unmerged_tags`）。
- Dockerfile の `FROM` からダイジェストが落ちる、行が増える: テストで落とす（Task 1 の `tests/test_trufflehog_dockerfile.sh`）。

---

### Task 1: `trufflehog` アクション

**Files:**
- Create: `trufflehog/Dockerfile`, `trufflehog/action.yml`, `tests/test_trufflehog_dockerfile.sh`
- Modify: `.github/workflows/test.yml`, `.github/workflows/trufflehog.yml`, `.github/dependabot.yml`, `README.md`

**Interfaces:**
- Produces: アクション `rewse/actions/trufflehog`、入力 `extra-args`（既定値 `""`）。呼び出し側は先に `actions/checkout` を `fetch-depth: 0` で実行する。

- [ ] **Step 1: `tests/test_trufflehog_dockerfile.sh` を書く**

`trufflehog/Dockerfile` について次を検査する: 空行とコメントを除くと 1 行だけ、その行が `^FROM ghcr\.io/trufflesecurity/trufflehog:[0-9]+\.[0-9]+\.[0-9]+@sha256:[0-9a-f]{64}$` に一致する。テスト名は `single_from_line` と `pins_tag_and_digest`。

- [ ] **Step 2: 実行して失敗を確かめる**

Run: `tests/test_trufflehog_dockerfile.sh`
Expected: Dockerfile がないので FAIL、終了コード 1。

- [ ] **Step 3: `trufflehog/Dockerfile` と `trufflehog/action.yml` を作る**

Dockerfile は Global Constraints の `FROM` 1 行だけ。`action.yml` は `runs.using: docker`、`runs.image: Dockerfile`、`runs.args` を `git`, `file:///github/workspace`, `--branch`, `main`, `--fail`, `--no-update`, `--github-actions`, `${{ inputs.extra-args }}` の順にする。上流エントリポイントが最後の引数を追加引数として展開するので、`extra-args` は必ず最後に置く理由をコメントで残す。

- [ ] **Step 4: テストを通す**

Run: `tests/test_trufflehog_dockerfile.sh`
Expected: `ok   single_from_line`、`ok   pins_tag_and_digest`、終了コード 0。

- [ ] **Step 5: ワークフローと Dependabot を更新する**

- `test.yml`: `unit` ジョブに `- run: tests/test_trufflehog_dockerfile.sh` を足す。ジョブ `trufflehog`（name `TruffleHog Action`）を足し、`fetch-depth: 0` の checkout のあとに `./trufflehog` を `extra-args: --results=verified,unknown` で実行する。
- `trufflehog.yml`: `trufflesecurity/trufflehog` のステップを `./trufflehog` と `extra-args: --results=verified,unknown` に置き換え、`base`/`head`/`version` と手で揃える旨のコメントを消す。
- `dependabot.yml`: `docker` エントリを `directory: /trufflehog`、`interval: weekly`、既存と同じ `cooldown.default-days: 5` と zizmor 抑制コメント、グループ名 `docker`（`patterns: ["*"]`）で足す。

- [ ] **Step 6: README に `trufflehog` 節を足す**

用途、`fetch-depth: 0` の前提、`extra-args` の例（`--results=verified,unknown` と `--exclude-detectors=lob`）、イメージは Dependabot が上げ、イメージ更新だけのときは自動でパッチリリースされること。

- [ ] **Step 7: pre-commit とテスト一式を通してコミットする**

```bash
git add trufflehog tests/test_trufflehog_dockerfile.sh .github README.md
git commit -m "feat(trufflehog): add a container action that pins the TruffleHog image"
```

### Task 2: `next-auto-tag.sh`

**Files:**
- Create: `.github/scripts/next-auto-tag.sh`, `tests/test_next_auto_tag.sh`
- Modify: `.github/workflows/test.yml`

**Interfaces:**
- Produces: `.github/scripts/next-auto-tag.sh [REV]`（`REV` 既定値 `HEAD`）。カレントディレクトリの git リポジトリで判定する。タグを作るべきときは次のタグ（例 `v1.1.7`）だけを stdout に出して終了コード 0。作らないときは理由 1 行を stdout に出して終了コード 1。理由の文言:
  - `No release tag found`
  - `No commits since <tag>`
  - `trufflehog/Dockerfile did not change since <tag>`
  - `Changed outside the allowed paths since <tag>: <files>`（ファイル名を空白区切り、全体を 500 文字で切る）
  - `Commits by someone other than Dependabot since <tag>: <short shas>`（同じく 500 文字で切る）

- [ ] **Step 1: `tests/test_next_auto_tag.sh` を書く**

`mktemp -d /tmp/next-auto-tag.XXXXXX` に一時リポジトリを作るヘルパーと、author を指定してファイルを変更・コミットするヘルパーを用意する。`semver-gate.sh` のテストと同じ `expect <name> <tag or block> <want-output>` 形式で、出力の完全一致を見る。初期状態は人のコミットに `v1.1.5` を付けたもの。

| テスト名 | 状態 | 期待 |
| --- | --- | --- |
| `tags_dockerfile_only` | Dependabot が `trufflehog/Dockerfile` を変更 | `v1.1.6` |
| `tags_with_allowed_paths` | Dependabot が Dockerfile、`.github/workflows/lint.yml`、`.pre-commit-config.yaml`、`tests/a.sh`、`docs/a.md` を別コミットで変更 | `v1.1.6` |
| `blocks_without_tag` | タグなし | `No release tag found` |
| `blocks_no_commits` | 変更なし | `No commits since v1.1.5` |
| `blocks_without_dockerfile` | Dependabot が `.github/` だけ変更 | `trufflehog/Dockerfile did not change since v1.1.5` |
| `blocks_action_code` | Dependabot が Dockerfile と `dependabot-review/action.yml` を変更 | `Changed outside the allowed paths since v1.1.5: dependabot-review/action.yml` |
| `blocks_other_trufflehog_file` | Dependabot が Dockerfile と `trufflehog/action.yml` を変更 | `Changed outside ...: trufflehog/action.yml` |
| `blocks_lookalike_paths` | Dependabot が Dockerfile、`.github-extra/x`、`docs.md` を変更 | `Changed outside ...: .github-extra/x docs.md` |
| `blocks_mixed_authors` | Dependabot の Dockerfile 変更の間に人の `docs/a.md` 変更 | `Commits by someone other than Dependabot since v1.1.5: <その short sha>` |
| `blocks_name_without_email` | 名前だけ `dependabot[bot]` でメールが違う | `Commits by someone other than Dependabot ...` |
| `ignores_prerelease_and_unmerged_tags` | `v1.2.0-rc1` を HEAD に、`v9.0.0` を HEAD の祖先でないブランチに付け、Dependabot が Dockerfile を変更 | `v1.1.6` |
| `sorts_versions_numerically` | `v1.1.9` と `v1.1.10` があり最新が `v1.1.10` | `v1.1.11` |

判定の順序は表の上から（タグ → コミット有無 → Dockerfile → パス → author）とし、複数に当たるときは先に当たった理由を出す。

- [ ] **Step 2: 実行して失敗を確かめる**

Run: `tests/test_next_auto_tag.sh`
Expected: スクリプトがないので全件 FAIL、終了コード 1。

- [ ] **Step 3: `.github/scripts/next-auto-tag.sh` を実装する**

最新タグは `git tag --merged "$rev" --sort=-v:refname` を Global Constraints の正規表現で絞った先頭。差分は `git diff --name-only "$tag" "$rev"`、author は `git log --format='%h %an <%ae>' "$tag..$rev"`。

- [ ] **Step 4: テストを通す**

Run: `tests/test_next_auto_tag.sh`
Expected: 全件 `ok`、終了コード 0。

- [ ] **Step 5: `test.yml` の `unit` ジョブに `- run: tests/test_next_auto_tag.sh` を足し、pre-commit とテスト一式を通してコミットする**

```bash
git add .github/scripts/next-auto-tag.sh tests/test_next_auto_tag.sh .github/workflows/test.yml
git commit -m "feat(ci): decide when an image update can be tagged automatically"
```

### Task 3: `trufflehog-auto-tag.yml`

**Files:**
- Create: `.github/workflows/trufflehog-auto-tag.yml`

**Interfaces:**
- Consumes: Task 2 の `next-auto-tag.sh` の出力と終了コード。Global Constraints の `AUTO_TAG_APP_CLIENT_ID` と `AUTO_TAG_APP_PRIVATE_KEY`。
- Produces: リリース専用 App が作る `refs/tags/vX.Y.Z`（lightweight、`github.sha` を指す）。

- [ ] **Step 1: ワークフローを書く**

- `name: TruffleHog Auto Tag`。トリガーは `push`（`branches: [main]`, `paths: [trufflehog/Dockerfile]`）と `workflow_dispatch`。
- `concurrency: { group: trufflehog-auto-tag, cancel-in-progress: false }`。
- ジョブ `tag`（name `Tag`）、`environment: auto-tag`、ジョブにも追加の `permissions` は付けない。
- checkout は `fetch-depth: 0`、`fetch-tags: true`、`ref: ${{ github.sha }}`。
- `next-auto-tag.sh` を実行し、終了コード 0 なら `tag` を出力に、1 なら理由を `$GITHUB_STEP_SUMMARY` に書いて正常終了する。
- `tag` があるときだけ `actions/create-github-app-token` を `client-id: ${{ vars.AUTO_TAG_APP_CLIENT_ID }}`、`private-key: ${{ secrets.AUTO_TAG_APP_PRIVATE_KEY }}`、`permission-contents: write` で実行する。
- そのトークンで `gh api "repos/$GITHUB_REPOSITORY/git/refs" -f ref="refs/tags/$TAG" -f sha="$GITHUB_SHA"` を実行し、作ったタグをサマリーに書く。値はすべて `env:` 経由で渡す。

- [ ] **Step 2: pre-commit（actionlint と zizmor）を通してコミットする**

```bash
git add .github/workflows/trufflehog-auto-tag.yml
git commit -m "feat(ci): tag a patch release after a TruffleHog image update"
```

### Task 4: `release.yml` と `cliff.toml`

**Files:**
- Create: `.github/workflows/release.yml`, `cliff.toml`

**Interfaces:**
- Consumes: `v*` タグの push（手動、または Task 3）。

- [ ] **Step 1: `cliff.toml` を `~/git/enecoq-data-fetcher/cliff.toml` から写し、比較 URL を `https://github.com/rewse/actions/compare/{{ previous.version }}...{{ version }}` に変える**

- [ ] **Step 2: ノートの出力を確かめる**

Run: `uvx git-cliff==<公開から 96 時間以上経った版> --unreleased --strip header`（`--unreleased` で未リリース分を表示）
Expected: このブランチの `feat(trufflehog)` / `feat(ci)` が「🚀 New Features」に出て、`81a6e14` の `build(deps)` が「📦 Build」に出る。

- [ ] **Step 3: `release.yml` を書く**

`name: Release`、`on: push: tags: ['v*']`。ジョブ `release`（name `Release`）だけ `permissions: contents: write`。checkout は `fetch-depth: 0`。`orhun/git-cliff-action` を `args: --latest --strip header` で実行し、`gh release create "$TAG_NAME" --title "$TAG_NAME" --notes "$RELEASE_NOTES" --verify-tag` を `GITHUB_TOKEN` で実行する。`enecoq-data-fetcher` の `release.yml` から PyPI 関連を除いた形になる。

- [ ] **Step 4: pre-commit を通してコミットする**

```bash
git add cliff.toml .github/workflows/release.yml
git commit -m "feat(ci): publish releases with git-cliff notes"
```

### Task 5: `rewse/actions` のドキュメント

**Files:**
- Modify: `AGENTS.md`, `README.md`

- [ ] **Step 1: `AGENTS.md` に節 `Releases` を足す**

`v*` タグの push で `release.yml` が git-cliff のノートでリリースを作ること、手動リリースはタグを push するだけであること、`trufflehog-auto-tag.yml` が自動でタグを作る条件（Global Constraints の許可パスと author）、タグ作成は ruleset `Protect release tags` で管理者とリリース専用 App に限られること。

- [ ] **Step 2: README の `trufflehog` 節に自動リリースの条件への参照を足し、コミットする**

```bash
git add AGENTS.md README.md
git commit -m "docs: describe the release flow and the TruffleHog auto tag"
```

### Task 6: GitHub 側の設定と v1.1.6

外部への書き込みなので、各ステップの前にユーザーの確認を取る。App の作成は GitHub の画面での手作業なので、ユーザーに頼む。

- [ ] **Step 1: ブランチを push し、`main` に取り込む方法をユーザーに確認して取り込む**

- [ ] **Step 2: ユーザーにリリース専用 App を作ってもらう**

権限は Repository の Contents: Read and write だけ、Webhook は無効、インストール先は `rewse/actions` だけ。

- [ ] **Step 3: Environment `auto-tag`（デプロイ対象ブランチは `main` だけ）を作り、secret `AUTO_TAG_APP_PRIVATE_KEY` と variable `AUTO_TAG_APP_CLIENT_ID` を登録する**

秘密鍵はユーザーに `gh secret set AUTO_TAG_APP_PRIVATE_KEY --env auto-tag -R rewse/actions < <鍵ファイル>` で入れてもらう。

- [ ] **Step 4: ruleset `Protect release tags` を作る**

`gh api repos/rewse/actions/rulesets` で、`target: tag`、`conditions.ref_name.include: ["refs/tags/v*"]`、rules `creation`・`update`・`deletion`、`bypass_actors` にリポジトリ管理者ロール（`actor_type: RepositoryRole`, `actor_id: 5`）とリリース専用 App（`actor_type: Integration`）を `bypass_mode: always` で入れる。

Run: `gh api repos/rewse/actions/rulesets --jq '.[].name'`
Expected: `Protect release tags`

- [ ] **Step 5: v1.1.6 を手動でリリースする**

`git tag v1.1.6 origin/main && git push origin v1.1.6`。

Run: `gh release view v1.1.6 -R rewse/actions --json body --jq .body`
Expected: git-cliff のノート（「🚀 New Features」と「📦 Build」の節、`Full Changelog` の比較リンク）。

- [ ] **Step 6: `trufflehog-auto-tag.yml` を `workflow_dispatch` で動かす**

Run: `gh workflow run trufflehog-auto-tag.yml -R rewse/actions` のあと `gh run view --log` で確認
Expected: 正常終了し、サマリーに `No commits since v1.1.6`。タグは増えない。

- [ ] **Step 7: `trufflehog.yml` を `workflow_dispatch` で動かし、自前アクションでスキャンが通ることを確かめる**

### Task 7: 12 リポジトリの切り替え

対象: `ansible-playbooks`, `cloudfront-waf`, `chezmoi`（`rewse/dotfiles`）, `enecoq-data-fetcher`, `gnucash-import-agent`, `mac-power-monitor-mqtt`, `rewse-blog`, `security-agent`, `stock-price-fetcher`, `textlint-config-rewse`, `textlint-rule-ja-space-around-phrase`, `zenn-content`。

- [ ] **Step 1: 各リポジトリで `git pull` し、`trufflehog.yml` のステップを置き換える**

`uses: rewse/actions/trufflehog@<v1.1.6 の SHA>  # v1.1.6` にし、`with:` は `extra-args:` に今の `extra_args` の値をそのまま入れる（`chezmoi` は `--exclude-detectors=lob --exclude-paths=.trufflehog-exclude-paths.txt --results=verified,unknown`、`enecoq-data-fetcher` と `stock-price-fetcher` は `--exclude-detectors=lob --results=verified,unknown`、ほかは `--results=verified,unknown`）。除外の理由コメントは残し、`base`/`head`/`version` と手で揃える旨のコメントを消す。

- [ ] **Step 2: pre-commit を通してコミットする**

```bash
git add .github/workflows/trufflehog.yml
git commit -m "ci: run TruffleHog through rewse/actions/trufflehog"
```

- [ ] **Step 3: ユーザーの確認を取って push し、`gh workflow run trufflehog.yml` でスキャンが通ることを確かめる**

push が失敗したら `github-push-via-fox` スキルに従う。

- [ ] **Step 4: trufflehog を含む開いた Dependabot PR を作り直させる**

`gh pr list -R rewse/<repo> --author app/dependabot --search trufflehog` で探し、ユーザーの確認を取ってから `@dependabot recreate` とコメントする。

### Task 8: `~/git/AGENTS.md`

`~/git/AGENTS.md` は chezmoi が管理しているので、ソースの `~/git/chezmoi/git/AGENTS.md` を編集して `chezmoi apply` する。Task 7 の `chezmoi` リポジトリと同じリポジトリなので、Task 7 のあとに `git pull` してから始める。

- [ ] **Step 1: GitHub Configuration の 2 つのルールを書き換える**

- `trufflehog.yml` のルール: 週次スイープは `rewse/actions/trufflehog` を使い、除外指定は `extra-args` に渡す、と書く。「When Dependabot bumps `trufflesecurity/trufflehog`, update the `version:` ...」の文は消す。
- tag ruleset のルール: `rewse/actions` では自動タグ付けのためリリース専用 App もバイパスに入れる、と足す。

- [ ] **Step 2: コミットし、ユーザーの確認を取って push し、`chezmoi apply ~/git/AGENTS.md` で反映する**

```bash
git add git/AGENTS.md
git commit -m "docs: point the TruffleHog rule at rewse/actions/trufflehog"
```

Run: `rg -n 'rewse/actions/trufflehog' ~/git/AGENTS.md`
Expected: 書き換えた行が出る。
