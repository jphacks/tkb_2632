import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PairingException implements Exception {
  const PairingException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PairDetails {
  const PairDetails({
    required this.myName,
    required this.myAvatar,
    required this.partnerName,
    required this.partnerAvatar,
  });

  final String myName;
  final String myAvatar;
  final String partnerName;
  final String partnerAvatar;
}

class PairService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String get _uid {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw const PairingException(
        'ユーザー情報を確認できません。アプリを開き直してください。',
      );
    }

    return user.uid;
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchMembership() {
    return _db.collection('memberships').doc(_uid).snapshots();
  }

  Future<String> createInvitation() async {
    final uid = _uid;
    final random = Random.secure();

    for (var attempt = 0; attempt < 12; attempt++) {
      final code = (100000 + random.nextInt(900000)).toString();
      final invitationRef = _db.collection('invitations').doc(code);
      final membershipRef = _db.collection('memberships').doc(uid);

      final created = await _db.runTransaction<bool>((transaction) async {
        final membership = await transaction.get(membershipRef);
        final invitation = await transaction.get(invitationRef);

        if (membership.exists) {
          throw const PairingException('すでに相手とつながっています。');
        }

        if (invitation.exists) {
          return false;
        }

        transaction.set(invitationRef, {
          'ownerUid': uid,
          'createdAt': FieldValue.serverTimestamp(),
          'expiresAt': Timestamp.fromDate(
            DateTime.now().add(const Duration(minutes: 30)),
          ),
        });

        return true;
      });

      if (created) return code;
    }

    throw const PairingException(
      '招待コードを作成できませんでした。もう一度お試しください。',
    );
  }

  Future<void> join(String input) async {
    final uid = _uid;
    final code = input.trim();

    if (!RegExp(r'^[0-9]{6}$').hasMatch(code)) {
      throw const PairingException('6桁の招待コードを入力してください。');
    }

    final invitationRef = _db.collection('invitations').doc(code);
    final myMembershipRef = _db.collection('memberships').doc(uid);

    try {
      await _db.runTransaction<void>((transaction) async {
        final invitation = await transaction.get(invitationRef);
        final myMembership = await transaction.get(myMembershipRef);

        if (myMembership.exists) {
          throw const PairingException('すでに相手とつながっています。');
        }

        final data = invitation.data();

        if (data == null) {
          throw const PairingException('招待コードが見つかりません。');
        }

        final ownerUid = data['ownerUid'] as String;
        final expiresAt = data['expiresAt'] as Timestamp;

        if (ownerUid == uid) {
          throw const PairingException(
            '自分の招待コードです。相手のブラウザで入力してください。',
          );
        }

        if (expiresAt.toDate().isBefore(DateTime.now())) {
          throw const PairingException(
            '有効期限が切れています。新しいコードを発行してもらってください。',
          );
        }

        // ペアと二人の所属を、まとめて保存する。
        // 相手が別のペアに所属済みの場合は、ルール側で拒否される。
        transaction.set(_db.collection('pairs').doc(code), {
          'memberIds': [ownerUid, uid],
          'createdAt': FieldValue.serverTimestamp(),
        });

        transaction.set(
          _db.collection('memberships').doc(ownerUid),
          {'pairId': code},
        );

        transaction.set(
          myMembershipRef,
          {'pairId': code},
        );
      });
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        throw const PairingException(
          'この招待には参加できません。'
          '相手が接続済みか、期限が切れている可能性があります。',
        );
      }

      rethrow;
    }
  }

  Future<PairDetails> loadPair(String pairId) async {
    final uid = _uid;
    final pair = await _db.collection('pairs').doc(pairId).get();

    if (!pair.exists) {
      throw const PairingException('ペア情報が見つかりません。');
    }

    final members = List<String>.from(pair.data()!['memberIds']);
    final partnerUid = members.firstWhere((id) => id != uid);

    final profiles = await Future.wait([
      _db.collection('users').doc(uid).get(),
      _db.collection('users').doc(partnerUid).get(),
    ]);

    final me = profiles[0].data();
    final partner = profiles[1].data();

    if (me == null || partner == null) {
      throw const PairingException('プロフィールを確認できません。');
    }

    return PairDetails(
      myName: me['nickname'] as String,
      myAvatar: me['avatarBase64'] as String? ?? '',
      partnerName: partner['nickname'] as String,
      partnerAvatar: partner['avatarBase64'] as String? ?? '',
    );
  }
}