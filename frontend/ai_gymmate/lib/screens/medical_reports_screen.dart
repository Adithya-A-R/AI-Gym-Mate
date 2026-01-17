import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/ocr_service.dart';
import '../services/profile_service.dart';
import '../services/medical_analysis_service.dart';


class MedicalReportsScreen extends StatefulWidget {
  const MedicalReportsScreen({super.key});

  @override
  State<MedicalReportsScreen> createState() => _MedicalReportsScreenState();
}

class _MedicalReportsScreenState extends State<MedicalReportsScreen> {
  final ImagePicker _picker = ImagePicker();

  bool isLoading = false;
  String extractedText = "";
  List<String> savedReports = [];

  @override
  void initState() {
    super.initState();
    _loadSavedReports();
  }

  Future<void> _loadSavedReports() async {
    final reports = await ProfileService.getMedicalReports();
    setState(() {
      savedReports = reports.reversed.toList(); // latest first
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    final XFile? image =
        await _picker.pickImage(source: source, imageQuality: 85);

    if (image == null) return;

    setState(() {
      isLoading = true;
      extractedText = "";
    });

    final text =
        await OCRService.extractTextFromImage(File(image.path));

    await ProfileService.saveMedicalReport(text);

    setState(() {
      extractedText = text;
      isLoading = false;
    });

    _loadSavedReports();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Medical Reports (OCR)")),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Scan Medical Report",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            const Text(
              "Upload blood reports, ECG summaries, or prescriptions. "
              "Text will be extracted and saved locally.",
              style: TextStyle(color: Colors.grey),
            ),

            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.camera_alt),
                    label: const Text("Camera"),
                    onPressed: () => _pickImage(ImageSource.camera),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.photo),
                    label: const Text("Gallery"),
                    onPressed: () => _pickImage(ImageSource.gallery),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            if (isLoading)
              const Center(child: CircularProgressIndicator()),

            if (extractedText.isNotEmpty) ...[
              const Divider(),
              const SizedBox(height: 12),

              const Text(
                "Latest Extracted Text",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),

              Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    extractedText,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ),
            ],

            if (!isLoading && extractedText.isEmpty) ...[
              const Divider(),
              const SizedBox(height: 12),

              const Text(
                "Saved Reports",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),

              Expanded(
                child: savedReports.isEmpty
                    ? const Center(
                        child: Text(
                          "No reports uploaded yet",
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: savedReports.length,
                        itemBuilder: (context, index) {
                          return Card(
                            child: ListTile(
                              leading:
                                  const Icon(Icons.description),
                              title: Text(
                                "Medical Report ${index + 1}",
                              ),
                              subtitle: const Text(
                                "Tap to view extracted text",
                              ),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ReportViewScreen(
                                      text: savedReports[index],
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ================= REPORT VIEW SCREEN =================

class ReportViewScreen extends StatelessWidget {
  final String text;

  const ReportViewScreen({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Medical Report")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ),
    );
  }
}
