import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'main.dart';
import 'pic.dart';

// 「撮影する」ボタンだけの仮の画面。
// 将来的には本来のホーム画面に置き換える。
class PicScr extends StatefulWidget {
  const PicScr({super.key});

  @override
  State<PicScr> createState() => _PicScrState();
}

class _PicScrState extends State<PicScr> {
  Uint8List? _lastPhotoBytes;

  Future<void> _openCamera() async {
    final result = await Navigator.of(context).push<XFile>(
      MaterialPageRoute(builder: (context) => const PicScreen()),
    );

    if (result == null || !mounted) return;

    final bytes = await result.readAsBytes();
    if (!mounted) return;

    setState(() {
      _lastPhotoBytes = bytes;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_lastPhotoBytes != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.memory(
                    _lastPhotoBytes!,
                    width: 220,
                    height: 220,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 24),
              ],
              FilledButton.icon(
                onPressed: _openCamera,
                icon: const Icon(Icons.camera_alt_rounded),
                label: const Text('撮影する'),
                style: FilledButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 18,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
