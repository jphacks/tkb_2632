import 'dart:typed_data';

// 2択クイズの内部処理（選択状態・正誤判定・選択肢記号）。
// UIとFirebaseには依存しない。
// 正誤判定は画面表示のためのローカル比較のみで、結果の保存は呼び出し元の責任。

// クイズの候補写真1件。
// photoId は Firebase Storage のパスをそのまま使う。
class GuessCandidate {
  const GuessCandidate({required this.photoId, required this.imageBytes});

  final String photoId;
  final Uint8List imageBytes;
}

// 0 → A, 1 → B
String guessLabelForIndex(int index) => String.fromCharCode(0x41 + index);

class GuessQuiz {
  GuessQuiz({
    required List<GuessCandidate> candidates,
    required this.correctPhotoId,
  }) : candidates = List.unmodifiable(candidates);

  // 呼び出し元でシャッフル済みの並びをそのまま使う。
  final List<GuessCandidate> candidates;
  final String correctPhotoId;

  String? _selectedPhotoId;

  String? get selectedPhotoId => _selectedPhotoId;

  bool get hasSelection => _selectedPhotoId != null;

  bool get isCorrect =>
      _selectedPhotoId != null && _selectedPhotoId == correctPhotoId;

  // 候補に含まれないIDは無視する。
  void select(String photoId) {
    if (candidates.any((candidate) => candidate.photoId == photoId)) {
      _selectedPhotoId = photoId;
    }
  }

  bool isSelected(String photoId) => _selectedPhotoId == photoId;

  // 正解IDが候補に含まれない場合は null。
  GuessCandidate? get correctCandidate {
    for (final candidate in candidates) {
      if (candidate.photoId == correctPhotoId) return candidate;
    }
    return null;
  }

  // 写真IDに対応する選択肢記号。候補に含まれない場合は null。
  String? labelOf(String photoId) {
    final index = candidates.indexWhere(
      (candidate) => candidate.photoId == photoId,
    );
    return index == -1 ? null : guessLabelForIndex(index);
  }
}
