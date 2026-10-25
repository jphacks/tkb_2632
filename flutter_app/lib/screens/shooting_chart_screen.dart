import 'dart:async';

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../pic.dart';
import '../services/favorite_service.dart';
import '../widgets/profile_avatar.dart';
import 'memories_screen.dart';

typedef _PairDoc = QueryDocumentSnapshot<Map<String, dynamic>>;

int _chartTime(dynamic value) {
  return value is Timestamp ? value.millisecondsSinceEpoch : 0;
}

class _ChartPartner {
  _ChartPartner({
    required this.uid,
    required this.pairs,
    this.profileName,
  });

  final String uid;
  final List<_PairDoc> pairs;

  // users/{uid} に設定されている最新の名前。取得できなければ null。
  final String? profileName;

  String get pairId => pairs.first.id;

  bool get connected {
    return pairs.any(
      (pair) => !pair.data().containsKey('disconnectedAt'),
    );
  }

  Map<String, dynamic>? get profile {
    for (final pair in pairs) {
      final profiles = pair.data()['memberProfiles'];

      if (profiles is! Map) {
        continue;
      }

      final value = profiles[uid];

      if (value is Map) {
        return Map<String, dynamic>.from(value);
      }
    }

    return null;
  }

  // 最新の名前 → 接続時に保存した名前 の順に使う。
  String get name {
    final latest = profileName;

    if (latest != null) {
      return latest;
    }

    final value = profile?['nickname'];

    if (value is String && value.trim().isNotEmpty) {
      return value;
    }

    return '名前未保存の相手';
  }

  String get avatar {
    final value = profile?['avatarBase64'];
    return value is String ? value : '';
  }
}

class _ChartPhoto {
  const _ChartPhoto({
    required this.path,
    required this.pairId,
    required this.sessionId,
    required this.reasonKeys,
    required this.selectedAt,
  });

  final String path;
  final String pairId;
  final String sessionId;
  final List<String> reasonKeys;
  final Timestamp? selectedAt;

  String get sessionKey => '$pairId/$sessionId';
}

class _ChartData {
  const _ChartData({
    required this.partner,
    required this.subject,
    required this.photos,
  });

  final _ChartPartner partner;

  // 「好き」を選んだ人（相手のカルテなら相手、自分のカルテなら自分）。
  final _ChartPartner subject;

  final List<_ChartPhoto> photos;

  int get sessionCount {
    return photos.map((photo) => photo.sessionKey).toSet().length;
  }

  int countReason(String reasonKey) {
    return photos
        .where((photo) => photo.reasonKeys.contains(reasonKey))
        .length;
  }

  List<String> get availableReasons {
    final keys = favoriteReasonLabels.keys
        .where((key) => countReason(key) > 0)
        .toList();

    keys.sort((a, b) {
      final countOrder = countReason(b).compareTo(countReason(a));

      if (countOrder != 0) {
        return countOrder;
      }

      return a.compareTo(b);
    });

    return keys;
  }
}

class _ChartRepository {
  final _db = FirebaseFirestore.instance;

  String get uid {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw StateError('ユーザー情報を確認できません。');
    }

    return user.uid;
  }

  Future<List<_ChartPartner>> loadPartners() async {
    final myUid = uid;

    final snapshot = await _db
        .collection('pairs')
        .where('memberIds', arrayContains: myUid)
        .get(const GetOptions(source: Source.server));

    final groups = <String, List<_PairDoc>>{};

    for (final pair in snapshot.docs) {
      final members = List<String>.from(
        pair.data()['memberIds'] as List,
      );

      if (members.length != 2 || !members.contains(myUid)) {
        continue;
      }

      final partnerUid = members.firstWhere(
        (memberUid) => memberUid != myUid,
      );

      groups.putIfAbsent(partnerUid, () => []).add(pair);
    }

    final partners = await Future.wait([
      for (final group in groups.entries)
        _loadNickname(group.key).then(
          (profileName) => _ChartPartner(
            uid: group.key,
            pairs: group.value
              ..sort(
                (a, b) => _chartTime(b.data()['createdAt']).compareTo(
                  _chartTime(a.data()['createdAt']),
                ),
              ),
            profileName: profileName,
          ),
        ),
    ]);

    partners.sort((a, b) {
      if (a.connected != b.connected) {
        return a.connected ? -1 : 1;
      }

      return _chartTime(b.pairs.first.data()['createdAt']).compareTo(
        _chartTime(a.pairs.first.data()['createdAt']),
      );
    });

    return partners;
  }

  // 接続を解除した相手などは読めないことがあるため、失敗しても null を返す。
  Future<String?> _loadNickname(String userId) async {
    try {
      final user = await _db.collection('users').doc(userId).get();
      final value = user.data()?['nickname'];

      return value is String && value.trim().isNotEmpty ? value : null;
    } catch (error) {
      debugPrint('名前の取得エラー: $error');
      return null;
    }
  }

  // mine が false：自分が撮った写真から、相手が選んだお気に入り。
  // mine が true：相手が撮った写真から、自分が選んだお気に入り。
  Future<_ChartData> loadChart(String pairId, {bool mine = false}) async {
    final myUid = uid;
    final partners = await loadPartners();

    _ChartPartner? selectedPartner;

    for (final partner in partners) {
      if (partner.pairs.any((pair) => pair.id == pairId)) {
        selectedPartner = partner;
        break;
      }
    }

    if (selectedPartner == null) {
      throw StateError('この相手との接続履歴を確認できません。');
    }

    final partner = selectedPartner;
    final authorUid = mine ? partner.uid : myUid;
    final selectorUid = mine ? myUid : partner.uid;

    // 同じ写真を重複集計しない。
    final photosByPath = <String, _ChartPhoto>{};

    for (final pair in partner.pairs) {
      final sessions = await pair.reference
          .collection('sessions')
          .where('status', isEqualTo: 'shared')
          .get(const GetOptions(source: Source.server));

      for (final session in sessions.docs) {
        final sessionData = session.data();

        // 「好き」を選ばれる側が撮影した写真だけをカルテの対象にする。
        if (sessionData['authorUid'] != authorUid) {
          continue;
        }

        final feedbackDocument = await session.reference
            .collection('feedback')
            .doc('selection')
            .get(const GetOptions(source: Source.server));

        final feedback = feedbackDocument.data();

        if (feedback == null) {
          continue;
        }

        if (feedback['authorUid'] != authorUid ||
            feedback['selectedByUid'] != selectorUid) {
          continue;
        }

        final sessionPaths = List<String>.from(
          sessionData['photoPaths'] as List,
        ).toSet();

        final favorites = List<String>.from(
          feedback['favorites'] as List,
        ).toSet();

        final reasons = Map<String, dynamic>.from(
          feedback['reasons'] as Map,
        );

        final timestamp = feedback['createdAt'];

        for (final path in favorites) {
          if (!sessionPaths.contains(path)) {
            continue;
          }

          final reasonKeys = <String>[];

          for (final key in favoriteReasonLabels.keys) {
            final reasonPaths = reasons[key];

            if (reasonPaths is List && reasonPaths.contains(path)) {
              reasonKeys.add(key);
            }
          }

          photosByPath[path] = _ChartPhoto(
            path: path,
            pairId: pair.id,
            sessionId: session.id,
            reasonKeys: reasonKeys,
            selectedAt: timestamp is Timestamp ? timestamp : null,
          );
        }
      }
    }

    final photos = photosByPath.values.toList()
      ..sort((a, b) {
        final dateOrder = _chartTime(b.selectedAt).compareTo(
          _chartTime(a.selectedAt),
        );

        if (dateOrder != 0) {
          return dateOrder;
        }

        return a.path.compareTo(b.path);
      });

    return _ChartData(
      partner: partner,
      subject: mine
          ? _ChartPartner(
              uid: myUid,
              pairs: partner.pairs,
              profileName: await _loadNickname(myUid),
            )
          : partner,
      photos: photos,
    );
  }
}

// pairIdなし：相手を選ぶ画面。
// pairIdあり：その相手のカルテを表示する。
class ShootingChartScreen extends StatefulWidget {
  const ShootingChartScreen({
    super.key,
    this.pairId,
    this.highlightSessionId,
    this.mine = false,
  });

  final String? pairId;
  final String? highlightSessionId;

  // true：自分が選んだ「好き」をまとめた、自分のカルテ。
  final bool mine;

  @override
  State<ShootingChartScreen> createState() => _ShootingChartScreenState();
}

class _ShootingChartScreenState extends State<ShootingChartScreen> {
  final _repository = _ChartRepository();

  Future<List<_ChartPartner>>? _partnersFuture;
  Future<_ChartData>? _chartFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final pairId = widget.pairId;

    if (pairId == null) {
      _partnersFuture = _repository.loadPartners().timeout(
        const Duration(seconds: 30),
      );
    } else {
      _chartFuture = _repository
          .loadChart(pairId, mine: widget.mine)
          .timeout(
        const Duration(seconds: 45),
      );
    }
  }

  void _reload() {
    setState(_load);
  }

  Widget _error(Object? error) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 40),
            const SizedBox(height: 16),
            const Text('撮影カルテを取得できませんでした。'),
            const SizedBox(height: 12),
            Text(
              '$error',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _reload,
              child: const Text('再試行'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('撮影カルテ'),
        actions: [
          IconButton(
            onPressed: _reload,
            tooltip: '更新',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: widget.pairId == null
          ? _buildPartnerPicker()
          : _buildChart(),
    );
  }

  Widget _buildPartnerPicker() {
    return FutureBuilder<List<_ChartPartner>>(
      future: _partnersFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return _error(snapshot.error);
        }

        final partners = snapshot.data ?? [];

        if (partners.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'まずは相手とつながって、写真を撮ってみよう。\n'
                '相手から届いた「好き」がカルテにたまります。',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: partners.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final partner = partners[index];

            return Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: ProfileAvatar(
                  avatarBase64: partner.avatar,
                  size: 48,
                ),
                title: Text('${partner.name}の撮影カルテ'),
                subtitle: Text(
                  partner.connected ? '接続中の相手' : 'これまでの撮影記録',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ShootingChartScreen(
                        pairId: partner.pairId,
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildChart() {
    return FutureBuilder<_ChartData>(
      future: _chartFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return _error(snapshot.error);
        }

        final data = snapshot.data!;
        final currentPhotos = <_ChartPhoto>[];
        final previousPhotos = <_ChartPhoto>[];

        for (final photo in data.photos) {
          final isCurrent = widget.highlightSessionId != null &&
              photo.pairId == widget.pairId &&
              photo.sessionId == widget.highlightSessionId;

          if (isCurrent) {
            currentPhotos.add(photo);
          } else {
            previousPhotos.add(photo);
          }
        }

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                ProfileAvatar(
                  avatarBase64: data.subject.avatar,
                  size: 64,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    '${data.subject.name}の「好き」',
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              widget.mine
                  ? '相手が撮ってくれた写真から、'
                      'あなたが選んだお気に入りをまとめました。'
                  : 'あなたが撮った写真から、'
                      '相手が選んでくれたお気に入りをまとめました。',
              style: const TextStyle(height: 1.7),
            ),
            const SizedBox(height: 20),
            if (data.photos.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    widget.mine
                        ? 'まだ「好き」の記録がありません。\n'
                            '撮ってもらった写真にいいねを送ると、ここにたまります。'
                        : 'まだ「好き」の記録がありません。\n'
                            '写真を撮って共有し、相手にお気に入りを選んでもらおう。',
                    style: const TextStyle(height: 1.8),
                  ),
                ),
              )
            else ...[
              Text(
                '${data.sessionCount}回の撮影セットから、'
                '${data.photos.length}枚のお気に入り',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final key in data.availableReasons)
                    Chip(
                      label: Text(
                        '${favoriteReasonLabels[key]}：'
                        '${data.countReason(key)}枚',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '理由は複数選択できるため、件数の合計は写真数と一致しません。',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
            const SizedBox(height: 24),
            // 撮影ガイドは相手を撮るためのものなので、相手のカルテにだけ出す。
            if (!widget.mine)
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _ShootingGuideScreen(data: data),
                    ),
                  );
                },
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('このカルテから撮影ガイドを見る'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            if (currentPhotos.isNotEmpty) ...[
              const SizedBox(height: 28),
              const Text(
                '今回選んでくれた写真',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              _ChartPhotoGrid(photos: currentPhotos),
            ],
            if (previousPhotos.isNotEmpty) ...[
              const SizedBox(height: 28),
              Text(
                currentPhotos.isEmpty
                    ? 'お気に入りの写真と理由'
                    : 'これまで選んでくれた写真',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              _ChartPhotoGrid(photos: previousPhotos),
            ],
          ],
        );
      },
    );
  }
}

class _ChartPhotoGrid extends StatelessWidget {
  const _ChartPhotoGrid({
    required this.photos,
  });

  final List<_ChartPhoto> photos;

  void _openPhoto(BuildContext context, _ChartPhoto photo) {
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
                path: photo.path,
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
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.65,
      ),
      itemCount: photos.length,
      itemBuilder: (context, index) {
        final photo = photos[index];

        final labels = [
          for (final key in photo.reasonKeys)
            favoriteReasonLabels[key] ?? key,
        ];

        return Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _openPhoto(context, photo),
                  child: SizedBox.expand(
                    child: StoredMemoryPhoto(path: photo.path),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: SizedBox(
                  height: 46,
                  child: Text(
                    labels.isEmpty ? '理由の記録なし' : labels.join('・'),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFB95849),
                    ),
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

class _ShootingGuideScreen extends StatefulWidget {
  const _ShootingGuideScreen({
    required this.data,
  });

  final _ChartData data;

  @override
  State<_ShootingGuideScreen> createState() => _ShootingGuideScreenState();
}

class _ShootingGuideScreenState extends State<_ShootingGuideScreen> {
  static const _tips = <String, String>{
    'expression':
        '表情を気に入ってくれた写真です。'
        '笑顔や視線、自然な表情になるタイミングを参考にしてみよう。',
    'composition':
        '構図を気に入ってくれた写真です。'
        '人物の位置や、周囲に残した余白を参考にしてみよう。',
    'size':
        '人物の大きさを気に入ってくれた写真です。'
        '顔・上半身・全身のどこまで写っているかを参考にしてみよう。',
    'background':
        '背景を気に入ってくれた写真です。'
        '人物の後ろに何が写っているかを参考にしてみよう。',
    'light':
        '光を気に入ってくれた写真です。'
        '顔の明るさや影の入り方を参考にしてみよう。',
    'mood':
        '雰囲気を気に入ってくれた写真です。'
        '場所や色、表情など、写真全体の印象を参考にしてみよう。',
  };

  String? _selectedReason;
  bool _openingCamera = false;

  @override
  void initState() {
    super.initState();

    final reasons = widget.data.availableReasons;

    if (reasons.isNotEmpty) {
      _selectedReason = reasons.first;
    }
  }

  Future<void> _openCamera() async {
    if (_openingCamera) {
      return;
    }

    setState(() => _openingCamera = true);

    try {
      final db = FirebaseFirestore.instance;
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        throw StateError('ユーザー情報を確認できません。');
      }

      final membership = await db
          .collection('memberships')
          .doc(user.uid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));

      final pairId = membership.data()?['pairId'];

      if (pairId is! String) {
        throw StateError('この相手と接続してから撮影してください。');
      }

      final pair = await db
          .collection('pairs')
          .doc(pairId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));

      final data = pair.data();
      final members = data?['memberIds'];

      if (data == null ||
          data.containsKey('disconnectedAt') ||
          members is! List ||
          !members.contains(user.uid) ||
          !members.contains(widget.data.partner.uid)) {
        throw StateError(
          '今接続している相手のカルテではありません。\n'
          'この相手と接続してから撮影してください。',
        );
      }

      if (!mounted) {
        return;
      }

      final result = await Navigator.of(context).push<XFile>(
        MaterialPageRoute<XFile>(
          builder: (_) => const PicScreen(),
        ),
      );

      if (!mounted || result == null) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('写真を共有しました。')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    } finally {
      if (mounted) {
        setState(() => _openingCamera = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final selectedReason = _selectedReason;

    final referencePhotos = data.photos.where((photo) {
      return selectedReason != null &&
          photo.reasonKeys.contains(selectedReason);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('撮影ガイド'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            '${data.partner.name}の「好き」を参考に',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '今回はどこを意識して撮ってみる？',
          ),
          const SizedBox(height: 20),
          if (data.availableReasons.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'まだ参考写真がありません。\n'
                  'まずは撮って、相手の「好き」を集めてみよう。',
                  style: TextStyle(height: 1.8),
                ),
              ),
            )
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final key in data.availableReasons)
                  ChoiceChip(
                    label: Text(favoriteReasonLabels[key]!),
                    selected: selectedReason == key,
                    onSelected: (_) {
                      setState(() {
                        _selectedReason = key;
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  _tips[selectedReason] ?? 'お気に入りの写真を参考にしてみよう。',
                  style: const TextStyle(height: 1.8),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _ChartPhotoGrid(photos: referencePhotos),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _openingCamera ? null : _openCamera,
            icon: const Icon(Icons.camera_alt_outlined),
            label: Text(
              _openingCamera ? '確認しています…' : '参考にして撮影する',
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '撮影・共有するには、この相手との接続が必要です。',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}