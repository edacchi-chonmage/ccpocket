# Contributing to CC Pocket

Thank you for your interest in contributing to CC Pocket!

## Prompt Request — Contributing in the AI Era

CC Pocket is a mobile client for Claude Code / Codex.
Given the nature of the project, we embrace an **AI-driven contribution style**.

In traditional OSS, the standard workflow is "write code and send a Pull Request."
In CC Pocket, we encourage **Prompt Requests** instead.

### What is a Prompt Request?

> A way to contribute by sharing "I achieved this feature/fix using this prompt" via a GitHub Issue.

Rather than sharing code diffs, you share the **instructions you gave to an AI** (intent, constraints, assumptions). This means:

- You can contribute without deep knowledge of the project's architecture
- Maintainers can re-run and adjust the prompt to fit the codebase
- Reviews focus on **what you intended to achieve** rather than implementation details

### How to Contribute

1. **Create an Issue** — Use the [Prompt Request template](https://github.com/K9i-0/ccpocket/issues/new?template=prompt_request.yml)
2. **Describe the prompt and results** — The actual prompt you used, what it achieved, screenshots, etc.
3. **Maintainers verify and apply** — We re-run the prompt, adjust as needed, and merge

### What to Include in a Prompt Request

- **Goal**: What you wanted to achieve
- **Prompt**: The exact instructions you gave to the AI (in a copy-pasteable format)
- **Result**: What worked, screenshots, etc.
- **Environment**: The AI tool you used (Claude Code, Codex, etc.)

## Bug Reports / Feature Requests

In addition to Prompt Requests, regular Issues are always welcome.

- [Bug Report](https://github.com/K9i-0/ccpocket/issues/new?template=bug_report.yml) — Report a bug
- [Feature Request](https://github.com/K9i-0/ccpocket/issues/new?template=feature_request.yml) — Suggest a feature

## Pull Requests

### Environment-Dependent PRs — Especially Welcome

We develop primarily on macOS and don't always have easy access to Linux, WSL, or Windows environments.
If you can **test on a platform we can't**, your PR is especially valuable.

Examples:

- Linux / systemd integration fixes
- WSL-specific workarounds
- Cross-platform compatibility improvements

For these cases, please include:

- What platform and version you tested on
- Steps to reproduce the issue (if it's a fix)
- Test results or logs

### Other PRs

For changes that don't require a specific environment, we recommend opening a **Prompt Request** or **Issue** first.

If you do send a PR, we may close it and re-implement the change ourselves to fit the codebase's conventions and architecture. In that case:

- Your contribution will be credited via `Co-authored-by` in the commit
- We'll comment on the PR explaining what we incorporated and what we adjusted

This isn't a rejection of your work — it's how we maintain consistency while honoring your contribution.

## Security

If you discover a vulnerability, please report it privately via [GitHub Security Advisories](https://github.com/K9i-0/ccpocket/security/advisories/new) rather than opening a public Issue. See [SECURITY.md](./SECURITY.md) for details.

---

## 日本語 / Japanese

### Prompt Request（プロンプトリクエスト）とは？

> 「こういうプロンプトで、こういう機能追加／修正ができた」を Issue で共有する貢献方法です。

コードの差分ではなく、**AI に渡した指示（意図・制約・前提）** を共有することで：

- プロジェクトのアーキテクチャを深く理解していなくても貢献できる
- メンテナがプロンプトを再実行・調整してコードベースに適合させられる
- レビューの焦点が「何を実現したいか」という意図に集中する

### 貢献の流れ

1. **Issue を作成する** — [Prompt Request テンプレート](https://github.com/K9i-0/ccpocket/issues/new?template=prompt_request.yml) を使用
2. **プロンプトと結果を記載する** — 実際に使ったプロンプト、実現できたこと、スクリーンショットなど
3. **メンテナが検証・適用する** — プロンプトを再実行し、必要に応じて調整してマージ

### Pull Request

#### 環境依存の PR — 特に歓迎

開発は主に macOS で行っており、Linux・WSL・Windows 環境を常に手元で用意できるわけではありません。
**メンテナが検証しづらいプラットフォームでテストできる方からの PR** は特に歓迎します。

例:

- Linux / systemd 関連の修正
- WSL 固有のワークアラウンド
- クロスプラットフォーム互換性の改善

#### その他の PR

環境依存でない変更は、先に **Prompt Request** や **Issue** で相談いただくのがスムーズです。

PR を送っていただいた場合でも、コードベースの規約やアーキテクチャに合わせるため、クローズした上でメンテナ側で再実装することがあります。その際は:

- コミットに `Co-authored-by` を付与して貢献をクレジットします
- PR コメントで、何を取り込み何を調整したかを説明します

これは PR の否定ではなく、一貫性を保ちつつ貢献を活かすための運用です。

### バグ報告・機能提案

- [Bug Report](https://github.com/K9i-0/ccpocket/issues/new?template=bug_report.yml) — バグの報告
- [Feature Request](https://github.com/K9i-0/ccpocket/issues/new?template=feature_request.yml) — 機能の提案

### セキュリティ

脆弱性を発見した場合は、公開 Issue ではなく [GitHub Security Advisories](https://github.com/K9i-0/ccpocket/security/advisories/new) から非公開で報告してください。詳細は [SECURITY.md](./SECURITY.md) を参照してください。
