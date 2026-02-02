import 'dart:convert';
import 'package:http/http.dart' as http;

class AuthService {
  // ✅ REAL DEVICE: use laptop IP + PORT
  // Example: http://192.168.1.x:5000 (Check using `ipconfig` on Windows)
  // NOTE: If using Android Emulator, use http://10.0.2.2:5000
  static const String baseUrl = "http://10.103.241.241:5000";

  static Future<Map<String, dynamic>> signup(
      String name, String email, String password) async {
    final response = await http.post(
      Uri.parse("$baseUrl/signup"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "name": name,
        "email": email,
        "password": password,
      }),
    );

    return {
      "status": response.statusCode,
      "body": jsonDecode(response.body),
    };
  }

  static Future<Map<String, dynamic>> login(
      String email, String password) async {
    final response = await http.post(
      Uri.parse("$baseUrl/login"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "email": email,
        "password": password,
      }),
    );

    return {
      "status": response.statusCode,
      "body": jsonDecode(response.body),
    };
  }
}
