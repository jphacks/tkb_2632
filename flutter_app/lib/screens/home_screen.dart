import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../pic.dart';
import '../services/pair_service.dart';
import '../widgets/account_actions.dart';
import '../widgets/profile_avatar.dart';

import 'album_screen.dart';
import 'connection_success_screen.dart';
import 'pair_registration_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.nickname,
    required this.onProfileChanged,
    this.avatarBase64 = '',
    this.onCapture,
    this.onAlbum,
  });

  final String nickname;
  final String avatarBase64;
  final VoidCallback onProfileChanged;
  final VoidCallback? onCapture;
  final VoidCallback? onAlbum;

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
          onAlbum: widget.onAlbum,
        );
      },
    );
  }

  Widget _buildUnconnectedHome() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [
                      Color(0xFFF1DCD4),
                      Color(0xFFFFFAF5),
                      Colors.white,
                    ],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                        child: Align(
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
                      ),
                      _LandingArtwork(
                        avatarBase64: widget.avatarBase64,
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
                child: Column(
                  children: [
                    const Text(
                      'ふたりでつないで、\n写真を撮る。',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 25,
                        height: 1.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF291F1D),
                      ),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _startConnection,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFF715E),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 19,
                          ),
                          shape: const StadiumBorder(),
                        ),
                        child: const Text(
                          '二人のつながりを始める',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'コードを作る・入力する方法を選べます',
                      style: TextStyle(
                        color: Color(0xFF929296),
                        fontSize: 13,
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

class _LandingArtwork extends StatelessWidget {
  const _LandingArtwork({required this.avatarBase64});

  final String avatarBase64;

  Widget _phone(double width) {
    return Container(
      width: width,
      height: width * 1.85,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF302D2B),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 12,
            offset: Offset(3, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: ColoredBox(
          color: const Color(0xFFFFF8F2),
          child: Column(
            children: [
              Container(
                width: width * 0.35,
                height: 9,
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF302D2B),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              Expanded(
                child: Center(
                  child: ProfileAvatar(
                    avatarBase64: avatarBase64,
                    size: width * 0.75,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 18),
                child: Icon(
                  Icons.photo_library_outlined,
                  color: Color(0xFFB95849),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;

          return ClipRect(
            child: Stack(
              children: [
                Positioned(
                  left: width * 0.07,
                  top: width * 0.04,
                  child: Transform.rotate(
                    angle: -12 * math.pi / 180,
                    child: _phone(width * 0.38),
                  ),
                ),
                Positioned(
                  right: width * 0.04,
                  bottom: width * 0.03,
                  child: Transform.rotate(
                    angle: 12 * math.pi / 180,
                    child: _phone(width * 0.38),
                  ),
                ),
                Positioned(
                  left: width * 0.39,
                  top: width * 0.35,
                  child: const Icon(
                    Icons.favorite_rounded,
                    color: Color(0xFFFFA18E),
                    size: 52,
                  ),
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
    this.onAlbum,
  });

  final String pairId;
  final bool showCelebration;
  final VoidCallback onEditProfile;
  final VoidCallback? onCapture;
  final VoidCallback? onAlbum;

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
          onAlbum: widget.onAlbum,
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
    this.onAlbum,
  });

  final String pairId;
  final PairDetails pair;
  final VoidCallback onEditProfile;
  final VoidCallback? onCapture;
  final VoidCallback? onAlbum;

  @override
  State<_ConnectedHome> createState() => _ConnectedHomeState();
}

class _ConnectedHomeState extends State<_ConnectedHome> {
  late final Stream<List<SharedPhoto>> _photosStream;
  bool _accountBusy = false;

  @override
  void initState() {
    super.initState();
    _photosStream = watchSharedPhotos(widget.pairId);
  }

  Future<void> _openCamera() async {
    if (widget.onCapture != null) {
      widget.onCapture!();
      return;
    }

    final result = await Navigator.of(context).push<XFile>(
      MaterialPageRoute<XFile>(
        builder: (_) => const PicScreen(),
      ),
    );

    if (!mounted || result == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('写真を共有しました。')),
    );
  }

  void _openAlbum() {
    if (widget.onAlbum != null) {
      widget.onAlbum!();
      return;
    }

    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AlbumScreen(
          pairId: widget.pairId,
          partnerName: widget.pair.partnerName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pair = widget.pair;

    return Scaffold(
      backgroundColor: const Color(0xFFFCFBFA),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              children: [
                Row(
                  children: [
                    Semantics(
                      label: 'プロフィールを変更',
                      button: true,
                      child: InkWell(
                        onTap: _accountBusy ? null : widget.onEditProfile,
                        child: ProfileAvatar(
                          avatarBase64: pair.myAvatar,
                          size: 42,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ProfileAvatar(
                      avatarBase64: pair.partnerAvatar,
                      size: 42,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        '${pair.partnerName}と接続中',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 38,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3E9E3),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.camera_alt_outlined,
                        size: 46,
                        color: Color(0xFFB95849),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'ふたりの写真を、ここから。',
                        style: TextStyle(fontSize: 17),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _accountBusy ? null : _openCamera,
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: const Text('相手を撮影する'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFFF715E),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              vertical: 18,
                            ),
                            shape: const StadiumBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: _accountBusy ? null : _openAlbum,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('ふたりのアルバム'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                const SizedBox(height: 20),
                StreamBuilder<List<SharedPhoto>>(
                  stream: _photosStream,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          '写真を取得できませんでした。\n'
                          'エミュレーターとルールを確認してください。',
                          textAlign: TextAlign.center,
                        ),
                      );
                    }

                    if (!snapshot.hasData) {
                      return const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }

                    final now = DateTime.now();

                    // 撮影時刻ではなく、共有が完了した日の写真。
                    final todayPhotos = snapshot.data!.where((photo) {
                      final date = photo.sharedAt;

                      return date != null &&
                          date.year == now.year &&
                          date.month == now.month &&
                          date.day == now.day;
                    }).toList();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              '今日の写真',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('${todayPhotos.length}枚'),
                            const Spacer(),
                            TextButton(
                              onPressed:
                                  _accountBusy ? null : _openAlbum,
                              child: const Text('すべて見る ›'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (todayPhotos.isEmpty)
                          Container(
                            height: 180,
                            width: double.infinity,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFECE9),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Text(
                              '今日の写真はまだありません。\n'
                              '撮影を終了して共有すると、ここに届きます。',
                              textAlign: TextAlign.center,
                              style: TextStyle(height: 1.8),
                            ),
                          )
                        else
                          SizedBox(
                            height: 190,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: todayPhotos.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 10),
                              itemBuilder: (context, index) {
                                final photo = todayPhotos[index];

                                return SizedBox(
                                  width: 140,
                                  child: GestureDetector(
                                    onTap: _accountBusy
                                        ? null
                                        : () {
                                            showSharedPhoto(
                                              context,
                                              photo,
                                              widget.pairId,
                                            );
                                          },
                                    child: ClipRRect(
                                      borderRadius:
                                          BorderRadius.circular(14),
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
                ),
                const SizedBox(height: 24),
                AccountActions(
                  enabled: !_accountBusy,
                  onFinished: () {
                    // membershipの変更を監視しているため、
                    // 両方のホームが未接続画面へ自動で切り替わる。
                  },
                  onBusyChanged: (busy) {
                    if (!mounted) return;
                    setState(() => _accountBusy = busy);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}