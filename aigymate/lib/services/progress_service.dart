import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ProgressService {
  static const String _workoutHistoryKey = 'workout_history';
  static const String _videoAnalysisKey = 'video_analysis_history';
  static const String _progressStatsKey = 'progress_stats';
  static const String _streakKey = 'workout_streak';

  // Save workout session from exercise selection screen
  static Future<void> saveWorkoutSession({
    required String exerciseType,
    required String exerciseName,
    required int reps,
    required double postureAccuracy,
    required double comprehensiveScore,
    required List<dynamic> feedback,
    required String? userId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    
    final session = {
      'id': 'workout_${DateTime.now().millisecondsSinceEpoch}',
      'type': 'workout',
      'exercise_type': exerciseType,
      'exercise_name': exerciseName,
      'timestamp': DateTime.now().toIso8601String(),
      'date': DateTime.now().toIso8601String(),
      'reps': reps,
      'posture_accuracy': postureAccuracy,
      'comprehensive_score': comprehensiveScore,
      'feedback': feedback,
      'user_id': userId ?? 'unknown',
      'duration_minutes': 0, // Will be updated when workout completes
    };

    // Save to workout history
    final history = prefs.getStringList(_workoutHistoryKey) ?? [];
    history.add(jsonEncode(session));
    await prefs.setStringList(_workoutHistoryKey, history);

    // Update streak
    await _updateStreak(prefs);
    
    // Update progress stats
    await _updateProgressStats(prefs, session);
    
    print('Workout session saved: ${session['id']}');
  }

  // Save video analysis session
  static Future<void> saveVideoAnalysis({
    required String exerciseType,
    required String exerciseName,
    required String? videoName,
    required int reps,
    required double postureAccuracy,
    required double comprehensiveScore,
    required List<dynamic> feedback,
    required List<dynamic> recommendations,
    required String? userId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    
    final analysis = {
      'id': 'video_${DateTime.now().millisecondsSinceEpoch}',
      'type': 'video_analysis',
      'exercise_type': exerciseType,
      'exercise_name': exerciseName,
      'video_name': videoName,
      'timestamp': DateTime.now().toIso8601String(),
      'date': DateTime.now().toIso8601String(),
      'reps': reps,
      'posture_accuracy': postureAccuracy,
      'comprehensive_score': comprehensiveScore,
      'feedback': feedback,
      'recommendations': recommendations,
      'user_id': userId ?? 'unknown',
    };

    // Save to video analysis history
    final history = prefs.getStringList(_videoAnalysisKey) ?? [];
    history.add(jsonEncode(analysis));
    await prefs.setStringList(_videoAnalysisKey, history);

    // Also add to workout history for unified tracking
    final workoutHistory = prefs.getStringList(_workoutHistoryKey) ?? [];
    workoutHistory.add(jsonEncode({
      'id': analysis['id'],
      'type': 'video_analysis',
      'exercise_type': exerciseType,
      'timestamp': analysis['timestamp'],
      'date': analysis['date'],
      'reps': reps,
      'posture_accuracy': postureAccuracy,
      'comprehensive_score': comprehensiveScore,
    }));
    await prefs.setStringList(_workoutHistoryKey, workoutHistory);

    // Update streak
    await _updateStreak(prefs);
    
    // Update progress stats
    await _updateProgressStats(prefs, analysis);
    
    print('Video analysis saved: ${analysis['id']}');
  }

  // Update workout streak
  static Future<void> _updateStreak(SharedPreferences prefs) async {
    final today = DateTime.now();
    final lastWorkoutStr = prefs.getString('last_workout_date');
    
    int currentStreak = prefs.getInt('current_streak') ?? 0;
    int longestStreak = prefs.getInt('longest_streak') ?? 0;
    
    if (lastWorkoutStr != null) {
      final lastWorkout = DateTime.parse(lastWorkoutStr);
      final difference = today.difference(lastWorkout).inDays;
      
      if (difference == 0) {
        // Already worked out today, don't increment
        return;
      } else if (difference == 1) {
        // Consecutive day, increment streak
        currentStreak++;
      } else {
        // Streak broken, reset to 1
        currentStreak = 1;
      }
    } else {
      // First workout
      currentStreak = 1;
    }
    
    // Update longest streak
    if (currentStreak > longestStreak) {
      longestStreak = currentStreak;
    }
    
    // Save streak data
    await prefs.setString('last_workout_date', today.toIso8601String());
    await prefs.setInt('current_streak', currentStreak);
    await prefs.setInt('longest_streak', longestStreak);
    
    print('Streak updated: $currentStreak (Longest: $longestStreak)');
  }

  // Update progress statistics
  static Future<void> _updateProgressStats(
    SharedPreferences prefs,
    Map<String, dynamic> session
  ) async {
    final statsJson = prefs.getString(_progressStatsKey);
    Map<String, dynamic> stats = statsJson != null 
        ? jsonDecode(statsJson) 
        : _getDefaultStats();
    
    // Update total sessions
    stats['total_sessions'] = (stats['total_sessions'] ?? 0) + 1;
    
    // Update total reps
    final reps = session['reps'] ?? 0;
    stats['total_reps'] = (stats['total_reps'] ?? 0) + reps;
    
    // Update average posture accuracy
    final postureAccuracy = session['posture_accuracy']?.toDouble() ?? 0.0;
    final currentAvg = stats['average_posture_accuracy']?.toDouble() ?? 0.0;
    final totalSessions = stats['total_sessions'];
    stats['average_posture_accuracy'] = 
        ((currentAvg * (totalSessions - 1)) + postureAccuracy) / totalSessions;
    
    // Update average comprehensive score
    final compScore = session['comprehensive_score']?.toDouble() ?? 0.0;
    final currentCompAvg = stats['average_comprehensive_score']?.toDouble() ?? 0.0;
    stats['average_comprehensive_score'] = 
        ((currentCompAvg * (totalSessions - 1)) + compScore) / totalSessions;
    
    // Update exercise-specific stats
    final exerciseType = session['exercise_type'];
    if (exerciseType != null) {
      stats['exercise_stats'] ??= {};
      stats['exercise_stats'][exerciseType] ??= {
        'sessions': 0,
        'total_reps': 0,
        'average_accuracy': 0.0,
      };
      
      final exStats = stats['exercise_stats'][exerciseType];
      exStats['sessions'] = (exStats['sessions'] ?? 0) + 1;
      exStats['total_reps'] = (exStats['total_reps'] ?? 0) + reps;
      
      final exAvg = exStats['average_accuracy']?.toDouble() ?? 0.0;
      final exSessions = exStats['sessions'];
      exStats['average_accuracy'] = 
          ((exAvg * (exSessions - 1)) + postureAccuracy) / exSessions;
    }
    
    // Update weekly progress
    final weekKey = _getWeekKey(DateTime.now());
    stats['weekly_progress'] ??= {};
    stats['weekly_progress'][weekKey] ??= {
      'sessions': 0,
      'reps': 0,
      'accuracy': 0.0,
    };
    
    final weekStats = stats['weekly_progress'][weekKey];
    final weekSessions = (weekStats['sessions'] ?? 0) + 1;
    final weekReps = (weekStats['reps'] ?? 0) + reps;
    final weekAcc = weekStats['accuracy']?.toDouble() ?? 0.0;
    
    weekStats['sessions'] = weekSessions;
    weekStats['reps'] = weekReps;
    weekStats['accuracy'] = ((weekAcc * (weekSessions - 1)) + postureAccuracy) / weekSessions;
    
    // Save stats
    await prefs.setString(_progressStatsKey, jsonEncode(stats));
    print('Progress stats updated');
  }

  static Map<String, dynamic> _getDefaultStats() {
    return {
      'total_sessions': 0,
      'total_reps': 0,
      'average_posture_accuracy': 0.0,
      'average_comprehensive_score': 0.0,
      'exercise_stats': {},
      'weekly_progress': {},
    };
  }

  static String _getWeekKey(DateTime date) {
    final startOfWeek = date.subtract(Duration(days: date.weekday - 1));
    return '${startOfWeek.year}-${startOfWeek.month.toString().padLeft(2, '0')}-${startOfWeek.day.toString().padLeft(2, '0')}';
  }

  // Get all progress data
  static Future<Map<String, dynamic>> getProgressData() async {
    final prefs = await SharedPreferences.getInstance();
    
    final workoutHistory = prefs.getStringList(_workoutHistoryKey) ?? [];
    final videoAnalysis = prefs.getStringList(_videoAnalysisKey) ?? [];
    final statsJson = prefs.getString(_progressStatsKey);
    
    final stats = statsJson != null 
        ? jsonDecode(statsJson) 
        : _getDefaultStats();
    
    // Parse all sessions
    final allSessions = [
      ...workoutHistory.map((s) => jsonDecode(s)),
      ...videoAnalysis.map((s) => jsonDecode(s)),
    ];
    
    // Sort by timestamp
    allSessions.sort((a, b) => 
        DateTime.parse(b['timestamp']).compareTo(DateTime.parse(a['timestamp'])));
    
    return {
      'stats': stats,
      'sessions': allSessions,
      'workout_count': workoutHistory.length,
      'video_analysis_count': videoAnalysis.length,
      'current_streak': prefs.getInt('current_streak') ?? 0,
      'longest_streak': prefs.getInt('longest_streak') ?? 0,
    };
  }

  // Get recent sessions (last 7 days)
  static Future<List<Map<String, dynamic>>> getRecentSessions({int days = 7}) async {
    final data = await getProgressData();
    final sessions = data['sessions'] as List<dynamic>;
    
    final cutoff = DateTime.now().subtract(Duration(days: days));
    
    return sessions
        .where((s) => DateTime.parse(s['timestamp']).isAfter(cutoff))
        .cast<Map<String, dynamic>>()
        .toList();
  }

  // Get streak info
  static Future<Map<String, int>> getStreakInfo() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'current': prefs.getInt('current_streak') ?? 0,
      'longest': prefs.getInt('longest_streak') ?? 0,
    };
  }

  // Clear all progress data
  static Future<void> clearAllData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_workoutHistoryKey);
    await prefs.remove(_videoAnalysisKey);
    await prefs.remove(_progressStatsKey);
    await prefs.remove(_streakKey);
    await prefs.remove('last_workout_date');
    await prefs.remove('current_streak');
    await prefs.remove('longest_streak');
  }
}
