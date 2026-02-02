class RecipeSuggestionService {
  static List<Map<String, String>> getRecipes({
    required double calories,
    double? glucose,
    double? cholesterol,
    double? systolicBP,
    List<String> conditions = const [],
  }) {
    final List<Map<String, String>> recipes = [];

    // ---------- DIABETES ----------
    if ((glucose != null && glucose > 140) ||
        conditions.any((c) => c.toLowerCase().contains("diabetes"))) {
      recipes.addAll([
        {
          "title": "Vegetable Oats",
          "description": "Low GI, high fiber breakfast option",
        },
        {
          "title": "Grilled Paneer Salad",
          "description": "High protein, low sugar meal",
        },
      ]);
    }

    // ---------- HIGH CHOLESTEROL ----------
    if ((cholesterol != null && cholesterol > 200) ||
        conditions.any((c) => c.toLowerCase().contains("cholesterol"))) {
      recipes.addAll([
        {
          "title": "Steamed Vegetables & Brown Rice",
          "description": "Low fat, heart-friendly meal",
        },
        {
          "title": "Fruit & Nut Smoothie",
          "description": "Good fats with antioxidants",
        },
      ]);
    }

    // ---------- HIGH BLOOD PRESSURE ----------
    if ((systolicBP != null && systolicBP > 140) ||
        conditions.any((c) => c.toLowerCase().contains("hypertension"))) {
      recipes.addAll([
        {
          "title": "Low-Sodium Vegetable Soup",
          "description": "Helps control blood pressure",
        },
        {
          "title": "Banana & Yogurt Bowl",
          "description": "Potassium-rich meal",
        },
      ]);
    }

    // ---------- GENERAL / FITNESS ----------
    if (recipes.isEmpty) {
      recipes.addAll([
        {
          "title": "Grilled Chicken with Quinoa",
          "description": "Balanced high-protein meal",
        },
        {
          "title": "Vegetable Stir Fry",
          "description": "Nutrient-dense and light",
        },
      ]);
    }

    // ---------- CALORIE ADJUSTMENT ----------
    if (calories < 1800) {
      recipes.add({
        "title": "Peanut Butter Banana Toast",
        "description": "Calorie-dense healthy snack",
      });
    }

    if (calories > 3000) {
      recipes.add({
        "title": "Large Veggie Bowl",
        "description": "Filling but calorie-controlled",
      });
    }

    return recipes;
  }
}
