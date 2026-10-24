import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as imaging;
import 'package:image_picker/image_picker.dart';

import 'controller.dart';
import 'main.dart';

class CaptureScreen extends StatefulWidget {
  final RelayController c;
  const CaptureScreen({super.key, required this.c});
  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final picker = ImagePicker();
  final List<Uint8List> drafts = [];
  bool picking = false;
  bool sent = false;

  Future<Uint8List> normalize(XFile file) async {
    final source = await file.readAsBytes();
    if (source.length > 30 * 1024 * 1024) throw Exception('写真は1枚30MBまでです');
    ui.Codec? codec;
    ui.Image? decoded;
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(source);
      codec = await ui.instantiateImageCodecWithSize(
        buffer,
        getTargetSize: (w, h) {
          final scale = 1400 / (w > h ? w : h);
          return ui.TargetImageSize(
            width: scale < 1 ? (w * scale).round() : w,
            height: scale < 1 ? (h * scale).round() : h,
          );
        },
      );
      final frame = await codec.getNextFrame();
      decoded = frame.image;
      final rgba = await decoded.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (rgba == null) throw Exception('画像を変換できません');
      final image = imaging.Image.fromBytes(
        width: decoded.width,
        height: decoded.height,
        bytes: rgba.buffer,
        bytesOffset: rgba.offsetInBytes,
        numChannels: 4,
      );
      final jpeg = imaging.encodeJpg(image, quality: 80);
      if (jpeg.length > 1800000) throw Exception('写真のサイズが大きすぎます');
      return jpeg;
    } catch (_) {
      throw Exception('この写真を読み込めませんでした。カメラで撮り直すか、JPEG・PNGの写真を選んでください。');
    } finally {
      decoded?.dispose();
      codec?.dispose();
    }
  }

  Future<void> pick(bool camera) async {
    if (picking || widget.c.busy) return;
    if (drafts.length >= 9) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('1セット9枚までです。先に送るか、写真を外してください。')),
      );
      return;
    }
    setState(() => picking = true);
    try {
      final files = camera
          ? [
              await picker.pickImage(
                source: ImageSource.camera,
                preferredCameraDevice: CameraDevice.rear,
                maxWidth: 1400,
                maxHeight: 1400,
                imageQuality: 80,
              ),
            ].whereType<XFile>().toList()
          : await picker.pickMultiImage(
              maxWidth: 1400,
              maxHeight: 1400,
              imageQuality: 80,
            );
      if (files.length + drafts.length > 9) throw Exception('1セット9枚まで選んでください');
      final converted = <Uint8List>[];
      for (final f in files) {
        converted.add(await normalize(f));
      }
      if (mounted) setState(() => drafts.addAll(converted));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> send() async {
    if (drafts.isEmpty || picking || widget.c.busy) return;
    final ok = await perform(
      context,
      () => widget.c.mutate('rounds', {
        'photos': drafts
            .map((b) => 'data:image/jpeg;base64,${base64Encode(b)}')
            .toList(),
      }),
    );
    if (!mounted || !ok) return;
    setState(() => sent = true);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => SentScreen(c: widget.c)),
    );
  }

  Future<void> leave(bool didPop, Object? result) async {
    if (didPop || widget.c.busy || picking || sent) return;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('撮影画面を閉じる？'),
        content: const Text('まだ送っていない写真は保存されません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('撮影を続ける'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      setState(() => sent = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.c,
    builder: (context, _) => PopScope(
      canPop: !picking && !widget.c.busy && (drafts.isEmpty || sent),
      onPopInvokedWithResult: leave,
      child: AppPage(
        title: '${widget.c.partner?.name ?? '相手'}を撮る',
        c: widget.c,
        bottom: FilledButton.icon(
          onPressed: drafts.isEmpty || picking || widget.c.busy ? null : send,
          icon: const Icon(Icons.send_rounded),
          label: Text(widget.c.busy ? '送っています…' : '${drafts.length}枚を相手に送る'),
        ),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: Container(
                height: 330,
                color: const Color(0xFF252323),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (drafts.isNotEmpty)
                      Image.memory(drafts.last, fit: BoxFit.contain)
                    else
                      const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.camera_alt_outlined,
                              color: Colors.white70,
                              size: 60,
                            ),
                            SizedBox(height: 18),
                            Text(
                              'いろんな構図で撮ってみよう',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                            SizedBox(height: 10),
                            Text(
                              '下のボタンで、iPhoneの撮影画面へ',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const Positioned(
                      top: 16,
                      left: 16,
                      child: Text(
                        '3 : 4',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                    Positioned(
                      bottom: 14,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          '${drafts.length} / 9',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                    if (picking)
                      const ColoredBox(
                        color: Colors.black54,
                        child: Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filledTonal(
                  tooltip: '写真を選ぶ',
                  onPressed: picking || widget.c.busy
                      ? null
                      : () => pick(false),
                  icon: const Icon(Icons.photo_library_outlined),
                ),
                const SizedBox(width: 24),
                SizedBox(
                  width: 80,
                  height: 80,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      shape: const CircleBorder(),
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: picking || widget.c.busy
                        ? null
                        : () => pick(true),
                    child: const Icon(Icons.camera_alt, size: 34),
                  ),
                ),
                const SizedBox(width: 24),
                const SizedBox(
                  width: 48,
                  child: Text(
                    '撮る',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text(
              '3枚以上で、相手の好みを予想するゲームに。\n送信前の写真は、ここで外せます。',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 12, height: 1.8),
            ),
            const SizedBox(height: 18),
            if (drafts.isNotEmpty)
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: drafts.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: .8,
                ),
                itemBuilder: (context, i) => Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.memory(drafts[i], fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: IconButton(
                        tooltip: '送信前の写真${i + 1}を外す',
                        onPressed: picking || widget.c.busy
                            ? null
                            : () => setState(() => drafts.removeAt(i)),
                        icon: const Icon(
                          Icons.cancel,
                          color: Colors.white,
                          shadows: [Shadow(blurRadius: 5)],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 18),
            const Text(
              'この版では標準カメラを開いて撮影します。ライブ映像や白枠ガイドは、まだ表示しません。',
              style: TextStyle(color: muted, fontSize: 11, height: 1.7),
            ),
          ],
        ),
      ),
    ),
  );
}

class SentScreen extends StatelessWidget {
  final RelayController c;
  const SentScreen({super.key, required this.c});
  @override
  Widget build(BuildContext context) => AppPage(
    title: '写真を送りました',
    c: c,
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 42),
        const CircleAvatar(
          radius: 45,
          backgroundColor: Color(0xFFFFE7DB),
          child: Icon(Icons.favorite, color: coral, size: 42),
        ),
        const SizedBox(height: 30),
        const Intro(
          'どの一枚を、\n好きって言ってくれるかな。',
          '相手が「届いた写真」からお気に入りを選ぶと、\nホームに予想ゲームのお知らせが届きます。',
        ),
        FilledButton(
          onPressed: () => goHome(context),
          child: const Text('ホームで待つ'),
        ),
        const SizedBox(height: 14),
        OutlinedButton(
          onPressed: () => Navigator.pushReplacement(
            context,
            MaterialPageRoute<void>(builder: (_) => AlbumScreen(c: c)),
          ),
          child: const Text('送った写真を見る'),
        ),
      ],
    ),
  );
}
