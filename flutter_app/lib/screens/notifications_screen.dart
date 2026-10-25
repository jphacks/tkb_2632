import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/favorite_service.dart';
import '../services/pair_service.dart';
import '../widgets/profile_avatar.dart';
import 'guess_screen.dart';
import 'shooting_chart_screen.dart';

const _titleColor = Color(0xFF0C1120);
const _timeColor = Color(0xFF5C5C5C);
const _dividerColor = Color(0xFFEBEBEB);
const _bellColor = Color(0xFF098C85);
const _unreadDotColor = Color(0xFFFF6048);

// ホーム右上のベル。未読の通知があれば赤い点を付ける。
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  late final Stream<bool> _hasUnread = FavoriteService()
      .watchNotifications()
      .map(
        (snapshot) => snapshot.docs.any(
          (document) => document.data()['read'] != true,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: _hasUnread,
      builder: (context, snapshot) {
        final hasUnread = snapshot.data ?? false;

        return IconButton(
          tooltip: hasUnread ? '通知（未読あり）' : '通知',
          onPressed: () {
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const NotificationsScreen(),
              ),
            );
          },
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(
                Icons.notifications_rounded,
                size: 28,
                color: _bellColor,
              ),
              if (hasUnread)
                Positioned(
                  top: 1,
                  right: 2,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: _unreadDotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// 通知一覧。未読（＝まだ回答していない）の通知だけを表示する。
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _service = FavoriteService();

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _notifications =
      _service.watchNotifications();

  // 通知に表示する相手の名前・アイコン。ペアごとに1回だけ取得する。
  final _pairs = <String, Future<PairDetails>>{};

  String? _openingId;

  Future<PairDetails> _pairFor(String pairId) {
    return _pairs.putIfAbsent(
      pairId,
      () => PairService().loadPair(pairId),
    );
  }

  Future<void> _openNotification(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) async {
    if (_openingId != null) {
      return;
    }

    setState(() {
      _openingId = document.id;
    });

    try {
      final data = document.data();
      final pairId = data['pairId'] as String;
      final sessionId = data['sessionId'] as String;

      final payload = await _service.loadQuiz(
        pairId: pairId,
        sessionId: sessionId,
      );

      if (!mounted) {
        return;
      }

      // 2択が作れない撮影セットは、クイズを出さずに既読にするだけ。
      if (payload == null) {
        await _service.markRead(document.id);
        return;
      }

      final candidates = [
        for (final photo in payload.photos)
          GuessCandidate(
            photoId: photo.id,
            imageBytes: photo.bytes,
          ),
      ];

      final candidateIds = candidates
          .map((candidate) => candidate.photoId)
          .toSet();

      if (candidates.length != 2 ||
          candidateIds.length != 2 ||
          !candidateIds.contains(payload.correctPhotoId)) {
        throw StateError('クイズの写真を確認できません。');
      }

      final partnerName = await _partnerName(pairId);

      if (!mounted) {
        return;
      }

      final selectedPhotoId = await Navigator.of(context).push<String>(
        MaterialPageRoute<String>(
          builder: (_) => GuessScreen(
            candidates: candidates,
            correctPhotoId: payload.correctPhotoId,
            reasonTags: payload.reasonLabels,
            partnerName: partnerName,
          ),
        ),
      );

      // 回答前に戻った場合は、未読のまま一覧に残す。
      if (selectedPhotoId == null) {
        return;
      }

      if (!candidateIds.contains(selectedPhotoId)) {
        throw StateError('クイズの回答を確認できませんでした。');
      }

      debugPrint(
        '[クイズ] 回答完了：'
        '${selectedPhotoId == payload.correctPhotoId ? '正解' : '不正解'}',
      );

      // 回答済みのクイズは一覧に出さないため、カルテを開く前に既読にする。
      await _service.markRead(document.id);

      if (!mounted) {
        return;
      }

      // 結果画面の「撮影カルテ」から、そのままカルテへ進む。
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ShootingChartScreen(
            pairId: pairId,
            highlightSessionId: sessionId,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              '画面を開くか、既読状態を保存する処理に失敗しました。\n'
              '$error',
            ),
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _openingId = null;
        });
      }
    }
  }

  // 名前を取得できなくてもクイズは開けるようにする。
  Future<String> _partnerName(String pairId) async {
    try {
      return (await _pairFor(pairId)).partnerName;
    } catch (error) {
      debugPrint('相手の名前の取得エラー: $error');
      return '相手';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            const SizedBox(height: 42),
            Expanded(child: _buildList()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
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
              tooltip: '戻る',
            ),
          ),
          const Text(
            '通知',
            style: TextStyle(
              fontSize: 16,
              height: 22 / 16,
              fontWeight: FontWeight.w600,
              color: _titleColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _notifications,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                '通知を取得できません。\n${snapshot.error}',
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final documents = snapshot.data!.docs
            .where((document) => document.data()['read'] != true)
            .toList()
          ..sort((a, b) {
            final aTime = a.data()['createdAt'];
            final bTime = b.data()['createdAt'];

            final aValue =
                aTime is Timestamp ? aTime.millisecondsSinceEpoch : 0;
            final bValue =
                bTime is Timestamp ? bTime.millisecondsSinceEpoch : 0;

            return bValue.compareTo(aValue);
          });

        if (documents.isEmpty) {
          return const Align(
            alignment: Alignment(0, -0.4),
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                '写真に「いいね！」が届くと、\n'
                'ここに通知が表示されます。',
                textAlign: TextAlign.center,
                style: TextStyle(color: _timeColor, height: 1.7),
              ),
            ),
          );
        }

        return ListView.builder(
          itemCount: documents.length,
          itemBuilder: (context, index) {
            final document = documents[index];
            final data = document.data();

            return FutureBuilder<PairDetails>(
              future: _pairFor(data['pairId'] as String),
              builder: (context, pairSnapshot) {
                final pair = pairSnapshot.data;

                return _NotificationTile(
                  partnerName: pair?.partnerName ?? '',
                  partnerAvatar: pair?.partnerAvatar ?? '',
                  time: notificationTime(data['createdAt']),
                  opening: _openingId == document.id,
                  onTap: _openingId == null
                      ? () => _openNotification(document)
                      : null,
                );
              },
            );
          },
        );
      },
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.partnerName,
    required this.partnerAvatar,
    required this.time,
    required this.opening,
    required this.onTap,
  });

  final String partnerName;
  final String partnerAvatar;
  final String time;
  final bool opening;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(21, 4, 20, 4),
        child: Row(
          children: [
            ProfileAvatar(avatarBase64: partnerAvatar, size: 48),
            const SizedBox(width: 19),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: _dividerColor),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            partnerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.25,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            '「いいね！」が届きました。',
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.25,
                              fontWeight: FontWeight.w500,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      time,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.25,
                        fontWeight: FontWeight.w500,
                        color: _timeColor,
                      ),
                    ),
                    SizedBox(
                      width: 24,
                      height: 18,
                      child: opening
                          ? const Center(
                              child: SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : const Icon(
                              Icons.chevron_right_rounded,
                              size: 22,
                              color: Color(0xFFB4B4B4),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 今日届いた通知は時刻、それより前は日付で表示する。
String notificationTime(dynamic value) {
  if (value is! Timestamp) {
    return '';
  }

  final date = value.toDate().toLocal();
  final now = DateTime.now();

  if (date.year == now.year &&
      date.month == now.month &&
      date.day == now.day) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  return '${date.month}/${date.day}';
}
