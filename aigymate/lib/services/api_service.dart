import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class ApiService {
  // NOTE: Backend endpoints already include /api/ prefix
  static const String baseUrl = 'http://192.168.29.186:5000';
  
  // Health check
  static Future<Map<String, dynamic>> checkHealth() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/health'),
        headers: {'Content-Type': 'application/json'},
      );
      
      print('Health check status: ${response.statusCode}');
      print('Health check response: ${response.body}');
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        // Check if response is HTML (error page)
        if (response.body.startsWith('<!DOCTYPE') || response.body.startsWith('<html')) {
          throw Exception('Server returned HTML instead of JSON. Backend may be down or wrong URL.');
        }
        
        throw Exception('Health check failed: ${response.statusCode}');
      }
    } catch (e) {
      print('Health check error: $e');
      throw Exception('Connection error: $e');
    }
  }
  
  // Analyze pose from image
  static Future<Map<String, dynamic>> analyzePose({
    required String base64Image,
    String? exerciseType,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/pose/analyze'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'image': base64Image,
          if (exerciseType != null) 'exercise_type': exerciseType,
        }),
      );
      
      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}');
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        // Check if response is HTML (error page)
        if (response.body.startsWith('<!DOCTYPE') || response.body.startsWith('<html')) {
          throw Exception('Server returned HTML instead of JSON. Backend may be down or wrong URL.');
        }
        
        try {
          final error = jsonDecode(response.body);
          throw Exception(error['error'] ?? 'Pose analysis failed');
        } catch (e) {
          if (e.toString().contains('JSON')) {
            throw Exception('Server error: ${response.statusCode} - ${response.body.substring(0, 100)}');
          }
          rethrow;
        }
      }
    } catch (e) {
      print('Pose analysis error: $e');
      throw Exception('Pose analysis error: $e');
    }
  }
  
  // Get available exercises with medical filtering (POST method)
  static Future<Map<String, dynamic>> getExercises({
    List<String>? medicalConditions,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/exercises'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'medical_conditions': medicalConditions ?? [],
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to get exercises');
      }
    } catch (e) {
      throw Exception('Failed to get exercises: $e');
    }
  }
  
  // Start exercise session
  static Future<Map<String, dynamic>> startExercise({
    required String exerciseType,
    List<String>? medicalConditions,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/exercise/start'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'exercise_type': exerciseType,
          if (medicalConditions != null) 'medical_conditions': medicalConditions,
        }),
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to start exercise');
      }
    } catch (e) {
      throw Exception('Start exercise error: $e');
    }
  }
  
  // Analyze nutrition and calculate calories
  static Future<Map<String, dynamic>> analyzeNutrition({
    required List<Map<String, String>> meals,
    required Map<String, dynamic> userProfile,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/nutrition/analyze'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'meals': meals,
          'user_profile': userProfile,
        }),
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Nutrition analysis failed');
      }
    } catch (e) {
      throw Exception('Nutrition analysis error: $e');
    }
  }

  // Analyze video file for pose detection
  static Future<Map<String, dynamic>> analyzeVideo({
    required XFile videoFile,
    String? exerciseType,
  }) async {
    try {
      // Create multipart request
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/video/analyze'),
      );
      
      // Add video file
      final videoBytes = await videoFile.readAsBytes();
      final multipartFile = http.MultipartFile.fromBytes(
        'video',
        videoBytes,
        filename: videoFile.name,
      );
      request.files.add(multipartFile);
      
      // Add exercise type if provided
      if (exerciseType != null) {
        request.fields['exercise_type'] = exerciseType;
      }
      
      // Send request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Video analysis failed');
      }
    } catch (e) {
      throw Exception('Video analysis error: $e');
    }
  }
  
  // Convert image to base64
  static String imageToBase64(Uint8List imageBytes) {
    return base64Encode(imageBytes);
  }

  // Process medical report with OCR
  static Future<Map<String, dynamic>> processMedicalReport({
    required XFile reportImage,
  }) async {
    try {
      // Create multipart request
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/ocr/medical-report'),
      );
      
      // Add image file
      final imageBytes = await reportImage.readAsBytes();
      final multipartFile = http.MultipartFile.fromBytes(
        'image',
        imageBytes,
        filename: reportImage.name,
      );
      request.files.add(multipartFile);
      
      // Send request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      print('OCR Response status: ${response.statusCode}');
      print('OCR Response body: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}');
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        // Check if response is HTML (error page)
        if (response.body.startsWith('<!DOCTYPE') || response.body.startsWith('<html')) {
          throw Exception('Server returned HTML instead of JSON. Backend may be down or wrong URL.');
        }
        
        try {
          final error = jsonDecode(response.body);
          throw Exception(error['error'] ?? 'OCR processing failed');
        } catch (e) {
          if (e.toString().contains('JSON')) {
            throw Exception('Server error: ${response.statusCode} - ${response.body.substring(0, 100)}');
          }
          rethrow;
        }
      }
    } catch (e) {
      print('OCR processing error: $e');
      throw Exception('OCR processing error: $e');
    }
  }

  // Get smart workout recommendations
  static Future<Map<String, dynamic>> getWorkoutRecommendations({
    required Map<String, dynamic> userProfile,
    List<Map<String, dynamic>>? sessionHistory,
    Map<String, dynamic>? currentSession,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/workout/recommendations'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_profile': userProfile,
          'session_history': sessionHistory ?? [],
          if (currentSession != null) 'current_session': currentSession,
        }),
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to get recommendations');
      }
    } catch (e) {
      throw Exception('Workout recommendations error: $e');
    }
  }

  // Calculate calories burned for workout
  static Future<Map<String, dynamic>> calculateWorkoutCalories({
    required String exerciseType,
    required double durationMinutes,
    required double userWeight,
    int? reps,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/workout/calories-burned'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'exercise_type': exerciseType,
          'duration_minutes': durationMinutes,
          'user_weight': userWeight,
          if (reps != null) 'reps': reps,
        }),
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to calculate calories');
      }
    } catch (e) {
      throw Exception('Calories calculation error: $e');
    }
  }

  // Analyze video with smart recommendations
  static Future<Map<String, dynamic>> analyzeVideoWithRecommendations({
    required XFile videoFile,
    required String exerciseType,
    required Map<String, dynamic> userProfile,
    List<Map<String, dynamic>>? sessionHistory,
  }) async {
    try {
      // Create multipart request
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/video/analyze'),
      );
      
      // Add video file
      final videoBytes = await videoFile.readAsBytes();
      final multipartFile = http.MultipartFile.fromBytes(
        'video',
        videoBytes,
        filename: videoFile.name,
      );
      request.files.add(multipartFile);
      
      // Add form fields
      request.fields['exercise_type'] = exerciseType;
      request.fields['user_profile'] = jsonEncode(userProfile);
      request.fields['session_history'] = jsonEncode(sessionHistory ?? []);
      
      // Send request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Video analysis failed');
      }
    } catch (e) {
      throw Exception('Video analysis error: $e');
    }
  }

  // User Profile Methods
  static Future<Map<String, dynamic>> getUserProfile({
    required Map<String, dynamic> userProfile,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/user/profile'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_profile': userProfile,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to get user profile');
      }
    } catch (e) {
      throw Exception('Failed to get user profile: $e');
    }
  }

  static Future<Map<String, dynamic>> updateUserProfile({
    required Map<String, dynamic> userProfile,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/user/update-profile'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_profile': userProfile,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to update user profile');
      }
    } catch (e) {
      throw Exception('Failed to update user profile: $e');
    }
  }

  // Nutrition Tracking Methods
  static Future<Map<String, dynamic>> logNutritionIntake({
    required String userId,
    required String date,
    required List<Map<String, dynamic>> meals,
    required int totalCalories,
    required Map<String, dynamic> userProfile,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/nutrition/log-intake'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'date': date,
          'meals': meals,
          'total_calories': totalCalories,
          'user_profile': userProfile,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to log nutrition intake');
      }
    } catch (e) {
      throw Exception('Failed to log nutrition intake: $e');
    }
  }

  static Future<Map<String, dynamic>> getNutritionIntake({
    required String userId,
    String? date,
    required Map<String, dynamic> userProfile,
    List<Map<String, dynamic>>? storedMeals,
    int? storedTotalCalories,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/nutrition/get-intake'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'date': date,
          'user_profile': userProfile,
          'stored_meals': storedMeals ?? [],
          'stored_total_calories': storedTotalCalories ?? 0,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to get nutrition intake');
      }
    } catch (e) {
      throw Exception('Failed to get nutrition intake: $e');
    }
  }

  // Diet Plan Methods
  static Future<Map<String, dynamic>> generateDietPlan({
    required Map<String, dynamic> userProfile,
    List<String>? medicalConditions,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/diet/generate-plan'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_profile': userProfile,
          'medical_conditions': medicalConditions ?? [],
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to generate diet plan');
      }
    } catch (e) {
      throw Exception('Failed to generate diet plan: $e');
    }
  }

  // Recipe Methods
  static Future<Map<String, dynamic>> getRecipeRecommendations({
    required Map<String, dynamic> userProfile,
    List<String>? medicalConditions,
    Map<String, dynamic>? dietPlan,
    String mealType = 'all',
    int targetCalories = 400,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/recipes/get-recommendations'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_profile': userProfile,
          'medical_conditions': medicalConditions ?? [],
          'diet_plan': dietPlan ?? {},
          'meal_type': mealType,
          'target_calories': targetCalories,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to get recipe recommendations');
      }
    } catch (e) {
      throw Exception('Failed to get recipe recommendations: $e');
    }
  }

  // Analytics Methods
  static Future<Map<String, dynamic>> getProgressAnalytics({
    required String userId,
    required Map<String, dynamic> userProfile,
    List<Map<String, dynamic>>? sessionHistory,
    List<Map<String, dynamic>>? nutritionHistory,
    String timeRange = '30_days',
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/analytics/progress'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'user_profile': userProfile,
          'session_history': sessionHistory ?? [],
          'nutrition_history': nutritionHistory ?? [],
          'time_range': timeRange,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to get progress analytics');
      }
    } catch (e) {
      throw Exception('Failed to get progress analytics: $e');
    }
  }

  // Medical Risk Assessment Methods
  static Future<Map<String, dynamic>> getExerciseRiskAssessment({
    required String userId,
    List<String>? medicalConditions,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/exercises/risk-assessment'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'medical_conditions': medicalConditions ?? [],
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to get risk assessment');
      }
    } catch (e) {
      throw Exception('Failed to get risk assessment: $e');
    }
  }

  // Advanced ML-based Recommendation Engine
  static Future<Map<String, dynamic>> getAdvancedRecommendations({
    required String userId,
    required Map<String, dynamic> userProfile,
    List<Map<String, dynamic>>? sessionHistory,
    List<Map<String, dynamic>>? nutritionHistory,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/workout/advanced-recommendations'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'user_profile': userProfile,
          'session_history': sessionHistory ?? [],
          'nutrition_history': nutritionHistory ?? [],
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to get advanced recommendations');
      }
    } catch (e) {
      throw Exception('Failed to get advanced recommendations: $e');
    }
  }
}
