import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/profile_avatar.dart';
import 'memories_screen.dart';

typedef _PairDocument = QueryDocumentSnapshot<Map<String, dynamic>>;

int _timestampValue(dynamic value) {
  return value is Timestamp ? value.millisecondsSinceEpoch : 0;
}

String? _partnerUid(Map<String, dynamic> data, String myUid) {
  final members = data['memberIds'];

  if (members is! List || !members.contains(myUid)) {
    return null;
  }

  for (final member in members) {
    if (member is String && member != myUid) {
      return member;
    }
  }

  return null;
}

class _PartnerAlbum {
  _PartnerAlbum({
    required this.partnerUid,
    required this.pairs,
  });

  final String partnerUid;
  final List<_PairDocument> pairs;

  bool get connected {
    return pairs.any(
      (pair) => !pair.data().containsKey('disconnectedAt'),
    );
  }

  int get latestTime {
    var latest = 0;

    for (final pair in pairs) {
      final value = _timestampValue(pair.data()['createdAt']);

      if (value > latest) {
        latest = value;
      }
    }

    return latest;
  }

  Map<String, dynamic>? get savedProfile {
    final sorted = pairs.toList()
      ..sort(
        (a, b) => _timestampValue(b.data()['createdAt']).compareTo(
          _timestampValue(a.data()['createdAt']),
        ),
      );

    for (final pair in sorted) {
      final profiles = pair.data()['memberProfiles'];

      if (profiles is! Map) {
        continue;
      }

      final profile = profiles[partnerUid];

      if (profile is Map) {
        final data = Map<String, dynamic>.from(profile);
        final nickname = data['nickname'];

        if (nickname is String && nickname.trim().isNotEmpty) {
          return data;
        }
      }
    }

    return null;
  }

  String get name {
    final nickname = savedProfile?['nickname'];

    if (nickname is String && nickname.trim().isNotEmpty) {
      return nickname;
    }

    return '名前未保存の相手';
  }

  String get avatar {
    final value = savedProfile?['avatarBase64'];
    return value is String ? value : '';
  }

  String get shortId {
    if (partnerUid.length <= 8) {
      return partnerUid;
    }

    return partnerUid.substring(0, 8);
  }
}

// 下部「アルバム」で表示する、相手ごとの一覧。
class PartnerAlbumsScreen extends StatefulWidget {
  const PartnerAlbumsScreen({super.key});

  @override
  State<PartnerAlbumsScreen> createState() => _PartnerAlbumsScreenState();
}

class _PartnerAlbumsScreenState extends State<PartnerAlbumsScreen> {
  final _db = FirebaseFirestore.instance;

  late final String _uid;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;

  List<_PairDocument> _pairs = [];
  final Set<String> _attemptedProfiles = {};
  final Map<String, String> _profileErrors = {};

  bool _loading = true;
  Object? _loadError;

  @override
  void initState() {
    super.initState();

    _uid = FirebaseAuth.instance.currentUser!.uid;
    _listen();
  }

  void _listen() {
    _subscription = _db
        .collection('pairs')
        .where('memberIds', arrayContains: _uid)
        .snapshots()
        .listen(
      (snapshot) {
        if (!mounted) {
          return;
        }

        setState(() {
          _pairs = snapshot.docs;
          _loading = false;
          _loadError = null;

          final activeIds = _pairs
              .where(
                (pair) => !pair.data().containsKey('disconnectedAt'),
              )
              .map((pair) => pair.id)
              .toSet();

          _profileErrors.removeWhere(
            (pairId, _) => !activeIds.contains(pairId),
          );
        });

        // キャッシュ上の古い接続状態だけでは保存を始めない。
        if (!snapshot.metadata.isFromCache) {
          for (final pair in snapshot.docs) {
            unawaited(_saveProfilesIfNeeded(pair));
          }
        }
      },
      onError: (Object error) {
        if (!mounted) {
          return;
        }

        setState(() {
          _loadError = error;
          _loading = false;
        });
      },
    );
  }

  Future<void> _saveProfilesIfNeeded(
    _PairDocument pair, {
    bool force = false,
  }) async {
    final data = pair.data();

    if (data.containsKey('disconnectedAt')) {
      return;
    }

    final members = List<String>.from(data['memberIds'] as List);
    final existing = data['memberProfiles'];

    final alreadySaved = existing is Map &&
        members.every((memberUid) => existing[memberUid] is Map);

    if (!force && alreadySaved) {
      return;
    }

    if (!_attemptedProfiles.add(pair.id)) {
      return;
    }

    try {
      final documents = await Future.wait(
        members.map(
          (memberUid) => _db
              .collection('users')
              .doc(memberUid)
              .get(const GetOptions(source: Source.server)),
        ),
      );

      final profiles = <String, Map<String, dynamic>>{};

      for (var index = 0; index < members.length; index++) {
        final profile = documents[index].data();

        if (profile == null) {
          throw StateError('相手のプロフィールを確認できません。');
        }

        profiles[members[index]] = profile;
      }

      // 写真や所属情報は変更せず、プロフィールの写しだけ保存。
      await pair.reference.update({
        'memberProfiles': profiles,
      });

      if (!mounted) {
        return;
      }

      setState(() {
        _profileErrors.remove(pair.id);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      final stillConnected = _pairs.any(
        (current) =>
            current.id == pair.id &&
            !current.data().containsKey('disconnectedAt'),
      );

      if (stillConnected) {
        setState(() {
          _profileErrors[pair.id] = error.toString();
        });
      }
    }
  }

  void _refreshProfiles() {
    _attemptedProfiles.clear();

    for (final pair in _pairs) {
      unawaited(
        _saveProfilesIfNeeded(pair, force: true),
      );
    }
  }

  List<_PartnerAlbum> _groupByPartner() {
    final groups = <String, List<_PairDocument>>{};

    for (final pair in _pairs) {
      final partner = _partnerUid(pair.data(), _uid);

      if (partner == null) {
        continue;
      }

      groups.putIfAbsent(partner, () => []).add(pair);
    }

    final albums = [
      for (final group in groups.entries)
        _PartnerAlbum(
          partnerUid: group.key,
          pairs: group.value,
        ),
    ];

    albums.sort((a, b) {
      // 接続中の相手を先頭にする。
      if (a.connected != b.connected) {
        return a.connected ? -1 : 1;
      }

      return b.latestTime.compareTo(a.latestTime);
    });

    return albums;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final albums = _groupByPartner();

    return Scaffold(
      appBar: AppBar(
        title: const Text('これまでのアルバム'),
        actions: [
          IconButton(
            onPressed: _refreshProfiles,
            tooltip: '接続中の名前・アイコンを更新',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_profileErrors.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '名前・アイコンを保存できませんでした。'
                    'ルールの更新と接続を確認してください。',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _profileErrors.values.first,
                    style: const TextStyle(fontSize: 11),
                  ),
                  TextButton(
                    onPressed: _refreshProfiles,
                    child: const Text('プロフィールの保存を再試行'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _buildAlbums(albums),
          ),
        ],
      ),
    );
  }

  Widget _buildAlbums(List<_PartnerAlbum> albums) {
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('アルバムを取得できません。\n$_loadError'),
        ),
      );
    }

    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (albums.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '相手とつながると、ここにアルバムができます。\n'
            '写真は相手ごとにまとまります。',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: albums.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final album = albums[index];
        final hasProfile = album.savedProfile != null;

        var subtitle = album.connected
            ? 'つながっています'
            : '過去の思い出を見る';

        if (!hasProfile) {
          subtitle += '\n相手ID：${album.shortId}';
        }

        return Card(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: ProfileAvatar(
              avatarBase64: album.avatar,
              size: 56,
            ),
            title: Text(
              '${album.name}とのアルバム',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(subtitle),
            isThreeLine: !hasProfile,
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _PartnerSessionsScreen(
                    partnerUid: album.partnerUid,
                    partnerName: album.name,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _SessionEntry {
  const _SessionEntry({
    required this.pairId,
    required this.sessionId,
    required this.data,
  });

  final String pairId;
  final String sessionId;
  final Map<String, dynamic> data;

  String get key => '$pairId/$sessionId';

  int get time {
    return _timestampValue(
      data['sharedAt'] ?? data['createdAt'],
    );
  }
}

// 同じ相手とのすべての接続履歴から、撮影セッションをまとめる。
class _PartnerSessionsScreen extends StatefulWidget {
  const _PartnerSessionsScreen({
    required this.partnerUid,
    required this.partnerName,
  });

  final String partnerUid;
  final String partnerName;

  @override
  State<_PartnerSessionsScreen> createState() =>
      _PartnerSessionsScreenState();
}

class _PartnerSessionsScreenState extends State<_PartnerSessionsScreen> {
  final _db = FirebaseFirestore.instance;

  late final String _uid;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _pairSubscription;

  final Map<
      String,
      StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
      _sessionSubscriptions = {};

  final Map<String, List<_SessionEntry>> _sessions = {};
  final Map<String, Object> _sessionErrors = {};
  final Set<String> _waitingPairs = {};

  bool _pairsLoaded = false;
  bool _receivedOnly = false;
  Object? _pairError;

  @override
  void initState() {
    super.initState();

    _uid = FirebaseAuth.instance.currentUser!.uid;

    _pairSubscription = _db
        .collection('pairs')
        .where('memberIds', arrayContains: _uid)
        .snapshots()
        .listen(
      _updatePairs,
      onError: (Object error) {
        if (!mounted) {
          return;
        }

        setState(() {
          _pairError = error;
          _pairsLoaded = true;
        });
      },
    );
  }

  void _updatePairs(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    if (!mounted) {
      return;
    }

    final pairIds = snapshot.docs
        .where(
          (pair) =>
              _partnerUid(pair.data(), _uid) == widget.partnerUid,
        )
        .map((pair) => pair.id)
        .toSet();

    final removedIds = _sessionSubscriptions.keys
        .where((pairId) => !pairIds.contains(pairId))
        .toList();

    for (final pairId in removedIds) {
      _sessionSubscriptions.remove(pairId)?.cancel();
      _sessions.remove(pairId);
      _sessionErrors.remove(pairId);
      _waitingPairs.remove(pairId);
    }

    for (final pairId in pairIds) {
      if (_sessionSubscriptions.containsKey(pairId)) {
        continue;
      }

      _waitingPairs.add(pairId);

      final stream = _db
          .collection('pairs')
          .doc(pairId)
          .collection('sessions')
          .where('status', isEqualTo: 'shared')
          .snapshots();

      _sessionSubscriptions[pairId] = stream.listen(
        (sessionsSnapshot) {
          if (!mounted || !_sessionSubscriptions.containsKey(pairId)) {
            return;
          }

          setState(() {
            _sessions[pairId] = [
              for (final document in sessionsSnapshot.docs)
                _SessionEntry(
                  pairId: pairId,
                  sessionId: document.id,
                  data: document.data(),
                ),
            ];

            _sessionErrors.remove(pairId);
            _waitingPairs.remove(pairId);
          });
        },
        onError: (Object error) {
          if (!mounted || !_sessionSubscriptions.containsKey(pairId)) {
            return;
          }

          setState(() {
            _sessionErrors[pairId] = error;
            _waitingPairs.remove(pairId);
          });
        },
      );
    }

    setState(() {
      _pairsLoaded = true;
      _pairError = null;
    });
  }

  List<_SessionEntry> _visibleSessions() {
    final entries = _sessions.values.expand((items) => items).where(
      (entry) {
        return !_receivedOnly || entry.data['authorUid'] != _uid;
      },
    ).toList();

    entries.sort((a, b) {
      final timeOrder = b.time.compareTo(a.time);

      if (timeOrder != 0) {
        return timeOrder;
      }

      return a.key.compareTo(b.key);
    });

    return entries;
  }

  @override
  void dispose() {
    _pairSubscription?.cancel();

    for (final subscription in _sessionSubscriptions.values) {
      subscription.cancel();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sessions = _visibleSessions();

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.partnerName}との思い出'),
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
          if (_waitingPairs.isNotEmpty && sessions.isNotEmpty)
            const LinearProgressIndicator(),
          if (_sessionErrors.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '一部の写真を取得できませんでした。\n'
                '${_sessionErrors.values.first}\n'
                '接続を確認して、この画面を開き直してください。',
              ),
            ),
          Expanded(
            child: _buildSessions(sessions),
          ),
        ],
      ),
    );
  }

  Widget _buildSessions(List<_SessionEntry> sessions) {
    if (_pairError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('接続履歴を取得できません。\n$_pairError'),
        ),
      );
    }

    if (!_pairsLoaded ||
        (_waitingPairs.isNotEmpty && sessions.isEmpty)) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (sessions.isEmpty) {
      return Center(
        child: Text(
          _sessionErrors.isEmpty
              ? 'まだ写真がありません。'
              : '写真を読み込めませんでした。',
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: sessions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final session = sessions[index];
        final data = session.data;

        final paths = List<String>.from(
          data['photoPaths'] as List,
        );

        final mine = data['authorUid'] == _uid;

        return Card(
          key: ValueKey(session.key),
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
              '${memoryDate(data['sharedAt'] ?? data['createdAt'])}\n'
              '${paths.length}枚',
            ),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SessionPhotosScreen(
                    pairId: session.pairId,
                    sessionId: session.sessionId,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}