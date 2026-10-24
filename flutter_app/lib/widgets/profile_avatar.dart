import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    this.avatarBase64 = '',
    this.size = 88,
  });

  final String avatarBase64;
  final double size;

  @override
  Widget build(BuildContext context) {
    Uint8List? bytes;

    if (avatarBase64.isNotEmpty) {
      try {
        bytes = base64Decode(avatarBase64);
      } on FormatException {
        bytes = null;
      }
    }

    final fallback = Icon(
      Icons.person_outline_rounded,
      size: size * 0.48,
      color: const Color(0xFFB95849),
    );

    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Color(0xFFFFEAE2),
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: bytes == null
          ? Center(child: fallback)
          : Image.memory(
              bytes,
              width: size,
              height: size,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) {
                return Center(child: fallback);
              },
            ),
    );
  }
}