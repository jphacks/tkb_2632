import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../guess_src.dart';

const _resultMutedColor = Color(0xFF8B8E92);
const _cardBorderColor = Color(0xFFE9E9E9);
const _correctBadgeColor = Color(0xFFFF745F);
const _tagBackgroundColor = Color(0xFFE5F7F5);
const _tagBorderColor = Color(0xFF5DC7C1);
const _tagTextColor = Color(0xFF098C85);

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
  // 呼び出し元の通知一覧が、その後に撮影カルテを開く。
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isCorrect
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      SizedBox(height: isCorrect ? 46 : 22),
                      _buildHeadline(),
                      const SizedBox(height: 12),
                      Text(
                        isCorrect
                            ? '$partnerNameも、$correctLabelを選んでいました。'
                            : '$partnerNameは、$correctLabelを選んでいました。',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          height: 36 / 16,
                          fontWeight: FontWeight.bold,
                          color: quizInkColor,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _buildPhotoCard(),
                      // 記号の円がカードの下にはみ出す分を含む。
                      const SizedBox(height: 40),
                      _buildReasonTags(),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
              QuizPrimaryButton(
                label: '撮影カルテ',
                onPressed: onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;

    return SizedBox(
      height: topPadding + (isCorrect ? 60 : 84),
      child: Stack(
        children: [
          if (!isCorrect)
            const Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _GloomPainter()),
              ),
            ),
          Padding(
            padding: EdgeInsets.only(top: topPadding),
            child: QuizTitleBar(
              color: isCorrect ? null : Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeadline() {
    final headline = Text(
      isCorrect ? '正解！' : '惜しい！',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: isCorrect ? 36 : 32,
        height: 1,
        fontWeight: FontWeight.bold,
        color: quizCoralColor,
      ),
    );

    if (!isCorrect) {
      return headline;
    }

    return SizedBox(
      height: 36,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _ConfettiPainter(centerY: 18),
              ),
            ),
          ),
          headline,
        ],
      ),
    );
  }

  Widget _buildPhotoCard() {
    return SizedBox(
      width: 204,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          Container(
            height: 286,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isCorrect ? quizCoralColor : _cardBorderColor,
                width: 2,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: SizedBox.expand(
                child: GuessPhoto(bytes: correctPhotoBytes),
              ),
            ),
          ),
          Positioned(
            bottom: -18,
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isCorrect ? _correctBadgeColor : _cardBorderColor,
              ),
              child: Text(
                correctLabel,
                style: TextStyle(
                  fontSize: 20,
                  height: 1,
                  fontWeight: FontWeight.bold,
                  color: isCorrect ? Colors.white : _resultMutedColor,
                ),
              ),
            ),
          ),
        ],
      ),
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
      spacing: 12,
      runSpacing: 10,
      children: [
        for (final tag in tags)
          Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: _tagBackgroundColor,
              borderRadius: BorderRadius.circular(500),
              border: Border.all(color: _tagBorderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: _tagTextColor,
                ),
                const SizedBox(width: 4),
                Text(
                  tag,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _tagTextColor,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  const _ConfettiPainter({
    required this.centerY,
  });

  // 紙吹雪を散らす中心（見出しの縦中央）。
  final double centerY;

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
    final center = Offset(size.width / 2, centerY);

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
    return oldDelegate.centerY != centerY;
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