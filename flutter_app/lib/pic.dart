import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'main.dart';

// カメラでの撮影を行う画面。
// 撮影が完了すると、呼び出し元に XFile を渡して閉じる（確認画面は挟まない）。
// 写真の保存・アップロードはこの画面の責務ではない。
class PicScreen extends StatefulWidget {
  const PicScreen({super.key});

  @override
  State<PicScreen> createState() => _PicScreenState();
}

class _PicScreenState extends State<PicScreen> {
  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  Future<void>? _initializeFuture;
  int _cameraIndex = 0;
  bool _isTakingPicture = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeFuture = _setUpCamera();
  }

  Future<void> _setUpCamera() async {
    try {
      _cameras = await availableCameras();

      if (_cameras.isEmpty) {
        setState(() {
          _errorMessage = '利用できるカメラが見つかりませんでした。';
        });
        return;
      }

      // 背面カメラを初期カメラにする。見つからない場合は先頭のカメラを使う。
      final backIndex = _cameras.indexWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
      );

      await _openCamera(backIndex == -1 ? 0 : backIndex);
    } on CameraException catch (error) {
      setState(() {
        _errorMessage = _messageForCameraException(error);
      });
    } catch (_) {
      setState(() {
        _errorMessage = 'カメラを起動できませんでした。';
      });
    }
  }

  Future<void> _openCamera(int index) async {
    final previousController = _controller;

    final controller = CameraController(
      _cameras[index],
      ResolutionPreset.high,
      enableAudio: false,
    );

    await controller.initialize();

    // 切り替え完了後に古いコントローラーを破棄する。
    await previousController?.dispose();

    if (!mounted) {
      await controller.dispose();
      return;
    }

    setState(() {
      _controller = controller;
      _cameraIndex = index;
    });
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _isTakingPicture) return;

    final nextIndex = (_cameraIndex + 1) % _cameras.length;

    try {
      await _openCamera(nextIndex);
    } on CameraException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(_messageForCameraException(error))),
        );
    }
  }

  Future<void> _takePicture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (_isTakingPicture) return;

    setState(() {
      _isTakingPicture = true;
    });

    try {
      final file = await controller.takePicture();

      if (!mounted) return;

      // 確認画面は挟まず、撮影結果をそのまま呼び出し元へ返す。
      Navigator.of(context).pop(file);
    } on CameraException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(_messageForCameraException(error))),
        );
    } finally {
      if (mounted) {
        setState(() {
          _isTakingPicture = false;
        });
      }
    }
  }

  String _messageForCameraException(CameraException error) {
    switch (error.code) {
      case 'CameraAccessDenied':
      case 'CameraAccessDeniedWithoutPrompt':
      case 'CameraAccessRestricted':
        return 'カメラへのアクセスが許可されていません。設定を確認してください。';
      default:
        return 'カメラでエラーが発生しました。';
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: FutureBuilder<void>(
          future: _initializeFuture,
          builder: (context, snapshot) {
            if (_errorMessage != null) {
              return _buildError(_errorMessage!);
            }

            final controller = _controller;
            if (snapshot.connectionState != ConnectionState.done ||
                controller == null ||
                !controller.value.isInitialized) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
            }

            return _buildCamera(controller);
          },
        ),
      ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.no_photography_rounded,
              size: 48,
              color: Colors.white,
            ),
            const SizedBox(height: 20),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, height: 1.8),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white),
              ),
              child: const Text('戻る'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCamera(CameraController controller) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(child: CameraPreview(controller)),
        Positioned(
          top: 8,
          left: 4,
          child: IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(
              Icons.close_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
        if (_cameras.length > 1)
          Positioned(
            top: 8,
            right: 4,
            child: IconButton(
              onPressed: _isTakingPicture ? null : _switchCamera,
              icon: const Icon(
                Icons.cameraswitch_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
        Positioned(
          bottom: 32,
          left: 0,
          right: 0,
          child: Center(
            child: GestureDetector(
              onTap: _isTakingPicture ? null : _takePicture,
              child: Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.fromBorderSide(
                    BorderSide(color: accentColor, width: 4),
                  ),
                ),
                child: _isTakingPicture
                    ? const Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: accentColor,
                        ),
                      )
                    : null,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
