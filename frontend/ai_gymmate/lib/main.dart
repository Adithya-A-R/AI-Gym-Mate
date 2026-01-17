import 'package:flutter/material.dart';
import 'package:ai_gymmate/screens/login_screen.dart';
import 'package:ai_gymmate/screens/home_screen.dart';
import 'package:ai_gymmate/theme.dart';

void main() {
  runApp(const AIGymMate());
}

class AIGymMate extends StatelessWidget {
  const AIGymMate({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routes: {
        '/home': (context) => const HomeScreen(),
      },
      home: const LoginScreen(),
    );
  }
}
