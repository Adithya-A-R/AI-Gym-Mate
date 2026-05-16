import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../models/user.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DietPlanScreen extends StatefulWidget {
  const DietPlanScreen({super.key});

  @override
  State<DietPlanScreen> createState() => _DietPlanScreenState();
}

class _DietPlanScreenState extends State<DietPlanScreen> {
  User? _currentUser;
  Map<String, dynamic>? _dietPlan;
  Map<String, dynamic>? _calculations;
  bool _isLoading = true;
  bool _isGenerating = false;
  List<String>? _medicalConditions;

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
      
      // Auto-generate diet plan if user has required data
      if (currentUser != null && 
          currentUser.age != null && 
          currentUser.weight != null && 
          currentUser.height != null) {
        await _generateDietPlan();
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading user data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _generateDietPlan() async {
    setState(() {
      _isGenerating = true;
    });

    try {
      final userProfile = {
        'id': _currentUser?.id,  // Add user ID
        'age': _currentUser?.age ?? 30,
        'weight': _currentUser?.weight ?? 70,
        'height': _currentUser?.height ?? 170,
        'gender': 'male', // Default, should come from user profile
        'goal': _currentUser?.goal ?? 'maintenance',
        'activity_level': 'moderate', // Default, should come from user profile
      };

      final result = await ApiService.generateDietPlan(
        userProfile: userProfile,
        medicalConditions: _medicalConditions,
      );

      if (result['success']) {
        setState(() {
          _dietPlan = result['diet_plan'];
          _calculations = result['calculations'];
        });
      }
    } catch (e) {
      print('Error generating diet plan: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error generating diet plan: $e',
              style: GoogleFonts.poppins(),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
        _isGenerating = false;
      });
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
              Colors.orange.shade600,
              Colors.orange.shade800,
              Colors.deepOrange.shade900,
            ],
          ),
        ),
        child: SafeArea(
          child: _isLoading || _isGenerating
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : _dietPlan == null
                  ? _buildNoDataView()
                  : _buildDietPlanView(),
        ),
      ),
    );
  }

  Widget _buildNoDataView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
              const SizedBox(width: 16),
              Text(
                'Diet Plan',
                style: GoogleFonts.poppins(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
          Icon(
            FontAwesomeIcons.utensils,
            size: 80,
            color: Colors.white.withOpacity(0.7),
          ),
          const SizedBox(height: 24),
          Text(
            'Complete Your Profile',
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'To generate a personalized diet plan, please update your profile with:\n\n• Age\n• Height\n• Weight\n• Fitness Goal',
            style: GoogleFonts.poppins(
              fontSize: 16,
              color: Colors.white.withOpacity(0.9),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () {
              // Navigate to profile screen
              Navigator.pushNamed(context, '/profile');
            },
            icon: const Icon(Icons.person),
            label: Text(
              'Go to Profile',
              style: GoogleFonts.poppins(fontSize: 16),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.orange.shade800,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDietPlanView() {
    final dailyTargets = _dietPlan!['daily_targets'];
    final mealDistribution = _dietPlan!['meal_distribution'];
    final medicalConstraints = _dietPlan!['medical_constraints'] ?? [];
    final recommendations = _dietPlan!['recommendations'] ?? [];

    return SingleChildScrollView(
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
              Expanded(
                child: Text(
                  'Your Personalized Diet Plan',
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              IconButton(
                onPressed: _generateDietPlan,
                icon: const Icon(Icons.refresh, color: Colors.white),
                tooltip: 'Regenerate Plan',
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Calculation Summary Card
          if (_calculations != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: Column(
                children: [
                  Text(
                    'Calorie Calculations',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildCalcItem('BMR', '${_calculations!['bmr'] ?? 'N/A'}', 'cal/day'),
                      _buildCalcItem('TDEE', '${_calculations!['tdee'] ?? 'N/A'}', 'cal/day'),
                      _buildCalcItem('Target', '${dailyTargets['calories'] ?? 'N/A'}', 'cal/day'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Daily Targets Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(FontAwesomeIcons.bullseye, color: Colors.white, size: 24),
                    const SizedBox(width: 12),
                    Text(
                      'Daily Targets',
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildMacroRow('Calories', dailyTargets['calories'], 'kcal', Colors.yellow),
                _buildMacroRow('Protein', dailyTargets['protein'], 'g', Colors.red.shade300),
                _buildMacroRow('Carbs', dailyTargets['carbs'], 'g', Colors.green.shade300),
                _buildMacroRow('Fats', dailyTargets['fats'], 'g', Colors.orange.shade300),
                _buildMacroRow('Fiber', dailyTargets['fiber'], 'g', Colors.brown.shade300),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Meal Distribution
          Text(
            'Meal Distribution',
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          
          ...(mealDistribution.entries.map((entry) {
            final mealData = entry.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
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
                        _capitalizeFirst(entry.key.replaceAll('_', ' ')),
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${mealData['calories']} kcal',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    mealData['timing'] ?? '',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    mealData['description'] ?? '',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildMiniMacro('P: ${mealData['protein']}g', Colors.red.shade300),
                      const SizedBox(width: 8),
                      _buildMiniMacro('C: ${mealData['carbs']}g', Colors.green.shade300),
                      const SizedBox(width: 8),
                      _buildMiniMacro('F: ${mealData['fats']}g', Colors.orange.shade300),
                    ],
                  ),
                ],
              ),
            );
          }).toList()),

          // Medical Constraints
          if (medicalConstraints.isNotEmpty) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withOpacity(0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(FontAwesomeIcons.exclamationTriangle, color: Colors.red.shade300),
                      const SizedBox(width: 8),
                      Text(
                        'Medical Considerations',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.red.shade100,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...medicalConstraints.map((constraint) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.close, color: Colors.red.shade300, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            constraint,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: Colors.white.withOpacity(0.9),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )).toList(),
                ],
              ),
            ),
          ],

          // Recommendations
          if (recommendations.isNotEmpty) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withOpacity(0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(FontAwesomeIcons.lightbulb, color: Colors.green.shade300),
                      const SizedBox(width: 8),
                      Text(
                        'Dietary Recommendations',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.green.shade100,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...recommendations.map((rec) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.check, color: Colors.green.shade300, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            rec,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: Colors.white.withOpacity(0.9),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )).toList(),
                ],
              ),
            ),
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildCalcItem(String label, String value, String unit) {
    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: Colors.white.withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(
          unit,
          style: GoogleFonts.poppins(
            fontSize: 10,
            color: Colors.white.withOpacity(0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildMacroRow(String label, dynamic value, String unit, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
            ],
          ),
          Text(
            '${value ?? 'N/A'} $unit',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniMacro(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
      ),
    );
  }

  String _capitalizeFirst(String text) {
    if (text.isEmpty) return text;
    return text.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');
  }
}
