import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint, listEquals;
import 'package:image/image.dart' as img;

// 撮影画像をプレビューに合わせた比率で切り抜き、JPEGへ縮小する。
Uint8List prepareSessionPhoto(
  Uint8List input,
  double targetAspectRatio,
) {
  if (!targetAspectRatio.isFinite || targetAspectRatio <= 0) {
    throw const FormatException('写真の縦横比を確認できませんでした。');
  }

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
    final bytes = img.encodeJpg(
      resized,
      quality: quality,
    );

    if (bytes.length <= 2 * 1024 * 1024) {
      return bytes;
    }
  }

  throw const FormatException(
    '写真を十分に縮小できませんでした。',
  );
}

class PhotoSessionUploader {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  static const _idleLimit = Duration(seconds: 60);
  static const _maxPhotoBytes = 2 * 1024 * 1024;

  DocumentReference<Map<String, dynamic>>? _sessionRef;

  List<String> _paths = [];
  List<Uint8List>? _photos;
  String? _ownerUid;

  final Set<int> _completedUploads = {};

  // タイムアウト後も実行中の処理を保持する。
  Future<void>? _pendingOperation;
  String? _pendingKind;

  Completer<void>? _waiter;
  Timer? _idleTimer;

  String _stage = '準備中';

  void Function(int completed, int total)? _onProgress;

  String get _uid {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw StateError('ログイン状態を確認できません。');
    }

    return user.uid;
  }

  void _log(String message) {
    debugPrint('[写真共有] $message');
  }

  void _setStage(String stage) {
    _stage = stage;
    _log('開始：$stage');
    _recordActivity();
  }

  // 処理段階が変わったときや、送信バイト数が増えたときに呼ぶ。
  void _recordActivity() {
    _idleTimer?.cancel();

    final waiter = _waiter;

    if (waiter == null || waiter.isCompleted) {
      return;
    }

    _idleTimer = Timer(_idleLimit, () {
      if (waiter.isCompleted) {
        return;
      }

      _log('タイムアウト：$_stage');

      waiter.completeError(
        TimeoutException(
          '「$_stage」で60秒間進展がありませんでした。\n'
          '通信処理はまだ継続している可能性があります。\n'
          '再試行すると、実行中の処理があればその結果を待ちます。',
          _idleLimit,
        ),
      );
    });
  }

  void _reportProgress() {
    final total = _photos?.length ?? 0;

    _onProgress?.call(
      _completedUploads.length,
      total,
    );
  }

  // 画面側の待ち時間だけを制限する。
  // 元の通信が終わるまでは、新しい処理を重ねて開始しない。
  Future<void> _execute(
    String kind,
    Future<void> Function() operation,
  ) async {
    if (_waiter != null) {
      throw StateError('すでに処理の結果を待っています。');
    }

    if (_pendingOperation != null && _pendingKind != kind) {
      throw StateError(
        '前の処理がまだ終了していません。\n'
        '処理結果を確認してから、もう一度お試しください。',
      );
    }

    final waiter = Completer<void>();
    _waiter = waiter;

    _recordActivity();

    try {
      if (_pendingOperation == null) {
        _pendingKind = kind;

        final pending = Future<void>.sync(operation);
        _pendingOperation = pending;

        // 元の処理の成功・失敗は、タイムアウト後も監視する。
        unawaited(
          pending.then<void>(
            (_) {
              if (!identical(_pendingOperation, pending)) {
                return;
              }

              _pendingOperation = null;
              _pendingKind = null;

              final currentWaiter = _waiter;

              if (currentWaiter != null && !currentWaiter.isCompleted) {
                currentWaiter.complete();
              }
            },
            onError: (Object error, StackTrace stackTrace) {
              if (!identical(_pendingOperation, pending)) {
                return;
              }

              final failedStage = _stage;

              _pendingOperation = null;
              _pendingKind = null;

              _log('失敗：$failedStage');
              _log('詳細：$error');

              final currentWaiter = _waiter;

              if (currentWaiter != null && !currentWaiter.isCompleted) {
                currentWaiter.completeError(
                  StateError(
                    '「$failedStage」で失敗しました。\n$error',
                  ),
                  stackTrace,
                );
              }
            },
          ),
        );
      } else {
        _log('再試行：実行中の「$_stage」の結果を待ちます。');
      }

      await waiter.future;
    } finally {
      _idleTimer?.cancel();
      _idleTimer = null;

      if (identical(_waiter, waiter)) {
        _waiter = null;
      }
    }
  }

  Future<void> share(
    List<Uint8List> photos, {
    required void Function(int completed, int total) onProgress,
  }) async {
    if (_waiter != null) {
      throw StateError('すでに共有処理を実行しています。');
    }

    if (_pendingOperation != null && _pendingKind != 'share') {
      throw StateError('写真の破棄処理がまだ終了していません。');
    }

    if (photos.isEmpty || photos.length > 30) {
      throw StateError('1セットの写真は1〜30枚にしてください。');
    }

    for (var index = 0; index < photos.length; index++) {
      final bytes = photos[index];

      if (bytes.isEmpty) {
        throw StateError('${index + 1}枚目の写真データが空です。');
      }

      if (bytes.length > _maxPhotoBytes) {
        throw StateError('${index + 1}枚目の写真が2MBを超えています。');
      }
    }

    final uid = _uid;

    if (_ownerUid != null && _ownerUid != uid) {
      throw StateError('撮影時と現在のユーザーが異なります。');
    }

    final savedPhotos = _photos;

    if (savedPhotos == null) {
      _ownerUid = uid;

      // 再試行中に画像が変更されないよう、最初の内容を保持する。
      _photos = [
        for (final photo in photos) Uint8List.fromList(photo),
      ];
    } else {
      if (savedPhotos.length != photos.length) {
        throw StateError('再送時は同じ撮影セットを使用してください。');
      }

      for (var index = 0; index < photos.length; index++) {
        if (!listEquals(savedPhotos[index], photos[index])) {
          throw StateError(
            '再送する写真が変更されています。\n'
            '最初に送信した撮影セットのまま再試行してください。',
          );
        }
      }
    }

    _onProgress = onProgress;

    try {
      _reportProgress();

      await _execute(
        'share',
        _performShare,
      );
    } finally {
      // タイムアウト後に、古い画面のコールバックを呼ばない。
      _onProgress = null;
    }
  }

  Future<void> _performShare() async {
    final uid = _ownerUid!;
    final photos = _photos!;

    if (_uid != uid) {
      throw StateError('ユーザー情報が変わりました。');
    }

    _log('共有開始：${photos.length}枚');

    if (_sessionRef == null) {
      _setStage('1/4 Firestore：ペア情報を確認');

      final membership = await _db
          .collection('memberships')
          .doc(uid)
          .get(const GetOptions(source: Source.server));

      final pairId = membership.data()?['pairId'];

      if (pairId is! String || pairId.isEmpty) {
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

      _log('ペア情報を確認できました。');
    }

    final ref = _sessionRef!;

    _setStage('2/4 Firestore：撮影セットを確認・作成');

    final alreadyShared = await _db.runTransaction<bool>(
      (transaction) async {
        final existing = await transaction.get(ref);

        if (existing.exists) {
          final data = existing.data()!;

          if (data['authorUid'] != uid) {
            throw StateError('撮影者の情報が一致しません。');
          }

          final savedPaths = List<String>.from(
            data['photoPaths'] as List,
          );

          if (!listEquals(savedPaths, _paths)) {
            throw StateError('保存済みの撮影セットと写真が一致しません。');
          }

          if (data['status'] == 'shared') {
            return true;
          }

          if (data['status'] != 'uploading') {
            throw StateError('撮影セットの状態を確認できません。');
          }

          return false;
        }

        transaction.set(ref, {
          'authorUid': uid,
          'createdAt': FieldValue.serverTimestamp(),
          'photoPaths': _paths,
          'status': 'uploading',
        });

        return false;
      },
    );

    if (alreadyShared) {
      _completedUploads.addAll(
        List.generate(photos.length, (index) => index),
      );

      _reportProgress();
      _log('共有済みであることを確認しました。');
      return;
    }

    _log('撮影セットの準備が完了しました。');
    _reportProgress();

    for (var index = 0; index < photos.length; index++) {
      if (_completedUploads.contains(index)) {
        _log('${index + 1}枚目：送信済みのためスキップ');
        continue;
      }

      _setStage(
        '3/4 Storage：${index + 1}/${photos.length}枚目を送信',
      );

      _log(
        '${index + 1}枚目のサイズ：'
        '${(photos[index].length / 1024).toStringAsFixed(1)} KB',
      );

      final task = _storage.ref(_paths[index]).putData(
        photos[index],
        SettableMetadata(
          contentType: 'image/jpeg',
        ),
      );

      var lastBytes = -1;
      var lastLoggedPercent = -10;

      final subscription = task.snapshotEvents.listen(
        (snapshot) {
          if (snapshot.bytesTransferred > lastBytes) {
            lastBytes = snapshot.bytesTransferred;
            _recordActivity();
          }

          final total = snapshot.totalBytes;

          if (total <= 0) {
            return;
          }

          final percent = (
            snapshot.bytesTransferred * 100 / total
          ).floor();

          if (percent >= lastLoggedPercent + 10 || percent == 100) {
            lastLoggedPercent = percent;

            _log(
              '${index + 1}/${photos.length}枚目：'
              '$percent% '
              '(${snapshot.bytesTransferred}/$total bytes)',
            );
          }
        },
        onError: (Object error) {
          // 最終的な成功・失敗は、下のawait taskで判定する。
          _log('Storageの進捗通知エラー：$error');
        },
      );

      try {
        await task;
      } finally {
        await subscription.cancel();
      }

      _completedUploads.add(index);

      _log('${index + 1}枚目のアップロードが完了しました。');

      _recordActivity();
      _reportProgress();
    }

    _setStage('4/4 Firestore：共有を確定');

    await ref.update({
      'status': 'shared',
      'sharedAt': FieldValue.serverTimestamp(),
    });

    _reportProgress();
    _log('共有完了：${photos.length}枚');
  }

  Future<void> discard() async {
    if (_waiter != null) {
      throw StateError('実行中の処理が終わるまでお待ちください。');
    }

    if (_pendingOperation != null && _pendingKind == 'share') {
      throw StateError(
        '共有処理がまだ終了していないため、写真を破棄できません。\n'
        '共有の再試行で処理結果を確認してください。',
      );
    }

    await _execute(
      'discard',
      _performDiscard,
    );
  }

  Future<void> _performDiscard() async {
    final ref = _sessionRef;

    if (ref == null) {
      _resetSession();
      return;
    }

    _setStage('Firestore：破棄前に共有状態を確認');

    final document = await ref.get(
      const GetOptions(source: Source.server),
    );

    if (!document.exists) {
      _resetSession();
      return;
    }

    if (document.data()?['status'] == 'shared') {
      _log('共有済みのため、写真は削除しません。');
      return;
    }

    for (var index = 0; index < _paths.length; index++) {
      _setStage(
        'Storage：未共有の写真を破棄 '
        '${index + 1}/${_paths.length}',
      );

      try {
        await _storage.ref(_paths[index]).delete();
      } on FirebaseException catch (error) {
        if (error.code != 'object-not-found') {
          rethrow;
        }
      }
    }

    _setStage('Firestore：未共有の撮影セットを破棄');

    await ref.delete();

    _resetSession();
    _log('未共有の撮影セットを破棄しました。');
  }

  void _resetSession() {
    _sessionRef = null;
    _paths = [];
    _photos = null;
    _ownerUid = null;
    _completedUploads.clear();
  }
}