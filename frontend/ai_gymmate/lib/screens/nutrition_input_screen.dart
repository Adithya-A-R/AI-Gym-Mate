import 'package:flutter/material.dart';
import '../services/profile_service.dart';
import 'nutrition_result_screen.dart';

class NutritionInputScreen extends StatefulWidget {
  const NutritionInputScreen({super.key});

  @override
  State<NutritionInputScreen> createState() => _NutritionInputScreenState();
}

class _NutritionInputScreenState extends State<NutritionInputScreen> {
  final weightController = TextEditingController();
  String activity = "Moderate";

  int age = 0;
  double height = 0;
  String gender = "";

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    final profile = await ProfileService.getProfile();
    setState(() {
      age = profile['age'];
      height = profile['height'];
      gender = profile['gender'];
      weightController.text = profile['weight'].toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Nutrition Assessment")),
      body: age == 0
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Confirm Details",
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),

                  _readonlyTile("Age", "$age years"),
                  _readonlyTile("Height", "$height cm"),
                  _readonlyTile("Gender", gender),

                  const SizedBox(height: 24),

                  _inputField("Current Weight (kg)", weightController),

                  const SizedBox(height: 24),
                  const Text("Activity Level"),
                  const SizedBox(height: 8),

                  DropdownButtonFormField<String>(
                    value: activity,
                    items: const [
                      DropdownMenuItem(value: "Low", child: Text("Low")),
                      DropdownMenuItem(value: "Moderate", child: Text("Moderate")),
                      DropdownMenuItem(value: "High", child: Text("High")),
                    ],
                    onChanged: (value) => setState(() => activity = value!),
                    decoration:
                        const InputDecoration(border: OutlineInputBorder()),
                  ),

                  const Spacer(),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _calculateNutrition,
                      child: const Text("Calculate Nutrition"),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _readonlyTile(String label, String value) {
    return ListTile(
      title: Text(label),
      trailing:
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  Widget _inputField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  void _calculateNutrition() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NutritionResultScreen(
          age: age,
          height: height,
          weight: double.parse(weightController.text),
          gender: gender,
          activity: activity,
        ),
      ),
    );
  }
}
