class NutritionWarningService {
  static List<String> generateWarnings({
    double? glucose,
    int? systolicBP,
    int? diastolicBP,
    double? cholesterol,
  }) {
    final List<String> warnings = [];

    // High blood sugar
    if (glucose != null && glucose >= 140) {
      warnings.add(
        "High blood sugar detected. Limit sugar and refined carbohydrates.",
      );
    }

    // High blood pressure
    if (systolicBP != null && systolicBP >= 140) {
      warnings.add(
        "High blood pressure detected. Reduce sodium intake and processed foods.",
      );
    }

    // High cholesterol
    if (cholesterol != null && cholesterol >= 240) {
      warnings.add(
        "High cholesterol detected. Avoid saturated fats and fried foods.",
      );
    }

    return warnings;
  }
}
