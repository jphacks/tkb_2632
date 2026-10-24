import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/pair_service.dart';

class PairRegistrationScreen extends StatefulWidget {
  const PairRegistrationScreen({
    super.key,
    required this.nickname,
    this.startWithJoin = false,
  });

  final String nickname;
  final bool startWithJoin;

  @override
  State<PairRegistrationScreen> createState() =>
      _PairRegistrationScreenState();
}

class _PairRegistrationScreenState
    extends State<PairRegistrationScreen> {
  final _service = PairService();
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();

  StreamSubscription<dynamic>? _membershipSubscription;

  late bool _joining;
  bool _busy = false;
  bool _closing = false;
  String? _invitationCode;
  String? _error;

  @override
  void initState() {
    super.initState();

    _joining = widget.startWithJoin;

    _membershipSubscription = _service.watchMembership().listen(
      (document) {
        if (!document.exists || _closing || !mounted) return;

        _closing = true;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;

          // ホーム側が接続成功を検知するので、この画面を閉じる。
          Navigator.of(context).pop(true);
        });
      },
      onError: (_) {
        if (!mounted) return;

        setState(() {
          _error = '接続状態を確認できません。通信環境を確認してください。';
        });
      },
    );

    if (!_joining) {
      _createInvitation();
    }
  }

  @override
  void dispose() {
    _membershipSubscription?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _createInvitation() async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _error = null;
      _invitationCode = null;
    });

    try {
      final code = await _service.createInvitation();

      if (!mounted) return;

      setState(() {
        _invitationCode = code;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error is PairingException
            ? error.message
            : 'コードを作成できませんでした。接続を確認してください。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _join() async {
    if (_busy) return;
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _service.join(_codeController.text);

      // 画面を閉じる処理は、所属情報の監視に任せる。
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error is PairingException
            ? error.message
            : '接続できませんでした。通信環境を確認してください。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  void _switchMode() {
    if (_busy) return;

    setState(() {
      _joining = !_joining;
      _error = null;
    });

    if (!_joining && _invitationCode == null) {
      _createInvitation();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: const Color(0xFFFFFAF2),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFFFAF2),
                Color(0xFFFFFBF1),
                Color(0xFFDFF5E8),
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                      Expanded(
                        child: Text(
                          _joining ? 'コードで参加する' : '相手を招待する',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(28),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 360),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'FocUS',
                              style: TextStyle(
                                fontSize: 48,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                shadows: [
                                  Shadow(
                                    color: Color(0x55000000),
                                    blurRadius: 5,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 42),
                            if (_joining)
                              _buildJoinForm()
                            else
                              _buildInvitation(),
                            if (_error != null) ...[
                              const SizedBox(height: 20),
                              Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFFB44238),
                                  height: 1.7,
                                ),
                              ),
                            ],
                            const SizedBox(height: 28),
                            TextButton(
                              onPressed: _busy ? null : _switchMode,
                              child: Text(
                                _joining
                                    ? '自分から相手を招待する'
                                    : '招待コードを持っている方はこちら',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInvitation() {
    final code = _invitationCode;

    if (_busy) {
      return const SizedBox(
        height: 280,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (code == null) {
      return FilledButton(
        onPressed: _createInvitation,
        child: const Text('コードを作り直す'),
      );
    }

    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(12),
          child: QrImageView(
            data: code,
            size: 210,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 18),
        SelectableText(
          '${code.substring(0, 3)} ${code.substring(3)}',
          style: const TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.w300,
            letterSpacing: 2,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          '6桁のコードを相手に伝えてね。\n'
          '相手が参加すると、自動で画面が切り替わります。',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF898D91),
            fontSize: 13,
            height: 1.9,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '有効期限：発行から30分',
          style: TextStyle(
            color: Color(0xFF898D91),
            fontSize: 12,
          ),
        ),
        TextButton(
          onPressed: _createInvitation,
          child: const Text('新しいコードを発行'),
        ),
      ],
    );
  }

  Widget _buildJoinForm() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          const Text(
            '相手から届いた6桁のコードを入力してね。',
            textAlign: TextAlign.center,
            style: TextStyle(height: 1.8),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _codeController,
            readOnly: _busy,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            textAlign: TextAlign.center,
            maxLength: 6,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
            ],
            style: const TextStyle(
              fontSize: 32,
              letterSpacing: 8,
            ),
            decoration: InputDecoration(
              hintText: '000000',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            validator: (value) {
              if (!RegExp(r'^[0-9]{6}$').hasMatch(value ?? '')) {
                return '6桁のコードを入力してください';
              }
              return null;
            },
            onFieldSubmitted: (_) => _join(),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _join,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF715E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
              ),
              child: Text(
                _busy ? '接続しています…' : 'このコードでつながる',
              ),
            ),
          ),
        ],
      ),
    );
  }
}