import 'package:flutter/material.dart';
import '../services/profile_service.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final nameController = TextEditingController();
  final ageController = TextEditingController();
  final heightController = TextEditingController();
  final weightController = TextEditingController();

  String gender = "Male";
  final Map<String, bool> conditions = {
    "Diabetes": false,
    "Hypertension": false,
    "Heart Disease": false,
    "Asthma": false,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Profile Setup")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Tell us about yourself",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),

            _inputField("Name", nameController, TextInputType.text),
            const SizedBox(height: 16),

            _inputField("Age", ageController, TextInputType.number),
            const SizedBox(height: 16),

            _inputField("Height (cm)", heightController, TextInputType.number),
            const SizedBox(height: 16),

            _inputField("Weight (kg)", weightController, TextInputType.number),
            const SizedBox(height: 24),

            const Text("Gender"),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: gender,
              items: const [
                DropdownMenuItem(value: "Male", child: Text("Male")),
                DropdownMenuItem(value: "Female", child: Text("Female")),
              ],
              onChanged: (value) => setState(() => gender = value!),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),

            const SizedBox(height: 24),
            const Text(
              "Health Conditions (if any)",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),

            ...conditions.keys.map((key) {
              return CheckboxListTile(
                title: Text(key),
                value: conditions[key],
                onChanged: (val) {
                  setState(() {
                    conditions[key] = val!;
                  });
                },
              );
            }).toList(),

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveProfile,
                child: const Text("Continue"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _inputField(
      String label, TextEditingController controller, TextInputType type) {
    return TextField(
      controller: controller,
      keyboardType: type,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

void _saveProfile() async {
  if (nameController.text.isEmpty ||
      ageController.text.isEmpty ||
      heightController.text.isEmpty ||
      weightController.text.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Please fill all required fields")),
    );
    return;
  }

  final selectedConditions = conditions.entries
      .where((e) => e.value)
      .map((e) => e.key)
      .toList();

  await ProfileService.saveProfile(
    name: nameController.text,
    age: int.parse(ageController.text),
    height: double.parse(heightController.text),
    weight: double.parse(weightController.text),
    gender: gender,
    conditions: selectedConditions,
  );

  Navigator.pushReplacementNamed(context, '/home');
 }
}
