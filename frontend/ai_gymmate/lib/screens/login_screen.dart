import 'package:flutter/material.dart';
import 'package:ai_gymmate/widgets/app_logo.dart';
import 'package:ai_gymmate/widgets/input_field.dart';
import 'package:ai_gymmate/widgets/primary_button.dart';
import 'signup_screen.dart';
import 'home_screen.dart';
import 'profile_setup_screen.dart';
import '../services/profile_service.dart';
import '../services/auth_service.dart';
import '../utils/page_transition.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
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
                      final result = await AuthService.login(
                        emailController.text.trim(),
                        passwordController.text.trim(),
                      );

                      if (result["status"] == 200) {
                        final isCompleted =
                            await ProfileService.isProfileCompleted();

                        Navigator.pushReplacement(
                          context,
                          AppPageRoute.fade(
                            isCompleted
                                ? const HomeScreen()
                                : const ProfileSetupScreen(),
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(result["body"]["error"]),
                          ),
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
                            AppPageRoute.fade(
                              const SignupScreen(),
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
        ),
      ),
    );
  }
}
