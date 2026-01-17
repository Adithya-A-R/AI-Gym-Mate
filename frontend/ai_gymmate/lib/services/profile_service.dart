import 'package:shared_preferences/shared_preferences.dart';

class ProfileService {
  static const _keyProfileCompleted = 'profile_completed';

  // ================================
  // SAVE PROFILE (called from Profile Setup)
  // ================================
  static Future<void> saveProfile({
    required String name,
    required int age,
    required double height,
    required double weight,
    required String gender,
    required List<String> conditions,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(_keyProfileCompleted, true);
    await prefs.setString('name', name);
    await prefs.setInt('age', age);
    await prefs.setDouble('height', height);
    await prefs.setDouble('weight', weight);
    await prefs.setString('gender', gender);
    await prefs.setStringList('conditions', conditions);
  }

  // ================================
  // CHECK IF PROFILE EXISTS (used in Login)
  // ================================
  static Future<bool> isProfileCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyProfileCompleted) ?? false;
  }

  // ================================
  // LOAD PROFILE (used in Home, Nutrition, Profile)
  // ================================
  static Future<Map<String, dynamic>> getProfile() async {
    final prefs = await SharedPreferences.getInstance();

    return {
      'name': prefs.getString('name') ?? '',
      'age': prefs.getInt('age') ?? 0,
      'height': prefs.getDouble('height') ?? 0,
      'weight': prefs.getDouble('weight') ?? 0,
      'gender': prefs.getString('gender') ?? '',
      'conditions': prefs.getStringList('conditions') ?? [],
    };
  }

  // ================================
  // SAVE LAST NUTRITION RESULT
  // ================================
  static Future<void> saveLastNutrition({
    required double calories,
    required double protein,
    required double carbs,
    required double fats,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setDouble('calories', calories);
    await prefs.setDouble('protein', protein);
    await prefs.setDouble('carbs', carbs);
    await prefs.setDouble('fats', fats);
  }

  // ================================
  // LOAD LAST NUTRITION RESULT
  // ================================
  static Future<Map<String, double>> getLastNutrition() async {
    final prefs = await SharedPreferences.getInstance();

    return {
      'calories': prefs.getDouble('calories') ?? 0,
      'protein': prefs.getDouble('protein') ?? 0,
      'carbs': prefs.getDouble('carbs') ?? 0,
      'fats': prefs.getDouble('fats') ?? 0,
    };
  }

  // ================================
  // CLEAR PROFILE (LOGOUT / RESET)
  // ================================
  static Future<void> clearProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  // ================================
// SAVE OCR REPORT
// ================================
static Future<void> saveMedicalReport(String text) async {
  final prefs = await SharedPreferences.getInstance();
  final reports = prefs.getStringList('medical_reports') ?? [];
  reports.add(text);
  await prefs.setStringList('medical_reports', reports);
}

// ================================
// LOAD OCR REPORTS
// ================================
static Future<List<String>> getMedicalReports() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getStringList('medical_reports') ?? [];
 }

 // ================================
// SAVE EXTRACTED MEDICAL VALUES
// ================================
static Future<void> saveMedicalValues({
  double? glucose,
  int? systolicBP,
  int? diastolicBP,
  double? cholesterol,
}) async {
  final prefs = await SharedPreferences.getInstance();

  if (glucose != null) {
    await prefs.setDouble('glucose', glucose);
  }
  if (systolicBP != null) {
    await prefs.setInt('systolicBP', systolicBP);
  }
  if (diastolicBP != null) {
    await prefs.setInt('diastolicBP', diastolicBP);
  }
  if (cholesterol != null) {
    await prefs.setDouble('cholesterol', cholesterol);
  }
}

// ================================
// LOAD EXTRACTED MEDICAL VALUES
// ================================
static Future<Map<String, dynamic>> getMedicalValues() async {
  final prefs = await SharedPreferences.getInstance();

  return {
    'glucose': prefs.getDouble('glucose'),
    'systolicBP': prefs.getInt('systolicBP'),
    'diastolicBP': prefs.getInt('diastolicBP'),
    'cholesterol': prefs.getDouble('cholesterol'),
  };
 }

}
