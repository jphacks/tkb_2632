import 'package:flutter/material.dart';

import '../guess.dart';
import '../guess_src.dart';
import 'guess_result_screen.dart';

export '../guess.dart' show GuessCandidate;

// 外部統合用の2択クイズ画面。
//
// 使い方:
//   final selectedPhotoId = await Navigator.of(context).push<String>(
//     MaterialPageRoute(
//       builder: (_) => GuessScreen(
//         candidates: candidates, // 呼び出し元でシャッフル済みの2件
//         correctPhotoId: correctPhotoId,
//         reasonTags: reasonTags,
//         partnerName: partnerName,
//       ),
//     ),
//   );
//
// 結果画面を閉じると（端末の戻る操作・下部ボタンのいずれでも）
// Navigator.pop(context, selectedPhotoId) で選択した写真IDを返す。
// 回答前に戻った場合は null を返す。
// 回答の保存・正誤結果の永続化は呼び出し元の責任。
class GuessScreen extends StatefulWidget {
  const GuessScreen({
    super.key,
    required this.candidates,
    required this.correctPhotoId,
    required this.reasonTags,
    required this.partnerName,
  });

  final List<GuessCandidate> candidates;
  final String correctPhotoId;
  final List<String> reasonTags;

  // お気に入りを選んだ相手のニックネーム。
  final String partnerName;

  @override
  State<GuessScreen> createState() => _GuessScreenState();
}

class _GuessScreenState extends State<GuessScreen> {
  late final GuessQuiz _quiz = GuessQuiz(
    candidates: widget.candidates,
    correctPhotoId: widget.correctPhotoId,
  );

  // 結果画面は別ルートにせず、この画面内で切り替える。
  // これにより、どの経路で閉じても選択IDを1回のpopで確実に返せる。
  bool _showResult = false;

  void _select(String photoId) {
    setState(() => _quiz.select(photoId));
  }

  void _submit() {
    if (!_quiz.hasSelection) return;
    setState(() => _showResult = true);
  }

  void _finish() {
    Navigator.of(context).pop(_quiz.selectedPhotoId);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<String>(
      // 結果画面表示中は、端末の戻る操作も _finish 経由で選択IDを返す。
      canPop: !_showResult,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _finish();
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _showResult ? _buildResult() : _buildAnswer(),
      ),
    );
  }

  Widget _buildAnswer() {
    return GuessAnswerView(
      key: const ValueKey('answer'),
      quiz: _quiz,
      partnerName: widget.partnerName,
      onSelect: _select,
      onSubmit: _submit,
    );
  }

  Widget _buildResult() {
    return GuessResultScreen(
      key: const ValueKey('result'),
      isCorrect: _quiz.isCorrect,
      partnerName: widget.partnerName,
      correctLabel: _quiz.labelOf(widget.correctPhotoId) ?? '?',
      correctPhotoBytes: _quiz.correctCandidate?.imageBytes,
      reasonTags: widget.reasonTags,
      onClose: _finish,
    );
  }
}
