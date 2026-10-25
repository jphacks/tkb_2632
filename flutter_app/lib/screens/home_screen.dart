import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../pic.dart';
import '../services/album_service.dart';
import '../services/pair_service.dart';
import '../widgets/account_actions.dart';
import '../widgets/profile_avatar.dart';

import 'album_screen.dart';
import 'connection_success_screen.dart';
import 'notifications_screen.dart';
import 'pair_registration_screen.dart';
import 'photo_viewer_sheet.dart';
import 'profile_screen.dart';
import 'shooting_chart_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.nickname,
    required this.onProfileChanged,
    this.avatarBase64 = '',
    this.onCapture,
  });

  final String nickname;
  final String avatarBase64;
  final VoidCallback onProfileChanged;
  final VoidCallback? onCapture;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _service = PairService();

  late final Stream<DocumentSnapshot<Map<String, dynamic>>>
      _membershipStream;

  bool _hasSeenUnpaired = false;

  @override
  void initState() {
    super.initState();
    _membershipStream = _service.watchMembership();
  }

  Future<void> _editProfile() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (pageContext) => ProfileScreen(
          initialNickname: widget.nickname,
          initialAvatarBase64: widget.avatarBase64,
          isEditing: true,
          onSaved: () {
            Navigator.of(pageContext).pop(true);
          },
        ),
      ),
    );

    if (!mounted) return;

    if (saved == true) {
      widget.onProfileChanged();
    }
  }

  Future<void> _startConnection() async {
    final join = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '二人のつながりを始める',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: const Icon(Icons.qr_code_rounded),
                  title: const Text('招待コードを作る'),
                  subtitle: const Text('相手にコードを伝える'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(sheetContext).pop(false),
                ),
                ListTile(
                  leading: const Icon(Icons.keyboard_rounded),
                  title: const Text('招待コードを入力する'),
                  subtitle: const Text('相手から届いたコードでつながる'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(sheetContext).pop(true),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (join == null || !mounted) return;

    Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PairRegistrationScreen(
          nickname: widget.nickname,
          startWithJoin: join,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _membershipStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Scaffold(
            body: Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Text(
                  '接続状態を確認できませんでした。\n'
                  '通信環境とFirestoreのルールを確認してください。',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        if (!snapshot.hasData ||
            (snapshot.data!.metadata.isFromCache &&
                !snapshot.data!.exists)) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final membership = snapshot.data!;

        if (!membership.exists) {
          _hasSeenUnpaired = true;
          return _buildUnconnectedHome();
        }

        final pairId = membership.data()?['pairId'];

        if (pairId is! String) {
          return const Scaffold(
            body: Center(child: Text('接続情報が正しくありません。')),
          );
        }

        return _ConnectedExperience(
          key: ValueKey(pairId),
          pairId: pairId,
          showCelebration: _hasSeenUnpaired,
          onEditProfile: _editProfile,
          onCapture: widget.onCapture,
        );
      },
    );
  }

  Widget _buildUnconnectedHome() {
    const coral = Color(0xFFFF715E);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Semantics(
                      label: 'プロフィールを変更',
                      button: true,
                      child: InkWell(
                        onTap: _editProfile,
                        borderRadius: BorderRadius.circular(24),
                        child: ProfileAvatar(
                          avatarBase64: widget.avatarBase64,
                          size: 40,
                        ),
                      ),
                    ),
                  ),
                  const Expanded(
                    child: Center(child: _LandingArtwork()),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _startConnection,
                      style: FilledButton.styleFrom(
                        backgroundColor: coral,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: const StadiumBorder(),
                      ),
                      child: const Text(
                        'コードで参加する',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      // TODO【未実装】：QRでの参加は今後対応する。
                      onPressed: () {},
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF291F1D),
                        side: const BorderSide(color: coral),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: const StadiumBorder(),
                      ),
                      child: const Text(
                        'QRで参加する',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LandingArtwork extends StatelessWidget {
  const _LandingArtwork();

  static const _frame = Color(0xFF9A9AA0);
  static const _coral = Color(0xFFFF7F78);
  static const _teal = Color(0xFF6E9E95);

  Widget _phone(double width, Color personColor) {
    return Container(
      width: width,
      height: width * 1.75,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(width * 0.12),
        border: Border.all(color: _frame, width: 1.5),
      ),
      child: Column(
        children: [
          Container(
            width: width * 0.32,
            height: 6,
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFC8C8CC),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          Expanded(
            child: Center(
              child: Icon(
                Icons.person_rounded,
                size: width * 0.6,
                color: personColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _photo(double width, Color color, double angle) {
    return Transform.rotate(
      angle: angle,
      child: Container(
        width: width,
        height: width * 0.85,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(3),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: ColoredBox(
          color: color.withValues(alpha: 0.18),
          child: Icon(
            Icons.landscape_rounded,
            size: width * 0.6,
            color: color.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.4,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final phoneWidth = width * 0.24;

          return ColoredBox(
            color: const Color(0xFFFAFAFA),
            child: Stack(
              children: [
                Positioned(
                  left: width * 0.2,
                  top: width * 0.1,
                  child: _phone(phoneWidth, _coral),
                ),
                Positioned(
                  right: width * 0.2,
                  top: width * 0.06,
                  child: _phone(phoneWidth, _teal),
                ),
                Positioned(
                  left: width * 0.39,
                  top: width * 0.17,
                  child: _photo(width * 0.13, _coral, -0.1),
                ),
                Positioned(
                  left: width * 0.47,
                  top: width * 0.29,
                  child: _photo(width * 0.13, _teal, 0.08),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ConnectedExperience extends StatefulWidget {
  const _ConnectedExperience({
    super.key,
    required this.pairId,
    required this.showCelebration,
    required this.onEditProfile,
    this.onCapture,
  });

  final String pairId;
  final bool showCelebration;
  final VoidCallback onEditProfile;
  final VoidCallback? onCapture;

  @override
  State<_ConnectedExperience> createState() =>
      _ConnectedExperienceState();
}

class _ConnectedExperienceState extends State<_ConnectedExperience> {
  late Future<PairDetails> _pairFuture;
  late bool _showCelebration;

  @override
  void initState() {
    super.initState();
    _showCelebration = widget.showCelebration;
    _pairFuture = PairService().loadPair(widget.pairId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PairDetails>(
      future: _pairFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('二人の情報を取得できませんでした。'),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () {
                      setState(() {
                        _pairFuture =
                            PairService().loadPair(widget.pairId);
                      });
                    },
                    child: const Text('再試行'),
                  ),
                ],
              ),
            ),
          );
        }

        final pair = snapshot.data!;

        if (_showCelebration) {
          return ConnectionSuccessScreen(
            pair: pair,
            onContinue: () {
              setState(() => _showCelebration = false);
            },
          );
        }

        return _ConnectedHome(
          pairId: widget.pairId,
          pair: pair,
          onEditProfile: widget.onEditProfile,
          onCapture: widget.onCapture,
        );
      },
    );
  }
}

class _ConnectedHome extends StatefulWidget {
  const _ConnectedHome({
    required this.pairId,
    required this.pair,
    required this.onEditProfile,
    this.onCapture,
  });

  final String pairId;
  final PairDetails pair;
  final VoidCallback onEditProfile;
  final VoidCallback? onCapture;

  @override
  State<_ConnectedHome> createState() => _ConnectedHomeState();
}

class _ConnectedHomeState extends State<_ConnectedHome> {
  late final _album = AlbumController(
    pairId: widget.pairId,
    myUid: FirebaseAuth.instance.currentUser!.uid,
  );

  bool _openingAlbum = false;
  bool _disconnecting = false;

  @override
  void dispose() {
    _album.dispose();
    super.dispose();
  }

  Future<void> _openCamera() async {
    if (widget.onCapture != null) {
      widget.onCapture!();
      return;
    }

    final result = await Navigator.of(
      context,
    ).push<XFile>(MaterialPageRoute<XFile>(builder: (_) => const PicScreen()));

    if (!mounted || result == null) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('写真を共有しました。')));
  }

  Future<void> _openAlbum([AlbumTab tab = AlbumTab.all]) async {
    // 「our picture」の引っ張りで何度も開かないようにする。
    if (_openingAlbum) return;
    _openingAlbum = true;

    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => AlbumScreen(
            controller: _album,
            title: '${widget.pair.myName}&${widget.pair.partnerName}🌷',
            initialTab: tab,
          ),
        ),
      );
    } finally {
      _openingAlbum = false;
    }
  }

  void _openChart({required bool mine}) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ShootingChartScreen(pairId: widget.pairId, mine: mine),
      ),
    );
  }

  // 「左にスライドして撮影を終了」：二人の共有（接続）を終える。
  Future<void> _endSharing() async {
    if (_disconnecting) return;

    final accepted = await confirmDisconnectDialog(context);

    if (accepted != true || !mounted) return;

    setState(() => _disconnecting = true);

    try {
      // membershipを監視しているため、両方のホームが未接続画面へ自動で切り替わる。
      await disconnectCurrentPair();
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('接続を解除できませんでした。\n$error')));
    } finally {
      if (mounted) {
        setState(() => _disconnecting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pair = widget.pair;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                _HomeHeader(
                  pair: pair,
                  onEditProfile: _disconnecting ? null : widget.onEditProfile,
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(top: 32, bottom: 24),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _HomeCamera(
                          date: albumDate(DateTime.now()),
                          onTap: _openCamera,
                        ),
                      ),
                      const SizedBox(height: 32),
                      ListenableBuilder(
                        listenable: _album,
                        builder: (context, _) => _OurPictures(
                          album: _album,
                          onOpenAlbum: _openAlbum,
                        ),
                      ),
                      const SizedBox(height: 26),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SizedBox(
                          height: 204,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: ListenableBuilder(
                                  listenable: _album,
                                  builder: (context, _) => _LikeCard(
                                    photo: _album.likedPhotos.firstOrNull,
                                    onTap: () => _openAlbum(AlbumTab.favorites),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  children: [
                                    Expanded(
                                      child: _ChartCard(
                                        name: pair.myName,
                                        onTap: () => _openChart(mine: true),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Expanded(
                                      child: _ChartCard(
                                        name: pair.partnerName,
                                        onTap: () => _openChart(mine: false),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: _EndSharingSlider(
                    busy: _disconnecting,
                    onEnd: _endSharing,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.pair, required this.onEditProfile});

  final PairDetails pair;
  final VoidCallback? onEditProfile;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.only(left: 12, right: 12),
        child: Row(
          children: [
            Semantics(
              label: 'プロフィールを変更',
              button: true,
              child: GestureDetector(
                onTap: onEditProfile,
                child: _ShadowedAvatar(avatarBase64: pair.myAvatar),
              ),
            ),
            const SizedBox(width: 4),
            _ShadowedAvatar(avatarBase64: pair.partnerAvatar),
            const SizedBox(width: 12),
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Color(0xFF098C85),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '${pair.partnerName}と共有中🌷',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF241616),
                ),
              ),
            ),
            const NotificationBell(),
          ],
        ),
      ),
    );
  }
}

class _ShadowedAvatar extends StatelessWidget {
  const _ShadowedAvatar({required this.avatarBase64});

  final String avatarBase64;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Color(0x0F000000), spreadRadius: 0),
          BoxShadow(
            color: Color(0x29000000),
            blurRadius: 36,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: ProfileAvatar(avatarBase64: avatarBase64, size: 40),
    );
  }
}

// カメラのイラスト。タップで撮影画面を開く。
class _HomeCamera extends StatelessWidget {
  const _HomeCamera({required this.date, required this.onTap});

  final String date;
  final VoidCallback onTap;

  static const _dark = Color(0xFF353535);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '写真を撮る',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 219,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(80),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF9F3E1), Color(0xFFF0E0B3)],
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A583C2C),
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(left: 53, top: 73, child: _part(38, 10, _dark, 8)),
              Positioned(
                left: 53,
                top: 123,
                child: _part(25, 23, const Color(0xFFFF6851), 32),
              ),
              Positioned(right: 57, top: 64, child: _part(30, 28, _dark, 8)),
              Center(child: _lens()),
              Positioned(
                left: 0,
                right: 0,
                bottom: 8,
                child: Text(
                  date,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF63676C),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _part(double width, double height, Color color, double radius) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  Widget _lens() {
    return Container(
      width: 120,
      height: 120,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: _dark, shape: BoxShape.circle),
      child: Container(
        width: 96,
        height: 96,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF77A2A3), Color(0xFF539D9F)],
          ),
        ),
        child: Container(
          width: 68,
          height: 68,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_dark, Color(0xFF131313)],
            ),
          ),
          child: Transform.translate(
            offset: const Offset(-10, -4),
            child: Center(
              // レンズの反射。
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 5.5, sigmaY: 5.5),
                child: Container(
                  width: 32,
                  height: 27,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF5F0E1),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// 新しい写真8枚。最後の写真を越えてさらに引っ張ると、アルバムを開く。
class _OurPictures extends StatelessWidget {
  const _OurPictures({required this.album, required this.onOpenAlbum});

  final AlbumController album;
  final VoidCallback onOpenAlbum;

  static const _size = 92.0;
  static const _pullDistance = 56.0;

  @override
  Widget build(BuildContext context) {
    final photos = album.photos;

    if (photos == null || photos.isEmpty) {
      return Container(
        height: _size,
        margin: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFEEF3F5),
          borderRadius: BorderRadius.circular(24),
        ),
        child: photos == null
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text(
                'まだ写真はありません。\n撮影して共有すると、ここに届きます。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Color(0xFF8B8E92)),
              ),
      );
    }

    final latest = photos.take(8).toList();

    return SizedBox(
      height: _size,
      child: NotificationListener<ScrollUpdateNotification>(
        onNotification: (notification) {
          final metrics = notification.metrics;

          if (notification.dragDetails != null &&
              metrics.pixels > metrics.maxScrollExtent + _pullDistance) {
            onOpenAlbum();
          }

          return false;
        },
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          // 端を越えて引っ張れるようにする（Androidでも同じ動き）。
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: latest.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final photo = latest[index];

            return Semantics(
              button: true,
              label: '写真を拡大',
              child: GestureDetector(
                onTap: () => showPhotoViewer(
                  context,
                  controller: album,
                  photos: latest,
                  initialIndex: index,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: SizedBox(
                    width: _size,
                    height: _size,
                    child: SharedPhotoImage(
                      key: ValueKey(photo.path),
                      path: photo.path,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// 最新のいいね写真。タップでお気に入りを開く。
class _LikeCard extends StatelessWidget {
  const _LikeCard({required this.photo, required this.onTap});

  final SharedPhoto? photo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final current = photo;

    return Semantics(
      button: true,
      label: 'お気に入りを見る',
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (current == null)
                const ColoredBox(color: Color(0xFFD9DEE2))
              else
                SharedPhotoImage(
                  key: ValueKey(current.path),
                  path: current.path,
                ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0x59000000)],
                  ),
                ),
              ),
              const Positioned(
                left: 8,
                bottom: 8,
                child: Row(
                  children: [
                    Icon(
                      Icons.favorite_border_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'いいね',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 撮影カルテへのカード。
class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.name, required this.onTap});

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFEEF3F5),
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF161D24),
                  ),
                ),
              ),
              Semantics(
                label: '$nameの撮影カルテを開く',
                child: const Icon(
                  Icons.north_east_rounded,
                  size: 20,
                  color: Colors.black,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 「左にスライドして撮影を終了」。つまみを左端まで動かすと onEnd を呼ぶ。
class _EndSharingSlider extends StatefulWidget {
  const _EndSharingSlider({required this.busy, required this.onEnd});

  final bool busy;
  final Future<void> Function() onEnd;

  @override
  State<_EndSharingSlider> createState() => _EndSharingSliderState();
}

class _EndSharingSliderState extends State<_EndSharingSlider> {
  static const _knobWidth = 46.0;
  static const _inset = 2.0;

  double _drag = 0;
  bool _dragging = false;

  Future<void> _release(double maxDrag) async {
    final reached = maxDrag > 0 && _drag >= maxDrag * 0.85;

    setState(() {
      _dragging = false;
      _drag = reached ? maxDrag : 0;
    });

    if (!reached) return;

    await widget.onEnd();

    if (mounted) {
      setState(() => _drag = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxDrag = constraints.maxWidth - _knobWidth - _inset * 2;
        final progress = maxDrag > 0 ? (_drag / maxDrag).clamp(0.0, 1.0) : 0.0;

        return Semantics(
          button: true,
          label: '撮影を終了（二人の接続を解除）',
          onTap: widget.busy ? null : widget.onEnd,
          child: Container(
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFE6EBEF),
              borderRadius: BorderRadius.circular(32),
            ),
            child: Stack(
              children: [
                Center(
                  child: Opacity(
                    opacity: 1 - progress,
                    child: Text(
                      widget.busy ? '終了しています…' : '左にスライドして撮影を終了',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF8B8E92),
                      ),
                    ),
                  ),
                ),
                AnimatedPositioned(
                  duration: _dragging
                      ? Duration.zero
                      : const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  right: _inset + _drag,
                  top: 3,
                  child: GestureDetector(
                    onHorizontalDragStart: widget.busy
                        ? null
                        : (_) => setState(() => _dragging = true),
                    onHorizontalDragUpdate: widget.busy
                        ? null
                        : (details) {
                            setState(() {
                              _drag = (_drag - details.delta.dx).clamp(
                                0.0,
                                maxDrag,
                              );
                            });
                          },
                    onHorizontalDragEnd: widget.busy
                        ? null
                        : (_) => _release(maxDrag),
                    child: Container(
                      width: _knobWidth,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(500),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 14,
                        color: Color(0xFF241616),
                      ),
                    ),
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
