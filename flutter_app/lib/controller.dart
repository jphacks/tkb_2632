import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'models.dart';

class RelayController extends ChangeNotifier {
  final Gateway gateway;
  Person? user;
  String? roomCode;
  List<Person> members = [];
  List<PhotoRound> rounds = [];
  bool loading = true;
  bool busy = false;
  bool active = true;
  String? error;
  String _signature = '';
  bool _disposed = false;
  Timer? _timer;
  Future<void>? _refreshJob;
  final Map<String, Future<Uint8List>> _images = {};

  RelayController(this.gateway);
  Person? get partner {
    for (final p in members) {
      if (p.id != user?.id) return p;
    }
    return null;
  }

  List<PhotoRound> get received =>
      rounds.where((r) => r.subjectId == user?.id).toList();
  List<PhotoRound> get guesses => rounds
      .where((r) => r.photographerId == user?.id && r.status == 'guessing')
      .toList();
  int get unread => received.where((r) => r.status == 'selecting').length;
  PhotoRound? round(String id) {
    for (final r in rounds) {
      if (r.id == id) return r;
    }
    return null;
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize({bool poll = true}) async {
    await refresh();
    if (poll && !_disposed) {
      _timer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (active && !busy && user != null) unawaited(refresh());
      });
    }
  }

  Future<void> refresh() async {
    if (_refreshJob != null) return _refreshJob!;
    final job = _load();
    _refreshJob = job;
    try {
      await job;
    } finally {
      _refreshJob = null;
    }
  }

  Future<void> _load() async {
    try {
      final data = await gateway.request('state');
      final signature = jsonEncode(data);
      if (_signature != signature || error != null || loading) {
        user = Person.fromJson(data['user'] as Json);
        final room = data['room'] as Json?;
        roomCode = room?['code'] as String?;
        members = ((room?['members'] ?? []) as List)
            .map((p) => Person.fromJson(p as Json))
            .toList();
        rounds = (data['rounds'] as List)
            .map((r) => PhotoRound.fromJson(r as Json))
            .toList();
        _signature = signature;
        error = null;
        loading = false;
        _emit();
      }
    } on ApiException catch (e) {
      if (e.status == 401) {
        user = null;
        roomCode = null;
        members = [];
        rounds = [];
        _signature = '';
        error = null;
      } else {
        error = e.message;
      }
      loading = false;
      _emit();
    } catch (_) {
      error = 'サーバーに接続できません。PCの起動状態とネットワークを確認してください。';
      loading = false;
      _emit();
    }
  }

  Future<void> mutate(String route, Json data) async {
    if (busy) throw const ApiException(0, '前の操作を処理しています');
    busy = true;
    _emit();
    try {
      // 更新前のポーリングが操作後の状態を上書きしないよう先に待つ。
      await _refreshJob;
      await gateway.request(route, data);
      await refresh();
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<Uint8List> photo(String roundId, String photoId) => _images
      .putIfAbsent('$roundId/$photoId', () => gateway.photo(roundId, photoId));
  void retryPhoto(String roundId, String photoId) =>
      _images.remove('$roundId/$photoId');

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    gateway.close();
    super.dispose();
  }
}
