import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../models/user.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class RecipeScreen extends StatefulWidget {
  const RecipeScreen({super.key});

  @override
  State<RecipeScreen> createState() => _RecipeScreenState();
}

class _RecipeScreenState extends State<RecipeScreen> {
  User? _currentUser;
  List<String>? _medicalConditions;
  Map<String, dynamic>? _dietPlan;
  Map<String, List<dynamic>>? _recipeRecommendations;
  bool _isLoading = true;
  String _selectedMealType = 'all';
  
  final List<String> _mealTypes = ['all', 'breakfast', 'lunch', 'dinner', 'snack'];

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final authService = AuthService();
      final currentUser = await authService.getCurrentUser();
      final prefs = await SharedPreferences.getInstance();
      final conditions = prefs.getStringList('medical_conditions');
      
      setState(() {
        _currentUser = currentUser;
        _medicalConditions = conditions;
      });

      if (currentUser != null) {
        // First get diet plan
        await _loadDietPlan();
        // Then get recipe recommendations
        await _loadRecipeRecommendations();
      }
    } catch (e) {
      print('Error loading user data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadDietPlan() async {
    try {
      final userProfile = {
        'id': _currentUser?.id,
        'age': _currentUser?.age ?? 30,
        'weight': _currentUser?.weight ?? 70,
        'height': _currentUser?.height ?? 170,
        'gender': 'male',
        'goal': _currentUser?.goal ?? 'maintenance',
        'activity_level': 'moderate',
      };

      final result = await ApiService.generateDietPlan(
        userProfile: userProfile,
        medicalConditions: _medicalConditions,
      );

      if (result['success']) {
        setState(() {
          _dietPlan = result['diet_plan'];
        });
      }
    } catch (e) {
      print('Error loading diet plan: $e');
    }
  }

  Future<void> _loadRecipeRecommendations() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final userProfile = {
        'id': _currentUser?.id,
        'age': _currentUser?.age ?? 30,
        'weight': _currentUser?.weight ?? 70,
        'height': _currentUser?.height ?? 170,
        'gender': 'male',
        'goal': _currentUser?.goal ?? 'maintenance',
      };

      final result = await ApiService.getRecipeRecommendations(
        userProfile: userProfile,
        medicalConditions: _medicalConditions,
        dietPlan: _dietPlan,
        mealType: _selectedMealType,
      );

      if (result['success']) {
        setState(() {
          _recipeRecommendations = Map<String, List<dynamic>>.from(
            result['recommendations'].map((key, value) => 
              MapEntry(key, List<dynamic>.from(value))
            ),
          );
        });
      }
    } catch (e) {
      print('Error loading recipes: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading recipes: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _logRecipeAsMeal(Map<String, dynamic> recipe, String mealType) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mealsKey = 'nutrition_meals_${_currentUser?.id}';
      final storedMealsJson = prefs.getStringList(mealsKey) ?? [];
      
      final meal = {
        'name': recipe['name'],
        'calories': recipe['calories'],
        'time': DateTime.now().toString().substring(11, 16),
        'type': mealType,
      };
      
      storedMealsJson.add(jsonEncode(meal));
      await prefs.setStringList(mealsKey, storedMealsJson);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${recipe['name']} added to your ${mealType}!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Error logging meal: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.pink.shade400,
              Colors.pink.shade600,
              Colors.purple.shade800,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Recipe Recommendations',
                            style: GoogleFonts.poppins(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'Personalized for your diet plan',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Meal Type Filter
              Container(
                height: 50,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _mealTypes.length,
                  itemBuilder: (context, index) {
                    final type = _mealTypes[index];
                    final isSelected = _selectedMealType == type;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(
                          type == 'all' ? 'All Meals' : type.capitalize(),
                          style: GoogleFonts.poppins(
                            color: isSelected ? Colors.pink.shade700 : Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        selected: isSelected,
                        selectedColor: Colors.white,
                        backgroundColor: Colors.white.withOpacity(0.2),
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _selectedMealType = type;
                            });
                            _loadRecipeRecommendations();
                          }
                        },
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 16),

              // Content
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Colors.white))
                    : _recipeRecommendations == null || _recipeRecommendations!.isEmpty
                        ? _buildNoRecipesView()
                        : _buildRecipesList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoRecipesView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FontAwesomeIcons.utensils,
            size: 80,
            color: Colors.white.withOpacity(0.5),
          ),
          const SizedBox(height: 24),
          Text(
            'No recipes available',
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Complete your profile to get personalized recipes',
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.white.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecipesList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _recipeRecommendations!.length,
      itemBuilder: (context, index) {
        final mealType = _recipeRecommendations!.keys.elementAt(index);
        final recipes = _recipeRecommendations![mealType]!;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Meal Type Header
            Padding(
              padding: const EdgeInsets.only(bottom: 12, top: 8),
              child: Row(
                children: [
                  Icon(
                    _getMealIcon(mealType),
                    color: Colors.white,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    mealType.capitalize(),
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  if (_dietPlan != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_dietPlan!['meal_distribution']?[mealType]?['calories'] ?? 'N/A'} kcal target',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            
            // Recipe Cards
            ...recipes.map((recipe) => _buildRecipeCard(recipe, mealType)).toList(),
            
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  Widget _buildRecipeCard(Map<String, dynamic> recipe, String mealType) {
    final matchScore = recipe['match_score'] ?? 0;
    final calorieDiff = recipe['calorie_difference'] ?? 0;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        childrenPadding: const EdgeInsets.all(16),
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.pink.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            FontAwesomeIcons.utensils,
            color: Colors.pink.shade700,
          ),
        ),
        title: Text(
          recipe['name'],
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.local_fire_department, size: 16, color: Colors.orange.shade600),
                const SizedBox(width: 4),
                Text(
                  '${recipe['calories']} kcal',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.orange.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 12),
                Icon(Icons.timer, size: 16, color: Colors.blue.shade600),
                const SizedBox(width: 4),
                Text(
                  recipe['prep_time'],
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.blue.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Match Score Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _getMatchColor(matchScore).withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${matchScore.toInt()}% match',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: _getMatchColor(matchScore),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        children: [
          // Macros
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMacroItem('Protein', '${recipe['protein']}g', Colors.red.shade400),
                _buildMacroItem('Carbs', '${recipe['carbs']}g', Colors.green.shade400),
                _buildMacroItem('Fats', '${recipe['fats']}g', Colors.orange.shade400),
                _buildMacroItem('Fiber', '${recipe['fiber']}g', Colors.brown.shade400),
              ],
            ),
          ),
          const SizedBox(height: 16),
          
          // Portion
          Row(
            children: [
              Icon(FontAwesomeIcons.scaleBalanced, size: 16, color: Colors.grey.shade600),
              const SizedBox(width: 8),
              Text(
                'Portion: ${recipe['portion']}',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Ingredients
          Text(
            'Ingredients:',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: (recipe['ingredients'] as List).map((ingredient) {
              return Chip(
                label: Text(
                  ingredient,
                  style: GoogleFonts.poppins(fontSize: 12),
                ),
                backgroundColor: Colors.pink.shade50,
                padding: EdgeInsets.zero,
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          
          // Dietary Tags
          if (recipe['dietary_tags'] != null) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: (recipe['dietary_tags'] as List).map((tag) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    tag.toString().replaceAll('_', ' ').capitalize(),
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: Colors.purple.shade800,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
          
          // Calorie Match Indicator
          if (calorieDiff > 0) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: calorieDiff <= 50 ? Colors.green.shade50 : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: calorieDiff <= 50 ? Colors.green.shade200 : Colors.orange.shade200,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    calorieDiff <= 50 ? Icons.check_circle : Icons.info,
                    color: calorieDiff <= 50 ? Colors.green.shade700 : Colors.orange.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      calorieDiff <= 50 
                          ? 'Perfect calorie match for your target!'
                          : '${calorieDiff.toInt()} calories from your target',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: calorieDiff <= 50 ? Colors.green.shade700 : Colors.orange.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          
          // Add to Meal Log Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _logRecipeAsMeal(recipe, mealType),
              icon: const Icon(Icons.add),
              label: Text(
                'Add to My ${mealType.capitalize()}',
                style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.pink.shade600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMacroItem(String label, String value, Color color) {
    return Column(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Color _getMatchColor(double score) {
    if (score >= 80) return Colors.green.shade700;
    if (score >= 60) return Colors.orange.shade700;
    return Colors.red.shade700;
  }

  IconData _getMealIcon(String mealType) {
    switch (mealType) {
      case 'breakfast':
        return FontAwesomeIcons.mugHot;
      case 'lunch':
        return FontAwesomeIcons.bowlFood;
      case 'dinner':
        return FontAwesomeIcons.utensils;
      case 'snack':
        return FontAwesomeIcons.cookie;
      default:
        return FontAwesomeIcons.utensils;
    }
  }
}

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}
