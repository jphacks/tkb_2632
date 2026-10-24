import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../screens/guess_screen.dart';
import '../screens/memories_screen.dart';
import '../screens/partner_albums_screen.dart';
import '../services/favorite_service.dart';

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

  // 独自のクイズ起動処理を指定する場合に使用する。
  // 指定しなければ、今回取り込んだGuessScreenを開く。
  final StartQuiz? onStartQuiz;

  @override
  State<FocusShell> createState() => _FocusShellState();
}

class _FocusShellState extends State<FocusShell> {
  final _service = FavoriteService();

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _notifications;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;

  int _selectedIndex = 0;
  int _unreadCount = 0;

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
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
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

      if (payload == null) {
        // お気に入り以外の写真が2枚未満の場合。
        // 3択を作れないため、お気に入りの結果を表示する。
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SessionPhotosScreen(
              pairId: pairId,
              sessionId: sessionId,
            ),
          ),
        );

        await _service.markRead(document.id);
        return;
      }

      final customStartQuiz = widget.onStartQuiz;

      if (customStartQuiz != null) {
        await customStartQuiz(context, payload);
        await _service.markRead(document.id);
        return;
      }

      // 保存済みの順番のまま、クイズ画面用のデータへ変換する。
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
        throw StateError(
          'クイズの写真を確認できません。\n'
          '異なる写真3枚と、正解の写真が必要です。',
        );
      }

      // 阿部さんのクイズ画面を開く。
      // 回答→結果表示→閉じると、選んだ写真IDが返ってくる。
      final selectedPhotoId = await Navigator.of(context).push<String>(
        MaterialPageRoute<String>(
          builder: (_) => GuessScreen(
            candidates: candidates,
            correctPhotoId: payload.correctPhotoId,
            reasonTags: payload.reasonLabels,
          ),
        ),
      );

      // 回答する前に戻った場合は、未読のまま残す。
      if (selectedPhotoId == null) {
        return;
      }

      if (!candidateIds.contains(selectedPhotoId)) {
        throw StateError('クイズの回答を確認できませんでした。');
      }

      // 正解・不正解の表示はGuessScreen側が行う。
      // ここでは、回答して戻ってきた通知を既読にする。
      await _service.markRead(document.id);

      debugPrint(
        '[クイズ] 回答完了：'
        '${selectedPhotoId == payload.correctPhotoId ? '正解' : '不正解'}',
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
              'お知らせを開くか、既読状態を保存する処理に失敗しました。\n'
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
            return const Center(
              child: CircularProgressIndicator(),
            );
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
            separatorBuilder: (_, _) {
              return const SizedBox(height: 12);
            },
            itemBuilder: (context, index) {
              final document = documents[index];
              final data = document.data();

              final unread = data['read'] != true;
              final opening = _openingId == document.id;
              final quizAvailable = data['quizAvailable'] == true;

              final description = quizAvailable
                  ? 'どの写真が選ばれたかな？タップしてクイズへ'
                  : 'お気に入りの写真を見てみよう';

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
                      : const Icon(
                          Icons.chevron_right,
                        ),
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
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          widget.child,
          const PartnerAlbumsScreen(),
          _buildNotifications(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
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