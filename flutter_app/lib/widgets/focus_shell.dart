import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../screens/memories_screen.dart';
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

  // クイズ担当者の画面ができたら、ここに画面遷移を渡す。
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
        if (!mounted) return;

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

          // 起動時に未読があれば、お知らせを最初に表示する。
          if (openInitially) {
            _selectedIndex = 2;
          }
        });
      },
      onError: (Object error) {
        // お知らせタブのStreamBuilderにもエラーが表示される。
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
    if (_openingId != null) return;

    setState(() => _openingId = document.id);

    final data = document.data();
    final pairId = data['pairId'] as String;
    final sessionId = data['sessionId'] as String;

    try {
      final payload = await _service.loadQuiz(
        pairId: pairId,
        sessionId: sessionId,
      );

      if (!mounted) return;

      if (payload == null) {
        // 不正解候補が2枚ない場合は、結果をそのまま見せる。
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SessionPhotosScreen(
              pairId: pairId,
              sessionId: sessionId,
            ),
          ),
        );
      } else if (widget.onStartQuiz != null) {
        await widget.onStartQuiz!(context, payload);
      } else {
        // ここをクイズ担当者の画面につなぐ。
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('お気に入りが届きました！'),
            content: const Text(
              'クイズに使う3枚の写真を読み込めました。\n\n'
              'クイズ画面との接続は準備中です。\n'
              '正解・写真の順番・好きな理由は保存されています。',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('閉じる'),
              ),
            ],
          ),
        );
      }

      // 既読にしても一覧には残り、何度でも開ける。
      await _service.markRead(document.id);
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('お知らせを開けませんでした。\n$error')),
      );
    } finally {
      if (mounted) {
        setState(() => _openingId = null);
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
                child: Text('お知らせを取得できません。\n${snapshot.error}'),
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
              child: Text(
                '写真にお気に入りが付くと、\nここにお知らせが届きます。',
                textAlign: TextAlign.center,
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
                  title: const Text('あなたの写真に「好き」が届きました！'),
                  subtitle: Text(
                    '${memoryDate(data['createdAt'])}\n'
                    '${quizAvailable ? 'どの写真が選ばれたかな？' : 'お気に入りの写真を見てみよう'}',
                  ),
                  isThreeLine: true,
                  trailing: opening
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
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
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          widget.child,
          const MemoriesScreen(),
          _buildNotifications(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
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