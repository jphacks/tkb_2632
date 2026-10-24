import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MyApp());
}

// アプリ全体の色
const backgroundColor = Color(0xFFFFFAF7);
const inkColor = Color(0xFF443A36);
const mutedColor = Color(0xFF897A73);
const accentColor = Color(0xFFB95849);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FocUS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: accentColor,
        ),
        scaffoldBackgroundColor: backgroundColor,
      ),
      home: const AuthGate(),
    );
  }
}

// 認証状態と登録情報に応じて、最初に表示する画面を決める。
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late Future<String?> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = _loadNickname();
  }

  Future<String?> _loadNickname() async {
    // 保存された認証情報の復元を待つ。
    final user = await FirebaseAuth.instance.authStateChanges().first;

    // まだ匿名認証していない場合。
    if (user == null) {
      return null;
    }

    // 登録済みのニックネームを取得する。
    // 通信エラーを「未登録」と誤判定しないよう、サーバーに確認する。
    final document = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get(const GetOptions(source: Source.server));

    final nickname = document.data()?['nickname'];

    if (nickname is String && nickname.trim().isNotEmpty) {
      return nickname;
    }

    // 認証だけ済み、名前の保存前に終了した場合も登録画面を表示する。
    return null;
  }

  void _reloadProfile() {
    setState(() {
      _profileFuture = _loadNickname();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _profileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.cloud_off_rounded,
                        size: 48,
                        color: mutedColor,
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        '登録情報を確認できませんでした。\n'
                        '接続を確認して、もう一度お試しください。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: inkColor,
                          height: 1.8,
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _reloadProfile,
                        child: const Text('再試行'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        final nickname = snapshot.data;

        if (nickname == null) {
          return RegistrationScreen(
            onRegistered: _reloadProfile,
          );
        }

        return RegistrationCompleteScreen(
          nickname: nickname,
        );
      },
    );
  }
}

// 初回のニックネーム登録画面
class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({
    super.key,
    required this.onRegistered,
  });

  final VoidCallback onRegistered;

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // 二重送信を防ぐ。
    if (_isSubmitting) return;

    // 空欄・スペースのみの入力を防ぐ。
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();

    final nickname = _nameController.text.trim();

    setState(() {
      _isSubmitting = true;
    });

    try {
      final auth = FirebaseAuth.instance;
      var user = auth.currentUser;

      // 未認証の場合だけ匿名ユーザーを作る。
      // 名前の保存に失敗して再試行する場合は、同じユーザーを使う。
      if (user == null) {
        final credential = await auth.signInAnonymously();
        user = credential.user;
      }

      if (user == null) {
        throw StateError('ユーザーを作成できませんでした');
      }

      // Firestoreのルールに合わせ、nicknameだけを保存する。
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
        'nickname': nickname,
      });

      if (!mounted) return;

      // 保存成功後に、登録状態を再取得する。
      widget.onRegistered();
    } catch (error) {
      if (!mounted) return;

      var message = '登録できませんでした。接続を確認して、もう一度お試しください。';

      if (error is FirebaseAuthException) {
        switch (error.code) {
          case 'operation-not-allowed':
            message = '匿名認証が有効になっていません。Firebaseの設定を確認してください。';
            break;
          case 'network-request-failed':
            message = '通信できませんでした。接続を確認して、もう一度お試しください。';
            break;
          case 'too-many-requests':
            message = '試行回数が多くなっています。少し時間を置いてお試しください。';
            break;
        }
      } else if (error is FirebaseException) {
        switch (error.code) {
          case 'permission-denied':
            message = '保存する権限がありません。Firestoreのルールを確認してください。';
            break;
          case 'unavailable':
            message = '保存先に接続できませんでした。通信環境を確認してください。';
            break;
        }
      }

      // 失敗しても入力した名前は消さない。
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(message)),
        );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 28,
              vertical: 40,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEAE2),
                          borderRadius: BorderRadius.circular(26),
                        ),
                        child: const Icon(
                          Icons.center_focus_strong_rounded,
                          size: 40,
                          color: accentColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Center(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: 'Foc',
                              style: TextStyle(color: inkColor),
                            ),
                            TextSpan(
                              text: 'US',
                              style: TextStyle(color: accentColor),
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
                          fontSize: 14,
                          height: 1.8,
                          color: mutedColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 56),
                    const Text(
                      'あなたの呼び名を教えてね',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: inkColor,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '相手に表示する名前です。\n'
                      '本名でなく、ニックネームで大丈夫。',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.8,
                        color: mutedColor,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _nameController,
                      readOnly: _isSubmitting,
                      maxLength: 24,
                      textInputAction: TextInputAction.done,
                      textCapitalization: TextCapitalization.none,
                      autocorrect: false,
                      style: const TextStyle(
                        fontSize: 16,
                        color: inkColor,
                      ),
                      decoration: InputDecoration(
                        labelText: 'ニックネーム',
                        hintText: '例：りお',
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 18,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: Color(0xFFE6DAD3),
                          ),
                        ),
                      ),
                      validator: (value) {
                        final name = value?.trim() ?? '';

                        if (name.isEmpty) {
                          return '呼び名を入力してください';
                        }

                        // Firestore側の24文字制限とも合わせる。
                        if (name.runes.length > 24) {
                          return '呼び名は24文字以内にしてください';
                        }

                        return null;
                      },
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _isSubmitting ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: accentColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 18,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          _isSubmitting ? '登録しています…' : 'はじめる',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Center(
                      child: Text(
                        'メールアドレス・パスワードの登録は不要です。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.8,
                          color: mutedColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// 登録後の確認画面。
// 次の段階で、ペア登録画面へ置き換える。
class RegistrationCompleteScreen extends StatelessWidget {
  const RegistrationCompleteScreen({
    super.key,
    required this.nickname,
  });

  final String nickname;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FocUS'),
        backgroundColor: backgroundColor,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.check_circle_outline_rounded,
                  size: 64,
                  color: accentColor,
                ),
                const SizedBox(height: 24),
                Text(
                  '$nicknameさん、ようこそ！',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: inkColor,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '呼び名の登録ができました。',
                  style: TextStyle(
                    color: mutedColor,
                    height: 1.8,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}