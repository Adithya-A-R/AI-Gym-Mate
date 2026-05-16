import 'dart:io';
import 'dart:typed_data';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:image/image.dart' as img;

class OcrService {
  static final List<String> _medicalKeywords = [
    // Common medical conditions
    'diabetes', 'hypertension', 'high blood pressure', 'cardiovascular',
    'heart disease', 'coronary artery disease', 'stroke', 'asthma',
    'copd', 'arthritis', 'osteoporosis', 'kidney disease', 'liver disease',
    
    // Orthopedic conditions
    'knee pain', 'back pain', 'neck pain', 'shoulder pain', 'hip pain',
    'joint pain', 'spinal injury', 'fracture', 'sprain', 'strain',
    'osteoarthritis', 'rheumatoid arthritis', 'disc herniation',
    
    // Neurological conditions
    'epilepsy', 'seizure', 'migraine', 'parkinson', 'multiple sclerosis',
    'neuropathy', 'paralysis', 'vertigo', 'dizziness',
    
    // Cardiovascular conditions
    'angina', 'heart attack', 'myocardial infarction', 'arrhythmia',
    'palpitations', 'chest pain', 'heart failure', 'valve disease',
    
    // Respiratory conditions
    'bronchitis', 'pneumonia', 'tuberculosis', 'sleep apnea',
    'allergy', 'sinusitis', 'emphysema',
    
    // Metabolic conditions
    'obesity', 'overweight', 'thyroid', 'hyperthyroidism', 'hypothyroidism',
    'metabolic syndrome', 'high cholesterol', 'lipid disorder',
    
    // Mental health
    'depression', 'anxiety', 'bipolar', 'schizophrenia', 'ptsd',
    'stress', 'insomnia', 'sleep disorder',
    
    // Women's health
    'pregnancy', 'menopause', 'pcos', 'endometriosis', 'fibroids',
    
    // Other conditions
    'anemia', 'diarrhea', 'constipation', 'ulcer', 'gallstones',
    'cataract', 'glaucoma', 'hearing loss', 'vertigo'
  ];

  static Future<List<String>> extractMedicalConditions(String imagePath) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final textRecognizer = GoogleMlKit.vision.textRecognizer();
      
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      
      await textRecognizer.close();
      
      // Extract text and process for medical conditions
      String fullText = recognizedText.text.toLowerCase();
      
      // Find medical conditions in the text
      List<String> foundConditions = [];
      
      for (String keyword in _medicalKeywords) {
        if (fullText.contains(keyword)) {
          foundConditions.add(keyword);
        }
      }
      
      // Also try to extract from individual text blocks for better accuracy
      for (TextBlock block in recognizedText.blocks) {
        String blockText = block.text.toLowerCase();
        for (String keyword in _medicalKeywords) {
          if (blockText.contains(keyword) && !foundConditions.contains(keyword)) {
            foundConditions.add(keyword);
          }
        }
      }
      
      return foundConditions;
      
    } catch (e) {
      print('Error in OCR processing: $e');
      return [];
    }
  }

  static Future<List<String>> extractMedicalConditionsFromBytes(Uint8List imageBytes) async {
    try {
      // Convert bytes to image and save temporarily
      img.Image? image = img.decodeImage(imageBytes);
      if (image == null) return [];
      
      // Create temporary file
      final tempDir = Directory.systemTemp;
      final tempPath = '${tempDir.path}/temp_medical_report_${DateTime.now().millisecondsSinceEpoch}.jpg';
      
      File tempFile = File(tempPath);
      await tempFile.writeAsBytes(imageBytes);
      
      // Process with existing method
      List<String> conditions = await extractMedicalConditions(tempPath);
      
      // Clean up temp file
      try {
        await tempFile.delete();
      } catch (e) {
        print('Error deleting temp file: $e');
      }
      
      return conditions;
      
    } catch (e) {
      print('Error processing image bytes: $e');
      return [];
    }
  }

  static String normalizeMedicalCondition(String condition) {
    // Normalize common variations
    Map<String, String> normalizations = {
      'high blood pressure': 'hypertension',
      'heart attack': 'cardiovascular',
      'myocardial infarction': 'cardiovascular',
      'chest pain': 'cardiovascular',
      'angina': 'cardiovascular',
      'back pain': 'back_pain',
      'neck pain': 'neck_pain',
      'shoulder pain': 'shoulder_pain',
      'hip pain': 'hip_pain',
      'knee pain': 'knee_pain',
      'joint pain': 'arthritis',
      'overweight': 'obesity',
      'sleep disorder': 'insomnia',
    };
    
    String normalized = condition.toLowerCase();
    for (String key in normalizations.keys) {
      if (normalized.contains(key)) {
        return normalizations[key]!;
      }
    }
    
    return condition.toLowerCase().replaceAll(' ', '_');
  }

  static List<String> normalizeAllConditions(List<String> conditions) {
    List<String> normalized = [];
    Set<String> seen = {};
    
    for (String condition in conditions) {
      String norm = normalizeMedicalCondition(condition);
      if (!seen.contains(norm)) {
        normalized.add(norm);
        seen.add(norm);
      }
    }
    
    return normalized;
  }
}
