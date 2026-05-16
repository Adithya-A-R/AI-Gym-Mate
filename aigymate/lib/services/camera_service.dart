import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image/image.dart' as img;
import 'dart:typed_data';
import 'dart:io';
import 'dart:convert';

class CameraService {
  static CameraController? _cameraController;
  static List<CameraDescription> _cameras = [];
  static bool _isInitialized = false;

  static Future<bool> initializeCamera() async {
    try {
      // Request camera permission
      final cameraPermission = await Permission.camera.request();
      if (!cameraPermission.isGranted) {
        return false;
      }

      // Get available cameras
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        return false;
      }

      // Initialize the rear camera (or first available)
      final camera = _cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );

      _cameraController = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();
      _isInitialized = true;
      return true;
    } catch (e) {
      print('Camera initialization error: $e');
      return false;
    }
  }

  static CameraController? get controller => _cameraController;
  static bool get isInitialized => _isInitialized;

  static Future<Uint8List?> captureFrame() async {
    try {
      if (!_isInitialized || _cameraController == null) {
        return null;
      }

      final image = await _cameraController!.takePicture();
      final bytes = await File(image.path).readAsBytes();
      
      // Resize image for faster processing
      final decodedImage = img.decodeImage(bytes);
      if (decodedImage != null) {
        final resizedImage = img.copyResize(
          decodedImage,
          width: 640,
          height: 480,
          maintainAspect: true,
        );
        return Uint8List.fromList(img.encodeJpg(resizedImage, quality: 85));
      }
      
      return bytes;
    } catch (e) {
      print('Frame capture error: $e');
      return null;
    }
  }

  static Future<void> dispose() async {
    if (_cameraController != null) {
      await _cameraController!.dispose();
      _cameraController = null;
      _isInitialized = false;
    }
  }

  static Future<void> switchCamera() async {
    if (_cameras.length < 2 || _cameraController == null) return;

    try {
      await _cameraController!.dispose();
      
      // Switch to next camera
      final currentCameraIndex = _cameras.indexOf(_cameraController!.description);
      final nextCameraIndex = (currentCameraIndex + 1) % _cameras.length;
      
      _cameraController = CameraController(
        _cameras[nextCameraIndex],
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();
    } catch (e) {
      print('Camera switch error: $e');
    }
  }

  static String imageToBase64(Uint8List imageBytes) {
    return 'data:image/jpeg;base64,${base64Encode(imageBytes)}';
  }
}
