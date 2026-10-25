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

## 2択クイズ（GuessScreen）

### ファイル構成

| ファイル | 責務 |
| --- | --- |
| `lib/guess_main.dart` | 単独動作確認用エントリーポイント（仮画像2枚） |
| `lib/guess_src.dart` | 回答画面の表示・ユーザー操作、クイズ共通のタイトル・ボタン |
| `lib/guess.dart` | 選択状態・正誤判定・選択肢記号（Firebase非依存） |
| `lib/screens/guess_screen.dart` | 外部統合用の公開 `GuessScreen` |
| `lib/screens/guess_result_screen.dart` | 結果画面（正解！／惜しい！） |
| `lib/screens/notifications_screen.dart` | ホーム右上のベルと通知一覧（未読のみ表示） |

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
      candidates: [ // 呼び出し元でシャッフル済みの2件
        GuessCandidate(photoId: 'photos/xxx.jpg', imageBytes: bytes1),
        GuessCandidate(photoId: 'photos/yyy.jpg', imageBytes: bytes2),
      ],
      correctPhotoId: 'photos/yyy.jpg',
      reasonTags: ['表情', '雰囲気'],
      partnerName: 'Haruka',
    ),
  ),
);
// selectedPhotoId: 選択した写真ID。回答前に戻った場合は null。
// 回答の保存・正誤結果の永続化は呼び出し元で行う。
```

結果画面は、端末の戻る操作・「撮影カルテ」ボタンのどちらで閉じても、クイズ全体を終了し `Navigator.pop(context, selectedPhotoId)` で写真IDを返します。通知一覧から開いた場合は、その後に撮影カルテへ進みます。

### 画面の流れ

1. ホーム右上のベル → 通知一覧（未読の通知のみ）
2. 「いいね！」が届きました。をタップ → クイズ（未選択）
3. カードをタップすると選択が切り替わる（結果へは進まない）
4. 「この写真だと思う！」で回答を確定 → 正解なら「正解！」、違えば「惜しい！」
5. 「撮影カルテ」→ 撮影カルテ。回答した通知は既読になり、一覧から消える

正解は、相手がお気に入り（いいね）にした写真です。お気に入り以外の写真がない撮影セットはクイズを作らず、通知をタップすると既読になるだけです。3択で保存された過去のクイズは、正解と残りの先頭1枚の2択で表示します。

### 動作確認

1. 仮画像2枚が表示され、カードのタップで選択が切り替わる
2. A/B を選ぶまで「この写真だと思う！」が押せない
3. 回答すると「正解！」（Bを選択）または「惜しい！」が表示され、正解写真と理由タグが出る
4. 結果画面を閉じると、起動画面に返ってきた写真IDが表示される

## ホーム・アルバム・いいね（05〜10）

| ファイル | 責務 |
| --- | --- |
| `lib/screens/home_screen.dart` | 05 ホーム（カメラ、新しい写真8枚、いいね、撮影カルテ、スライドで接続解除） |
| `lib/screens/album_screen.dart` | 06〜08 アルバム（すべて／撮ってもらった／お気に入り）、写真データのキャッシュ |
| `lib/screens/photo_viewer_sheet.dart` | 09 拡大表示、10「どこが好き？」 |
| `lib/services/album_service.dart` | 写真一覧と、自分のいいね（送信済み・未送信）の状態 |

### いいねの流れ

1. 撮ってもらった写真のハートを押すと「どこが好き？」が開く
2. 理由を1つ以上選ぶといいねが成立し、選ぶたびに `pairs/{pairId}/sessions/{sessionId}/likeDrafts/{uid}` に保存される（1つも選ばずに閉じると取り消し）
3. 未送信のいいねは、もう一度ハートを押すと取り消せる
4. アルバム下部の「◯枚の「好き」を送る」で、撮影セットごとに通知とクイズを作る。送信後は変更できない

ルールに `likeDrafts` を追加しているため、エミュレーターは再起動してください。
