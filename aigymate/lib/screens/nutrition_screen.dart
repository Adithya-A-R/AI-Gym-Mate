import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../models/user.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class NutritionScreen extends StatefulWidget {
  const NutritionScreen({super.key});

  @override
  State<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends State<NutritionScreen> {
  User? _currentUser;
  Map<String, dynamic>? _nutritionData;
  Map<String, dynamic>? _userProfile;
  List<String>? _medicalConditions;
  bool _isLoading = true;
  bool _isLoggingMeal = false;
  
  // Controllers for meal input
  final _mealNameController = TextEditingController();
  final _mealCaloriesController = TextEditingController();
  String _selectedMealType = 'breakfast';
  
  final List<String> _mealTypes = ['breakfast', 'lunch', 'dinner', 'snack'];

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _mealNameController.dispose();
    _mealCaloriesController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    try {
      final authService = AuthService();
      final currentUser = await authService.getCurrentUser();
      final prefs = await SharedPreferences.getInstance();
      final conditions = prefs.getStringList('medical_conditions');
      
      if (currentUser != null) {
        setState(() {
          _currentUser = currentUser;
          _medicalConditions = conditions;
        });
        
        // Load nutrition data and user profile
        await _loadNutritionData();
        await _loadUserProfile();
      }
    } catch (e) {
      print('Error loading user data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadNutritionData() async {
    try {
      // Create user profile for calculating daily needs
      final userProfile = {
        'id': _currentUser?.id,
        'age': _currentUser?.age,
        'weight': _currentUser?.weight,
        'height': _currentUser?.height,
        'goal': _currentUser?.goal,
        'gender': 'male',
      };

      // Get stored meals from local storage or state
      final prefs = await SharedPreferences.getInstance();
      final storedMealsJson = prefs.getStringList('nutrition_meals_${_currentUser?.id}') ?? [];
      final storedMeals = storedMealsJson.map((json) => jsonDecode(json) as Map<String, dynamic>).toList();
      
      int storedTotal = storedMeals.fold(0, (sum, meal) => sum + (meal['calories'] as int));

      final result = await ApiService.getNutritionIntake(
        userId: _currentUser?.id ?? '',
        date: DateTime.now().toString().split(' ')[0],
        userProfile: userProfile,
        storedMeals: storedMeals,
        storedTotalCalories: storedTotal,
      );
      
      if (result['success']) {
        setState(() {
          _nutritionData = result['nutrition_data'];
        });
      }
    } catch (e) {
      print('Error loading nutrition data: $e');
    }
  }

  Future<void> _loadUserProfile() async {
    try {
      // Create user profile from current user data
      final userProfile = {
        'id': _currentUser?.id,
        'fullName': _currentUser?.fullName,
        'email': _currentUser?.email,
        'age': _currentUser?.age,
        'height': _currentUser?.height,
        'weight': _currentUser?.weight,
        'goal': _currentUser?.goal,
        'medicalConditions': _medicalConditions,
      };

      final result = await ApiService.getUserProfile(userProfile: userProfile);
      
      if (result['success']) {
        setState(() {
          _userProfile = result['user_profile'];
        });
      }
    } catch (e) {
      print('Error loading user profile: $e');
    }
  }

  Future<void> _logMeal() async {
    if (_mealNameController.text.trim().isEmpty || 
        _mealCaloriesController.text.trim().isEmpty) {
      return;
    }

    setState(() {
      _isLoggingMeal = true;
    });

    try {
      final calories = int.tryParse(_mealCaloriesController.text.trim());
      if (calories == null) {
        throw Exception('Invalid calories value');
      }

      // Get current meals or create empty list
      List<Map<String, dynamic>> currentMeals = [];
      if (_nutritionData != null && _nutritionData!['meals'] != null) {
        currentMeals = List<Map<String, dynamic>>.from(_nutritionData!['meals']);
      }

      // Add new meal
      currentMeals.add({
        'name': _mealNameController.text.trim(),
        'calories': calories,
        'time': DateTime.now().toString().substring(11, 16), // HH:MM format
        'type': _selectedMealType,
      });

      // Calculate new total
      int totalCalories = currentMeals.fold(0, (sum, meal) => sum + (meal['calories'] as int));

      // Log to backend with user profile
      final userProfile = {
        'id': _currentUser?.id,
        'age': _currentUser?.age,
        'weight': _currentUser?.weight,
        'height': _currentUser?.height,
        'goal': _currentUser?.goal,
        'gender': 'male', // Add gender to User model if needed
      };

      await ApiService.logNutritionIntake(
        userId: _currentUser?.id ?? '',
        date: DateTime.now().toString().split(' ')[0],
        meals: currentMeals,
        totalCalories: totalCalories,
        userProfile: userProfile,
      );

      // Clear controllers
      _mealNameController.clear();
      _mealCaloriesController.clear();

      // Reload data
      await _loadNutritionData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Meal logged successfully!',
              style: GoogleFonts.poppins(),
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error logging meal: $e',
              style: GoogleFonts.poppins(),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoggingMeal = false;
      });
    }
  }

  double _getCalorieProgress() {
    if (_nutritionData == null) return 0.0;
    final total = _nutritionData!['total_calories'] ?? 0;
    final needs = _nutritionData!['daily_needs'] ?? 2000;
    return (total / needs).clamp(0.0, 1.0);
  }

  String _getCalorieStatus() {
    final progress = _getCalorieProgress();
    if (progress < 0.8) return 'Below Target';
    if (progress <= 1.0) return 'On Track';
    return 'Exceeded';
  }

  Color _getStatusColor() {
    final progress = _getCalorieProgress();
    if (progress < 0.8) return Colors.orange;
    if (progress <= 1.0) return Colors.green;
    return Colors.red;
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
              Colors.green.shade600,
              Colors.green.shade800,
              Colors.teal.shade900,
            ],
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.arrow_back, color: Colors.white),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            'Nutrition Tracking',
                            style: GoogleFonts.poppins(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // User Info Card
                      if (_userProfile != null) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withOpacity(0.2)),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                FontAwesomeIcons.userCircle,
                                color: Colors.white,
                                size: 40,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _userProfile!['fullName'] ?? 'User',
                                      style: GoogleFonts.poppins(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Age: ${_userProfile!['age'] ?? 'N/A'} | '
                                      'Height: ${_userProfile!['height'] ?? 'N/A'}cm | '
                                      'Weight: ${_userProfile!['weight'] ?? 'N/A'}kg',
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        color: Colors.white.withOpacity(0.8),
                                      ),
                                    ),
                                    Text(
                                      'Goal: ${(_userProfile!['goal'] ?? 'maintenance').toString().split('_').map((word) => word[0].toUpperCase() + word.substring(1)).join(' ')}',
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        color: Colors.white.withOpacity(0.8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],

                      // Calorie Progress Card
                      if (_nutritionData != null) ...[
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withOpacity(0.2)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    "Today's Calories",
                                    style: GoogleFonts.poppins(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _getStatusColor().withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: _getStatusColor()),
                                    ),
                                    child: Text(
                                      _getCalorieStatus(),
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        color: _getStatusColor(),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              
                              // Progress Bar
                              Container(
                                height: 20,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: _getCalorieProgress(),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: _getStatusColor(),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              
                              // Calories Text
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${_nutritionData!['total_calories'] ?? 0}',
                                    style: GoogleFonts.poppins(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  Text(
                                    'of ${_nutritionData!['daily_needs'] ?? 2000} cal',
                                    style: GoogleFonts.poppins(
                                      fontSize: 16,
                                      color: Colors.white.withOpacity(0.8),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],

                      // Log Meal Section
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Log Your Meal',
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 16),
                            
                            // Meal Type Selection
                            Row(
                              children: _mealTypes.map((type) => Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(right: type != _mealTypes.last ? 8 : 0),
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _selectedMealType = type;
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      decoration: BoxDecoration(
                                        color: _selectedMealType == type 
                                            ? Colors.white 
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.white),
                                      ),
                                      child: Text(
                                        type[0].toUpperCase() + type.substring(1),
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          color: _selectedMealType == type 
                                              ? Colors.green.shade800 
                                              : Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              )).toList(),
                            ),
                            const SizedBox(height: 16),
                            
                            // Meal Name Input
                            TextField(
                              controller: _mealNameController,
                              style: GoogleFonts.poppins(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: 'Meal Name',
                                labelStyle: GoogleFonts.poppins(
                                  color: Colors.white.withOpacity(0.7),
                                ),
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.1),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Colors.white.withOpacity(0.3),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Colors.white.withOpacity(0.3),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(color: Colors.white),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            
                            // Calories Input
                            TextField(
                              controller: _mealCaloriesController,
                              keyboardType: TextInputType.number,
                              style: GoogleFonts.poppins(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: 'Calories',
                                labelStyle: GoogleFonts.poppins(
                                  color: Colors.white.withOpacity(0.7),
                                ),
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.1),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Colors.white.withOpacity(0.3),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Colors.white.withOpacity(0.3),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(color: Colors.white),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            
                            // Log Button
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _isLoggingMeal ? null : _logMeal,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.green.shade800,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: _isLoggingMeal
                                    ? const CircularProgressIndicator(
                                        color: Colors.green,
                                      )
                                    : Text(
                                        'Log Meal',
                                        style: GoogleFonts.poppins(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Today's Meals
                      if (_nutritionData != null && 
                          _nutritionData!['meals'] != null && 
                          (_nutritionData!['meals'] as List).isNotEmpty) ...[
                        Text(
                          "Today's Meals",
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        ...( _nutritionData!['meals'] as List).map((meal) => Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withOpacity(0.2)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  _getMealIcon(meal['type'] ?? 'snack'),
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      meal['name'] ?? 'Unknown Meal',
                                      style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                    Text(
                                      meal['time'] ?? '',
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        color: Colors.white.withOpacity(0.7),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '${meal['calories'] ?? 0} cal',
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        )).toList(),
                      ],
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  IconData _getMealIcon(String mealType) {
    switch (mealType.toLowerCase()) {
      case 'breakfast':
        return FontAwesomeIcons.sun;
      case 'lunch':
        return FontAwesomeIcons.utensils;
      case 'dinner':
        return FontAwesomeIcons.moon;
      case 'snack':
        return FontAwesomeIcons.cookie;
      default:
        return FontAwesomeIcons.utensils;
    }
  }
}
