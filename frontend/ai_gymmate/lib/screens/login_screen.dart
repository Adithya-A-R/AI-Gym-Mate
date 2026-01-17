import 'package:flutter/material.dart';
import 'package:ai_gymmate/widgets/app_logo.dart';
import 'package:ai_gymmate/widgets/input_field.dart';
import 'package:ai_gymmate/widgets/primary_button.dart';
import 'signup_screen.dart';
import 'home_screen.dart';
import '../services/profile_service.dart';
import 'profile_setup_screen.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(child: AppLogo(size: 120)),
              const SizedBox(height: 24),

              const Text(
                "Welcome Back",
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              ),
              const Text("Login to continue"),

              const SizedBox(height: 32),

              InputField(
                label: "Email",
                controller: emailController,
              ),
              const SizedBox(height: 16),

              InputField(
                label: "Password",
                controller: passwordController,
                isPassword: true,
              ),
              const SizedBox(height: 24),

              PrimaryButton(
                text: "Login",
                onPressed: () async {
                 final isCompleted = await ProfileService.isProfileCompleted();

                if (isCompleted) {
                Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const HomeScreen()),
                );
         } else {
           Navigator.pushReplacement(
           context,
           MaterialPageRoute(builder: (_) => const ProfileSetupScreen()),
      );
        }
      },
            ),

              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Don’t have an account? "),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SignupScreen(),
                        ),
                      );
                    },
                    child: const Text(
                      "Sign up",
                      style: TextStyle(
                        color: Color(0xFF1565C0),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}
