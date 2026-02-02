class NutritionWarningService {
  static List<String> generateWarnings({
    required double calories,
    required double carbs,
    required double fats,
    required double protein,

    // Optional medical values
    double? glucose,
    double? systolicBP,
    double? diastolicBP,
    double? cholesterol,

    // Optional profile conditions
    List<String> conditions = const [],
  }) {
    final List<String> warnings = [];

    // ---------- CONDITION-BASED RULES ----------
    for (final condition in conditions) {
      final c = condition.toLowerCase();

      if (c.contains("diabetes") && carbs > 250) {
        warnings.add(
          "High carbohydrate intake may not be suitable for diabetes.",
        );
      }

      if (c.contains("hypertension")) {
        warnings.add(
          "Reduce salt intake to help control blood pressure.",
        );
      }

      if (c.contains("cholesterol") && fats > 70) {
        warnings.add(
          "High fat intake may affect cholesterol levels.",
        );
      }

      if (c.contains("kidney") && protein > 100) {
        warnings.add(
          "Excess protein intake may stress kidney function.",
        );
      }
    }

    // ---------- MEDICAL VALUE-BASED RULES ----------
    if (glucose != null && glucose > 140) {
      warnings.add(
        "Elevated blood glucose detected. Monitor sugar intake.",
      );
    }

    if (systolicBP != null &&
        diastolicBP != null &&
        (systolicBP > 140 || diastolicBP > 90)) {
      warnings.add(
        "High blood pressure detected. Limit sodium intake.",
      );
    }

    if (cholesterol != null && cholesterol > 200) {
      warnings.add(
        "High cholesterol detected. Prefer low-fat foods.",
      );
    }

    if (calories > 3500) {
      warnings.add(
        "Very high calorie intake detected. Monitor weight goals.",
      );
    }

    return warnings;
  }
}
