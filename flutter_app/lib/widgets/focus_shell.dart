import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../screens/guess_screen.dart';
import '../screens/memories_screen.dart';
import '../screens/partner_albums_screen.dart';
import '../screens/shooting_chart_screen.dart';
import '../services/favorite_service.dart';
import '../services/pair_service.dart';

typedef StartQuiz = Future<void> Function(
  BuildContext context,
  QuizPayload payload,
);

class FocusShell extends StatefulWidget {
  const FocusShell({
    super.key,
    required this.child,
    this.onStartQuiz,
  });

  final Widget child;

  // 既存の呼び出しとの互換性のため残す。
  // 通常は指定せず、GuessScreenを使用する。
  final StartQuiz? onStartQuiz;

  @override
  State<FocusShell> createState() => _FocusShellState();
}

class _FocusShellState extends State<FocusShell> {
  final _service = FavoriteService();

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _notifications;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _membershipSubscription;

  int _selectedIndex = 0;
  int _unreadCount = 0;

  // つながる前は「お知らせ」タブを出さない。
  bool _connected = false;

  bool _checkedInitialNotifications = false;
  String? _openingId;

  @override
  void initState() {
    super.initState();

    _notifications = _service.watchNotifications();

    _subscription = _notifications.listen(
      (snapshot) {
        if (!mounted) {
          return;
        }

        final unread = snapshot.docs
            .where((document) => document.data()['read'] != true)
            .length;

        final openInitially = !_checkedInitialNotifications &&
            !snapshot.metadata.isFromCache &&
            unread > 0;

        if (!snapshot.metadata.isFromCache) {
          _checkedInitialNotifications = true;
        }

        setState(() {
          _unreadCount = unread;

          if (openInitially) {
            _selectedIndex = 2;
          }
        });
      },
      onError: (Object error) {
        debugPrint('お知らせの取得エラー: $error');
      },
    );

    _membershipSubscription = PairService().watchMembership().listen(
      (document) {
        if (!mounted || document.exists == _connected) {
          return;
        }

        setState(() {
          _connected = document.exists;
        });
      },
      onError: (Object error) {
        debugPrint('接続状態の取得エラー: $error');
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _membershipSubscription?.cancel();
    super.dispose();
  }

  Future<void> _openChart({
    required String pairId,
    required String sessionId,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ShootingChartScreen(
          pairId: pairId,
          highlightSessionId: sessionId,
        ),
      ),
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

      if (payload != null) {
        final customStartQuiz = widget.onStartQuiz;

        if (customStartQuiz != null) {
          // 独自の起動処理を使う場合は、完了後にカルテへ進む。
          await customStartQuiz(context, payload);
        } else {
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

          if (candidates.length != 3 ||
              candidateIds.length != 3 ||
              !candidateIds.contains(payload.correctPhotoId)) {
            throw StateError('クイズの写真を確認できません。');
          }

          final selectedPhotoId =
              await Navigator.of(context).push<String>(
            MaterialPageRoute<String>(
              builder: (_) => GuessScreen(
                candidates: candidates,
                correctPhotoId: payload.correctPhotoId,
                reasonTags: payload.reasonLabels,
              ),
            ),
          );

          // 回答前に戻った場合はカルテを開かず、未読のまま残す。
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
        }
      }

      if (!mounted) {
        return;
      }

      // 正解・不正解を問わず、回答後は必ずカルテへ進む。
      // 3択が作れない撮影セットも、カルテでお気に入りを確認する。
      await _openChart(
        pairId: pairId,
        sessionId: sessionId,
      );

      // カルテから戻ったら通知を既読にする。
      await _service.markRead(document.id);
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

  Widget _buildNotifications() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('お知らせ'),
        automaticallyImplyLeading: false,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _notifications,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'お知らせを取得できません。\n${snapshot.error}',
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final documents = snapshot.data!.docs.toList()
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
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '写真にお気に入りが付くと、\n'
                  'ここにお知らせが届きます。',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: documents.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final document = documents[index];
              final data = document.data();

              final unread = data['read'] != true;
              final opening = _openingId == document.id;
              final quizAvailable = data['quizAvailable'] == true;

              final description = quizAvailable
                  ? 'どの写真が選ばれたかな？タップしてクイズへ'
                  : '届いた「好き」を撮影カルテで見てみよう';

              return Card(
                color: unread
                    ? const Color(0xFFFFEDE7)
                    : Theme.of(context).colorScheme.surface,
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: const Icon(
                    Icons.favorite,
                    color: Color(0xFFB95849),
                  ),
                  title: const Text(
                    'あなたの写真に「好き」が届きました！',
                  ),
                  subtitle: Text(
                    '${memoryDate(data['createdAt'])}\n$description',
                  ),
                  isThreeLine: true,
                  trailing: opening
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: _openingId == null
                      ? () => _openNotification(document)
                      : null,
                ),
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex =
        !_connected && _selectedIndex == 2 ? 0 : _selectedIndex;

    return Scaffold(
      body: IndexedStack(
        index: selectedIndex,
        children: [
          widget.child,
          const PartnerAlbumsScreen(),
          _buildNotifications(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'ホーム',
          ),
          const NavigationDestination(
            icon: Icon(Icons.photo_library_outlined),
            selectedIcon: Icon(Icons.photo_library),
            label: 'アルバム',
          ),
          if (_connected)
            NavigationDestination(
              icon: const Icon(Icons.notifications_none),
              selectedIcon: const Icon(Icons.notifications),
              label: _unreadCount == 0
                  ? 'お知らせ'
                  : 'お知らせ ($_unreadCount)',
            ),
        ],
      ),
    );
  }
}