class User {
  final String id;
  final String fullName;
  final String email;
  final String password;
  final String? phoneNumber;
  final List<String>? medicalConditions;
  final String? medicalReportPath;
  final int? age;
  final int? height; // in cm
  final int? weight; // in kg
  final String? goal; // weight_loss, muscle_gain, maintenance
  final DateTime createdAt;
  final DateTime? updatedAt;

  User({
    required this.id,
    required this.fullName,
    required this.email,
    required this.password,
    this.phoneNumber,
    this.medicalConditions,
    this.medicalReportPath,
    this.age,
    this.height,
    this.weight,
    this.goal,
    required this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fullName': fullName,
      'email': email,
      'password': password,
      'phoneNumber': phoneNumber,
      'medicalConditions': medicalConditions,
      'medicalReportPath': medicalReportPath,
      'age': age,
      'height': height,
      'weight': weight,
      'goal': goal,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      fullName: json['fullName'],
      email: json['email'],
      password: json['password'],
      phoneNumber: json['phoneNumber'],
      medicalConditions: json['medicalConditions'] != null 
          ? List<String>.from(json['medicalConditions']) 
          : null,
      medicalReportPath: json['medicalReportPath'],
      age: json['age'],
      height: json['height'],
      weight: json['weight'],
      goal: json['goal'],
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null,
    );
  }

  User copyWith({
    String? id,
    String? fullName,
    String? email,
    String? password,
    String? phoneNumber,
    List<String>? medicalConditions,
    String? medicalReportPath,
    int? age,
    int? height,
    int? weight,
    String? goal,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return User(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      password: password ?? this.password,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      medicalConditions: medicalConditions ?? this.medicalConditions,
      medicalReportPath: medicalReportPath ?? this.medicalReportPath,
      age: age ?? this.age,
      height: height ?? this.height,
      weight: weight ?? this.weight,
      goal: goal ?? this.goal,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
