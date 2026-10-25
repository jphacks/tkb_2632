import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import '../services/favorite_service.dart';

String memoryDate(dynamic value) {
  if (value is! Timestamp) {
    return '日時を確認しています';
  }

  final date = value.toDate().toLocal();
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');

  return '${date.year}/$month/$day $hour:$minute';
}

int _timeValue(dynamic value) {
  return value is Timestamp ? value.millisecondsSinceEpoch : 0;
}

// 接続中・接続終了後のペアを一覧表示する画面。
class MemoriesScreen extends StatefulWidget {
  const MemoriesScreen({super.key});

  @override
  State<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends State<MemoriesScreen> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _pairs;

  @override
  void initState() {
    super.initState();

    final uid = FirebaseAuth.instance.currentUser!.uid;

    _pairs = FirebaseFirestore.instance
        .collection('pairs')
        .where('memberIds', arrayContains: uid)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('アルバム'),
        automaticallyImplyLeading: false,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _pairs,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'アルバムを取得できません。\n${snapshot.error}',
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final pairs = snapshot.data!.docs.toList()
            ..sort(
              (a, b) => _timeValue(
                b.data()['createdAt'],
              ).compareTo(
                _timeValue(a.data()['createdAt']),
              ),
            );

          if (pairs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '相手とつながると、ここにアルバムができます。\n'
                  '接続を解除したあとも写真は残ります。',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: pairs.length,
            separatorBuilder: (_, _) {
              return const SizedBox(height: 12);
            },
            itemBuilder: (context, index) {
              final pair = pairs[index];
              final data = pair.data();
              final disconnected = data.containsKey('disconnectedAt');

              final statusText = disconnected
                  ? '接続終了・写真は保存されています'
                  : '接続中';

              return Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: const Icon(
                    Icons.photo_library_outlined,
                  ),
                  title: Text(
                    'ふたりのアルバム · ${pair.id}',
                  ),
                  subtitle: Text(
                    '${memoryDate(data['createdAt'])}\n$statusText',
                  ),
                  isThreeLine: true,
                  trailing: const Icon(
                    Icons.chevron_right,
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PairSessionsScreen(
                          pairId: pair.id,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// 選択したペアの撮影セッションを一覧表示する画面。
class PairSessionsScreen extends StatefulWidget {
  const PairSessionsScreen({
    super.key,
    required this.pairId,
  });

  final String pairId;

  @override
  State<PairSessionsScreen> createState() => _PairSessionsScreenState();
}

class _PairSessionsScreenState extends State<PairSessionsScreen> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _sessions;

  bool _receivedOnly = false;

  @override
  void initState() {
    super.initState();

    _sessions = FirebaseFirestore.instance
        .collection('pairs')
        .doc(widget.pairId)
        .collection('sessions')
        .where('status', isEqualTo: 'shared')
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('撮影ごとの思い出'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('すべて'),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('撮ってもらった'),
                ),
              ],
              selected: {_receivedOnly},
              onSelectionChanged: (values) {
                setState(() {
                  _receivedOnly = values.first;
                });
              },
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _sessions,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        '写真を取得できません。\n${snapshot.error}',
                      ),
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                final sessions = snapshot.data!.docs.where((document) {
                  return !_receivedOnly ||
                      document.data()['authorUid'] != uid;
                }).toList()
                  ..sort(
                    (a, b) => _timeValue(
                      b.data()['sharedAt'],
                    ).compareTo(
                      _timeValue(a.data()['sharedAt']),
                    ),
                  );

                if (sessions.isEmpty) {
                  return const Center(
                    child: Text('まだ写真がありません。'),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: sessions.length,
                  separatorBuilder: (_, _) {
                    return const SizedBox(height: 12);
                  },
                  itemBuilder: (context, index) {
                    final session = sessions[index];
                    final data = session.data();

                    final paths = List<String>.from(
                      data['photoPaths'] as List,
                    );

                    final mine = data['authorUid'] == uid;

                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(12),
                        leading: SizedBox(
                          width: 64,
                          height: 64,
                          child: paths.isEmpty
                              ? const Icon(Icons.photo_outlined)
                              : StoredMemoryPhoto(
                                  path: paths.first,
                                ),
                        ),
                        title: Text(
                          mine ? '自分が撮った写真' : '撮ってもらった写真',
                        ),
                        subtitle: Text(
                          '${memoryDate(data['sharedAt'])}\n'
                          '${paths.length}枚',
                        ),
                        isThreeLine: true,
                        trailing: const Icon(
                          Icons.chevron_right,
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => SessionPhotosScreen(
                                pairId: widget.pairId,
                                sessionId: session.id,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// 1セッションの写真と、お気に入り選択を表示する画面。
class SessionPhotosScreen extends StatefulWidget {
  const SessionPhotosScreen({
    super.key,
    required this.pairId,
    required this.sessionId,
  });

  final String pairId;
  final String sessionId;

  @override
  State<SessionPhotosScreen> createState() => _SessionPhotosScreenState();
}

class _SessionPhotosScreenState extends State<SessionPhotosScreen> {
  final _service = FavoriteService();

  final Map<String, Set<String>> _selections = {};

  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _session;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _feedback;

  bool _saving = false;

  @override
  void initState() {
    super.initState();

    _session = _service
        .sessionRef(widget.pairId, widget.sessionId)
        .snapshots();

    _feedback = _service
        .feedbackRef(widget.pairId, widget.sessionId)
        .snapshots();
  }

  Future<void> _editFavorite(String path) async {
    final selectedReasons = Set<String>.from(
      _selections[path] ?? <String>{},
    );

    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'この写真のどこが好き？',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '理由を1つ以上選んでください。複数選べます。',
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 200,
                      child: StoredMemoryPhoto(
                        path: path,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final reason in favoriteReasonLabels.entries)
                          FilterChip(
                            label: Text(reason.value),
                            selected: selectedReasons.contains(reason.key),
                            onSelected: (selected) {
                              setSheetState(() {
                                if (selected) {
                                  selectedReasons.add(reason.key);
                                } else {
                                  selectedReasons.remove(reason.key);
                                }
                              });
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: selectedReasons.isEmpty
                          ? null
                          : () {
                              Navigator.of(sheetContext).pop(
                                Set<String>.from(selectedReasons),
                              );
                            },
                      child: const Text('お気に入りにする'),
                    ),
                    if (_selections.containsKey(path))
                      TextButton(
                        onPressed: () {
                          Navigator.of(sheetContext).pop(
                            <String>{},
                          );
                        },
                        child: const Text('お気に入りから外す'),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted || result == null) {
      return;
    }

    setState(() {
      if (result.isEmpty) {
        _selections.remove(path);
      } else {
        _selections[path] = result;
      }
    });
  }

  Future<void> _submit() async {
    if (_saving || _selections.isEmpty) {
      return;
    }

    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('お気に入りを送りますか？'),
        content: Text(
          '${_selections.length}枚のお気に入りと理由をまとめて送ります。\n\n'
          '確定後は、この撮影セットの選び直しはできません。',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(false);
            },
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(true);
            },
            child: const Text('送る'),
          ),
        ],
      ),
    );

    if (accepted != true || !mounted) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final created = await _service.submit(
        pairId: widget.pairId,
        sessionId: widget.sessionId,
        selections: _selections,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            created
                ? 'お気に入りを送りました！'
                : 'この撮影セットのお気に入りは送信済みです。',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '送信できませんでした。\n$error',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  void _showPhoto(String path) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: StoredMemoryPhoto(
                path: path,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('撮影セット'),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _session,
        builder: (context, sessionSnapshot) {
          if (sessionSnapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '写真を取得できません。\n${sessionSnapshot.error}',
                ),
              ),
            );
          }

          if (!sessionSnapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final session = sessionSnapshot.data!.data();

          if (session == null || session['status'] != 'shared') {
            return const Center(
              child: Text('共有済みの写真がありません。'),
            );
          }

          final paths = List<String>.from(
            session['photoPaths'] as List,
          );

          final received = session['authorUid'] != _service.uid;

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _feedback,
            builder: (context, feedbackSnapshot) {
              if (feedbackSnapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'お気に入りを取得できません。\n'
                      '${feedbackSnapshot.error}',
                    ),
                  ),
                );
              }

              if (!feedbackSnapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              }

              final feedback = feedbackSnapshot.data!.data();
              final finalized = feedback != null;

              var quizAvailable = false;
              var showResults = false;

              final savedFavorites = <String>{};
              final reasonMap = <String, dynamic>{};

              if (feedback != null) {
                quizAvailable = feedback['quizAvailable'] == true;

                // 撮影者にはクイズ前に正解を表示しない。
                showResults = received || !quizAvailable;

                savedFavorites.addAll(
                  List<String>.from(
                    feedback['favorites'] as List,
                  ),
                );

                reasonMap.addAll(
                  Map<String, dynamic>.from(
                    feedback['reasons'] as Map,
                  ),
                );
              }

              // 状態に応じた案内文を作成する。
              final String statusMessage;

              if (received) {
                if (finalized) {
                  statusMessage = 'お気に入りを送信しました';
                } else {
                  statusMessage = 'ハートを押して、好きな写真と理由を選ぼう';
                }
              } else {
                if (!finalized) {
                  statusMessage = '相手のお気に入りを待っています';
                } else if (quizAvailable) {
                  statusMessage =
                      'お気に入りが届いています。ホームのベル（通知）から確認できます。';
                } else {
                  statusMessage = 'お気に入りが届きました';
                }
              }

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text(
                          memoryDate(session['sharedAt']),
                          style: const TextStyle(
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          statusMessage,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.fromLTRB(
                        16,
                        0,
                        16,
                        16,
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.63,
                      ),
                      itemCount: paths.length,
                      itemBuilder: (context, index) {
                        final path = paths[index];

                        final bool selected;
                        final labels = <String>[];

                        if (finalized) {
                          selected =
                              showResults && savedFavorites.contains(path);

                          if (showResults) {
                            for (final reason
                                in favoriteReasonLabels.entries) {
                              final reasonPaths =
                                  reasonMap[reason.key] as List? ?? [];

                              if (reasonPaths.contains(path)) {
                                labels.add(reason.value);
                              }
                            }
                          }
                        } else {
                          selected = _selections.containsKey(path);

                          for (final key
                              in _selections[path] ?? <String>{}) {
                            final label = favoriteReasonLabels[key];

                            if (label != null) {
                              labels.add(label);
                            }
                          }
                        }

                        final canEdit =
                            received && !finalized && !_saving;

                        return Card(
                          margin: EdgeInsets.zero,
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    _showPhoto(path);
                                  },
                                  child: SizedBox.expand(
                                    child: StoredMemoryPhoto(
                                      path: path,
                                    ),
                                  ),
                                ),
                              ),
                              Row(
                                children: [
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      '写真 ${index + 1}',
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: canEdit
                                        ? () => _editFavorite(path)
                                        : null,
                                    icon: Icon(
                                      selected
                                          ? Icons.favorite
                                          : Icons.favorite_border,
                                      color: selected
                                          ? const Color(0xFFB95849)
                                          : Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(
                                height: 38,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  child: Text(
                                    labels.join('・'),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  if (received && !finalized)
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _saving || _selections.isEmpty
                                ? null
                                : _submit,
                            icon: const Icon(
                              Icons.favorite,
                            ),
                            label: Text(
                              _saving
                                  ? '送信しています…'
                                  : '${_selections.length}枚の「好き」をまとめて送る',
                            ),
                          ),
                        ),
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

// Storageの写真を読み込んで表示するウィジェット。
class StoredMemoryPhoto extends StatefulWidget {
  const StoredMemoryPhoto({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
  });

  final String path;
  final BoxFit fit;

  @override
  State<StoredMemoryPhoto> createState() => _StoredMemoryPhotoState();
}

class _StoredMemoryPhotoState extends State<StoredMemoryPhoto> {
  late Future<Uint8List?> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant StoredMemoryPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.path != widget.path) {
      _load();
    }
  }

  void _load() {
    _future = FirebaseStorage.instance
        .ref(widget.path)
        .getData(2 * 1024 * 1024)
        .timeout(
          const Duration(seconds: 30),
        );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
              ),
            ),
          );
        }

        if (snapshot.hasError || snapshot.data == null) {
          return Center(
            child: IconButton(
              tooltip: '写真を再読み込み',
              onPressed: () {
                setState(_load);
              },
              icon: const Icon(
                Icons.refresh,
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
          errorBuilder: (_, _, _) {
            return const Center(
              child: Icon(
                Icons.broken_image_outlined,
              ),
            );
          },
        );
      },
    );
  }
}