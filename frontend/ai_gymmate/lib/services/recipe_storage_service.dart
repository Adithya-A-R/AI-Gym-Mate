import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class RecipeStorageService {
  static const _keySavedRecipes = "saved_recipes";

  static Future<void> saveRecipe(
    String title,
    String description,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    final List<String> existing =
        prefs.getStringList(_keySavedRecipes) ?? [];

    final recipe = {
      "title": title,
      "description": description,
      "date": DateTime.now().toIso8601String(),
    };

    existing.add(jsonEncode(recipe));
    await prefs.setStringList(_keySavedRecipes, existing);
  }

  static Future<List<Map<String, dynamic>>> getSavedRecipes() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> stored =
        prefs.getStringList(_keySavedRecipes) ?? [];

    return stored
        .map((e) => jsonDecode(e) as Map<String, dynamic>)
        .toList();
  }
}
