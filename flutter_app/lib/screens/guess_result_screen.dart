import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// 3択クイズの結果画面。
// デザインは暫定のため、色・余白・文言はこのファイル内だけで変更できるようにしている。
// 不正解時も正解時と同じレイアウトを使い、見出しを「残念！」に、
// 見出し背景を紙吹雪から沈んだ雰囲気のイラストに変える。
const _resultBackgroundColor = Color(0xFFFCFBF9);
const _resultInkColor = Color(0xFF291F1D);
const _resultCoralColor = Color(0xFFFF735C);
const _resultMutedColor = Color(0xFF8F8A87);
const _tagBackgroundColor = Color(0xFFE6ECEE);
const _tagTextColor = Color(0xFF3A4A52);
const _photoPlaceholderColor = Color(0xFFE0E0E0);

class GuessResultScreen extends StatelessWidget {
  const GuessResultScreen({
    super.key,
    required this.isCorrect,
    required this.partnerName,
    required this.correctLabel,
    required this.correctPhotoBytes,
    required this.reasonTags,
    required this.onClose,
  });

  final bool isCorrect;
  final String partnerName;
  final String correctLabel;
  // 正解IDが候補に無い場合は null。プレースホルダーを表示する。
  final Uint8List? correctPhotoBytes;
  final List<String> reasonTags;
  // 戻る矢印・下部ボタンのどちらでも呼ばれる。クイズ全体を終了する。
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // 不正解時はヘッダーが暗いので、ステータスバーの文字を白にする。
      value: isCorrect ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _resultBackgroundColor,
        body: SafeArea(
          // ヘッダーの背景をステータスバーの裏まで広げるため、上端はヘッダー側で処理する。
          top: false,
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 4),
                      Text.rich(
                        TextSpan(
                          text: '$partnerNameが選んだのは  ',
                          children: [
                            TextSpan(
                              text: correctLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: _resultInkColor,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: AspectRatio(
                          aspectRatio: 7 / 6,
                          child: _buildPhoto(),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        '選ばれた理由',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _resultInkColor,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildReasonTags(),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    // ========================================================
                    // TODO: 将来撮影ガイド遷移に変更
                    // 現在は暫定でクイズ全体を終了し、選択写真IDを呼び出し元に返す。
                    // ========================================================
                    onPressed: onClose,
                    style: FilledButton.styleFrom(
                      backgroundColor: _resultCoralColor,
                      foregroundColor: Colors.white,
                      shape: const StadiumBorder(),
                      textStyle: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    child: const Text('撮影ガイドを見る'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 正解時は紙吹雪、不正解時は「ガーン」と沈む縦線と青いグラデーション。
  Widget _buildHeader(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;
    final foregroundColor = isCorrect ? _resultInkColor : Colors.white;

    return SizedBox(
      height: topPadding + (isCorrect ? 80 : 120),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: isCorrect
                    ? _ConfettiPainter(topPadding: topPadding)
                    : const _GloomPainter(),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: topPadding),
            child: SizedBox(
              height: 80,
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      onPressed: onClose,
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      color: foregroundColor,
                      tooltip: '戻る',
                    ),
                  ),
                  Center(
                    child: Text(
                      isCorrect ? '正解！' : '残念！',
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w900,
                        color: isCorrect ? _resultCoralColor : foregroundColor,
                        shadows: isCorrect
                            ? null
                            : const [
                                Shadow(
                                  color: Color(0x66000000),
                                  blurRadius: 8,
                                  offset: Offset(0, 2),
                                ),
                              ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoto() {
    const placeholder = ColoredBox(
      color: _photoPlaceholderColor,
      child: Center(
        child: Icon(Icons.broken_image_outlined, color: _resultMutedColor),
      ),
    );

    final bytes = correctPhotoBytes;
    if (bytes == null) return placeholder;

    return Image.memory(
      bytes,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => placeholder,
    );
  }

  Widget _buildReasonTags() {
    final tags = reasonTags.where((tag) => tag.trim().isNotEmpty).toList();

    if (tags.isEmpty) {
      return const Text(
        '理由は登録されていません',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: _resultMutedColor),
      );
    }

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 16,
      runSpacing: 10,
      children: [
        for (final tag in tags)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: _tagBackgroundColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              tag,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: _tagTextColor,
              ),
            ),
          ),
      ],
    );
  }
}

// 見出しの周りの紙吹雪。位置は見出し中央からの相対値で固定配置する。
class _ConfettiPainter extends CustomPainter {
  const _ConfettiPainter({required this.topPadding});

  // ステータスバー分。紙吹雪は見出しの周りにだけ描く。
  final double topPadding;

  static const _pieces = [
    // (中央からのx, 中央からのy, 角度, 色)
    (-118.0, -22.0, -0.6, Color(0xFFFFC94D)),
    (-150.0, 6.0, 0.9, Color(0xFFFFC94D)),
    (-100.0, 12.0, -0.8, Color(0xFFFF735C)),
    (108.0, -18.0, 0.8, Color(0xFF6CCFD0)),
    (140.0, 4.0, -0.7, Color(0xFFFFC94D)),
    (96.0, 18.0, 0.6, Color(0xFFFF735C)),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, topPadding + 40);
    final paint = Paint();

    for (final (dx, dy, angle, color) in _pieces) {
      paint.color = color;
      canvas.save();
      canvas.translate(center.dx + dx, center.dy + dy);
      canvas.rotate(angle * pi / 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-3, -8, 6, 16),
          const Radius.circular(3),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      oldDelegate.topPadding != topPadding;
}

// 不正解時の見出し背景。漫画の「ガーン」表現のように、
// 紺から水色へのグラデーションに、上から垂れる縦線と下端の波を重ねる。
class _GloomPainter extends CustomPainter {
  const _GloomPainter();

  static const _topColor = Color(0xFF2E3B55);
  static const _bottomColor = Color(0xFF6FB6E0);
  static const _waveColor = Color(0xFF8CC6E8);
  static const _lineColor = Color(0xFF26324A);

  @override
  void paint(Canvas canvas, Size size) {
    // 下端は波で切り取り、下のページ背景へなじませる。
    final waveTop = size.height - 22;
    final shape = Path()..lineTo(size.width, 0);
    _addWave(shape, size.width, waveTop, 10, reverse: true);
    shape.close();

    canvas.drawPath(
      shape,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_topColor, _bottomColor],
        ).createShader(Offset.zero & size),
    );

    // 少し上にもう一段、明るい波を重ねて奥行きを出す。
    final wave = Path()..moveTo(0, waveTop - 14);
    _addWave(wave, size.width, waveTop - 14, 8);
    wave
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.save();
    canvas.clipPath(shape);
    canvas.drawPath(wave, Paint()..color = _waveColor.withValues(alpha: 0.5));
    canvas.restore();

    // 縦線の長さは毎回同じになるよう固定シードで決める。
    final random = Random(7);
    final linePaint = Paint()
      ..color = _lineColor.withValues(alpha: 0.75)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    const spacing = 14.0;
    for (var x = spacing / 2; x < size.width; x += spacing) {
      final length = size.height * (0.35 + random.nextDouble() * 0.4);
      canvas.drawLine(Offset(x, -4), Offset(x, length), linePaint);
    }
  }

  void _addWave(
    Path path,
    double width,
    double baseY,
    double amplitude, {
    bool reverse = false,
  }) {
    const waveLength = 180.0;
    final steps = (width / 4).ceil();
    for (var i = 0; i <= steps; i++) {
      final x = reverse ? width - i * width / steps : i * width / steps;
      path.lineTo(x, baseY + sin(x / waveLength * 2 * pi) * amplitude);
    }
  }

  @override
  bool shouldRepaint(covariant _GloomPainter oldDelegate) => false;
}
