# shotrelay

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## 3択クイズ（GuessScreen）

### ファイル構成

| ファイル | 責務 |
| --- | --- |
| `lib/guess_main.dart` | 単独動作確認用エントリーポイント（仮画像3枚） |
| `lib/guess_src.dart` | 回答画面の表示・ユーザー操作、写真拡大ダイアログ |
| `lib/guess.dart` | 選択状態・正誤判定・選択肢記号（Firebase非依存） |
| `lib/screens/guess_screen.dart` | 外部統合用の公開 `GuessScreen` |
| `lib/screens/guess_result_screen.dart` | 結果画面（デザイン差し替え用に独立） |

### 単独起動

```sh
flutter run -t lib/guess_main.dart
```

### 統合方法

```dart
import 'screens/guess_screen.dart';

final selectedPhotoId = await Navigator.of(context).push<String>(
  MaterialPageRoute(
    builder: (_) => GuessScreen(
      candidates: [ // 呼び出し元でシャッフル済みの3件
        GuessCandidate(photoId: 'photos/xxx.jpg', imageBytes: bytes1),
        GuessCandidate(photoId: 'photos/yyy.jpg', imageBytes: bytes2),
        GuessCandidate(photoId: 'photos/zzz.jpg', imageBytes: bytes3),
      ],
      correctPhotoId: 'photos/yyy.jpg',
      reasonTags: ['表情', '雰囲気'],
    ),
  ),
);
// selectedPhotoId: 選択した写真ID。回答前に戻った場合は null。
// 回答の保存・正誤結果の永続化は呼び出し元で行う。
```

結果画面は、戻る矢印・端末の戻る操作・「撮影ガイドを見る」ボタンのどれで閉じても、クイズ全体を終了し `Navigator.pop(context, selectedPhotoId)` で写真IDを返します。

### 動作確認

1. 仮画像3枚が表示され、写真タップで拡大ダイアログが開閉できる
2. A/B/C を選ぶまで「この写真だと思う！」が押せない
3. 回答すると「正解！」（Bを選択）または「残念！」が表示され、正解写真と理由タグが出る
4. 結果画面を閉じると、起動画面に返ってきた写真IDが表示される

### 既知のTODO

- `Haruka` は仮名。将来は呼び出し元から名前を受け取る（`guess_screen.dart`）
- 写真タップ拡大はチーム未確認の暫定仕様（`guess_src.dart`）
- 「撮影ガイドを見る」は現在クイズ終了のみ。将来撮影ガイドへの遷移に変更（`guess_result_screen.dart`）
- 結果画面のデザインは暫定（不正解時は見出しのみ「残念！」に変更）
