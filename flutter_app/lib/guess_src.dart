import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'guess.dart';

const _quizInkColor = Color(0xFF291F1D);
const _quizCoralColor = Color(0xFFFF735C);
const _photoPlaceholderColor = Color(0xFFE0E0E0);
const _labelBackgroundColor = Color(0xFFF1EDEA);
const _labelTextColor = Color(0xFF8F8A87);
const _hintBackgroundColor = Color(0xFFF1F2F4);
const _hintTextColor = Color(0xFF55575C);

// 3択クイズの回答画面（表示とユーザー操作のみ）。
// 選択状態は GuessQuiz が持ち、変更は onSelect で親に通知する。
class GuessAnswerView extends StatelessWidget {
  const GuessAnswerView({
    super.key,
    required this.quiz,
    required this.partnerName,
    required this.onSelect,
    required this.onSubmit,
  });

  final GuessQuiz quiz;
  final String partnerName;
  final ValueChanged<String> onSelect;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            const Text(
              'クイズ🌷',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _quizInkColor,
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    const SizedBox(height: 56),
                    // NOTE: partnerName は現在 'Haruka' の仮置き（guess_screen.dart のTODO参照）。
                    Text(
                      '$partnerNameが選んだのは、\nどの１枚？',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        height: 1.5,
                        fontWeight: FontWeight.w800,
                        color: _quizInkColor,
                      ),
                    ),
                    const SizedBox(height: 48),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < quiz.candidates.length; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          Expanded(
                            child: _CandidateTile(
                              candidate: quiz.candidates[i],
                              label: guessLabelForIndex(i),
                              isSelected: quiz.isSelected(
                                quiz.candidates[i].photoId,
                              ),
                              onSelect: () =>
                                  onSelect(quiz.candidates[i].photoId),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 36),
                    const _HintPill(),
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
                  // 未選択の間は押せない。
                  onPressed: quiz.hasSelection ? onSubmit : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: _quizCoralColor,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _quizCoralColor.withValues(
                      alpha: 0.4,
                    ),
                    disabledForegroundColor: Colors.white,
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  child: const Text('この写真だと思う！'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({
    required this.candidate,
    required this.label,
    required this.isSelected,
    required this.onSelect,
  });

  final GuessCandidate candidate;
  final String label;
  final bool isSelected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ==============================================================
        // TODO【チーム未確認】：写真タップ拡大は暫定仕様。
        //                      確認後に変更する可能性あり。
        // ==============================================================
        GestureDetector(
          onTap: () => showGuessPhotoDialog(context, candidate.imageBytes),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              border: Border.all(
                color: isSelected ? _quizCoralColor : Colors.transparent,
                width: 3,
              ),
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(9),
              ),
              child: AspectRatio(
                aspectRatio: 114 / 203,
                child: _GuessPhoto(bytes: candidate.imageBytes),
              ),
            ),
          ),
        ),
        // 回答の選択は A/B/C のタップで行う。タップ領域は記号より広めに取る。
        Semantics(
          button: true,
          selected: isSelected,
          label: '選択肢$label',
          child: InkResponse(
            onTap: onSelect,
            radius: 24,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? _quizCoralColor : _labelBackgroundColor,
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : _labelTextColor,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HintPill extends StatelessWidget {
  const _HintPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: _hintBackgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lightbulb_outline_rounded,
            size: 22,
            color: _labelTextColor,
          ),
          SizedBox(width: 10),
          Flexible(
            child: Text(
              '写真をタッチすると、大きく見れる',
              style: TextStyle(fontSize: 12, color: _hintTextColor),
            ),
          ),
        ],
      ),
    );
  }
}

// 画像データが不正でもクラッシュせず、プレースホルダーを表示する。
class _GuessPhoto extends StatelessWidget {
  const _GuessPhoto({required this.bytes, this.fit = BoxFit.cover});

  final Uint8List bytes;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return Image.memory(
      bytes,
      fit: fit,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => const ColoredBox(
        color: _photoPlaceholderColor,
        child: Center(
          child: Icon(Icons.broken_image_outlined, color: _labelTextColor),
        ),
      ),
    );
  }
}

// ==============================================================
// TODO【チーム未確認】：写真タップ拡大は暫定仕様。
//                      確認後に変更する可能性あり。
// ==============================================================
Future<void> showGuessPhotoDialog(BuildContext context, Uint8List bytes) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Stack(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: InteractiveViewer(
              maxScale: 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _GuessPhoto(bytes: bytes, fit: BoxFit.contain),
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton.filled(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
              style: IconButton.styleFrom(
                backgroundColor: Colors.black54,
                foregroundColor: Colors.white,
              ),
              tooltip: '閉じる',
            ),
          ),
        ],
      ),
    ),
  );
}
