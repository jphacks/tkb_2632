import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'guess.dart';

const quizInkColor = Color(0xFF241616);
const quizCoralColor = Color(0xFFFF6048);
const _titleColor = Color(0xFF0C1120);
const _buttonColor = Color(0xFFFF745F);
const _buttonDisabledColor = Color(0xFFCCCCCC);
const _cardBorderColor = Color(0xFFE9E9E9);
const _photoPlaceholderColor = Color(0xFFE1E1E1);
const _labelBackgroundColor = Color(0xFFF2EFED);
const _labelTextColor = Color(0xFF8B8E92);

// 2択クイズの回答画面（表示とユーザー操作のみ）。
// 選択状態は GuessQuiz が持ち、変更は onSelect で親に通知する。
// カードのタップは選択の切り替えだけで、回答の確定は下部のボタンで行う。
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
            const QuizTitleBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    const SizedBox(height: 50),
                    Text(
                      '$partnerNameが選んだのは、\nどの１枚？',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        height: 1.5,
                        fontWeight: FontWeight.bold,
                        color: quizInkColor,
                      ),
                    ),
                    const SizedBox(height: 48),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < quiz.candidates.length; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          Expanded(
                            child: _CandidateCard(
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
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            QuizPrimaryButton(
              label: 'この写真だと思う！',
              // 未選択の間は押せない。
              onPressed: quiz.hasSelection ? onSubmit : null,
            ),
          ],
        ),
      ),
    );
  }
}

// クイズ・結果画面で共通の上部タイトル。
class QuizTitleBar extends StatelessWidget {
  const QuizTitleBar({super.key, this.color});

  // 省略時は通常の文字色。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: Center(
        child: Text(
          'クイズ',
          style: TextStyle(
            fontSize: 16,
            height: 22 / 16,
            fontWeight: FontWeight.w600,
            color: color ?? _titleColor,
          ),
        ),
      ),
    );
  }
}

// クイズ・結果画面で共通の下部ボタン。
class QuizPrimaryButton extends StatelessWidget {
  const QuizPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 40),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: _buttonColor,
            foregroundColor: Colors.white,
            disabledBackgroundColor: _buttonDisabledColor,
            disabledForegroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(36),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: Text(label),
        ),
      ),
    );
  }
}

// 写真と記号（A/B）を載せたカード。カード全体がタップ領域。
class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
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
    return Semantics(
      button: true,
      selected: isSelected,
      label: '選択肢$label',
      child: GestureDetector(
        onTap: onSelect,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isSelected ? quizCoralColor : _cardBorderColor,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
                child: AspectRatio(
                  aspectRatio: 175 / 220,
                  child: GuessPhoto(bytes: candidate.imageBytes),
                ),
              ),
              SizedBox(
                height: 49,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected
                          ? quizCoralColor
                          : _labelBackgroundColor,
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 16,
                        height: 1,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.white : _labelTextColor,
                      ),
                    ),
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

// 画像データが不正でもクラッシュせず、プレースホルダーを表示する。
class GuessPhoto extends StatelessWidget {
  const GuessPhoto({super.key, required this.bytes});

  final Uint8List? bytes;

  @override
  Widget build(BuildContext context) {
    const placeholder = ColoredBox(
      color: _photoPlaceholderColor,
      child: Center(
        child: Icon(Icons.broken_image_outlined, color: _labelTextColor),
      ),
    );

    final data = bytes;

    if (data == null) {
      return placeholder;
    }

    return Image.memory(
      data,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => placeholder,
    );
  }
}
