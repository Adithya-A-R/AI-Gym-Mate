import 'package:flutter/material.dart';
import 'package:ai_gymmate/widgets/app_logo.dart';
import 'package:ai_gymmate/widgets/input_field.dart';
import 'package:ai_gymmate/widgets/primary_button.dart';
import '../services/auth_service.dart';

class SignupScreen extends StatelessWidget {
  const SignupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final nameController = TextEditingController();
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
                    "Create Account",
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  const Text("Sign up to get started"),

                  const SizedBox(height: 32),

                  InputField(
                    label: "Name",
                    controller: nameController,
                  ),
                  const SizedBox(height: 16),

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
                    text: "Sign Up",
                    onPressed: () async {
                      final result = await AuthService.signup(
                        nameController.text.trim(),
                        emailController.text.trim(),
                        passwordController.text.trim(),
                      );

                      if (result["status"] == 200) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Account created successfully"),
                          ),
                        );
                        Navigator.pop(context);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(result["body"]["error"]),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
