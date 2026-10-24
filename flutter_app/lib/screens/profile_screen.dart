import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;

import '../widgets/profile_avatar.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.onSaved,
    this.initialNickname = '',
    this.initialAvatarBase64 = '',
    this.isEditing = false,
  });

  final VoidCallback onSaved;
  final String initialNickname;
  final String initialAvatarBase64;
  final bool isEditing;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const _background = Color(0xFFFFFAF7);
  static const _ink = Color(0xFF443A36);
  static const _muted = Color(0xFF897A73);
  static const _accent = Color(0xFFB95849);

  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  late final TextEditingController _nameController;
  late String _avatarBase64;

  bool _isPicking = false;
  bool _isSaving = false;
  String? _error;

  bool get _busy => _isPicking || _isSaving;

  @override
  void initState() {
    super.initState();

    _nameController = TextEditingController(
      text: widget.initialNickname,
    );
    _avatarBase64 = widget.initialAvatarBase64;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    if (_busy) return;

    setState(() {
      _isPicking = true;
      _error = null;
    });

    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
      );

      // 写真選択をキャンセルした場合は変更しない。
      if (file == null) return;

      if (await file.length() > 10 * 1024 * 1024) {
        throw const FormatException('10MB以下の画像を選んでください。');
      }

      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);

      if (decoded == null) {
        throw const FormatException(
          'この画像は読み込めません。JPEG・PNGなどの画像を選んでください。',
        );
      }

      // 向きを補正し、中央を正方形に切り抜いて縮小する。
      final oriented = img.bakeOrientation(decoded);
      final square = img.copyResizeCropSquare(
        oriented,
        size: 128,
      );

      final jpeg = img.encodeJpg(
        square,
        quality: 80,
      );

      final encoded = base64Encode(jpeg);

      if (encoded.length > 60000) {
        throw const FormatException(
          '画像を小さくできませんでした。別の写真をお試しください。',
        );
      }

      if (!mounted) return;

      setState(() {
        _avatarBase64 = encoded;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error is FormatException
            ? error.message
            : '写真を読み込めませんでした。もう一度お試しください。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isPicking = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();

    final nickname = _nameController.text.trim();

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final auth = FirebaseAuth.instance;
      var user = auth.currentUser;

      if (user == null) {
        if (widget.isEditing) {
          throw StateError('認証情報を確認できません');
        }

        final credential = await auth.signInAnonymously();
        user = credential.user;
      }

      if (user == null) {
        throw StateError('ユーザーを作成できません');
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(
        {
          'nickname': nickname,
          'avatarBase64': _avatarBase64,
        },
        SetOptions(merge: true),
      );

      if (!mounted) return;

      widget.onSaved();
    } catch (error) {
      if (!mounted) return;

      var message = '保存できませんでした。接続を確認して再度お試しください。';

      if (error is FirebaseAuthException) {
        if (error.code == 'operation-not-allowed') {
          message = '匿名認証の設定を確認してください。';
        } else if (error.code == 'too-many-requests') {
          message = '少し時間を置いて、もう一度お試しください。';
        }
      } else if (error is FirebaseException &&
          error.code == 'permission-denied') {
        message = '保存する権限がありません。Firestoreのルールを確認してください。';
      }

      setState(() {
        _error = message;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: _background,
        appBar: widget.isEditing
            ? AppBar(
                title: const Text('プロフィール'),
                centerTitle: true,
                backgroundColor: _background,
              )
            : null,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 28,
                vertical: 36,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!widget.isEditing) ...[
                        const Center(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: 'Foc',
                                  style: TextStyle(color: _ink),
                                ),
                                TextSpan(
                                  text: 'US',
                                  style: TextStyle(color: _accent),
                                ),
                              ],
                            ),
                            style: TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -2,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Center(
                          child: Text(
                            '撮るたび、ふたりの「好き」が伝わる。',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _muted,
                              height: 1.8,
                            ),
                          ),
                        ),
                        const SizedBox(height: 36),
                      ],

                      Center(
                        child: Semantics(
                          label: 'プロフィール写真を選ぶ',
                          button: true,
                          child: InkWell(
                            onTap: _busy ? null : _pickAvatar,
                            borderRadius: BorderRadius.circular(64),
                            child: Stack(
                              children: [
                                ProfileAvatar(
                                  avatarBase64: _avatarBase64,
                                  size: 112,
                                ),
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: _accent,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: _background,
                                        width: 3,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.camera_alt_outlined,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Center(
                        child: TextButton(
                          onPressed: _busy ? null : _pickAvatar,
                          child: Text(
                            _isPicking ? '写真を読み込んでいます…' : '写真を選ぶ（任意）',
                          ),
                        ),
                      ),
                      if (_avatarBase64.isNotEmpty)
                        Center(
                          child: TextButton(
                            onPressed: _busy
                                ? null
                                : () {
                                    setState(() {
                                      _avatarBase64 = '';
                                    });
                                  },
                            child: const Text('写真を外す'),
                          ),
                        ),
                      const SizedBox(height: 24),
                      Text(
                        widget.isEditing
                            ? '呼び名とアイコン'
                            : 'あなたの呼び名を教えてね',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        '本名でなく、ニックネームで大丈夫。\n'
                        '写真はあとから変更できます。',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.8,
                          color: _muted,
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _nameController,
                        readOnly: _busy,
                        maxLength: 24,
                        textInputAction: TextInputAction.done,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: 'ニックネーム',
                          hintText: '例：りお',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        validator: (value) {
                          final name = value?.trim() ?? '';

                          if (name.isEmpty) {
                            return '呼び名を入力してください';
                          }

                          if (name.runes.length > 24) {
                            return '24文字以内にしてください';
                          }

                          return null;
                        },
                        onFieldSubmitted: (_) => _save(),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            height: 1.7,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _busy ? null : _save,
                          style: FilledButton.styleFrom(
                            backgroundColor: _accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              vertical: 18,
                            ),
                          ),
                          child: Text(
                            _isSaving
                                ? '保存しています…'
                                : widget.isEditing
                                    ? '変更を保存'
                                    : 'はじめる',
                          ),
                        ),
                      ),
                      if (!widget.isEditing) ...[
                        const SizedBox(height: 20),
                        const Center(
                          child: Text(
                            'メールアドレス・パスワードの登録は不要です。',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.8,
                              color: _muted,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}