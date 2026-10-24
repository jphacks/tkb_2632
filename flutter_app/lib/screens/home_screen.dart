import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../pic.dart';
import '../services/pair_service.dart';
import '../widgets/profile_avatar.dart';

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

  void _openPairRegistration({required bool join}) {
    Navigator.of(context).push(
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
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Text(
                    '接続状態を確認できませんでした。\n'
                    '通信環境とFirestoreのルールを確認してください。',
                    textAlign: TextAlign.center,
                    style: TextStyle(height: 1.8),
                  ),
                ),
              ),
            ),
          );
        }

        if (!snapshot.hasData ||
            (snapshot.data!.metadata.isFromCache &&
                !snapshot.data!.exists)) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final membership = snapshot.data!;

        if (!membership.exists) {
          _hasSeenUnpaired = true;
          return _buildUnconnectedHome();
        }

        final pairId = membership.data()!['pairId'] as String;

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
                        padding: const EdgeInsets.fromLTRB(
                          20,
                          16,
                          20,
                          0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Semantics(
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
                            FilledButton.icon(
                              onPressed: () {
                                _openPairRegistration(join: true);
                              },
                              icon: const Icon(
                                Icons.people_alt_rounded,
                                size: 20,
                              ),
                              label: const Text('参加する'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFFFFAF7),
                                foregroundColor: const Color(0xFF291F1D),
                              ),
                            ),
                          ],
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
                padding: const EdgeInsets.fromLTRB(
                  24,
                  12,
                  24,
                  36,
                ),
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
                        onPressed: () {
                          _openPairRegistration(join: false);
                        },
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
                      '招待された方は、コードで参加',
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

// 未接続画面の紹介用イラスト
class _LandingArtwork extends StatelessWidget {
  const _LandingArtwork({
    required this.avatarBase64,
  });

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

// ペア情報を取得し、接続成功画面・接続後ホームを表示する。
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

  void _retry() {
    setState(() {
      _pairFuture = PairService().loadPair(widget.pairId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PairDetails>(
      future: _pairFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: SafeArea(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('二人の情報を取得できませんでした。'),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _retry,
                      child: const Text('再試行'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final pair = snapshot.data!;

        if (_showCelebration) {
          return ConnectionSuccessScreen(
            pair: pair,
            onContinue: () {
              setState(() {
                _showCelebration = false;
              });
            },
          );
        }

        return _ConnectedHome(
          pair: pair,
          onEditProfile: widget.onEditProfile,
          onCapture: widget.onCapture,
          onAlbum: widget.onAlbum,
        );
      },
    );
  }
}

// 接続後のホーム画面
class _ConnectedHome extends StatelessWidget {
  const _ConnectedHome({
    required this.pair,
    required this.onEditProfile,
    this.onCapture,
    this.onAlbum,
  });

  final PairDetails pair;
  final VoidCallback onEditProfile;
  final VoidCallback? onCapture;
  final VoidCallback? onAlbum;

  void _openCamera(BuildContext context) {
    // 呼び出し元から処理を指定した場合は、そちらを使う。
    final callback = onCapture;

    if (callback != null) {
      callback();
      return;
    }

    // 阿部さんが作成した撮影画面へ遷移する。
    // 撮影完了時はPicScreenが写真を返して閉じる。
    // 写真の保存・共有処理は、次の段階でここにつなぐ。
    Navigator.of(context).push<XFile>(
      MaterialPageRoute<XFile>(
        builder: (_) => const PicScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCFBFA),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.only(
                top: 32,
                bottom: 32,
              ),
              children: [
                Container(
                  height: 300,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDFDFDF),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            Semantics(
                              label: 'プロフィールを変更',
                              button: true,
                              child: InkWell(
                                onTap: onEditProfile,
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
                            const SizedBox(width: 20),
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
                      ),
                      Expanded(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                            ),
                            child: SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: () {
                                  _openCamera(context);
                                },
                                icon: const Icon(
                                  Icons.camera_alt_outlined,
                                ),
                                label: const Text(
                                  '相手を撮影する',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor:
                                      const Color(0xFFFF715E),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 18,
                                  ),
                                  shape: const StadiumBorder(),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 24),
                        child: Text(
                          'ふたりの写真を、ここから。',
                          style: TextStyle(
                            color: Color(0xFF787878),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                  ),
                  child: Row(
                    children: [
                      const Text(
                        '今日の写真',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '0枚',
                        style: TextStyle(
                          color: Color(0xFF929296),
                          fontSize: 12,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: onAlbum,
                        child: const Text('すべて見る ›'),
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 196,
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E5E5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.photo_library_outlined,
                        color: Color(0xFF999999),
                        size: 36,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'まだ写真はありません',
                        style: TextStyle(
                          color: Color(0xFF888888),
                        ),
                      ),
                    ],
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