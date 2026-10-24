import 'dart:math';

import 'package:flutter/material.dart';

import '../services/pair_service.dart';
import '../widgets/profile_avatar.dart';

class ConnectionSuccessScreen extends StatelessWidget {
  const ConnectionSuccessScreen({
    super.key,
    required this.pair,
    required this.onContinue,
  });

  final PairDetails pair;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white,
              Color(0xFFF1F1F1),
            ],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              const Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _ConfettiPainter(),
                  ),
                ),
              ),
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '接続成功！',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF291F1D),
                        ),
                      ),
                      const SizedBox(height: 48),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ProfileAvatar(
                            avatarBase64: pair.myAvatar,
                            size: 88,
                          ),
                          const SizedBox(width: 20),
                          ProfileAvatar(
                            avatarBase64: pair.partnerAvatar,
                            size: 88,
                          ),
                        ],
                      ),
                      const SizedBox(height: 42),
                      Text(
                        '${pair.myName} ＆ ${pair.partnerName} 🌷',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 22,
                          height: 1.6,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF291F1D),
                        ),
                      ),
                      const SizedBox(height: 56),
                      FilledButton(
                        onPressed: onContinue,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFF715E),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 48,
                            vertical: 16,
                          ),
                        ),
                        child: const Text('はじめる'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  const _ConfettiPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final random = Random(18);
    const colors = [
      Color(0xFFFA6B78),
      Color(0xFF4CCBE8),
      Color(0xFFF7DE47),
    ];

    for (var i = 0; i < 24; i++) {
      final x = i.isEven
          ? size.width * (0.02 + random.nextDouble() * 0.18)
          : size.width * (0.80 + random.nextDouble() * 0.18);

      final y = size.height * (0.12 + random.nextDouble() * 0.75);
      final paint = Paint()..color = colors[i % colors.length];

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(random.nextDouble() * pi);

      if (i % 3 == 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(-5, -10, 10, 20),
            const Radius.circular(5),
          ),
          paint,
        );
      } else {
        canvas.drawCircle(Offset.zero, 5, paint);
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => false;
}