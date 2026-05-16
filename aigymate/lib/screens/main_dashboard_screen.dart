import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'dashboard_screen.dart';
import 'profile_screen.dart';
import 'exercise_selection_screen.dart';
import 'video_analysis_screen.dart';
import 'nutrition_screen.dart';
import 'diet_plan_screen.dart';
import 'recipe_screen.dart';
import 'analytics_dashboard_screen.dart';

class MainDashboardScreen extends StatefulWidget {
  const MainDashboardScreen({super.key});

  @override
  State<MainDashboardScreen> createState() => _MainDashboardScreenState();
}

class _MainDashboardScreenState extends State<MainDashboardScreen> {
  int _currentIndex = 0;
  bool _isDrawerOpen = false;

  final List<Widget> _screens = [
    const DashboardScreen(),
    const ExerciseSelectionScreen(),
    const VideoAnalysisScreen(),
    const NutritionScreen(),
    const DietPlanScreen(),
    const RecipeScreen(),
    const AnalyticsDashboardScreen(),
    const ProfileScreen(),
  ];

  final List<NavigationItem> _navItems = [
    NavigationItem(icon: FontAwesomeIcons.house, label: 'Home'),
    NavigationItem(icon: FontAwesomeIcons.dumbbell, label: 'Exercises'),
    NavigationItem(icon: FontAwesomeIcons.video, label: 'Analysis'),
    NavigationItem(icon: FontAwesomeIcons.appleAlt, label: 'Nutrition'),
    NavigationItem(icon: FontAwesomeIcons.clipboardList, label: 'Diet Plan'),
    NavigationItem(icon: FontAwesomeIcons.bookOpen, label: 'Recipes'),
    NavigationItem(icon: FontAwesomeIcons.chartLine, label: 'Analytics'),
    NavigationItem(icon: FontAwesomeIcons.user, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue.shade600,
        elevation: 2,
        title: Text(
          'AI GYMATE',
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          onPressed: () {
            setState(() {
              _isDrawerOpen = !_isDrawerOpen;
            });
          },
          icon: const Icon(
            FontAwesomeIcons.bars,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
      body: Stack(
        children: [
          // Main content (always full width)
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.blue.shade600,
                  Colors.blue.shade800,
                  Colors.indigo.shade900,
                ],
              ),
            ),
            child: _screens[_currentIndex],
          ),

          // Drawer overlay (shown only when open)
          if (_isDrawerOpen) ...[
            // Scrim — tap outside to close
            GestureDetector(
              onTap: () => setState(() => _isDrawerOpen = false),
              child: Container(color: Colors.black.withOpacity(0.4)),
            ),

            // Drawer panel
            Positioned(
              top: 0,
              left: 0,
              bottom: 0,
              child: Container(
                width: 240,
                decoration: BoxDecoration(
                  color: Colors.indigo.shade900,
                  border: Border(
                    right: BorderSide(color: Colors.white.withOpacity(0.1)),
                  ),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 40),

                    // App logo
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.blue.shade400,
                            Colors.indigo.shade500,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        FontAwesomeIcons.dumbbell,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),

                    const SizedBox(height: 40),

                    // Nav items
                    Expanded(
                      child: ListView.builder(
                        itemCount: _navItems.length,
                        itemBuilder: (context, index) {
                          final item = _navItems[index];
                          final isSelected = _currentIndex == index;

                          return Container(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () {
                                  setState(() {
                                    _currentIndex = index;
                                    _isDrawerOpen = false;
                                  });
                                },
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Colors.white.withOpacity(0.2)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(16),
                                    border: isSelected
                                        ? Border.all(
                                            color: Colors.white.withOpacity(0.3),
                                          )
                                        : null,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        item.icon,
                                        color: isSelected
                                            ? Colors.white
                                            : Colors.white.withOpacity(0.6),
                                        size: 24,
                                      ),
                                      const SizedBox(width: 16),
                                      Text(
                                        item.label,
                                        style: GoogleFonts.poppins(
                                          color: isSelected
                                              ? Colors.white
                                              : Colors.white.withOpacity(0.6),
                                          fontSize: 16,
                                          fontWeight: isSelected
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class NavigationItem {
  final IconData icon;
  final String label;

  NavigationItem({required this.icon, required this.label});
}