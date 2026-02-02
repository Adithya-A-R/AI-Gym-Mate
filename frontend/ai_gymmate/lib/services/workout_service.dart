import 'dart:convert';
import 'package:http/http.dart' as http;

class WorkoutService {
  // Emulator
  //static const String baseUrl = "http://10.0.2.2:5000";

  // 🔁 If REAL PHONE, use:
   static const String baseUrl = "http://192.168.56.1:5000";

  static Future<void> saveWorkout({
    required String email,
    required String exercise,
    required int reps,
    required double calories,
  }) async {
    await http.post(
      Uri.parse("$baseUrl/save_workout"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "email": email,
        "exercise": exercise,
        "reps": reps,
        "calories": calories,
      }),
    );
  }
}
