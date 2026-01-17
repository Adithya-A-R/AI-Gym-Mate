class MedicalAnalysisService {
  static Map<String, dynamic> extractHealthValues(String text) {
    final lowerText = text.toLowerCase();

    double? glucose;
    int? systolicBP;
    int? diastolicBP;
    double? cholesterol;

    // -------- GLUCOSE --------
    final glucoseMatch =
        RegExp(r'glucose[:\s]+(\d{2,3})').firstMatch(lowerText);
    if (glucoseMatch != null) {
      glucose = double.tryParse(glucoseMatch.group(1)!);
    }

    // -------- BLOOD PRESSURE --------
    final bpMatch =
        RegExp(r'(\d{2,3})\s*/\s*(\d{2,3})').firstMatch(lowerText);
    if (bpMatch != null) {
      systolicBP = int.tryParse(bpMatch.group(1)!);
      diastolicBP = int.tryParse(bpMatch.group(2)!);
    }

    // -------- CHOLESTEROL --------
    final cholesterolMatch =
        RegExp(r'cholesterol[:\s]+(\d{2,3})').firstMatch(lowerText);
    if (cholesterolMatch != null) {
      cholesterol = double.tryParse(cholesterolMatch.group(1)!);
    }

    return {
      'glucose': glucose,
      'systolicBP': systolicBP,
      'diastolicBP': diastolicBP,
      'cholesterol': cholesterol,
    };
  }
}
