import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'pic.dart';

class PicScr extends StatefulWidget {
  const PicScr({super.key});

  @override
  State<PicScr> createState() => _PicScrState();
}

class _PicScrState extends State<PicScr> {
  Uint8List? _lastPhotoBytes;

  Future<void> _openCamera() async {
    final result = await Navigator.of(context).push<XFile>(
      MaterialPageRoute<XFile>(
        builder: (_) => const PicScreen(
          shareOnFinish: false,
        ),
      ),
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
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