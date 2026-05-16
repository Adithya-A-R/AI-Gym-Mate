import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../models/user.dart';
import '../services/progress_service.dart';
import 'dart:convert';

class VideoAnalysisScreen extends StatefulWidget {
  const VideoAnalysisScreen({super.key});

  @override
  State<VideoAnalysisScreen> createState() => _VideoAnalysisScreenState();
}

class _VideoAnalysisScreenState extends State<VideoAnalysisScreen> {
  final ImagePicker _picker = ImagePicker();
  XFile? _selectedVideo;
  String? _selectedExercise;
  bool _isAnalyzing = false;
  Map<String, dynamic>? _analysisResult;
  User? _currentUser;
  List<Map<String, dynamic>> _sessionHistory = [];

  // NOTE: Only these 5 exercises are supported by CNN+MediaPipe model
  final List<Map<String, String>> _exercises = [
    {'id': 'jumping_jacks', 'name': 'Jumping Jacks', 'icon': '🤸'},
    {'id': 'pull_ups', 'name': 'Pull-ups', 'icon': '💪'},
    {'id': 'pushups', 'name': 'Push-ups', 'icon': '🔥'},
    {'id': 'russian_twists', 'name': 'Russian Twists', 'icon': '🔄'},
    {'id': 'squats', 'name': 'Squats', 'icon': '🏋️'},
  ];

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = await AuthService().getCurrentUser();
    final prefs = await SharedPreferences.getInstance();
    
    // Load session history
    final history = prefs.getStringList('workout_history') ?? [];
    final sessionHistory = history.map((session) => jsonDecode(session) as Map<String, dynamic>).toList();
    
    setState(() {
      _currentUser = user;
      _sessionHistory = sessionHistory;
    });
  }

  Future<void> _pickVideo() async {
    try {
      final XFile? video = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );

      if (video != null) {
        setState(() {
          _selectedVideo = video;
          _analysisResult = null;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Video selected: ${video.name}',
              style: GoogleFonts.poppins(),
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error picking video: $e',
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _analyzeVideo() async {
    if (_selectedVideo == null || _selectedExercise == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please select a video and exercise type',
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _analysisResult = null;
    });

    try {
      // Create user profile for API call using real user data
      final userProfile = {
        'medical_conditions': _currentUser?.medicalConditions ?? [],
        'goal': _currentUser?.goal ?? 'maintenance',
        'fitness_level': 'beginner', // This should come from user profile
        'weight': _currentUser?.weight ?? 70,
        'height': _currentUser?.height ?? 170,
        'age': _currentUser?.age ?? 30,
      };

      final result = await ApiService.analyzeVideoWithRecommendations(
        videoFile: _selectedVideo!,
        exerciseType: _selectedExercise!,
        userProfile: userProfile,
        sessionHistory: _sessionHistory,
      );

      if (mounted) {
        setState(() {
          _analysisResult = result;
          _isAnalyzing = false;
        });

        // Save analysis to database
        await _saveVideoAnalysis(result);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Video analysis complete and saved!',
              style: GoogleFonts.poppins(),
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Analysis failed: $e',
              style: GoogleFonts.poppins(),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _saveVideoAnalysis(Map<String, dynamic> result) async {
    try {
      await ProgressService.saveVideoAnalysis(
        exerciseType: _selectedExercise!,
        exerciseName: _exercises.firstWhere((e) => e['id'] == _selectedExercise)['name']!,
        videoName: _selectedVideo?.name,
        reps: result['reps'] ?? 0,
        postureAccuracy: (result['posture_accuracy'] ?? 0.0).toDouble(),
        comprehensiveScore: (result['comprehensive_score'] ?? 0.0).toDouble(),
        feedback: result['feedback'] ?? [],
        recommendations: result['recommendations'] ?? [],
        userId: _currentUser?.id,
      );
      print('Video analysis saved successfully');
    } catch (e) {
      print('Error saving video analysis: $e');
      throw Exception('Failed to save analysis: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Text(
              'Video Analysis',
              style: GoogleFonts.poppins(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Upload a video of your exercise for AI-powered form analysis',
              style: GoogleFonts.poppins(
                fontSize: 16,
                color: Colors.white.withOpacity(0.8),
              ),
            ),
            
            const SizedBox(height: 32),
            
            // Content
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // Video Selection
                    _buildVideoSelection(),
                    const SizedBox(height: 24),
                    
                    // Exercise Selection
                    _buildExerciseSelection(),
                    const SizedBox(height: 24),
                    
                    // Analyze Button
                    if (_selectedVideo != null && _selectedExercise != null) ...[
                      _buildAnalyzeButton(),
                      const SizedBox(height: 24),
                    ],
                    
                    // Analysis Results
                    if (_analysisResult != null) ...[
                      _buildAnalysisResults(),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoSelection() {
    return Container(
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                FontAwesomeIcons.video,
                color: Colors.blue.shade600,
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                'Select Video',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_selectedVideo != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    FontAwesomeIcons.checkCircle,
                    color: Colors.green.shade600,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedVideo!.name,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.green.shade700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Ready for analysis',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.green.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _selectedVideo = null;
                        _analysisResult = null;
                      });
                    },
                    icon: Icon(
                      FontAwesomeIcons.timesCircle,
                      color: Colors.red.shade400,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            ElevatedButton.icon(
              onPressed: _pickVideo,
              icon: const Icon(FontAwesomeIcons.upload),
              label: Text(
                'Choose Video',
                style: GoogleFonts.poppins(),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade600,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Supported formats: MP4, AVI, MOV, MKV\nMax duration: 5 minutes',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExerciseSelection() {
    return Container(
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                FontAwesomeIcons.dumbbell,
                color: Colors.orange.shade600,
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                'Select Exercise',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _exercises.map((exercise) {
              final isSelected = _selectedExercise == exercise['id'];
              return FilterChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      exercise['icon']!,
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      exercise['name']!,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    _selectedExercise = selected ? exercise['id'] : null;
                  });
                },
                backgroundColor: Colors.grey.shade100,
                selectedColor: Colors.orange.shade100,
                checkmarkColor: Colors.orange.shade700,
                labelStyle: GoogleFonts.poppins(
                  color: isSelected ? Colors.orange.shade700 : Colors.black87,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyzeButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: (_selectedVideo != null && _selectedExercise != null) 
            ? _analyzeVideo 
            : null,
        icon: _isAnalyzing 
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Icon(FontAwesomeIcons.play),
        label: Text(
          _isAnalyzing ? 'Analyzing...' : 'Analyze Video',
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Container(
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
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Analyzing Video...',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Processing frames and detecting poses',
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalysisResults() {
    final result = _analysisResult!;
    
    return Container(
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                FontAwesomeIcons.chartLine,
                color: Colors.green.shade600,
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                'Analysis Results',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Stats Grid
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Form Accuracy',
                  '${((result['performance_metrics']?['posture_accuracy'] ?? 0.7) * 100).toStringAsFixed(1)}%',
                  Colors.green,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Reps Counted',
                  '${result['rep_count'] ?? 0}',
                  Colors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Calories Burned',
                  '${result['calories_burned']?.toStringAsFixed(1) ?? '0.0'}',
                  Colors.orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Performance Score',
                  '${((result['recommendations']?['performance_score'] ?? 0.7) * 100).toStringAsFixed(1)}%',
                  Colors.purple,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Smart Recommendations Section
          if (result['recommendations'] != null && 
              result['recommendations']['recommendations'] != null &&
              result['recommendations']['recommendations'].isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        FontAwesomeIcons.lightbulb,
                        color: Colors.blue.shade700,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'AI Smart Recommendations',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Nutrition Analysis Summary
                  if (result['recommendations']['nutrition_analysis'] != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Nutrition Analysis',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.green.shade700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Daily Needs: ${(result['recommendations']['nutrition_analysis']['daily_needs'] ?? 0).toStringAsFixed(0)} cal',
                            style: GoogleFonts.poppins(fontSize: 12),
                          ),
                          Text(
                            'Calories Burned: ${(result['recommendations']['nutrition_analysis']['calories_burned'] ?? 0).toStringAsFixed(1)} cal',
                            style: GoogleFonts.poppins(fontSize: 12),
                          ),
                          Text(
                            'Progress: ${(result['recommendations']['nutrition_analysis']['progress_percentage'] ?? 0).toStringAsFixed(1)}%',
                            style: GoogleFonts.poppins(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  // AI Recommendations with Model Confidence
                  ...(result['recommendations']['recommendations'] as List).map((rec) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _getRecommendationColor(rec['type'] ?? 'general').withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _getRecommendationColor(rec['type'] ?? 'general').withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _getRecommendationIcon(rec['type'] ?? 'general'),
                                color: _getRecommendationColor(rec['type'] ?? 'general'),
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  rec['message'] ?? 'No recommendation available',
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    color: Colors.black87,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          // Show model confidence if available
                          if (rec['confidence'] != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'AI Model Confidence: ${(rec['confidence'] * 100).toStringAsFixed(1)}%',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                          // Show calorie context if available
                          if (rec['calorie_context'] != null) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Calorie Balance: ${(rec['calorie_context']['calorie_balance'] ?? 0).toStringAsFixed(0)} cal',
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  color: Colors.orange.shade700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )).toList(),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          
          // Session Summary
          if (result['session_summary'] != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Session Summary',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Next Session Difficulty: ${_getDifficultyText(result['session_summary']['next_difficulty'] ?? 'maintain')}',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: color.withOpacity(0.8),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  IconData _getRecommendationIcon(String type) {
    switch (type) {
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

  Color _getRecommendationColor(String type) {
    switch (type) {
      case 'challenge':
        return Colors.orange;
      case 'encouragement':
        return Colors.green;
      case 'correction':
        return Colors.red;
      case 'progression':
        return Colors.blue;
      case 'recovery':
        return Colors.purple;
      case 'cardio_boost':
        return Colors.teal;
      case 'strength_focus':
        return Colors.indigo;
      default:
        return Colors.grey;
    }
  }

  String _getDifficultyText(String difficulty) {
    switch (difficulty) {
      case 'significant_increase':
        return 'Significant Increase 🔥';
      case 'slight_increase':
        return 'Slight Increase ⬆️';
      case 'decrease':
        return 'Decrease ⬇️';
      case 'maintain':
      default:
        return 'Maintain ➡️';
    }
  }
}
