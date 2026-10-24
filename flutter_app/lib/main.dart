import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:device_preview/device_preview.dart';
import 'package:device_preview/presets.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';

Future<void> main() async {
  DevicePreview.enable(enabled: kDebugMode);

  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  if (kDebugMode) {
    await DevicePreview.controller.applyPreset(
      DevicePresets.iPhone16,
    );
  }

  runApp(const MyApp());
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
    final user = await FirebaseAuth.instance.authStateChanges().first;

    if (user == null) return null;

    final document = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get(const GetOptions(source: Source.server));

    final data = document.data();
    final nickname = data?['nickname'];

    if (nickname is! String || nickname.trim().isEmpty) {
      return null;
    }

    return data;
  }

  void _reloadProfile() {
    setState(() {
      _profileFuture = _loadProfile();
    });
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
                child: Padding(
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
                        '登録情報を確認できませんでした。\n'
                        '接続を確認して、もう一度お試しください。',
                        textAlign: TextAlign.center,
                        style: TextStyle(height: 1.8),
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

        return HomeScreen(
          nickname: profile['nickname'] as String,
          avatarBase64: avatar is String ? avatar : '',
          onProfileChanged: _reloadProfile,
        );
      },
    );
  }
}