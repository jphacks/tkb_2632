import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image/image.dart' as img;

// 撮影画像をプレビューに合わせた比率で切り抜き、JPEGへ縮小する。
Uint8List prepareSessionPhoto(
  Uint8List input,
  double targetAspectRatio,
) {
  final decoded = img.decodeImage(input);

  if (decoded == null) {
    throw const FormatException('撮影した写真を読み込めませんでした。');
  }

  final oriented = img.bakeOrientation(decoded);
  final sourceAspect = oriented.width / oriented.height;

  late final img.Image cropped;

  if (sourceAspect > targetAspectRatio) {
    final cropWidth = (oriented.height * targetAspectRatio)
        .round()
        .clamp(1, oriented.width)
        .toInt();

    cropped = img.copyCrop(
      oriented,
      x: (oriented.width - cropWidth) ~/ 2,
      y: 0,
      width: cropWidth,
      height: oriented.height,
    );
  } else {
    final cropHeight = (oriented.width / targetAspectRatio)
        .round()
        .clamp(1, oriented.height)
        .toInt();

    cropped = img.copyCrop(
      oriented,
      x: 0,
      y: (oriented.height - cropHeight) ~/ 2,
      width: oriented.width,
      height: cropHeight,
    );
  }

  final longestSide = cropped.width > cropped.height
      ? cropped.width
      : cropped.height;

  final resized = longestSide > 1600
      ? img.copyResize(
          cropped,
          width: (cropped.width * 1600 / longestSide).round(),
          height: (cropped.height * 1600 / longestSide).round(),
        )
      : cropped;

  for (final quality in [85, 70, 55]) {
    final bytes = img.encodeJpg(resized, quality: quality);

    if (bytes.length <= 2 * 1024 * 1024) {
      return bytes;
    }
  }

  throw const FormatException(
    '写真を十分に縮小できませんでした。',
  );
}

class PhotoSessionUploader {
  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  DocumentReference<Map<String, dynamic>>? _sessionRef;
  List<String> _paths = [];
  final Set<int> _completedUploads = {};

  String get _uid {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw StateError('ログイン状態を確認できません。');
    }

    return user.uid;
  }

  Future<void> share(
    List<Uint8List> photos, {
    required void Function(int completed, int total) onProgress,
  }) async {
    if (photos.isEmpty || photos.length > 30) {
      throw StateError('1セットの写真は1〜30枚にしてください。');
    }

    final uid = _uid;

    if (_sessionRef == null) {
      final membership = await _db
          .collection('memberships')
          .doc(uid)
          .get(const GetOptions(source: Source.server));

      final pairId = membership.data()?['pairId'];

      if (pairId is! String) {
        throw StateError('先に相手とペア登録してください。');
      }

      final ref = _db
          .collection('pairs')
          .doc(pairId)
          .collection('sessions')
          .doc();

      _sessionRef = ref;

      _paths = List.generate(
        photos.length,
        (index) => 'pairs/$pairId/sessions/${ref.id}/$index.jpg',
      );
    }

    if (_paths.length != photos.length) {
      throw StateError('再送時は同じ撮影セットを使用してください。');
    }

    final ref = _sessionRef!;

    // 初回だけセットを作る。
    // 共有の確定まで届いていた場合は、再アップロードしない。
    final alreadyShared =
        await _db.runTransaction<bool>((transaction) async {
      final existing = await transaction.get(ref);

      if (existing.exists) {
        final data = existing.data()!;

        if (data['authorUid'] != uid) {
          throw StateError('撮影者の情報が一致しません。');
        }

        return data['status'] == 'shared';
      }

      transaction.set(ref, {
        'authorUid': uid,
        'createdAt': FieldValue.serverTimestamp(),
        'photoPaths': _paths,
        'status': 'uploading',
      });

      return false;
    });

    if (alreadyShared) return;

    onProgress(_completedUploads.length, photos.length);

    for (var index = 0; index < photos.length; index++) {
      if (_completedUploads.contains(index)) continue;

      await _storage.ref(_paths[index]).putData(
            photos[index],
            SettableMetadata(contentType: 'image/jpeg'),
          );

      _completedUploads.add(index);
      onProgress(_completedUploads.length, photos.length);
    }

    // 全画像のアップロード成功後に、アルバムへ公開する。
    await ref.update({
      'status': 'shared',
      'sharedAt': FieldValue.serverTimestamp(),
    });
  }

  // 未共有のアップロードを破棄する。
  Future<void> discard() async {
    final ref = _sessionRef;

    if (ref == null) return;

    final document = await ref.get(
      const GetOptions(source: Source.server),
    );

    if (!document.exists) return;

    // 共有済みの写真は、この操作では削除しない。
    if (document.data()?['status'] == 'shared') return;

    for (final path in _paths) {
      try {
        await _storage.ref(path).delete();
      } on FirebaseException catch (error) {
        if (error.code != 'object-not-found') rethrow;
      }
    }

    await ref.delete();
  }
}