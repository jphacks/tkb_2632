import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'services/photo_session_service.dart';

class PicScreen extends StatefulWidget {
  const PicScreen({
    super.key,
    this.shareOnFinish = true,
  });

  // 単体テスト用の撮影画面ではfalseを指定する。
  final bool shareOnFinish;

  @override
  State<PicScreen> createState() => _PicScreenState();
}

class _CapturedPhoto {
  const _CapturedPhoto({
    required this.file,
    required this.bytes,
  });

  final XFile file;
  final Uint8List bytes;
}

class _PicScreenState extends State<PicScreen> {
  List<CameraDescription> _cameras = [];
  CameraController? _controller;

  final List<_CapturedPhoto> _photos = [];
  PhotoSessionUploader? _uploader;

  int _cameraIndex = 0;
  int _uploadedCount = 0;

  bool _taking = false;
  bool _switching = false;
  bool _sharing = false;
  bool _discarding = false;
  bool _lockedForSharing = false;
  bool _allowPop = false;

  double _viewportAspectRatio = 9 / 16;

  String? _cameraError;
  String? _message;

  bool get _busy => _taking || _switching || _sharing || _discarding;

  @override
  void initState() {
    super.initState();
    _setUpCamera();
  }

  Future<void> _setUpCamera() async {
    try {
      _cameras = await availableCameras();

      if (!mounted) return;

      if (_cameras.isEmpty) {
        setState(() {
          _cameraError = '利用できるカメラが見つかりませんでした。';
        });
        return;
      }

      final backIndex = _cameras.indexWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
      );

      await _openCamera(backIndex == -1 ? 0 : backIndex);
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _cameraError = error is CameraException
            ? _cameraMessage(error)
            : 'カメラを起動できませんでした。';
      });
    }
  }

  Future<void> _openCamera(int index) async {
    final previous = _controller;

    if (mounted) {
      setState(() {
        _controller = null;
        _cameraError = null;
      });
    }

    await previous?.dispose();

    if (!mounted) return;

    final controller = CameraController(
      _cameras[index],
      ResolutionPreset.high,
      enableAudio: false,
    );

    try {
      await controller.initialize();
    } catch (_) {
      await controller.dispose();
      rethrow;
    }

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
    if (_busy || _cameras.length < 2 || _lockedForSharing) return;

    setState(() {
      _switching = true;
    });

    try {
      await _openCamera(
        (_cameraIndex + 1) % _cameras.length,
      );
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _cameraError = error is CameraException
            ? _cameraMessage(error)
            : 'カメラを切り替えられませんでした。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _switching = false;
        });
      }
    }
  }

  Future<void> _takePicture() async {
    final controller = _controller;

    if (_busy || _lockedForSharing) return;
    if (controller == null || !controller.value.isInitialized) return;

    if (_photos.length >= 30) {
      setState(() {
        _message = '1回に撮影できる写真は30枚までです。撮影を終了してください。';
      });
      return;
    }

    final aspectRatio = _viewportAspectRatio;

    setState(() {
      _taking = true;
      _message = null;
    });

    try {
      final file = await controller.takePicture();
      final source = await file.readAsBytes();

      final prepared = prepareSessionPhoto(
        source,
        aspectRatio,
      );

      if (!mounted) return;

      setState(() {
        _photos.add(
          _CapturedPhoto(
            file: file,
            bytes: prepared,
          ),
        );
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        if (error is CameraException) {
          _message = _cameraMessage(error);
        } else if (error is FormatException) {
          _message = error.message;
        } else {
          _message = '撮影できませんでした。もう一度お試しください。';
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _taking = false;
        });
      }
    }
  }

  Future<void> _finish() async {
    if (_busy || _photos.isEmpty) return;

    // 撮影機能だけを試す場合は、最後の写真を返す。
    if (!widget.shareOnFinish) {
      await _pop(_photos.last.file);
      return;
    }

    setState(() {
      _sharing = true;
      _lockedForSharing = true;
      _message = null;
    });

    try {
      _uploader ??= PhotoSessionUploader();

      await _uploader!.share(
        _photos.map((photo) => photo.bytes).toList(),
        onProgress: (completed, total) {
          if (!mounted) return;

          setState(() {
            _uploadedCount = completed;
          });
        },
      );

      if (!mounted) return;

      // 現在の呼び出し元との互換性のため、最後のXFileを返す。
      // セット全体は、この時点ですでに保存・共有済み。
      await _pop(_photos.last.file);
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _message = '共有できませんでした。写真はこの画面に残っています。\n'
            '接続を確認して「共有を再試行」を押してください。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _sharing = false;
        });
      }
    }
  }

  Future<void> _requestClose() async {
    if (_busy) return;

    if (_photos.isEmpty) {
      await _pop();
      return;
    }

    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('撮影を終了しますか？'),
        content: const Text(
          'まだ共有していない写真を破棄して、ホームへ戻ります。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('撮影に戻る'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('破棄して戻る'),
          ),
        ],
      ),
    );

    if (discard != true || !mounted) return;

    setState(() {
      _discarding = true;
      _message = null;
    });

    try {
      await _uploader?.discard();

      if (!mounted) return;

      await _pop();
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _message = '未共有の写真を整理できませんでした。\n'
            '接続を確認して、もう一度お試しください。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _discarding = false;
        });
      }
    }
  }

  Future<void> _pop([XFile? result]) async {
    if (!mounted) return;

    setState(() {
      _allowPop = true;
    });

    await WidgetsBinding.instance.endOfFrame;

    if (!mounted) return;

    Navigator.of(context).pop(result);
  }

  void _removePhoto(int index) {
    if (_busy || _lockedForSharing) return;

    setState(() {
      _photos.removeAt(index);
    });
  }

  String _cameraMessage(CameraException error) {
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
    return PopScope<XFile>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _requestClose();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: LayoutBuilder(
          builder: (context, constraints) {
            _viewportAspectRatio =
                constraints.maxWidth / constraints.maxHeight;

            final controller = _controller;

            return Stack(
              fit: StackFit.expand,
              children: [
                if (_cameraError != null)
                  _buildCameraError()
                else if (controller != null &&
                    controller.value.isInitialized)
                  _buildPreview(controller)
                else
                  const Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                    ),
                  ),

                // 上部の操作
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          IconButton.filledTonal(
                            onPressed: _busy ? null : _requestClose,
                            icon: const Icon(Icons.close_rounded),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Text(
                              '${_photos.length} / 30枚',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const Spacer(),
                          IconButton.filledTonal(
                            onPressed: _busy ||
                                    _lockedForSharing ||
                                    _cameras.length < 2
                                ? null
                                : _switchCamera,
                            icon: const Icon(
                              Icons.cameraswitch_rounded,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // 下部の撮影・共有操作
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(
                      16,
                      32,
                      16,
                      16,
                    ),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black87,
                        ],
                      ),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_photos.isNotEmpty) ...[
                            SizedBox(
                              height: 70,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: _photos.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 8),
                                itemBuilder: (context, index) {
                                  return Stack(
                                    children: [
                                      ClipRRect(
                                        borderRadius:
                                            BorderRadius.circular(8),
                                        child: Image.memory(
                                          _photos[index].bytes,
                                          width: 52,
                                          height: 70,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                      if (!_lockedForSharing && !_busy)
                                        Positioned(
                                          top: 0,
                                          right: 0,
                                          child: InkWell(
                                            onTap: () {
                                              _removePhoto(index);
                                            },
                                            child: const DecoratedBox(
                                              decoration: BoxDecoration(
                                                color: Colors.black54,
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                Icons.close_rounded,
                                                color: Colors.white,
                                                size: 20,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (_message != null) ...[
                            Text(
                              _message!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                height: 1.6,
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 72,
                                height: 72,
                                child: IconButton(
                                  onPressed: _busy ||
                                          _lockedForSharing ||
                                          _photos.length >= 30 ||
                                          controller == null
                                      ? null
                                      : _takePicture,
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    disabledBackgroundColor:
                                        Colors.white38,
                                    foregroundColor: accentColor,
                                    side: const BorderSide(
                                      color: accentColor,
                                      width: 4,
                                    ),
                                  ),
                                  icon: _taking
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child:
                                              CircularProgressIndicator(
                                            strokeWidth: 3,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.camera_alt_rounded,
                                          size: 30,
                                        ),
                                ),
                              ),
                              const SizedBox(width: 20),
                              Flexible(
                                child: FilledButton(
                                  onPressed: _busy || _photos.isEmpty
                                      ? null
                                      : _finish,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: accentColor,
                                    foregroundColor: Colors.white,
                                    padding:
                                        const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 17,
                                    ),
                                  ),
                                  child: Text(
                                    !widget.shareOnFinish
                                        ? '撮影終了'
                                        : _lockedForSharing
                                            ? '共有を再試行'
                                            : '撮影終了・共有',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                if (_sharing || _discarding)
                  ColoredBox(
                    color: Colors.black87,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(
                            color: Colors.white,
                          ),
                          const SizedBox(height: 24),
                          Text(
                            _discarding
                                ? '写真を整理しています…'
                                : '写真を共有しています…\n'
                                    '$_uploadedCount / ${_photos.length}枚',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              height: 1.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildPreview(CameraController controller) {
    final previewSize = controller.value.previewSize!;

    // Webでは配信される映像の縦横比を使う。
    // ネイティブの縦画面ではプレビューの向きを考慮する。
    final nativePortrait = !kIsWeb &&
        MediaQuery.orientationOf(context) == Orientation.portrait;

    final aspect = nativePortrait
        ? previewSize.height / previewSize.width
        : previewSize.width / previewSize.height;

    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: aspect * 1000,
            height: 1000,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
  }

  Widget _buildCameraError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Text(
          _cameraError!,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            height: 1.8,
          ),
        ),
      ),
    );
  }
}