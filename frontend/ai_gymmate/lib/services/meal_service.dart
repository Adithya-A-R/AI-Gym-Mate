import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart'; // To reuse baseUrl if possible, or just duplicate for now to be safe

class MealService {
  // We can reuse the baseUrl from AuthService if it's public, or define it here.
  // AuthService.baseUrl is static const, so we can access it.
  static const String baseUrl = AuthService.baseUrl;

  // Add a meal
  static Future<Map<String, dynamic>> addMeal(String email, String meal) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/add_meal"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "email": email,
          "meal": meal,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {
          "status": "error",
          "message": "Failed to add meal: ${response.statusCode}"
        };
      }
    } catch (e) {
      return {"status": "error", "message": "Connection error: $e"};
    }
  }

  // Get nutrition summary
  static Future<Map<String, dynamic>> getNutritionSummary(String email) async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/nutrition_summary?email=$email"),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {};
      }
    } catch (e) {
      return {};
    }
  }
}
