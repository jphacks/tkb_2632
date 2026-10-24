import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

class SharedPhoto {
  const SharedPhoto({
    required this.path,
    required this.authorUid,
    required this.sharedAt,
  });

  final String path;
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

      return (bDate?.millisecondsSinceEpoch ?? 0)
          .compareTo(aDate?.millisecondsSinceEpoch ?? 0);
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
            authorUid: authorUid,
            sharedAt: dateOf(data),
          ),
        );
      }
    }

    return photos;
  });
}

// Futureを保持し、画面の再描画のたびに取得し直さないようにする。
class SharedPhotoImage extends StatefulWidget {
  const SharedPhotoImage({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
  });

  final String path;
  final BoxFit fit;

  @override
  State<SharedPhotoImage> createState() => _SharedPhotoImageState();
}

class _SharedPhotoImageState extends State<SharedPhotoImage> {
  late Future<Uint8List?> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SharedPhotoImage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.path != widget.path) {
      _load();
    }
  }

  void _load() {
    _future = FirebaseStorage.instance
        .ref(widget.path)
        .getData(2 * 1024 * 1024);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError ||
            (snapshot.connectionState == ConnectionState.done &&
                snapshot.data == null)) {
          return ColoredBox(
            color: const Color(0xFFECE8E5),
            child: Center(
              child: TextButton.icon(
                onPressed: () {
                  setState(_load);
                },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('再読込'),
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const ColoredBox(
            color: Color(0xFFECE8E5),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        return Image.memory(
          snapshot.data!,
          fit: widget.fit,
          width: double.infinity,
          height: double.infinity,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) {
            return const Center(
              child: Icon(Icons.broken_image_outlined),
            );
          },
        );
      },
    );
  }
}

class AlbumScreen extends StatefulWidget {
  const AlbumScreen({
    super.key,
    required this.pairId,
    required this.partnerName,
  });

  final String pairId;
  final String partnerName;

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  late final Stream<List<SharedPhoto>> _photosStream;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>>
      _membershipStream;

  bool _receivedOnly = false;

  @override
  void initState() {
    super.initState();

    _photosStream = watchSharedPhotos(widget.pairId);

    final uid = FirebaseAuth.instance.currentUser!.uid;

    _membershipStream = FirebaseFirestore.instance
        .collection('memberships')
        .doc(uid)
        .snapshots(includeMetadataChanges: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFAF7),
      appBar: AppBar(
        title: const Text('ふたりのアルバム'),
        backgroundColor: const Color(0xFFFFFAF7),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _membershipStream,
        builder: (context, membershipSnapshot) {
          if (membershipSnapshot.hasError) {
            return const Center(
              child: Text('接続状態を確認できませんでした。'),
            );
          }

          final membership = membershipSnapshot.data;

          if (membership == null ||
              (membership.metadata.isFromCache && !membership.exists)) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!membership.exists ||
              membership.data()?['pairId'] != widget.pairId) {
            return const Center(
              child: Text('接続が解除されました。\nホームへ戻ってください。'),
            );
          }

          return StreamBuilder<List<SharedPhoto>>(
            stream: _photosStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      '写真を取得できませんでした。\n'
                      'エミュレーターの起動状態とルールを確認してください。',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final uid = FirebaseAuth.instance.currentUser?.uid;

              final photos = snapshot.data!
                  .where(
                    (photo) => !_receivedOnly || photo.authorUid != uid,
                  )
                  .toList();

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${widget.partnerName}との写真'),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          children: [
                            ChoiceChip(
                              label: const Text('すべて'),
                              selected: !_receivedOnly,
                              onSelected: (_) {
                                setState(() => _receivedOnly = false);
                              },
                            ),
                            ChoiceChip(
                              label: const Text('撮ってもらった'),
                              selected: _receivedOnly,
                              onSelected: (_) {
                                setState(() => _receivedOnly = true);
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('${photos.length}枚'),
                      ],
                    ),
                  ),
                  Expanded(
                    child: photos.isEmpty
                        ? const Center(
                            child: Text('まだ写真はありません。'),
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.all(12),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: 0.75,
                            ),
                            itemCount: photos.length,
                            itemBuilder: (context, index) {
                              final photo = photos[index];

                              return Semantics(
                                button: true,
                                label: '写真${index + 1}を拡大',
                                child: GestureDetector(
                                  onTap: () {
                                    showSharedPhoto(
                                      context,
                                      photo,
                                      widget.pairId,
                                    );
                                  },
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: SharedPhotoImage(
                                      key: ValueKey(photo.path),
                                      path: photo.path,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

// 拡大表示中に接続が解除された場合も、画像を画面から外す。
void showSharedPhoto(
  BuildContext context,
  SharedPhoto photo,
  String pairId,
) {
  final uid = FirebaseAuth.instance.currentUser!.uid;

  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: SafeArea(
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('memberships')
                .doc(uid)
                .snapshots(includeMetadataChanges: true),
            builder: (context, snapshot) {
              final membership = snapshot.data;
              final active = !snapshot.hasError &&
                  membership != null &&
                  membership.exists &&
                  membership.data()?['pairId'] == pairId;

              return Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      tooltip: '閉じる',
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Expanded(
                    child: active
                        ? InteractiveViewer(
                            minScale: 1,
                            maxScale: 4,
                            child: SharedPhotoImage(
                              path: photo.path,
                              fit: BoxFit.contain,
                            ),
                          )
                        : const Center(
                            child: Text(
                              '写真を表示できません。\n接続状態を確認してください。',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                  ),
                  if (active && photo.sharedAt != null)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        '${photo.sharedAt!.year}/'
                        '${photo.sharedAt!.month}/'
                        '${photo.sharedAt!.day}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      );
    },
  );
}