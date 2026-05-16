import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';

class AuthService {
  static const String _usersKey = 'app_users';
  static const String _currentUserKey = 'current_user';

  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<List<User>> getUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final usersJson = prefs.getStringList(_usersKey) ?? [];
    
    return usersJson
        .map((json) => User.fromJson(jsonDecode(json)))
        .toList();
  }

  Future<void> _saveUsers(List<User> users) async {
    final prefs = await SharedPreferences.getInstance();
    final usersJson = users.map((user) => jsonEncode(user.toJson())).toList();
    await prefs.setStringList(_usersKey, usersJson);
  }

  Future<User?> register({
    required String fullName,
    required String email,
    required String password,
    String? phoneNumber,
    int? age,
    int? height,
    int? weight,
    String? goal,
  }) async {
    final users = await getUsers();
    
    if (users.any((user) => user.email == email)) {
      throw Exception('Email already exists');
    }

    final newUser = User(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      fullName: fullName,
      email: email,
      password: _hashPassword(password),
      phoneNumber: phoneNumber,
      age: age,
      height: height,
      weight: weight,
      goal: goal,
      createdAt: DateTime.now(),
    );

    users.add(newUser);
    await _saveUsers(users);

    return newUser;
  }

  Future<User?> login({
    required String email,
    required String password,
  }) async {
    final users = await getUsers();
    final hashedPassword = _hashPassword(password);

    final user = users.firstWhere(
      (user) => user.email == email && user.password == hashedPassword,
      orElse: () => throw Exception('Invalid email or password'),
    );

    await _setCurrentUser(user);
    return user;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_currentUserKey);
  }

  Future<User?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final currentUserJson = prefs.getString(_currentUserKey);

    if (currentUserJson == null) return null;

    return User.fromJson(jsonDecode(currentUserJson));
  }

  Future<void> _setCurrentUser(User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentUserKey, jsonEncode(user.toJson()));
  }

  Future<bool> isLoggedIn() async {
    final currentUser = await getCurrentUser();
    return currentUser != null;
  }

  Future<void> resetPassword({
    required String email,
    required String newPassword,
  }) async {
    final users = await getUsers();
    
    final userIndex = users.indexWhere((user) => user.email == email);
    if (userIndex == -1) {
      throw Exception('Email not found');
    }

    users[userIndex] = users[userIndex].copyWith(
      password: _hashPassword(newPassword),
      updatedAt: DateTime.now(),
    );

    await _saveUsers(users);
  }

  Future<void> updateProfile({
    required String userId,
    String? fullName,
    String? phoneNumber,
  }) async {
    final users = await getUsers();
    
    final userIndex = users.indexWhere((user) => user.id == userId);
    if (userIndex == -1) {
      throw Exception('User not found');
    }

    users[userIndex] = users[userIndex].copyWith(
      fullName: fullName ?? users[userIndex].fullName,
      phoneNumber: phoneNumber ?? users[userIndex].phoneNumber,
      updatedAt: DateTime.now(),
    );

    await _saveUsers(users);

    final currentUser = await getCurrentUser();
    if (currentUser?.id == userId) {
      await _setCurrentUser(users[userIndex]);
    }
  }
}
