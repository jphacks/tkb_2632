import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'screens/guess_screen.dart';

// 3択クイズ（GuessScreen）の動作確認専用のエントリーポイント。
// main.dart のFirebase初期化・認証フローを経由せず、仮画像3枚でクイズを起動する。
//   flutter run -t lib/guess_main.dart
void main() {
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _GuessLauncher(),
    ),
  );
}

// クイズを開き、返ってきた写真IDを表示するだけの仮の呼び出し元。
class _GuessLauncher extends StatefulWidget {
  const _GuessLauncher();

  @override
  State<_GuessLauncher> createState() => _GuessLauncherState();
}

class _GuessLauncherState extends State<_GuessLauncher> {
  // 写真IDは Firebase Storage のパスを想定した仮の値。
  late final List<GuessCandidate> _candidates = [
    GuessCandidate(
      photoId: 'photos/dummy/photo_1.png',
      imageBytes: _dummyPhoto('1', img.ColorRgb8(0xF4, 0xA2, 0x8C)),
    ),
    GuessCandidate(
      photoId: 'photos/dummy/photo_2.png',
      imageBytes: _dummyPhoto('2', img.ColorRgb8(0x8C, 0xB8, 0xF4)),
    ),
    GuessCandidate(
      photoId: 'photos/dummy/photo_3.png',
      imageBytes: _dummyPhoto('3', img.ColorRgb8(0x9C, 0xD4, 0x9A)),
    ),
  ];

  String _lastResult = 'まだ回答していません';

  Future<void> _openQuiz() async {
    final selectedPhotoId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => GuessScreen(
          candidates: _candidates,
          correctPhotoId: 'photos/dummy/photo_2.png',
          reasonTags: const ['表情', '雰囲気'],
        ),
      ),
    );

    if (!mounted) return;

    setState(() {
      _lastResult = selectedPhotoId ?? '回答せずに戻りました（null）';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton(onPressed: _openQuiz, child: const Text('クイズを開始')),
                const SizedBox(height: 24),
                const Text('返ってきた写真ID'),
                const SizedBox(height: 8),
                Text(
                  _lastResult,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// 縦長の単色画像に番号を描いた仮写真。
Uint8List _dummyPhoto(String text, img.Color color) {
  final image = img.Image(width: 360, height: 640);
  img.fill(image, color: color);
  img.drawString(
    image,
    text,
    font: img.arial48,
    x: 160,
    y: 296,
    color: img.ColorRgb8(255, 255, 255),
  );
  return img.encodePng(image);
}
