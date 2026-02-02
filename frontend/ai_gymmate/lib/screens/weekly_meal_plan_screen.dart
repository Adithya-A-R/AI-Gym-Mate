import 'package:flutter/material.dart';
import '../services/recipe_storage_service.dart';

class WeeklyMealPlanScreen extends StatelessWidget {
  const WeeklyMealPlanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Weekly Meal Plan"),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: RecipeStorageService.getSavedRecipes(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final recipes = snapshot.data!;

          if (recipes.isEmpty) {
            return const Center(
              child: Text(
                "No saved recipes yet 🍽️",
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: recipes.length,
            itemBuilder: (context, index) {
              final recipe = recipes[index];
              final date = DateTime.parse(recipe["date"]);

              return Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: const Icon(Icons.restaurant),
                  title: Text(recipe["title"]),
                  subtitle: Text(
                    "${recipe["description"]}\n"
                    "Saved on: ${date.day}/${date.month}/${date.year}",
                  ),
                  isThreeLine: true,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
