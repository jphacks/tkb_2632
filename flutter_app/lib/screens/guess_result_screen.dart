import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  final Uint8List? correctPhotoBytes;
  final List<String> reasonTags;

  // クイズを閉じる。
  // 呼び出し元のFocusShellが、その後に撮影カルテを開く。
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isCorrect
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _resultBackgroundColor,
        body: SafeArea(
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
                      const Text(
                        '相手の「好き」を撮影カルテで振り返って、'
                        '次の一枚に生かしてみよう。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _resultMutedColor,
                          height: 1.7,
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
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
                    child: const Text('撮影カルテを見る'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                      ),
                      color: foregroundColor,
                      tooltip: '撮影カルテへ',
                    ),
                  ),
                  Center(
                    child: Text(
                      isCorrect ? '正解！' : '残念！',
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w900,
                        color: isCorrect
                            ? _resultCoralColor
                            : foregroundColor,
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
        child: Icon(
          Icons.broken_image_outlined,
          color: _resultMutedColor,
        ),
      ),
    );

    final bytes = correctPhotoBytes;

    if (bytes == null) {
      return placeholder;
    }

    return Image.memory(
      bytes,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => placeholder,
    );
  }

  Widget _buildReasonTags() {
    final tags = reasonTags
        .where((tag) => tag.trim().isNotEmpty)
        .toList();

    if (tags.isEmpty) {
      return const Text(
        '理由は登録されていません',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13,
          color: _resultMutedColor,
        ),
      );
    }

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 16,
      runSpacing: 10,
      children: [
        for (final tag in tags)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 10,
            ),
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

class _ConfettiPainter extends CustomPainter {
  const _ConfettiPainter({
    required this.topPadding,
  });

  final double topPadding;

  static const _pieces = [
    (-118.0, -22.0, -0.6, Color(0xFFFFC94D)),
    (-150.0, 6.0, 0.9, Color(0xFFFFC94D)),
    (-100.0, 12.0, -0.8, Color(0xFFFF735C)),
    (108.0, -18.0, 0.8, Color(0xFF6CCFD0)),
    (140.0, 4.0, -0.7, Color(0xFFFFC94D)),
    (96.0, 18.0, 0.6, Color(0xFFFF735C)),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(
      size.width / 2,
      topPadding + 40,
    );

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
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) {
    return oldDelegate.topPadding != topPadding;
  }
}

class _GloomPainter extends CustomPainter {
  const _GloomPainter();

  static const _topColor = Color(0xFF2E3B55);
  static const _bottomColor = Color(0xFF6FB6E0);
  static const _waveColor = Color(0xFF8CC6E8);
  static const _lineColor = Color(0xFF26324A);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }

    final waveTop = size.height - 22;

    final shape = Path()
      ..lineTo(size.width, 0);

    _addWave(
      shape,
      size.width,
      waveTop,
      10,
      reverse: true,
    );

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

    final wave = Path()
      ..moveTo(0, waveTop - 14);

    _addWave(
      wave,
      size.width,
      waveTop - 14,
      8,
    );

    wave
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.save();
    canvas.clipPath(shape);

    canvas.drawPath(
      wave,
      Paint()..color = _waveColor.withValues(alpha: 0.5),
    );

    canvas.restore();

    final random = Random(7);

    final linePaint = Paint()
      ..color = _lineColor.withValues(alpha: 0.75)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    const spacing = 14.0;

    for (var x = spacing / 2; x < size.width; x += spacing) {
      final length = size.height *
          (0.35 + random.nextDouble() * 0.4);

      canvas.drawLine(
        Offset(x, -4),
        Offset(x, length),
        linePaint,
      );
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

    if (steps <= 0) {
      return;
    }

    for (var i = 0; i <= steps; i++) {
      final x = reverse
          ? width - i * width / steps
          : i * width / steps;

      path.lineTo(
        x,
        baseY + sin(x / waveLength * 2 * pi) * amplitude,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GloomPainter oldDelegate) {
    return false;
  }
}