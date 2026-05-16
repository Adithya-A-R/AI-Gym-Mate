import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/progress_service.dart';
import 'workout_screen.dart';

class ExerciseSelectionScreen extends StatefulWidget {
  const ExerciseSelectionScreen({super.key});

  @override
  State<ExerciseSelectionScreen> createState() => _ExerciseSelectionScreenState();
}

class _ExerciseSelectionScreenState extends State<ExerciseSelectionScreen> {
  Map<String, dynamic>? exercises;
  bool _isLoading = true;
  String? _error;
  List<String>? _medicalConditions;
  Map<String, dynamic> _progressData = {};
  bool _isLoadingProgress = true;

  @override
  void initState() {
    super.initState();
    _loadMedicalConditions();
    _loadExercises();
    _loadProgressData();
  }

  Future<void> _loadProgressData() async {
    try {
      final data = await ProgressService.getProgressData();
      setState(() {
        _progressData = data;
        _isLoadingProgress = false;
      });
    } catch (e) {
      print('Error loading progress: $e');
      setState(() {
        _isLoadingProgress = false;
      });
    }
  }

  Future<void> _loadMedicalConditions() async {
    final prefs = await SharedPreferences.getInstance();
    final conditions = prefs.getStringList('medical_conditions');
    setState(() {
      _medicalConditions = conditions;
    });
  }

  Future<void> _loadExercises() async {
    try {
      final response = await ApiService.getExercises(
        medicalConditions: _medicalConditions,
      );
      setState(() {
        exercises = response['exercises'];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _startExercise(
      String exerciseId, Map<String, dynamic> exerciseData) async {
    try {
      setState(() {
        _isLoading = true;
      });

      final response = await ApiService.startExercise(
        exerciseType: exerciseId,
        medicalConditions: _medicalConditions,
      );

      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => WorkoutScreen(
              exerciseId: exerciseId,
              exerciseData: exerciseData,
              sessionId: response['session_id'],
              medicalConditions: _medicalConditions,
            ),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error starting exercise: $e',
              style: GoogleFonts.poppins(),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Text(
                'Exercises',
                style: GoogleFonts.poppins(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose an exercise to start your workout',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  color: Colors.white.withOpacity(0.8),
                ),
              ),

              const SizedBox(height: 32),

              // Progress Summary Card
              if (!_isLoadingProgress) ...[
                _buildProgressSummaryCard(),
                const SizedBox(height: 24),
              ],

              // Medical Conditions Warning
              if (_medicalConditions != null &&
                  _medicalConditions!.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.orange.withOpacity(0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        FontAwesomeIcons.triangleExclamation,
                        color: Colors.orange.shade300,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Medical-Aware Filtering Active',
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.orange.shade300,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Exercises filtered for: ${_medicalConditions!.join(', ')}',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: Colors.white.withOpacity(0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Content
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Colors.white,
                        ),
                      )
                    : _error != null
                        ? _buildErrorWidget()
                        : _buildExercisesList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.red.withOpacity(0.4),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FontAwesomeIcons.triangleExclamation,
              color: Colors.red.shade300,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              'Error Loading Exercises',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.red.shade300,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.white.withOpacity(0.8),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadExercises,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.withOpacity(0.3),
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExercisesList() {
    if (exercises == null || exercises!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FontAwesomeIcons.dumbbell,
              size: 64,
              color: Colors.white.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No exercises available',
              style: GoogleFonts.poppins(
                fontSize: 18,
                color: Colors.white.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _medicalConditions != null && _medicalConditions!.isNotEmpty
                  ? 'All exercises are filtered based on your medical conditions'
                  : 'Please check your connection and try again',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.white.withOpacity(0.5),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: exercises!.length,
      itemBuilder: (context, index) {
        final exerciseId = exercises!.keys.elementAt(index);
        final exercise = exercises![exerciseId]!;
        return _buildExerciseCard(exerciseId, exercise);
      },
    );
  }

  Widget _buildExerciseCard(
      String exerciseId, Map<String, dynamic> exercise) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _startExercise(exerciseId, exercise),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                // Exercise Icon
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.blue.shade400,
                        Colors.indigo.shade500,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    _getExerciseIcon(exerciseId),
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),

                // Exercise Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exercise['name'],
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        exercise['description'],
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.7),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _getDifficultyColor(exercise['difficulty'])
                                  .withOpacity(0.3),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              exercise['difficulty'].toUpperCase(),
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Risk Level Badge
                          if (exercise['risk_level'] != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    _getRiskColor(exercise['risk_level'])
                                        .withOpacity(0.3),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color:
                                      _getRiskColor(exercise['risk_level']),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _getRiskIcon(exercise['risk_level']),
                                    color:
                                        _getRiskColor(exercise['risk_level']),
                                    size: 12,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'RISK: ${exercise['risk_level'].toUpperCase()}',
                                    style: GoogleFonts.poppins(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: _getRiskColor(
                                          exercise['risk_level']),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      // Warnings
                      if (exercise['warnings'] != null &&
                          (exercise['warnings'] as List).isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ...((exercise['warnings'] as List).map(
                          (warning) => Container(
                            margin: const EdgeInsets.only(bottom: 4),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: Colors.red.withOpacity(0.5)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  FontAwesomeIcons.triangleExclamation,
                                  color: Colors.red.shade300,
                                  size: 10,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  warning.toString(),
                                  style: GoogleFonts.poppins(
                                    fontSize: 10,
                                    color: Colors.red.shade300,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ).toList()),
                      ],
                      // Modifications
                      if (exercise['modifications'] != null &&
                          (exercise['modifications'] as List).isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ...((exercise['modifications'] as List).map(
                          (mod) => Container(
                            margin: const EdgeInsets.only(bottom: 4),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: Colors.orange.withOpacity(0.5)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  FontAwesomeIcons.circleInfo,
                                  color: Colors.orange.shade300,
                                  size: 10,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '${mod['condition']}: ${mod['instruction']}',
                                    style: GoogleFonts.poppins(
                                      fontSize: 10,
                                      color: Colors.orange.shade300,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ).toList()),
                      ],
                    ],
                  ),
                ),

                // Arrow Icon
                Icon(
                  FontAwesomeIcons.chevronRight,
                  color: Colors.white.withOpacity(0.5),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressSummaryCard() {
    final stats = _progressData['stats'] as Map<String, dynamic>? ?? {};
    final totalSessions = stats['total_sessions'] ?? 0;
    final totalReps = stats['total_reps'] ?? 0;
    final avgAccuracy = stats['average_posture_accuracy']?.toDouble() ?? 0.0;
    final currentStreak = _progressData['current_streak'] ?? 0;
    
    if (totalSessions == 0) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.withOpacity(0.4)),
        ),
        child: Row(
          children: [
            Icon(FontAwesomeIcons.infoCircle, color: Colors.blue.shade300),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Start your first workout to track progress!',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.8),
                ),
              ),
            ),
          ],
        ),
      );
    }
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade700, Colors.teal.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(FontAwesomeIcons.chartLine, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                'Your Progress',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildProgressStat('Sessions', totalSessions.toString(), FontAwesomeIcons.dumbbell),
              _buildProgressStat('Reps', totalReps.toString(), FontAwesomeIcons.fire),
              _buildProgressStat('Accuracy', '${(avgAccuracy * 100).toInt()}%', FontAwesomeIcons.bullseye),
              _buildProgressStat('Streak', '$currentStreak days', FontAwesomeIcons.calendarCheck),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgressStat(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 16),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 10,
            color: Colors.white.withOpacity(0.7),
          ),
        ),
      ],
    );
  }

  Color _getDifficultyColor(String difficulty) {
    switch (difficulty.toLowerCase()) {
      case 'low':
        return Colors.green;
      case 'medium':
        return Colors.orange;
      case 'high':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }

  IconData _getExerciseIcon(String exerciseId) {
    // NOTE: Only these 5 exercises are supported by CNN+MediaPipe model
    switch (exerciseId) {
      case 'jumping_jacks':
        return FontAwesomeIcons.personRunning;
      case 'pull_ups':
        return FontAwesomeIcons.arrowUp;
      case 'pushups':
        return FontAwesomeIcons.hands;
      case 'russian_twists':
        return FontAwesomeIcons.rotate;
      case 'squats':
        return FontAwesomeIcons.personWalking;
      default:
        return FontAwesomeIcons.dumbbell;
    }
  }

  Color _getRiskColor(String riskLevel) {
    switch (riskLevel.toLowerCase()) {
      case 'low':
        return Colors.green;
      case 'medium':
        return Colors.orange;
      case 'high':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }

  IconData _getRiskIcon(String riskLevel) {
    switch (riskLevel.toLowerCase()) {
      case 'low':
        return FontAwesomeIcons.circleCheck;
      case 'medium':
        return FontAwesomeIcons.circleExclamation;
      case 'high':
        return FontAwesomeIcons.triangleExclamation;
      default:
        return FontAwesomeIcons.circle;
    }
  }
}