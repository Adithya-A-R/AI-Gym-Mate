import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

class PoseDetectionScreen extends StatefulWidget {
  const PoseDetectionScreen({super.key});

  @override
  State<PoseDetectionScreen> createState() => _PoseDetectionScreenState();
}

class _PoseDetectionScreenState extends State<PoseDetectionScreen> {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isDetecting = false;

  String _selectedExercise = "Squat";

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    final camera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
    );

    _cameraController = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await _cameraController!.initialize();

    setState(() {
      _isCameraInitialized = true;
    });
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  void _toggleDetection() {
    setState(() {
      _isDetecting = !_isDetecting;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Pose Detection")),
      body: !_isCameraInitialized
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                CameraPreview(_cameraController!),

                // ===== SKELETON OVERLAY PLACEHOLDER =====
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _PoseOverlayPainter(),
                    ),
                  ),
                ),

                // ===== TOP CONTROLS =====
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedExercise,
                          items: const [
                            DropdownMenuItem(
                              value: "Squat",
                              child: Text("Squat"),
                            ),
                            DropdownMenuItem(
                              value: "Push-up",
                              child: Text("Push-up"),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedExercise = value!;
                            });
                          },
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.white70,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ===== BOTTOM CONTROLS =====
                Positioned(
                  bottom: 24,
                  left: 24,
                  right: 24,
                  child: Column(
                    children: [
                      if (_isDetecting)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            "Detecting pose...",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        icon: Icon(
                          _isDetecting
                              ? Icons.stop
                              : Icons.play_arrow,
                        ),
                        label: Text(
                          _isDetecting
                              ? "Stop Detection"
                              : "Start Detection",
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: 14,
                            horizontal: 24,
                          ),
                        ),
                        onPressed: _toggleDetection,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

// ================= OVERLAY PAINTER =================
class _PoseOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    // Placeholder stick figure (for demo)
    canvas.drawCircle(
        Offset(size.width / 2, size.height / 3), 10, paint);
    canvas.drawLine(
        Offset(size.width / 2, size.height / 3 + 10),
        Offset(size.width / 2, size.height / 2),
        paint);
    canvas.drawLine(
        Offset(size.width / 2, size.height / 2),
        Offset(size.width / 2 - 40, size.height / 2 + 60),
        paint);
    canvas.drawLine(
        Offset(size.width / 2, size.height / 2),
        Offset(size.width / 2 + 40, size.height / 2 + 60),
        paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
