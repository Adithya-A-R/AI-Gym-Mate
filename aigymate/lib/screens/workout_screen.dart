import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:camera/camera.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/camera_service.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../models/user.dart';
import 'dart:async';
import 'dart:convert';

class WorkoutScreen extends StatefulWidget {
  final String exerciseId;
  final Map<String, dynamic> exerciseData;
  final String sessionId;
  final List<String>? medicalConditions;

  const WorkoutScreen({
    super.key,
    required this.exerciseId,
    required this.exerciseData,
    required this.sessionId,
    this.medicalConditions,
  });

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  int _reps = 0;
  int _sets = 0;
  bool _isWorkoutActive = false;
  String _postureFeedback = 'Get ready to start!';
  double _postureAccuracy = 0.0;
  bool _cameraInitialized = false;
  bool _isAnalyzing = false;
  Timer? _analysisTimer;
  Timer? _recommendationTimer;
  List<List<dynamic>> _landmarksHistory = [];
  
  // Smart recommendation variables
  String _recommendation = '';
  String _recommendationType = '';
  Color _recommendationColor = Colors.grey;
  User? _currentUser;
  List<Map<String, dynamic>> _sessionHistory = [];
  DateTime _workoutStartTime = DateTime.now();
  double _totalCaloriesBurned = 0.0;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _loadUserData();
  }

  @override
  void dispose() {
    _analysisTimer?.cancel();
    _recommendationTimer?.cancel();
    CameraService.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final user = await AuthService().getCurrentUser();
    final prefs = await SharedPreferences.getInstance();
    
    setState(() {
      _currentUser = user;
    });
  }

  Future<void> _initializeCamera() async {
    final initialized = await CameraService.initializeCamera();
    if (mounted) {
      setState(() {
        _cameraInitialized = initialized;
        if (!initialized) {
          _postureFeedback = 'Camera initialization failed. Please check permissions.';
        }
      });
    }
  }

  Future<void> _testConnection() async {
    try {
      setState(() {
        _postureFeedback = 'Testing connection...';
      });
      
      final result = await ApiService.checkHealth();
      
      if (mounted) {
        setState(() {
          _postureFeedback = '✅ Connected! Model: ${result['model_loaded'] ? 'Loaded' : 'Not found'}';
          _postureAccuracy = 1.0;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _postureFeedback = '❌ Connection failed: $e';
          _postureAccuracy = 0.0;
        });
      }
    }
  }

  Future<void> _analyzePose() async {
    if (_isAnalyzing || !_isWorkoutActive || !_cameraInitialized) return;

    setState(() {
      _isAnalyzing = true;
    });

    try {
      final imageBytes = await CameraService.captureFrame();
      if (imageBytes != null) {
        final base64Image = CameraService.imageToBase64(imageBytes);
        final response = await ApiService.analyzePose(
          base64Image: base64Image,
          exerciseType: widget.exerciseId,
        );

        if (response['success'] && mounted) {
          final landmarks = response['landmarks'] as List<dynamic>;
          final posture = response['posture'];

          setState(() {
            _landmarksHistory.add(landmarks.cast<dynamic>());
            if (_landmarksHistory.length > 10) {
              _landmarksHistory.removeAt(0);
            }

            if (posture != null) {
              _postureAccuracy = posture['confidence']?.toDouble() ?? 0.0;
              _postureFeedback = posture['feedback'] ?? 'Keep going!';
              
              // Count reps based on movement
              if (_landmarksHistory.length >= 2) {
                final repCounted = _countReps();
                if (repCounted) {
                  _reps++;
                  if (_reps % 10 == 0) {
                    _sets++;
                  }
                }
              }
            }
          });

          // Update calories burned
          _updateCaloriesBurned();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _postureFeedback = 'Analysis error: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
        });
      }
    }
  }

  Future<void> _updateCaloriesBurned() async {
    if (_currentUser == null) return;
    
    try {
      final duration = DateTime.now().difference(_workoutStartTime).inMinutes.toDouble();
      final result = await ApiService.calculateWorkoutCalories(
        exerciseType: widget.exerciseId,
        durationMinutes: duration,
        userWeight: _currentUser!.weight?.toDouble() ?? 70.0,
        reps: _reps,
      );
      
      if (mounted && result['success']) {
        setState(() {
          _totalCaloriesBurned = result['calories_burned']?.toDouble() ?? 0.0;
        });
      }
    } catch (e) {
      print('Error calculating calories: $e');
    }
  }

  Future<void> _getRealTimeRecommendations() async {
    if (_currentUser == null) return;
    
    try {
      // Create current session data with landmarks for CNN analysis
      final currentSession = {
        'exercise_type': widget.exerciseId,
        'rep_count': _reps,
        'landmarks': _landmarksHistory.isNotEmpty ? _landmarksHistory.last : [],
        'target_reps': 10,
        'confidence_history': _landmarksHistory.map((landmarks) => _postureAccuracy).toList(),
        'rep_completion': (_reps / 10.0).clamp(0.0, 1.0),
        'form_consistency': _postureAccuracy,
        'duration_seconds': DateTime.now().difference(_workoutStartTime).inSeconds.toDouble(),
      };

      // Create user profile for recommendation using real user data
      final userProfile = {
        'medical_conditions': widget.medicalConditions ?? [],
        'goal': _currentUser?.goal ?? 'maintenance',
        'fitness_level': 'beginner', // This should come from user profile
        'weight': _currentUser?.weight ?? 70,
        'height': _currentUser?.height ?? 170,
        'age': _currentUser?.age ?? 30,
      };

      final result = await ApiService.getWorkoutRecommendations(
        userProfile: userProfile,
        sessionHistory: _sessionHistory,
        currentSession: currentSession,
      );

      if (mounted && result['success'] && result['recommendations'].isNotEmpty) {
        final recommendations = result['recommendations'] as List;
        if (recommendations.isNotEmpty) {
          final recommendation = recommendations.first;
          setState(() {
            _recommendation = recommendation['message'] ?? '';
            _recommendationType = recommendation['type'] ?? '';
            
            // Set color based on recommendation type
            switch (_recommendationType) {
              case 'challenge':
                _recommendationColor = Colors.orange;
                break;
              case 'encouragement':
                _recommendationColor = Colors.green;
                break;
              case 'correction':
                _recommendationColor = Colors.red;
                break;
              case 'nutrition_focus':
                _recommendationColor = Colors.blue;
                break;
              case 'recovery_nutrition':
                _recommendationColor = Colors.purple;
                break;
              case 'cardio_boost':
                _recommendationColor = Colors.teal;
                break;
              case 'nutrition_increase':
                _recommendationColor = Colors.indigo;
                break;
              default:
                _recommendationColor = Colors.blue;
            }
          });
        }
      }
    } catch (e) {
      print('Error getting recommendations: $e');
    }
  }

  void _startWorkout() {
    setState(() {
      _isWorkoutActive = true;
      _workoutStartTime = DateTime.now();
      _reps = 0;
      _sets = 0;
      _postureFeedback = 'Workout started! Keep going!';
    });

    // Start pose analysis timer
    _analysisTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _analyzePose();
    });

    // Start recommendation timer (every 10 seconds)
    _recommendationTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _getRealTimeRecommendations();
    });
  }

  void _stopWorkout() {
    setState(() {
      _isWorkoutActive = false;
      _postureFeedback = 'Workout completed! Great job!';
    });

    _analysisTimer?.cancel();
    _recommendationTimer?.cancel();

    // Save session to history
    _saveSessionToHistory();
  }

  Future<void> _saveSessionToHistory() async {
    if (_currentUser == null) return;
    
    final session = {
      'exercise_type': widget.exerciseId,
      'reps': _reps,
      'sets': _sets,
      'posture_accuracy': _postureAccuracy,
      'calories_burned': _totalCaloriesBurned,
      'duration_minutes': DateTime.now().difference(_workoutStartTime).inMinutes.toDouble(),
      'timestamp': DateTime.now().toIso8601String(),
    };

    setState(() {
      _sessionHistory.add(session);
    });

    // Here you could also save to persistent storage
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('workout_history') ?? [];
    history.add(jsonEncode(session));
    await prefs.setStringList('workout_history', history);
  }

  bool _countReps() {
    // Simplified rep counting logic
    if (_landmarksHistory.length < 2) return false;

    final current = _landmarksHistory.last;
    final previous = _landmarksHistory[_landmarksHistory.length - 2];

    // For squats, track hip movement
    if (widget.exerciseId == 'squats' && current.length > 24 && previous.length > 24) {
      final hipYCurrent = double.tryParse(current[24].toString()) ?? 0.0;
      final hipYPrevious = double.tryParse(previous[24].toString()) ?? 0.0;
      return (hipYCurrent - hipYPrevious).abs() > 0.1;
    }

    // For pushups, track elbow movement
    if (widget.exerciseId == 'pushups' && current.length > 14 && previous.length > 14) {
      final elbowYCurrent = double.tryParse(current[14].toString()) ?? 0.0;
      final elbowYPrevious = double.tryParse(previous[14].toString()) ?? 0.0;
      return (elbowYCurrent - elbowYPrevious).abs() > 0.1;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.exerciseData['name'],
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(FontAwesomeIcons.arrowLeft),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.blue.shade50,
              Colors.white,
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Exercise Info Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Session ID',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        Text(
                          widget.sessionId,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue.shade600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.exerciseData['description'],
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Camera View
              Expanded(
                flex: 2,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.grey.shade300,
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: _cameraInitialized && CameraService.controller != null
                        ? Stack(
                            children: [
                              // Camera preview
                              SizedBox(
                                width: double.infinity,
                                height: double.infinity,
                                child: FittedBox(
                                  fit: BoxFit.cover,
                                  child: SizedBox(
                                    width: CameraService.controller!.value.previewSize!.height,
                                    height: CameraService.controller!.value.previewSize!.width,
                                    child: CameraPreview(CameraService.controller!),
                                  ),
                                ),
                              ),
                              
                              // Analysis indicator
                              if (_isAnalyzing)
                                Positioned(
                                  top: 16,
                                  right: 16,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withOpacity(0.8),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Analyzing',
                                          style: GoogleFonts.poppins(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              
                              // Posture accuracy overlay
                              if (_isWorkoutActive)
                                Positioned(
                                  bottom: 16,
                                  left: 16,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _postureAccuracy > 0.7 
                                          ? Colors.green.withOpacity(0.8)
                                          : Colors.orange.withOpacity(0.8),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'Form Accuracy',
                                          style: GoogleFonts.poppins(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          '${(_postureAccuracy * 100).toInt()}%',
                                          style: GoogleFonts.poppins(
                                            color: Colors.white,
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                FontAwesomeIcons.camera,
                                size: 64,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _cameraInitialized ? 'Camera Ready' : 'Initializing Camera...',
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              if (!_cameraInitialized) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Please check camera permissions',
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: _initializeCamera,
                                  icon: const Icon(FontAwesomeIcons.rotate),
                                  label: Text(
                                    'Retry',
                                    style: GoogleFonts.poppins(),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ],
                            ],
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Stats Row
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      icon: FontAwesomeIcons.repeat,
                      title: 'Reps',
                      value: _reps.toString(),
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildStatCard(
                      icon: FontAwesomeIcons.layerGroup,
                      title: 'Sets',
                      value: _sets.toString(),
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildStatCard(
                      icon: FontAwesomeIcons.bullseye,
                      title: 'Accuracy',
                      value: '${(_postureAccuracy * 100).toInt()}%',
                      color: Colors.purple,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Second Stats Row with Calories
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      icon: FontAwesomeIcons.fire,
                      title: 'Calories',
                      value: '${_totalCaloriesBurned.toStringAsFixed(1)}',
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildStatCard(
                      icon: FontAwesomeIcons.clock,
                      title: 'Duration',
                      value: '${DateTime.now().difference(_workoutStartTime).inMinutes}:${(DateTime.now().difference(_workoutStartTime).inSeconds % 60).toString().padLeft(2, '0')}',
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(child: SizedBox()), // Empty space for balance
                ],
              ),
              const SizedBox(height: 24),

              // Smart Recommendations
              if (_recommendation.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _recommendationColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _recommendationColor.withOpacity(0.3),
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _getRecommendationIcon(),
                            color: _recommendationColor,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'AI Recommendation',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _recommendationColor.withOpacity(0.8),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _recommendation,
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: _recommendationColor.withOpacity(0.9),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      // Show model confidence
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'AI Model Confidence: ${(_postureAccuracy * 100).toStringAsFixed(1)}%',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: Colors.grey.shade700,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_recommendation.isNotEmpty) const SizedBox(height: 24),

              // Posture Feedback
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _postureAccuracy > 0.7 ? Colors.green.shade100 : Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _postureAccuracy > 0.7 ? Colors.green.shade300 : Colors.orange.shade300,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _postureAccuracy > 0.7 ? FontAwesomeIcons.checkCircle : FontAwesomeIcons.exclamationTriangle,
                      color: _postureAccuracy > 0.7 ? Colors.green.shade700 : Colors.orange.shade700,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _postureFeedback,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: _postureAccuracy > 0.7 ? Colors.green.shade700 : Colors.orange.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Control Buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isWorkoutActive ? _pauseWorkout : _startWorkout,
                      icon: Icon(
                        _isWorkoutActive ? FontAwesomeIcons.pause : FontAwesomeIcons.play,
                      ),
                      label: Text(
                        _isWorkoutActive ? 'Pause' : 'Start',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isWorkoutActive ? Colors.orange : Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _testConnection,
                      icon: const Icon(FontAwesomeIcons.wifi),
                      label: Text(
                        'Test',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _endWorkout,
                      icon: const Icon(FontAwesomeIcons.stop),
                      label: Text(
                        'End',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: color,
            size: 24,
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getRecommendationIcon() {
    switch (_recommendationType) {
      case 'challenge':
        return FontAwesomeIcons.trophy;
      case 'encouragement':
        return FontAwesomeIcons.thumbsUp;
      case 'correction':
        return FontAwesomeIcons.exclamationTriangle;
      case 'progression':
        return FontAwesomeIcons.arrowUp;
      case 'recovery':
        return FontAwesomeIcons.heart;
      case 'cardio_boost':
        return FontAwesomeIcons.running;
      case 'strength_focus':
        return FontAwesomeIcons.dumbbell;
      default:
        return FontAwesomeIcons.lightbulb;
    }
  }

  void _pauseWorkout() {
    setState(() {
      _isWorkoutActive = false;
      _postureFeedback = 'Workout paused. Press Start to resume.';
    });

    _analysisTimer?.cancel();
    _recommendationTimer?.cancel();
  }

  void _endWorkout() {
    _stopWorkout();
    
    // Show completion dialog with recommendations
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Workout Complete!',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Great job! Here\'s your summary:',
              style: GoogleFonts.poppins(),
            ),
            const SizedBox(height: 16),
            Text('• Total Reps: $_reps'),
            Text('• Total Sets: $_sets'),
            Text('• Calories Burned: ${_totalCaloriesBurned.toStringAsFixed(1)}'),
            Text('• Average Accuracy: ${(_postureAccuracy * 100).toInt()}%'),
            if (_recommendation.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'AI Recommendation:',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
              Text(_recommendation),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }
}
