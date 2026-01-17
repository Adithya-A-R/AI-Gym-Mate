import 'package:flutter/material.dart';
import 'package:ai_gymmate/widgets/app_logo.dart';
import 'package:ai_gymmate/widgets/input_field.dart';
import 'package:ai_gymmate/widgets/primary_button.dart';

class SignupScreen extends StatelessWidget {
  const SignupScreen({super.key});

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
                "Create Account",
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              ),
              const Text("Sign up to get started"),

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
                text: "Sign Up",
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
