import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:device_preview/device_preview.dart';
import 'package:device_preview/presets.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'widgets/focus_shell.dart';

@JS('window.sessionStorage.setItem')
external void _setSessionItem(JSString key, JSString value);

const _demoOptions = FirebaseOptions(
  apiKey: 'ADemoProjectApiKey000000000000000000000',
  appId: '1:1:web:1',
  messagingSenderId: '1',
  projectId: 'demo-focus',
  authDomain: 'demo-focus.firebaseapp.com',
  storageBucket: 'demo-focus.appspot.com',
);

Future<void> main() async {
  DevicePreview.enable(enabled: kDebugMode);
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // 匿名ユーザーの復元もAuthエミュレーターへ接続させる。
    _setSessionItem(
      '[DEFAULT]-firebaseEmulatorOrigin'.toJS,
      'http://127.0.0.1:9099'.toJS,
    );

    await Firebase.initializeApp(options: _demoOptions);

    await FirebaseAuth.instance.useAuthEmulator(
      '127.0.0.1',
      9099,
    );

    FirebaseFirestore.instance.useFirestoreEmulator(
      '127.0.0.1',
      8081,
    );

    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: false,
    );

    await FirebaseStorage.instance.useStorageEmulator(
      '127.0.0.1',
      9199,
    );

    if (kDebugMode) {
      await DevicePreview.controller.applyPreset(
        DevicePresets.iPhone16,
      );
    }

    runApp(const MyApp());
  } catch (error, stackTrace) {
    debugPrint('Firebase初期化エラー: $error');
    debugPrintStack(stackTrace: stackTrace);

    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: SelectableText(
                  'デモ環境の初期化に失敗しました。\n\n'
                  '$error\n\n'
                  'Firebaseエミュレーターの起動を確認して、'
                  'ブラウザを再読み込みしてください。',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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
          seedColor: const Color(0xFFB95849),
        ),
        scaffoldBackgroundColor: const Color(0xFFFFFAF7),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late Future<Map<String, dynamic>?> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = _loadProfile();
  }

  Future<Map<String, dynamic>?> _loadProfile() async {
    try {
      final user = await FirebaseAuth.instance
          .authStateChanges()
          .first
          .timeout(const Duration(seconds: 20));

      if (user == null) {
        return null;
      }

      await user.getIdToken(true).timeout(
        const Duration(seconds: 20),
      );

      final document = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));

      final data = document.data();
      final nickname = data?['nickname'];

      if (nickname is! String || nickname.trim().isEmpty) {
        return null;
      }

      return data;
    } catch (error, stackTrace) {
      debugPrint('登録情報の取得エラー: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  void _reloadProfile() {
    setState(() {
      _profileFuture = _loadProfile();
    });
  }

  String _errorDetail(Object? error) {
    if (error is TimeoutException) {
      return '接続がタイムアウトしました。\n'
          'Firebaseエミュレーターが起動しているか確認してください。';
    }

    if (error is FirebaseException) {
      return '${error.plugin}/${error.code}\n${error.message ?? ''}';
    }

    return error.toString();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
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
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.cloud_off_rounded,
                        size: 48,
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        '登録情報を確認できませんでした。',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      SelectableText(
                        _errorDetail(snapshot.error),
                        textAlign: TextAlign.center,
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

        final profile = snapshot.data;

        if (profile == null) {
          return ProfileScreen(
            onSaved: _reloadProfile,
          );
        }

        final avatar = profile['avatarBase64'];
        final uid = FirebaseAuth.instance.currentUser!.uid;

        return FocusShell(
          key: ValueKey(uid),
          child: HomeScreen(
            nickname: profile['nickname'] as String,
            avatarBase64: avatar is String ? avatar : '',
            onProfileChanged: _reloadProfile,
          ),
        );
      },
    );
  }
}                                                                                                                                                                                                                                                                                                                                                                                                 