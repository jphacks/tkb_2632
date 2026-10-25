import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

const favoriteReasonLabels = <String, String>{
  'expression': '表情',
  'composition': '構図',
  'size': '人物の大きさ',
  'background': '背景',
  'light': '光',
  'mood': '雰囲気',
};

class QuizPhoto {
  const QuizPhoto({
    required this.id,
    required this.bytes,
  });

  // Storage上のパスを写真IDとして使用する。
  final String id;
  final Uint8List bytes;
}

class QuizPayload {
  const QuizPayload({
    required this.pairId,
    required this.sessionId,
    required this.photos,
    required this.correctPhotoId,
    required this.reasonLabels,
  });

  final String pairId;
  final String sessionId;

  // 順番はお気に入り確定時に保存した順番。
  final List<QuizPhoto> photos;

  final String correctPhotoId;
  final List<String> reasonLabels;
}

class FavoriteService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  String get uid {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw StateError('ユーザー情報を確認できません。');
    }

    return user.uid;
  }

  DocumentReference<Map<String, dynamic>> sessionRef(
    String pairId,
    String sessionId,
  ) {
    return _db
        .collection('pairs')
        .doc(pairId)
        .collection('sessions')
        .doc(sessionId);
  }

  DocumentReference<Map<String, dynamic>> feedbackRef(
    String pairId,
    String sessionId,
  ) {
    return sessionRef(pairId, sessionId)
        .collection('feedback')
        .doc('selection');
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchNotifications() {
    return _db
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .snapshots();
  }

  Future<void> markRead(String notificationId) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .doc(notificationId)
        .update({'read': true});
  }

  // true: 今回確定した
  // false: すでに確定済みだった
  Future<bool> submit({
    required String pairId,
    required String sessionId,
    required Map<String, Set<String>> selections,
  }) async {
    final currentUid = uid;

    // 呼び出し後にUI側で変更されても影響しないようコピーする。
    final selected = <String, Set<String>>{
      for (final entry in selections.entries)
        entry.key: Set<String>.from(entry.value),
    };

    if (selected.isEmpty || selected.length > 30) {
      throw StateError('お気に入りを1枚以上選んでください。');
    }

    for (final reasons in selected.values) {
      if (reasons.isEmpty ||
          reasons.any(
            (reason) => !favoriteReasonLabels.containsKey(reason),
          )) {
        throw StateError('各写真の好きな理由を1つ以上選んでください。');
      }
    }

    final feedback = feedbackRef(pairId, sessionId);
    final session = sessionRef(pairId, sessionId);

    return _db.runTransaction<bool>((transaction) async {
      final existing = await transaction.get(feedback);

      // 通信の再試行でも、通知やクイズを作り直さない。
      if (existing.exists) {
        return false;
      }

      final sessionSnapshot = await transaction.get(session);
      final data = sessionSnapshot.data();

      if (data == null || data['status'] != 'shared') {
        throw StateError('共有済みの写真を確認できません。');
      }

      final authorUid = data['authorUid'] as String;

      if (authorUid == currentUid) {
        throw StateError('撮ってもらった写真から選んでください。');
      }

      final allPaths = List<String>.from(data['photoPaths'] as List);
      final favorites = selected.keys.toList();

      if (favorites.any((path) => !allPaths.contains(path))) {
        throw StateError('撮影セットに含まれていない写真があります。');
      }

      final random = Random.secure();
      final correctPath = favorites[random.nextInt(favorites.length)];

      final nonFavorites = allPaths
          .where((path) => !selected.containsKey(path))
          .toList()
        ..shuffle(random);

      // クイズは2択（正解1枚＋お気に入り以外の1枚）。
      final quizAvailable = nonFavorites.isNotEmpty;
      final choices = <String>[];

      if (quizAvailable) {
        choices.addAll([
          correctPath,
          nonFavorites[0],
        ]);
        choices.shuffle(random);
      }

      final reasons = <String, List<String>>{
        for (final reason in favoriteReasonLabels.keys)
          reason: [
            for (final entry in selected.entries)
              if (entry.value.contains(reason)) entry.key,
          ],
      };

      final notification = _db
          .collection('users')
          .doc(authorUid)
          .collection('notifications')
          .doc('${pairId}_$sessionId');

      transaction.set(feedback, {
        'authorUid': authorUid,
        'selectedByUid': currentUid,
        'favorites': favorites,
        'reasons': reasons,
        'correctPath': correctPath,
        'choices': choices,
        'quizAvailable': quizAvailable,
        'createdAt': FieldValue.serverTimestamp(),
      });

      transaction.set(notification, {
        'pairId': pairId,
        'sessionId': sessionId,
        'quizAvailable': quizAvailable,
        'createdAt': FieldValue.serverTimestamp(),
        'read': false,
      });

      return true;
    });
  }

  // クイズ担当者の画面へ渡すデータを取得する。
  // 不正解候補がない場合はnull。
  Future<QuizPayload?> loadQuiz({
    required String pairId,
    required String sessionId,
  }) async {
    final document = await feedbackRef(pairId, sessionId).get(
      const GetOptions(source: Source.server),
    );

    final data = document.data();

    if (data == null) {
      throw StateError('お気に入り情報が見つかりません。');
    }

    if (data['authorUid'] != uid) {
      throw StateError('このクイズは撮影した人が開けます。');
    }

    if (data['quizAvailable'] != true) {
      return null;
    }

    final correctPath = data['correctPath'] as String;
    final paths = List<String>.from(data['choices'] as List);

    // 3択で保存された過去のクイズは、正解と残りの先頭1枚で2択にする。
    if (paths.length > 2) {
      final other = paths.firstWhere((path) => path != correctPath);
      paths.retainWhere((path) => path == correctPath || path == other);
    }
    final reasonMap = Map<String, dynamic>.from(data['reasons'] as Map);

    final photos = await Future.wait(
      paths.map((path) async {
        final bytes = await _storage
            .ref(path)
            .getData(2 * 1024 * 1024)
            .timeout(const Duration(seconds: 30));

        if (bytes == null) {
          throw StateError('クイズの写真を読み込めませんでした。');
        }

        return QuizPhoto(id: path, bytes: bytes);
      }),
    );

    return QuizPayload(
      pairId: pairId,
      sessionId: sessionId,
      photos: photos,
      correctPhotoId: correctPath,
      reasonLabels: [
        for (final entry in favoriteReasonLabels.entries)
          if ((reasonMap[entry.key] as List? ?? []).contains(correctPath))
            entry.value,
      ],
    );
  }
}