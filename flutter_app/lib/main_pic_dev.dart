import 'package:flutter/material.dart';

import 'pic_scr.dart';

// pic_scr.dart / pic.dart の動作確認専用のエントリーポイント。
// main.dart のFirebase初期化・認証フローを経由せず、PicScr単体を起動する。
void main() {
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: PicScr(),
    ),
  );
}
