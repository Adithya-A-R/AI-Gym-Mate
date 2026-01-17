import 'package:flutter/material.dart';
import '../services/profile_service.dart';
import '../services/nutrition_warning_service.dart';

class NutritionResultScreen extends StatelessWidget {
  final int age;
  final double height;
  final double weight;
  final String gender;
  final String activity;

  const NutritionResultScreen({
    super.key,
    required this.age,
    required this.height,
    required this.weight,
    required this.gender,
    required this.activity,
  });

  double _calculateCalories() {
    double bmr;
    if (gender == "Male") {
      bmr = 10 * weight + 6.25 * height - 5 * age + 5;
    } else {
      bmr = 10 * weight + 6.25 * height - 5 * age - 161;
    }

    double factor = activity == "Low"
        ? 1.2
        : activity == "Moderate"
            ? 1.55
            : 1.75;

    return bmr * factor;
  }

  @override
  Widget build(BuildContext context) {
    final calories = _calculateCalories();
    final protein = weight * 1.8;
    final carbs = (calories * 0.5) / 4;
    final fats = (calories * 0.25) / 9;

    // SAVE LAST NUTRITION RESULT
    ProfileService.saveLastNutrition(
      calories: calories,
      protein: protein,
      carbs: carbs,
      fats: fats,
    );

    return FutureBuilder<Map<String, dynamic>>(
      future: ProfileService.getMedicalValues(),
      builder: (context, snapshot) {
        final medical = snapshot.data ?? {};

        final warnings = NutritionWarningService.generateWarnings(
          glucose: medical['glucose'],
          systolicBP: medical['systolicBP'],
          diastolicBP: medical['diastolicBP'],
          cholesterol: medical['cholesterol'],
        );

        return Scaffold(
          appBar: AppBar(title: const Text("Nutrition Result")),
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Your Daily Requirement",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),

                // ================= HEALTH WARNINGS =================
                if (warnings.isNotEmpty) ...[
                  Card(
                    color: Colors.orange.shade50,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Health Warnings",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...warnings.map(
                            (w) => Padding(
                              padding:
                                  const EdgeInsets.only(bottom: 4),
                              child: Text("⚠️ $w"),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            "These are general recommendations only.",
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // ================= NUTRITION RESULTS =================
                _resultTile(
                  Icons.local_fire_department,
                  "Calories",
                  "${calories.toStringAsFixed(0)} kcal/day",
                ),
                _resultTile(
                  Icons.fitness_center,
                  "Protein",
                  "${protein.toStringAsFixed(0)} g",
                ),
                _resultTile(
                  Icons.rice_bowl,
                  "Carbohydrates",
                  "${carbs.toStringAsFixed(0)} g",
                ),
                _resultTile(
                  Icons.opacity,
                  "Fats",
                  "${fats.toStringAsFixed(0)} g",
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _resultTile(IconData icon, String title, String value) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        leading: Icon(icon, color: Colors.green),
        title: Text(title),
        trailing: Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
