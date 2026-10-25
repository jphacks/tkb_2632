import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import '../services/album_service.dart';
import 'photo_viewer_sheet.dart';

export '../services/album_service.dart' show SharedPhoto;

const _inkColor = Color(0xFF241616);
const _titleColor = Color(0xFF0C1120);
const _mutedColor = Color(0xFF8B8E92);
const _tabBackgroundColor = Color(0xFFEEF3F5);
const _placeholderColor = Color(0xFFECE8E5);
const _buttonColor = Color(0xFFFF745F);
const _buttonDisabledColor = Color(0xFFCCCCCC);

// Storageの写真データを、ホーム・アルバム・拡大表示で使い回す。
final _photoBytes = <String, Future<Uint8List?>>{};
final _photoAspects = <String, Future<double?>>{};

Future<Uint8List?> loadSharedPhotoBytes(String path) {
  return _photoBytes.putIfAbsent(path, () async {
    try {
      return await FirebaseStorage.instance.ref(path).getData(2 * 1024 * 1024);
    } catch (_) {
      // 失敗した結果は残さず、次の表示で取得し直す。
      _photoBytes.remove(path);
      rethrow;
    }
  });
}

// 写真本来の縦横比（幅÷高さ）。取得できない場合は null。
Future<double?> sharedPhotoAspect(String path) {
  return _photoAspects.putIfAbsent(path, () async {
    try {
      final bytes = await loadSharedPhotoBytes(path);
      if (bytes == null) return null;

      final image = await decodeImageFromList(bytes);
      final aspect = image.width / image.height;
      image.dispose();
      return aspect;
    } catch (_) {
      _photoAspects.remove(path);
      return null;
    }
  });
}

class SharedPhotoImage extends StatefulWidget {
  const SharedPhotoImage({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
    this.showProgress = true,
  });

  final String path;
  final BoxFit fit;

  // 小さな表示では、読み込み中の表示を省く。
  final bool showProgress;

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
    _future = loadSharedPhotoBytes(widget.path);
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
            color: _placeholderColor,
            child: Center(
              child: IconButton(
                tooltip: '再読込',
                onPressed: () {
                  setState(_load);
                },
                icon: const Icon(Icons.refresh_rounded),
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return ColoredBox(
            color: _placeholderColor,
            child: widget.showProgress
                ? const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          );
        }

        return Image.memory(
          snapshot.data!,
          fit: widget.fit,
          width: double.infinity,
          height: double.infinity,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) {
            return const Center(child: Icon(Icons.broken_image_outlined));
          },
        );
      },
    );
  }
}

enum AlbumTab {
  all('すべて'),
  received('撮ってもらった'),
  favorites('お気に入り');

  const AlbumTab(this.label);

  final String label;
}

// 06〜08 アルバム。タブは同じ画面の中で切り替える。
class AlbumScreen extends StatefulWidget {
  const AlbumScreen({
    super.key,
    required this.controller,
    required this.title,
    this.initialTab = AlbumTab.all,
  });

  final AlbumController controller;
  final String title;
  final AlbumTab initialTab;

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _membershipStream;

  late AlbumTab _tab = widget.initialTab;

  @override
  void initState() {
    super.initState();

    final uid = FirebaseAuth.instance.currentUser!.uid;

    _membershipStream = FirebaseFirestore.instance
        .collection('memberships')
        .doc(uid)
        .snapshots(includeMetadataChanges: true);
  }

  List<SharedPhoto> _photosFor(AlbumTab tab) {
    final controller = widget.controller;

    return switch (tab) {
      AlbumTab.all => [...?controller.photos],
      AlbumTab.received => controller.receivedPhotos,
      AlbumTab.favorites => controller.likedPhotos,
    };
  }

  Future<void> _send() async {
    final controller = widget.controller;
    final count = controller.unsentCount;

    if (count == 0 || controller.sending) return;

    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('「好き」を送りますか？'),
        content: Text(
          '$count枚のいいねと理由をまとめて送ります。\n\n'
          '送ったあとは、いいねの取り消しや理由の変更はできません。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('送る'),
          ),
        ],
      ),
    );

    if (accepted != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);

    try {
      final sent = await controller.sendAll();

      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('$sent枚の「好き」を送りました！')));
    } catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('送信できませんでした。\n$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Color(0xFFE7E2E1)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _AlbumTabs(
                  selected: _tab,
                  onSelected: (tab) => setState(() => _tab = tab),
                ),
              ),
              Expanded(
                child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: _membershipStream,
                  builder: (context, membershipSnapshot) {
                    if (membershipSnapshot.hasError) {
                      return const Center(child: Text('接続状態を確認できませんでした。'));
                    }

                    final membership = membershipSnapshot.data;

                    if (membership == null ||
                        (membership.metadata.isFromCache &&
                            !membership.exists)) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (!membership.exists ||
                        membership.data()?['pairId'] !=
                            widget.controller.pairId) {
                      return const Center(
                        child: Text(
                          '接続が解除されました。\nホームへ戻ってください。',
                          textAlign: TextAlign.center,
                        ),
                      );
                    }

                    return ListenableBuilder(
                      listenable: widget.controller,
                      builder: (context, _) => _buildPhotos(),
                    );
                  },
                ),
              ),
              ListenableBuilder(
                listenable: widget.controller,
                builder: (context, _) => _buildSendButton(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return SizedBox(
      height: 60,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 4,
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              color: _titleColor,
              tooltip: 'ホームへ戻る',
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 60),
            child: Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                height: 22 / 16,
                fontWeight: FontWeight.w600,
                color: _titleColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotos() {
    final controller = widget.controller;

    if (controller.error != null) {
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

    if (controller.photos == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final photos = _photosFor(_tab);

    if (photos.isEmpty) {
      final message = switch (_tab) {
        AlbumTab.all => 'まだ写真はありません。',
        AlbumTab.received => '撮ってもらった写真はまだありません。',
        AlbumTab.favorites => 'ハートを押した写真が、ここに並びます。',
      };

      return Center(
        child: Text(message, style: const TextStyle(color: _mutedColor)),
      );
    }

    // 共有された日ごとにまとめる（photos は新しい順）。
    final groups = <({String date, List<int> indexes})>[];

    for (var i = 0; i < photos.length; i++) {
      final date = albumDate(photos[i].sharedAt);

      if (groups.isEmpty || groups.last.date != date) {
        groups.add((date: date, indexes: []));
      }

      groups.last.indexes.add(i);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        for (final group in groups) ...[
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 15),
            child: Text(
              group.date,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _mutedColor,
              ),
            ),
          ),
          _MasonryGroup(
            indexes: group.indexes,
            itemBuilder: (index) => _AlbumTile(
              photo: photos[index],
              controller: controller,
              onTap: () => showPhotoViewer(
                context,
                controller: controller,
                photos: photos,
                initialIndex: index,
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ],
    );
  }

  Widget _buildSendButton() {
    final controller = widget.controller;
    final count = controller.unsentCount;
    final enabled = count > 0 && !controller.sending;

    final String label;

    if (controller.sending) {
      label = '送信しています…';
    } else if (count == 0) {
      label = '「好き」を送る';
    } else {
      label = '$count枚の「好き」を送る';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: FilledButton(
          onPressed: enabled ? _send : null,
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

class _AlbumTabs extends StatelessWidget {
  const _AlbumTabs({required this.selected, required this.onSelected});

  final AlbumTab selected;
  final ValueChanged<AlbumTab> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: _tabBackgroundColor,
        borderRadius: BorderRadius.circular(36),
      ),
      child: Row(
        children: [
          for (final tab in AlbumTab.values)
            Expanded(
              child: Semantics(
                button: true,
                selected: tab == selected,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelected(tab),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tab == selected
                          ? Colors.white
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(500),
                    ),
                    child: Text(
                      tab.label,
                      style: const TextStyle(fontSize: 12, color: _inkColor),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// 2列に交互に並べる。各写真は本来の縦横比で表示する。
class _MasonryGroup extends StatelessWidget {
  const _MasonryGroup({required this.indexes, required this.itemBuilder});

  final List<int> indexes;
  final Widget Function(int index) itemBuilder;

  @override
  Widget build(BuildContext context) {
    Widget column(int parity) {
      final items = [
        for (var i = parity; i < indexes.length; i += 2) indexes[i],
      ];

      return Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            itemBuilder(items[i]),
          ],
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: column(0)),
        const SizedBox(width: 8),
        Expanded(child: column(1)),
      ],
    );
  }
}

class _AlbumTile extends StatelessWidget {
  const _AlbumTile({
    required this.photo,
    required this.controller,
    required this.onTap,
  });

  final SharedPhoto photo;
  final AlbumController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<double?>(
      future: sharedPhotoAspect(photo.path),
      builder: (context, snapshot) {
        return AspectRatio(
          aspectRatio: snapshot.data ?? 3 / 4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Semantics(
                  button: true,
                  label: '写真を拡大',
                  child: GestureDetector(
                    onTap: onTap,
                    child: SharedPhotoImage(
                      key: ValueKey(photo.path),
                      path: photo.path,
                    ),
                  ),
                ),
                // ハートは撮ってもらった写真にだけ付ける。
                if (controller.isReceived(photo))
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: AlbumHeartButton(
                      liked: controller.isLiked(photo),
                      onPressed: () =>
                          onHeartPressed(context, controller, photo),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// 写真の上に重ねる白いハート。
class AlbumHeartButton extends StatelessWidget {
  const AlbumHeartButton({
    super.key,
    required this.liked,
    required this.onPressed,
  });

  final bool liked;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: liked ? 'いいねを取り消す' : 'いいね',
      onPressed: onPressed,
      icon: Icon(
        liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        size: 20,
        color: Colors.white,
        shadows: const [ui.Shadow(color: Color(0x66000000), blurRadius: 6)],
      ),
    );
  }
}
