import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

enum CameraStatus { initialising, ready, capturing, permissionDenied, error }

class CameraStateModel {
  final CameraStatus status;
  final CameraController? controller;
  final String? error;

  const CameraStateModel({
    this.status = CameraStatus.initialising,
    this.controller,
    this.error,
  });

  bool get isReady => status == CameraStatus.ready && controller != null;
  bool get isCapturing => status == CameraStatus.capturing;
  bool get isPermissionDenied => status == CameraStatus.permissionDenied;
}

class TaveraCameraController
    extends AsyncNotifier<CameraStateModel> {
  @override
  Future<CameraStateModel> build() async {
    final result = await _initialise();
    // Ensure camera is released when the provider is disposed
    ref.onDispose(() => result.controller?.dispose());
    return result;
  }

  Future<CameraStateModel> _initialise() async {
    try {
      // Check permission before touching the camera API.
      // On first launch this shows the system dialog; on subsequent launches
      // it reads the cached status without any UI.
      final status = await Permission.camera.request();

      if (status.isPermanentlyDenied || status.isDenied) {
        return const CameraStateModel(
          status: CameraStatus.permissionDenied,
        );
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        return const CameraStateModel(
          status: CameraStatus.error,
          error: 'No camera found on this device',
        );
      }

      final controller = CameraController(
        cameras.first,
        // medium = 1280×720 on iOS/Android — enough for GPT-4o Vision and
        // uses ~3× less preview-buffer memory than ResolutionPreset.high.
        // The API downsamples internally to 768 px tiles so higher res
        // provides zero accuracy gain at significant memory cost.
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();
      await controller.setFlashMode(FlashMode.auto);

      return CameraStateModel(
        status: CameraStatus.ready,
        controller: controller,
      );
    } on CameraException catch (e) {
      // The camera plugin also throws CameraException when permission is
      // denied on some Android versions — normalise to permissionDenied.
      if (e.code == 'cameraPermission' ||
          (e.description?.toLowerCase().contains('permission') ?? false)) {
        return const CameraStateModel(status: CameraStatus.permissionDenied);
      }
      return CameraStateModel(
        status: CameraStatus.error,
        error: e.description ?? 'Camera initialisation failed',
      );
    } catch (e) {
      return CameraStateModel(
        status: CameraStatus.error,
        error: e.toString(),
      );
    }
  }

  /// Captures a photo and returns the [File], or null on failure.
  Future<File?> capture() async {
    final current = state.valueOrNull;
    if (current?.controller == null || !current!.isReady) return null;

    try {
      // Update state to capturing to show flash animation
      state = AsyncData(
        CameraStateModel(
          status: CameraStatus.capturing,
          controller: current.controller,
        ),
      );

      final xFile = await current.controller!.takePicture();

      // Restore ready state
      state = AsyncData(
        CameraStateModel(
          status: CameraStatus.ready,
          controller: current.controller,
        ),
      );

      return File(xFile.path);
    } catch (e) {
      state = AsyncData(
        CameraStateModel(
          status: CameraStatus.ready,
          controller: current.controller,
        ),
      );
      return null;
    }
  }

  /// Called when the app resumes from background.
  Future<void> reinitialise() async {
    final old = state.valueOrNull?.controller;
    await old?.dispose();
    state = const AsyncLoading();
    final result = await _initialise();
    ref.onDispose(() => result.controller?.dispose());
    state = AsyncData(result);
  }
}

final cameraControllerProvider =
    AsyncNotifierProvider<TaveraCameraController, CameraStateModel>(
  TaveraCameraController.new,
);
