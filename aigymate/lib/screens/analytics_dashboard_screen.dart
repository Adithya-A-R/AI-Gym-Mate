import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../models/user.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class AnalyticsDashboardScreen extends StatefulWidget {
  const AnalyticsDashboardScreen({super.key});

  @override
  State<AnalyticsDashboardScreen> createState() => _AnalyticsDashboardScreenState();
}

class _AnalyticsDashboardScreenState extends State<AnalyticsDashboardScreen> {
  User? _currentUser;
  Map<String, dynamic>? _analytics;
  bool _isLoading = true;
  String _selectedTimeRange = '30_days';
  
  final List<String> _timeRanges = ['7_days', '30_days', '90_days'];

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final authService = AuthService();
      final currentUser = await authService.getCurrentUser();
      final prefs = await SharedPreferences.getInstance();
      
      // Load session history
      final workoutHistory = prefs.getStringList('workout_history') ?? [];
      final sessionHistory = workoutHistory.map((json) => jsonDecode(json) as Map<String, dynamic>).toList();
      
      // Load nutrition history
      final mealsKey = 'nutrition_meals_${currentUser?.id}';
      final nutritionJson = prefs.getStringList(mealsKey) ?? [];
      final nutritionHistory = _processNutritionHistory(nutritionJson);
      
      setState(() {
        _currentUser = currentUser;
      });

      if (currentUser != null) {
        final userProfile = {
          'id': currentUser.id,
          'age': currentUser.age ?? 30,
          'weight': currentUser.weight ?? 70,
          'height': currentUser.height ?? 170,
          'goal': currentUser.goal ?? 'maintenance',
          'gender': 'male',
        };

        final result = await ApiService.getProgressAnalytics(
          userId: currentUser.id ?? '',
          userProfile: userProfile,
          sessionHistory: sessionHistory,
          nutritionHistory: nutritionHistory,
          timeRange: _selectedTimeRange,
        );

        if (result['success']) {
          setState(() {
            _analytics = result['analytics'];
          });
        }
      }
    } catch (e) {
      print('Error loading analytics: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> _processNutritionHistory(List<String> nutritionJson) {
    // Group meals by date
    Map<String, List<Map<String, dynamic>>> mealsByDate = {};
    
    for (String json in nutritionJson) {
      final meal = jsonDecode(json) as Map<String, dynamic>;
      final date = DateTime.now().toString().split(' ')[0]; // Simplified - should use actual meal date
      mealsByDate.putIfAbsent(date, () => []).add(meal);
    }
    
    return mealsByDate.entries.map((entry) {
      final totalCalories = entry.value.fold(0, (sum, m) => sum + (m['calories'] as int));
      return {
        'date': entry.key,
        'total_calories': totalCalories,
        'meals': entry.value,
      };
    }).toList();
  }

  String _getTimeRangeLabel(String range) {
    switch (range) {
      case '7_days':
        return 'Last 7 Days';
      case '30_days':
        return 'Last 30 Days';
      case '90_days':
        return 'Last 90 Days';
      default:
        return 'Last 30 Days';
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
              Colors.indigo.shade600,
              Colors.indigo.shade800,
              Colors.deepPurple.shade900,
            ],
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : _analytics == null
                  ? _buildNoDataView()
                  : _buildAnalyticsView(),
        ),
      ),
    );
  }

  Widget _buildNoDataView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FontAwesomeIcons.chartLine,
            size: 80,
            color: Colors.white.withOpacity(0.5),
          ),
          const SizedBox(height: 24),
          Text(
            'No Analytics Available',
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start working out and tracking nutrition to see your progress!',
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.white.withOpacity(0.8),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsView() {
    final workoutStats = _analytics!['workout_stats'] ?? {};
    final nutritionStats = _analytics!['nutrition_stats'] ?? {};
    final performanceTrends = _analytics!['performance_trends'] ?? {};
    final goalProgress = _analytics!['goal_progress'] ?? {};
    final weeklyBreakdown = _analytics!['weekly_breakdown'] ?? [];
    final summary = _analytics!['summary'] ?? [];

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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Progress Analytics',
                      style: GoogleFonts.poppins(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      _getTimeRangeLabel(_selectedTimeRange),
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
          const SizedBox(height: 16),

          // Time Range Selector
          Container(
            height: 45,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _timeRanges.length,
              itemBuilder: (context, index) {
                final range = _timeRanges[index];
                final isSelected = _selectedTimeRange == range;
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: ChoiceChip(
                    label: Text(
                      _getTimeRangeLabel(range),
                      style: GoogleFonts.poppins(
                        color: isSelected ? Colors.indigo.shade700 : Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: Colors.white,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedTimeRange = range;
                        });
                        _loadAnalytics();
                      }
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),

          // Goal Progress Card
          if (goalProgress.isNotEmpty) ...[
            _buildGoalProgressCard(goalProgress),
            const SizedBox(height: 24),
          ],

          // Summary Cards
          if (summary.isNotEmpty) ...[
            _buildSummaryCards(summary),
            const SizedBox(height: 24),
          ],

          // Workout Stats Grid
          _buildSectionTitle('Workout Statistics'),
          const SizedBox(height: 16),
          _buildWorkoutStatsGrid(workoutStats),
          const SizedBox(height: 24),

          // Weekly Progress Chart
          if (weeklyBreakdown.isNotEmpty) ...[
            _buildSectionTitle('Weekly Progress'),
            const SizedBox(height: 16),
            _buildWeeklyChart(weeklyBreakdown),
            const SizedBox(height: 24),
          ],

          // Nutrition Stats
          _buildSectionTitle('Nutrition Statistics'),
          const SizedBox(height: 16),
          _buildNutritionStats(nutritionStats),
          const SizedBox(height: 24),

          // Performance Trends
          if (performanceTrends.isNotEmpty) ...[
            _buildSectionTitle('Performance Trends'),
            const SizedBox(height: 16),
            _buildPerformanceTrends(performanceTrends),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.poppins(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    );
  }

  Widget _buildGoalProgressCard(Map<String, dynamic> goalProgress) {
    final progress = goalProgress['progress_percentage'] ?? 0.0;
    final goal = goalProgress['goal'] ?? 'maintenance';
    final targetMessage = goalProgress['target_message'] ?? '';
    
    Color progressColor;
    if (progress >= 80) {
      progressColor = Colors.green;
    } else if (progress >= 50) {
      progressColor = Colors.orange;
    } else {
      progressColor = Colors.red;
    }

    return Container(
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
              Expanded(
                child: Text(
                  'Goal Progress: ${goal.toString().split('_').map((w) => w.capitalize()).join(' ')}',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress / 100,
              backgroundColor: Colors.white.withOpacity(0.2),
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              minHeight: 20,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${progress.toInt()}% Complete',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                targetMessage,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(List<dynamic> summary) {
    return Container(
      height: 120,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: summary.length,
        itemBuilder: (context, index) {
          return Container(
            width: 280,
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: Icon(
                    FontAwesomeIcons.checkCircle,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    summary[index],
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.white,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildWorkoutStatsGrid(Map<String, dynamic> stats) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 1.5,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      children: [
        _buildStatCard('Workouts', '${stats['total_workouts'] ?? 0}', FontAwesomeIcons.dumbbell, Colors.blue),
        _buildStatCard('Total Reps', '${stats['total_reps'] ?? 0}', FontAwesomeIcons.repeat, Colors.green),
        _buildStatCard('Calories Burned', '${stats['total_calories_burned'] ?? 0}', FontAwesomeIcons.fire, Colors.orange),
        _buildStatCard('Avg Duration', '${stats['avg_workout_duration'] ?? 0} min', FontAwesomeIcons.clock, Colors.purple),
        _buildStatCard('Posture Accuracy', '${stats['avg_posture_accuracy']?.toInt() ?? 0}%', FontAwesomeIcons.crosshairs, Colors.teal),
        _buildStatCard('Consistency', '${stats['consistency_score']?.toInt() ?? 0}%', FontAwesomeIcons.calendarCheck, Colors.pink),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: Colors.white.withOpacity(0.8),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyChart(List<dynamic> weeklyData) {
    return Container(
      height: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: weeklyData.map((w) => w['workouts'] as int).reduce((a, b) => a > b ? a : b).toDouble() + 1,
          barTouchData: BarTouchData(enabled: false),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  if (value.toInt() >= 0 && value.toInt() < weeklyData.length) {
                    return Text(
                      weeklyData[value.toInt()]['week'],
                      style: GoogleFonts.poppins(
                        color: Colors.white70,
                        fontSize: 10,
                      ),
                    );
                  }
                  return const Text('');
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  return Text(
                    value.toInt().toString(),
                    style: GoogleFonts.poppins(
                      color: Colors.white70,
                      fontSize: 10,
                    ),
                  );
                },
                reservedSize: 30,
              ),
            ),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barGroups: weeklyData.asMap().entries.map((entry) {
            return BarChartGroupData(
              x: entry.key,
              barRods: [
                BarChartRodData(
                  toY: (entry.value['workouts'] as int).toDouble(),
                  color: Colors.blue.shade400,
                  width: 20,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildNutritionStats(Map<String, dynamic> stats) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNutritionItem('Avg Calories', '${stats['avg_daily_calories']?.toInt() ?? 0}', Colors.orange),
              _buildNutritionItem('Protein', '${stats['avg_daily_protein']?.toInt() ?? 0}g', Colors.red),
              _buildNutritionItem('Carbs', '${stats['avg_daily_carbs']?.toInt() ?? 0}g', Colors.green),
              _buildNutritionItem('Fats', '${stats['avg_daily_fats']?.toInt() ?? 0}g', Colors.yellow),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(FontAwesomeIcons.clipboardCheck, color: Colors.white70, size: 20),
                const SizedBox(width: 12),
                Text(
                  'Goal Adherence: ${stats['calorie_goal_adherence']?.toInt() ?? 0}%',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNutritionItem(String label, String value, Color color) {
    return Column(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: color.withOpacity(0.3),
            borderRadius: BorderRadius.circular(25),
          ),
          child: Center(
            child: Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 11,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  Widget _buildPerformanceTrends(Map<String, dynamic> trends) {
    final postureTrend = trends['posture_trend'] ?? 'stable';
    final repsTrend = trends['reps_trend'] ?? 'stable';
    final postureImprovement = trends['posture_improvement'] ?? 0.0;
    final repsImprovement = trends['reps_improvement'] ?? 0.0;

    return Row(
      children: [
        Expanded(
          child: _buildTrendCard('Posture', postureTrend, postureImprovement, FontAwesomeIcons.personWalking),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildTrendCard('Reps', repsTrend, repsImprovement, FontAwesomeIcons.arrowTrendUp),
        ),
      ],
    );
  }

  Widget _buildTrendCard(String label, String trend, double improvement, IconData icon) {
    Color trendColor;
    IconData trendIcon;
    
    switch (trend) {
      case 'improving':
        trendColor = Colors.green;
        trendIcon = Icons.trending_up;
        break;
      case 'declining':
        trendColor = Colors.red;
        trendIcon = Icons.trending_down;
        break;
      default:
        trendColor = Colors.orange;
        trendIcon = Icons.trending_flat;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white70, size: 28),
          const SizedBox(height: 12),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(trendIcon, color: trendColor, size: 24),
              const SizedBox(width: 8),
              Text(
                '${improvement > 0 ? '+' : ''}${improvement.toInt()}%',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: trendColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            trend.capitalize(),
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: trendColor,
            ),
          ),
        ],
      ),
    );
  }
}

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}
