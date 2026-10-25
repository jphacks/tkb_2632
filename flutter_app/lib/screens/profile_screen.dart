import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;

import '../widgets/account_actions.dart';
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
  bool _accountBusy = false;

  String? _error;

  bool get _busy => _isPicking || _isSaving || _accountBusy;

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

      if (file == null) return;

      if (await file.length() > 10 * 1024 * 1024) {
        throw const FormatException(
          '10MB以下の画像を選んでください。',
        );
      }

      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);

      if (decoded == null) {
        throw const FormatException(
          'この画像は読み込めません。JPEG・PNGなどを選んでください。',
        );
      }

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
          throw StateError('認証情報を確認できません。');
        }

        final credential = await auth.signInAnonymously();
        user = credential.user;
      }

      if (user == null) {
        throw StateError('ユーザーを作成できません。');
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

  List<Widget> _buildAvatarPicker({
    required double size,
    required Color accent,
    required Color ringColor,
  }) {
    return [
      Center(
        child: Semantics(
          label: 'プロフィール写真を選ぶ',
          button: true,
          child: InkWell(
            onTap: _busy ? null : _pickAvatar,
            borderRadius: BorderRadius.circular(size / 2),
            child: Stack(
              children: [
                ProfileAvatar(
                  avatarBase64: _avatarBase64,
                  size: size,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: ringColor,
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
          style: TextButton.styleFrom(foregroundColor: accent),
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
            style: TextButton.styleFrom(foregroundColor: accent),
            child: const Text('写真を外す'),
          ),
        ),
    ];
  }

  Widget _buildNameField({required InputDecoration decoration}) {
    return TextFormField(
      controller: _nameController,
      readOnly: _busy,
      maxLength: 24,
      textInputAction: TextInputAction.done,
      autocorrect: false,
      decoration: decoration,
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
    );
  }

  List<Widget> _buildError(BuildContext context) {
    final error = _error;

    if (error == null) {
      return const [];
    }

    return [
      const SizedBox(height: 12),
      Text(
        error,
        style: TextStyle(
          color: Theme.of(context).colorScheme.error,
          height: 1.7,
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return widget.isEditing
        ? _buildEditing(context)
        : _buildOnboarding(context);
  }

  // 初回登録（02_onboarding）の画面。
  Widget _buildOnboarding(BuildContext context) {
    const ink = Color(0xFF2B2220);
    const muted = Color(0xFF8A7F7B);
    const coral = Color(0xFFFF7360);

    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: coral),
    );

    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0, 0.3],
              colors: [
                Color(0xFFF3DDD5),
                Colors.white,
              ],
            ),
          ),
          child: SafeArea(
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  SizedBox(
                    height: 56,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (Navigator.of(context).canPop())
                          Positioned(
                            left: 4,
                            child: IconButton(
                              onPressed: _busy
                                  ? null
                                  : () => Navigator.of(context).maybePop(),
                              icon: const Icon(
                                Icons.arrow_back_ios_new,
                                size: 20,
                                color: ink,
                              ),
                            ),
                          ),
                        Image.asset(
                          'assets/images/logo.png',
                          height: 21,
                          semanticLabel: 'FocUS',
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 40, 16, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ニックネームを決めてください',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: ink,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            '友だちに表示される名前となります。',
                            style: TextStyle(
                              fontSize: 13,
                              color: muted,
                            ),
                          ),
                          const SizedBox(height: 32),
                          ..._buildAvatarPicker(
                            size: 96,
                            accent: coral,
                            ringColor: Colors.white,
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'ニックネーム',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: ink,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _buildNameField(
                            decoration: InputDecoration(
                              hintText: '例：やまだ',
                              filled: true,
                              fillColor: Colors.white,
                              border: fieldBorder,
                              enabledBorder: fieldBorder,
                              focusedBorder: fieldBorder.copyWith(
                                borderSide: const BorderSide(
                                  color: coral,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                          ..._buildError(context),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _busy ? null : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: coral,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        child: Text(
                          _isSaving ? '保存しています…' : '二人のつながりを始める',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // プロフィール編集の画面。
  Widget _buildEditing(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: _background,
        appBar: AppBar(
          title: const Text('プロフィール'),
          centerTitle: true,
          backgroundColor: _background,
        ),
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
                      ..._buildAvatarPicker(
                        size: 112,
                        accent: _accent,
                        ringColor: _background,
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        '呼び名とアイコン',
                        style: TextStyle(
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
                      _buildNameField(
                        decoration: InputDecoration(
                          labelText: 'ニックネーム',
                          hintText: '例：やまだ',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                      ..._buildError(context),
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
                            _isSaving ? '保存しています…' : '変更を保存',
                          ),
                        ),
                      ),
                      AccountActions(
                          enabled: !_isPicking && !_isSaving,
                          onFinished: widget.onSaved,
                          onBusyChanged: (busy) {
                            if (!mounted) return;

                            setState(() {
                              _accountBusy = busy;
                            });
                          },
                        ),
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