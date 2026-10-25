import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'favorite_service.dart';

class SharedPhoto {
  const SharedPhoto({
    required this.path,
    required this.sessionId,
    required this.authorUid,
    required this.sharedAt,
  });

  final String path;
  final String sessionId;
  final String authorUid;
  final DateTime? sharedAt;
}

// アップロードがすべて完了した撮影セットだけを取得する。
// 日付順の並べ替えはアプリ側で行い、複合インデックスを不要にする。
Stream<List<SharedPhoto>> watchSharedPhotos(String pairId) {
  return FirebaseFirestore.instance
      .collection('pairs')
      .doc(pairId)
      .collection('sessions')
      .where('status', isEqualTo: 'shared')
      .snapshots()
      .map((snapshot) {
        final sessions = snapshot.docs.toList();

        DateTime? dateOf(Map<String, dynamic> data) {
          final value = data['sharedAt'] ?? data['createdAt'];
          return value is Timestamp ? value.toDate() : null;
        }

        sessions.sort((a, b) {
          final aDate = dateOf(a.data());
          final bDate = dateOf(b.data());

          return (bDate?.millisecondsSinceEpoch ?? 0).compareTo(
            aDate?.millisecondsSinceEpoch ?? 0,
          );
        });

        final photos = <SharedPhoto>[];

        for (final session in sessions) {
          final data = session.data();
          final authorUid = data['authorUid'];
          final paths = data['photoPaths'];

          if (authorUid is! String || paths is! List) continue;

          for (final path in paths.whereType<String>()) {
            photos.add(
              SharedPhoto(
                path: path,
                sessionId: session.id,
                authorUid: authorUid,
                sharedAt: dateOf(data),
              ),
            );
          }
        }

        return photos;
      });
}

enum LikeStatus {
  // いいねしていない。
  none,
  // いいね済み・未送信（理由の変更や取り消しができる）。
  draft,
  // 送信済み（変更できない）。
  sent,
}

// 1組のペアのアルバムと、自分のいいねの状態をまとめて監視する。
// ホーム・アルバム・拡大表示で同じインスタンスを共有する。
class AlbumController extends ChangeNotifier {
  AlbumController({required this.pairId, required this.myUid}) {
    _photosSubscription = watchSharedPhotos(pairId).listen(
      _onPhotos,
      onError: (Object error) {
        _error = error;
        notifyListeners();
      },
    );
  }

  final String pairId;
  final String myUid;

  final _service = FavoriteService();

  StreamSubscription<List<SharedPhoto>>? _photosSubscription;

  // 撮ってもらった撮影セットごとの購読（送信済み・下書き）。
  final _feedbackSubscriptions =
      <String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>{};
  final _draftSubscriptions =
      <String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>{};

  List<SharedPhoto>? _photos;
  Object? _error;

  // 撮影セットID → 送信済みのお気に入りのパス。
  final _sent = <String, Set<String>>{};

  // 撮影セットID → { 写真のパス: 理由キー }。
  final _drafts = <String, Map<String, Set<String>>>{};

  // 「どこが好き？」を開いている間だけ、ハートを押した状態で表示する。
  String? _pendingPath;

  bool _sending = false;

  List<SharedPhoto>? get photos => _photos;
  Object? get error => _error;
  bool get sending => _sending;

  bool isReceived(SharedPhoto photo) => photo.authorUid != myUid;

  LikeStatus statusOf(SharedPhoto photo) {
    if (_sent[photo.sessionId]?.contains(photo.path) ?? false) {
      return LikeStatus.sent;
    }

    if (_drafts[photo.sessionId]?.containsKey(photo.path) ?? false) {
      return LikeStatus.draft;
    }

    return LikeStatus.none;
  }

  // ハートを押した状態で表示するか。
  bool isLiked(SharedPhoto photo) {
    return photo.path == _pendingPath || statusOf(photo) != LikeStatus.none;
  }

  Set<String> draftReasonsOf(SharedPhoto photo) {
    return Set<String>.from(
      _drafts[photo.sessionId]?[photo.path] ?? const <String>{},
    );
  }

  List<SharedPhoto> get receivedPhotos {
    return [...?_photos?.where(isReceived)];
  }

  // 自分がいいねした写真（送信済み・未送信の両方）。新しい順。
  List<SharedPhoto> get likedPhotos {
    return [
      ...?_photos?.where(
        (photo) => isReceived(photo) && statusOf(photo) != LikeStatus.none,
      ),
    ];
  }

  // 未送信のいいねの枚数。
  int get unsentCount {
    return _drafts.entries
        .where((entry) => !_sent.containsKey(entry.key))
        .fold(0, (total, entry) => total + entry.value.length);
  }

  set pendingPath(String? path) {
    if (_pendingPath == path) return;
    _pendingPath = path;
    notifyListeners();
  }

  void _onPhotos(List<SharedPhoto> photos) {
    _photos = photos;
    _error = null;

    final receivedSessions = photos
        .where(isReceived)
        .map((photo) => photo.sessionId)
        .toSet();

    for (final sessionId in receivedSessions) {
      _feedbackSubscriptions.putIfAbsent(
        sessionId,
        () => _service
            .feedbackRef(pairId, sessionId)
            .snapshots()
            .listen(
              (document) {
                final data = document.data();

                if (data == null) {
                  _sent.remove(sessionId);
                } else {
                  _sent[sessionId] = Set<String>.from(
                    data['favorites'] as List? ?? const [],
                  );
                }

                notifyListeners();
              },
              onError: (Object error) {
                debugPrint('お気に入りの取得エラー: $error');
              },
            ),
      );

      _draftSubscriptions.putIfAbsent(
        sessionId,
        () => _service
            .likeDraftRef(pairId, sessionId)
            .snapshots()
            .listen(
              (document) {
                // 書き込み直後の自分の変更は、ローカルの状態を正とする。
                if (document.metadata.hasPendingWrites) return;

                final selections = document.data()?['selections'];

                if (selections is Map && selections.isNotEmpty) {
                  _drafts[sessionId] = {
                    for (final entry in selections.entries)
                      if (entry.key is String && entry.value is List)
                        entry.key as String: Set<String>.from(
                          (entry.value as List).whereType<String>(),
                        ),
                  };
                } else {
                  _drafts.remove(sessionId);
                }

                notifyListeners();
              },
              onError: (Object error) {
                debugPrint('いいねの下書きの取得エラー: $error');
              },
            ),
      );
    }

    notifyListeners();
  }

  // 理由を保存する。空なら、いいね自体を取り消す。
  Future<void> setDraftReasons(SharedPhoto photo, Set<String> reasons) async {
    if (statusOf(photo) == LikeStatus.sent) {
      throw StateError('送信済みの「好き」は変更できません。');
    }

    final sessionId = photo.sessionId;
    final previous = _drafts[sessionId] == null
        ? null
        : {
            for (final entry in _drafts[sessionId]!.entries)
              entry.key: Set<String>.from(entry.value),
          };

    final next = {...?previous};

    if (reasons.isEmpty) {
      next.remove(photo.path);
    } else {
      next[photo.path] = Set<String>.from(reasons);
    }

    if (next.isEmpty) {
      _drafts.remove(sessionId);
    } else {
      _drafts[sessionId] = next;
    }

    notifyListeners();

    final reference = _service.likeDraftRef(pairId, sessionId);

    try {
      if (next.isEmpty) {
        await reference.delete();
      } else {
        await reference.set({
          'selections': {
            for (final entry in next.entries)
              entry.key: [
                for (final key in favoriteReasonLabels.keys)
                  if (entry.value.contains(key)) key,
              ],
          },
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (_) {
      if (previous == null) {
        _drafts.remove(sessionId);
      } else {
        _drafts[sessionId] = previous;
      }

      notifyListeners();
      rethrow;
    }
  }

  // 未送信のいいねを、撮影セットごとにまとめて送る。
  // 送信できた枚数を返す。
  Future<int> sendAll() async {
    if (_sending) return 0;

    _sending = true;
    notifyListeners();

    var sentCount = 0;

    try {
      final pending = {
        for (final entry in _drafts.entries)
          if (!_sent.containsKey(entry.key) && entry.value.isNotEmpty)
            entry.key: {
              for (final selection in entry.value.entries)
                selection.key: Set<String>.from(selection.value),
            },
      };

      for (final entry in pending.entries) {
        await _service.submit(
          pairId: pairId,
          sessionId: entry.key,
          selections: entry.value,
        );

        sentCount += entry.value.length;
      }

      return sentCount;
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _photosSubscription?.cancel();

    for (final subscription in _feedbackSubscriptions.values) {
      subscription.cancel();
    }

    for (final subscription in _draftSubscriptions.values) {
      subscription.cancel();
    }

    super.dispose();
  }
}

// 「18 May 2026」形式の日付。
String albumDate(DateTime? date) {
  if (date == null) return '';

  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  final local = date.toLocal();
  return '${local.day} ${months[local.month - 1]} ${local.year}';
}
