import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../services/workout_service.dart';

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

  // 🔥 NEW: workout state
  int _totalReps = 0;
  double _caloriesBurned = 0.0;

  final String _userEmail = "test@gmail.com"; // TODO: load from auth/profile

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

  // 🔥 START / STOP WORKOUT
  Future<void> _toggleDetection() async {
    if (_isDetecting) {
      // ===== STOP WORKOUT =====
      await WorkoutService.saveWorkout(
        email: _userEmail,
        exercise: _selectedExercise.toLowerCase(),
        reps: _totalReps,
        calories: _caloriesBurned,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Workout saved successfully"),
        ),
      );
    } else {
      // ===== START WORKOUT =====
      _totalReps = 0;
      _caloriesBurned = 0.0;
    }

    setState(() {
      _isDetecting = !_isDetecting;
    });
  }

  // 🔧 TEMP PLACEHOLDER (later replaced by model output)
  void _simulateRep() {
    if (!_isDetecting) return;

    setState(() {
      _totalReps++;
      _caloriesBurned += _estimateCaloriesPerRep();
    });
  }

  double _estimateCaloriesPerRep() {
    switch (_selectedExercise) {
      case "Push-up":
        return 0.35;
      case "Squat":
        return 0.32;
      default:
        return 0.3;
    }
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

                // ===== OVERLAY (DEMO ONLY) =====
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

                // ===== BOTTOM PANEL =====
                Positioned(
                  bottom: 24,
                  left: 24,
                  right: 24,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Text(
                              "Reps: $_totalReps",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              "Calories: ${_caloriesBurned.toStringAsFixed(1)}",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // 🔥 TEMP BUTTON TO SIMULATE REP
                      if (_isDetecting)
                        ElevatedButton(
                          onPressed: _simulateRep,
                          child: const Text("Simulate Rep (Demo)"),
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
                              ? "Finish Workout"
                              : "Start Workout",
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

    canvas.drawCircle(
      Offset(size.width / 2, size.height / 3),
      10,
      paint,
    );
    canvas.drawLine(
      Offset(size.width / 2, size.height / 3 + 10),
      Offset(size.width / 2, size.height / 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
