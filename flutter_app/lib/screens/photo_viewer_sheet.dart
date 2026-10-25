import 'package:flutter/material.dart';

import '../services/album_service.dart';
import '../services/favorite_service.dart';
import 'album_screen.dart';

const _sheetColor = Color(0xFFF1F3F5);
const _handleColor = Color(0xFFC8CDD3);
const _barrierColor = Color(0x40000000);
const _inkColor = Color(0xFF241616);
const _mutedColor = Color(0xFF8B8E92);
const _likedHeartColor = Color(0xFFFF3040);
const _coralColor = Color(0xFFFF6048);
const _chipSelectedColor = Color(0xFFFFF5F4);
const _chipSelectedBorderColor = Color(0xFFFFE4E0);

const _sheetShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
);

// ハートを押したときの処理（一覧・拡大表示で共通）。
// 未いいね：「どこが好き？」を開く。未送信のいいね：取り消す。送信済み：変更不可。
Future<void> onHeartPressed(
  BuildContext context,
  AlbumController controller,
  SharedPhoto photo,
) async {
  switch (controller.statusOf(photo)) {
    case LikeStatus.sent:
      _showMessage(context, '送信済みの「好き」は変更できません。');
    case LikeStatus.draft:
      try {
        await controller.setDraftReasons(photo, const {});
      } catch (error) {
        if (context.mounted) {
          _showMessage(context, 'いいねを取り消せませんでした。\n$error');
        }
      }
    case LikeStatus.none:
      await showLikeReasonSheet(context, controller, photo);
  }
}

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

// 10「どこが好き？」。理由を1つ以上選んだ時点でいいねが成立し、
// 選ぶたびに保存する。1つも選ばずに閉じると、いいねは取り消される。
Future<void> showLikeReasonSheet(
  BuildContext context,
  AlbumController controller,
  SharedPhoto photo,
) async {
  controller.pendingPath = photo.path;

  try {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _sheetColor,
      barrierColor: _barrierColor,
      shape: _sheetShape,
      builder: (_) => _LikeReasonSheet(controller: controller, photo: photo),
    );
  } finally {
    controller.pendingPath = null;
  }
}

class _LikeReasonSheet extends StatefulWidget {
  const _LikeReasonSheet({required this.controller, required this.photo});

  final AlbumController controller;
  final SharedPhoto photo;

  @override
  State<_LikeReasonSheet> createState() => _LikeReasonSheetState();
}

class _LikeReasonSheetState extends State<_LikeReasonSheet> {
  late Set<String> _selected = widget.controller.draftReasonsOf(widget.photo);

  Future<void> _toggle(String key) async {
    final previous = Set<String>.from(_selected);
    final next = Set<String>.from(_selected);

    if (!next.remove(key)) {
      next.add(key);
    }

    setState(() => _selected = next);

    try {
      await widget.controller.setDraftReasons(widget.photo, next);
    } catch (error) {
      if (!mounted) return;
      setState(() => _selected = previous);
      _showMessage(context, '保存できませんでした。\n$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SheetHandle(),
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 15, 12, 15),
            child: Text(
              'どこが好き？',
              style: TextStyle(
                fontSize: 18,
                height: 26 / 18,
                fontWeight: FontWeight.bold,
                color: _inkColor,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            child: Wrap(
              spacing: 4,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final reason in favoriteReasonLabels.entries)
                  _ReasonChip(
                    label: reason.value,
                    selected: _selected.contains(reason.key),
                    onTap: () => _toggle(reason.key),
                  ),
                // TODO【未実装】：項目の追加は仕様が決まってから対応する。
                Semantics(
                  label: '項目を追加（準備中）',
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.add, size: 16, color: Colors.black),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReasonChip extends StatelessWidget {
  const _ReasonChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 34,
          padding: EdgeInsets.symmetric(horizontal: selected ? 16 : 20),
          decoration: BoxDecoration(
            color: selected ? _chipSelectedColor : Colors.white,
            borderRadius: BorderRadius.circular(500),
            border: Border.all(
              color: selected ? _chipSelectedBorderColor : Colors.white,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(Icons.check_rounded, size: 18, color: _coralColor),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: selected ? _coralColor : _inkColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      width: double.infinity,
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          margin: const EdgeInsets.only(top: 8),
          width: 40,
          height: 6,
          decoration: BoxDecoration(
            color: _handleColor,
            borderRadius: BorderRadius.circular(100),
          ),
        ),
      ),
    );
  }
}

// 09 写真の拡大表示。photos の中を左右に切り替えられる。
Future<void> showPhotoViewer(
  BuildContext context, {
  required AlbumController controller,
  required List<SharedPhoto> photos,
  required int initialIndex,
}) {
  final height = MediaQuery.sizeOf(context).height;

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: _sheetColor,
    barrierColor: _barrierColor,
    shape: _sheetShape,
    constraints: BoxConstraints(maxHeight: height * 768 / 844),
    builder: (_) => _PhotoViewerSheet(
      controller: controller,
      photos: List.unmodifiable(photos),
      initialIndex: initialIndex,
    ),
  );
}

class _PhotoViewerSheet extends StatefulWidget {
  const _PhotoViewerSheet({
    required this.controller,
    required this.photos,
    required this.initialIndex,
  });

  final AlbumController controller;
  final List<SharedPhoto> photos;
  final int initialIndex;

  @override
  State<_PhotoViewerSheet> createState() => _PhotoViewerSheetState();
}

class _PhotoViewerSheetState extends State<_PhotoViewerSheet> {
  static const _thumbWidth = 95.0;
  static const _thumbGap = 10.0;

  late int _index = widget.initialIndex.clamp(0, widget.photos.length - 1);
  late final _pageController = PageController(initialPage: _index);
  final _thumbController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerThumbnail(animate: false);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _thumbController.dispose();
    super.dispose();
  }

  void _centerThumbnail({bool animate = true}) {
    if (!_thumbController.hasClients) return;

    final position = _thumbController.position;
    final target =
        (_index * (_thumbWidth + _thumbGap) -
                (position.viewportDimension - _thumbWidth) / 2)
            .clamp(0.0, position.maxScrollExtent);

    if (animate) {
      _thumbController.animateTo(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      _thumbController.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photos[_index];

    return SafeArea(
      child: Column(
        children: [
          const _SheetHandle(),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.photos.length,
              onPageChanged: (index) {
                setState(() => _index = index);
                _centerThumbnail();
              },
              itemBuilder: (context, index) {
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final height = constraints.maxHeight.clamp(0.0, 413.0);
                    final width = (height * 300 / 413).clamp(
                      0.0,
                      constraints.maxWidth - 32,
                    );

                    return Center(
                      child: SizedBox(
                        width: width,
                        height: width * 413 / 300,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: SharedPhotoImage(
                            key: ValueKey(widget.photos[index].path),
                            path: widget.photos[index].path,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Text(
            albumDate(photo.sharedAt),
            style: const TextStyle(
              fontSize: 13,
              height: 20 / 13,
              fontWeight: FontWeight.w500,
              color: _mutedColor,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: widget.controller.isReceived(photo)
                ? ListenableBuilder(
                    listenable: widget.controller,
                    builder: (context, _) {
                      final liked = widget.controller.isLiked(photo);

                      return IconButton(
                        tooltip: liked ? 'いいねを取り消す' : 'いいね',
                        onPressed: () =>
                            onHeartPressed(context, widget.controller, photo),
                        icon: Icon(
                          liked
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 30,
                          color: liked ? _likedHeartColor : _mutedColor,
                        ),
                      );
                    },
                  )
                : null,
          ),
          const SizedBox(height: 49),
          SizedBox(
            height: 28,
            child: ListView.separated(
              controller: _thumbController,
              scrollDirection: Axis.horizontal,
              itemCount: widget.photos.length,
              separatorBuilder: (_, _) => const SizedBox(width: _thumbGap),
              itemBuilder: (context, index) {
                return GestureDetector(
                  onTap: () {
                    _pageController.animateToPage(
                      index,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                    );
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: SizedBox(
                      width: _thumbWidth,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          SharedPhotoImage(
                            key: ValueKey(widget.photos[index].path),
                            path: widget.photos[index].path,
                            showProgress: false,
                          ),
                          // 表示中以外の写真は少し暗くする。
                          ColoredBox(
                            color: Colors.black.withValues(
                              alpha: index == _index ? 0 : 0.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
