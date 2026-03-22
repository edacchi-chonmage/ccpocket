# 新規セッションシート タブ設定

## Context

Note機能（`docs/design/note.md`）の追加により、新規セッションシートのタブが3つ（Codex / Claude Code / Note）になる。
ユーザーによっては特定のツールしか使わないため、表示タブと順序をカスタマイズ可能にする。

## 要件

- 表示するタブの選択（最低1つ必須）
- 表示順の変更
- SharedPreferences でアプリ側に永続化

## 設計判断

| 判断 | 決定 | 理由 |
|------|------|------|
| タブの型 | `NewSessionTab` enum を新設 | `Provider` enum は AI セッション専用（claude/codex）。Note は Provider ではないため別の型が必要 |
| デフォルト | `[codex, claude]` | 現在の並び順を維持。Note 追加時に `[codex, claude, note]` に変更 |
| 永続化 | SharedPreferences (JSON文字列配列) | 既存の SettingsCubit パターンに合わせる |
| 設定 UI | ReorderableListView + チェックボックス | ドラッグで並べ替え、チェックで表示/非表示。最低1つのバリデーション |
| 設定の配置 | Settings > General セクション | セッション作成に関わる基本設定 |
| lockProvider 時 | 設定を無視して指定 Provider のみ表示 | lockProvider は「このプロバイダで固定」の意味なので、設定より優先。既存動作と完全互換 |
| 保存済みデフォルトとの整合性 | 設定タブの先頭にフォールバック | 非表示タブの provider が保存されていたら、設定の先頭タブに切り替える |
| 実装タイミング | Note 機能と同時に実装 | 2タブだけのうちはオーバースペック。Note 追加時にまとめて入れるのが自然 |
| 1タブのみ表示時 | トグル UI を非表示 | 1つしかないのにトグルを表示するのは無駄。ヘッダが省スペースになる |

## データモデル

```dart
enum NewSessionTab {
  codex('codex', 'Codex'),
  claude('claude', 'Claude Code'),
  note('note', 'Note');

  final String value;
  final String label;

  /// AI Provider への変換（Note は null）
  Provider? toProvider() => switch (this) {
    NewSessionTab.claude => Provider.claude,
    NewSessionTab.codex => Provider.codex,
    NewSessionTab.note => null,
  };
}

const defaultNewSessionTabs = [NewSessionTab.codex, NewSessionTab.claude];
```

## 永続化

```
key:   "settings_new_session_tabs"
value: '["codex","claude"]'  // JSON string array, ordered
```

- 空配列は無効 → デフォルトにフォールバック
- 未知の値は無視（前方互換）

## 新規セッションシートの動的描画

### タブ数に応じた UI

| タブ数 | トグル UI | PageView |
|--------|----------|----------|
| 1 | **非表示** | スワイプ無効、単一ページ |
| 2+ | 表示 | スワイプ有効、設定順でページ配置 |

### lockProvider 時

タブ設定に関係なく、指定された Provider のタブのみ表示（既存動作を維持）。

### 保存済みデフォルトの Provider が非表示の場合

設定タブリストの先頭タブの Provider にフォールバック。

## 変更ファイル（予定）

| ファイル | 変更内容 |
|----------|----------|
| `models/messages.dart` | `NewSessionTab` enum 追加 |
| `settings/state/settings_state.dart` | `newSessionTabs` フィールド追加 |
| `settings/state/settings_cubit.dart` | 永続化ロジック追加 |
| `settings/settings_screen.dart` | タブ設定 UI 追加 |
| `settings/widgets/new_session_tabs_bottom_sheet.dart` | 並べ替え・選択シート（新規） |
| `widgets/new_session_sheet.dart` | 設定に基づく動的タブ描画 |
| `theme/provider_style.dart` | Note 用スタイル追加（Note 実装時） |
| `l10n/app_*.arb` | ローカライズ文字列追加 |
| `settings_state.freezed.dart` | コード生成 |
