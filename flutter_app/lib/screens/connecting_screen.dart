import 'package:flutter/material.dart';

class ConnectingScreen extends StatelessWidget {
  const ConnectingScreen({
    super.key,
    required this.onStart,
  });

  // 「二人のつながりを始める」「参加する」「コード・QRで参加」の共通遷移先。
  final VoidCallback onStart;

  static const _ink = Color(0xFF2B2220);
  static const _muted = Color(0xFF8A7F7B);
  static const _coral = Color(0xFFFF7360);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFF3DDD5),
                    Colors.white,
                  ],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Stack(
                  children: [
                    const Positioned.fill(child: _PlaceholderArtwork()),
                    Positioned(
                      top: 8,
                      right: 16,
                      child: _JoinChip(onPressed: onStart),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
              child: Column(
                children: [
                  const Text(
                    'ふたりでつないで、\n写真を撮る。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      height: 1.6,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: onStart,
                      style: FilledButton.styleFrom(
                        backgroundColor: _coral,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      child: const Text('二人のつながりを始める'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: onStart,
                    style: TextButton.styleFrom(foregroundColor: _muted),
                    child: const Text(
                      'コード・QRで参加',
                      style: TextStyle(fontSize: 13),
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
}

class _JoinChip extends StatelessWidget {
  const _JoinChip({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.85),
      shape: const StadiumBorder(),
      child: InkWell(
        onTap: onPressed,
        customBorder: const StadiumBorder(),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people, size: 20, color: Color(0xFF2B2220)),
              SizedBox(width: 6),
              Text(
                '参加する',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2B2220),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// TODO【要差し替え】：デザインの写真・スマホ画像が届いたら置き換える。
class _PlaceholderArtwork extends StatelessWidget {
  const _PlaceholderArtwork();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: -width * 0.12,
              top: height * 0.06,
              child: _tilted(
                -0.12,
                _PlaceholderFrame(
                  width: width * 0.6,
                  height: height * 0.42,
                  radius: 28,
                ),
              ),
            ),
            Positioned(
              left: width * 0.32,
              top: height * 0.3,
              child: _tilted(
                0.1,
                _PlaceholderFrame(
                  width: width * 0.36,
                  height: width * 0.28,
                  radius: 4,
                ),
              ),
            ),
            Positioned(
              right: -width * 0.06,
              bottom: height * 0.04,
              child: _tilted(
                -0.12,
                _PlaceholderFrame(
                  width: width * 0.5,
                  height: height * 0.42,
                  radius: 28,
                ),
              ),
            ),
            Positioned(
              left: width * 0.12,
              top: height * 0.56,
              child: _tilted(
                0.12,
                _PlaceholderFrame(
                  width: width * 0.36,
                  height: width * 0.28,
                  radius: 4,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _tilted(double angle, Widget child) {
    return Transform.rotate(angle: angle, child: child);
  }
}

class _PlaceholderFrame extends StatelessWidget {
  const _PlaceholderFrame({
    required this.width,
    required this.height,
    required this.radius,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFE4E1DF),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.white, width: 6),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: const Icon(
        Icons.image_outlined,
        size: 32,
        color: Color(0xFFB9B4B1),
      ),
    );
  }
}
