import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AccountActions extends StatefulWidget {
  const AccountActions({
    super.key,
    required this.onFinished,
    required this.onBusyChanged,
    this.enabled = true,
  });

  final VoidCallback onFinished;
  final ValueChanged<bool> onBusyChanged;
  final bool enabled;

  @override
  State<AccountActions> createState() => _AccountActionsState();
}

class _AccountActionsState extends State<AccountActions> {
  final _db = FirebaseFirestore.instance;

  late final Stream<DocumentSnapshot<Map<String, dynamic>>>
      _membershipStream;

  bool _running = false;

  @override
  void initState() {
    super.initState();

    final uid = FirebaseAuth.instance.currentUser?.uid;

    _membershipStream = uid == null
        ? const Stream.empty()
        : _db
            .collection('memberships')
            .doc(uid)
            .snapshots(includeMetadataChanges: true);
  }

  Future<void> _disconnect() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw StateError('ユーザー情報を確認できません。');
    }

    final membershipRef = _db.collection('memberships').doc(user.uid);

    await _db.runTransaction<void>((transaction) async {
      final membership = await transaction.get(membershipRef);

      if (!membership.exists) return;

      final pairId = membership.data()?['pairId'];

      if (pairId is! String) {
        throw StateError('ペア情報を確認できません。');
      }

      final pairRef = _db.collection('pairs').doc(pairId);
      final pair = await transaction.get(pairRef);
      final data = pair.data();

      if (data == null) {
        throw StateError('ペア情報を確認できません。');
      }

      final members = List<String>.from(data['memberIds'] as List);

      if (members.length != 2 || !members.contains(user.uid)) {
        throw StateError('ペア情報を確認できません。');
      }

      // memberIds・セッション・写真は残す。
      transaction.update(pairRef, {
        'disconnectedAt': FieldValue.serverTimestamp(),
      });

      for (final memberUid in members) {
        transaction.delete(
          _db.collection('memberships').doc(memberUid),
        );
      }
    });
  }

  Future<void> _confirmDisconnect() async {
    if (_running || !widget.enabled) return;

    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('二人の接続を解除しますか？'),
        content: const Text(
          '相手側も未接続のホーム画面に戻ります。\n\n'
          '名前・アイコン・ログイン状態は残ります。\n'
          '共有済みの写真とお気に入りは、'
          '解除後も二人それぞれの「アルバム」から見返せます。\n\n'
          '新しい相手には、このペアの写真は共有されません。\n'
          '保存前のプロフィール変更は破棄されます。',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(false);
            },
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(true);
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB44238),
            ),
            child: const Text('接続を解除する'),
          ),
        ],
      ),
    );

    if (accepted != true || !mounted) return;

    setState(() {
      _running = true;
    });

    widget.onBusyChanged(true);

    try {
      await _disconnect();

      if (!mounted) return;

      widget.onFinished();
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              '接続を解除できませんでした。\n$error',
            ),
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
        });

        widget.onBusyChanged(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _membershipStream,
      builder: (context, snapshot) {
        final paired = snapshot.data?.exists ?? false;

        if (!paired) {
          return const SizedBox.shrink();
        }

        return Column(
          children: [
            const Divider(height: 40),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: widget.enabled && !_running
                    ? _confirmDisconnect
                    : null,
                icon: const Icon(Icons.link_off_rounded),
                label: Text(
                  _running ? '解除しています…' : '二人の接続を解除',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFB44238),
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}