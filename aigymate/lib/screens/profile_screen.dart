import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../services/auth_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  User? _currentUser;
  List<String> _medicalConditions = [];
  String? _medicalReportPath;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final authService = AuthService();
      final user = await authService.getCurrentUser();
      final prefs = await SharedPreferences.getInstance();
      
      // Load medical conditions from SharedPreferences
      final medicalConditions = prefs.getStringList('medical_conditions') ?? [];
      final medicalReportPath = prefs.getString('medical_report_path');

      setState(() {
        _currentUser = user;
        _medicalConditions = medicalConditions;
        _medicalReportPath = medicalReportPath;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading user data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildProfileHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  Colors.blue.shade300,
                  Colors.indigo.shade400,
                ],
              ),
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 3,
              ),
            ),
            child: Icon(
              FontAwesomeIcons.user,
              size: 40,
              color: Colors.white.withOpacity(0.9),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _currentUser?.fullName ?? 'User',
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _currentUser?.email ?? 'email@example.com',
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.white.withOpacity(0.7),
            ),
          ),
          if (_currentUser?.phoneNumber != null) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  FontAwesomeIcons.phone,
                  size: 14,
                  color: Colors.white.withOpacity(0.7),
                ),
                const SizedBox(width: 6),
                Text(
                  _currentUser!.phoneNumber!,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  color: Colors.white.withOpacity(0.7),
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildMedicalConditionsSection() {
    if (_medicalConditions.isEmpty) {
      return Column(
        children: [
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                FontAwesomeIcons.infoCircle,
                color: Colors.blue.shade300,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'No medical conditions recorded. You can add them during registration or upload a medical report for OCR processing.',
                  style: GoogleFonts.poppins(
                    color: Colors.blue.shade300,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      children: [
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _medicalConditions.map((condition) {
            Color chipColor;
            IconData chipIcon;
            
            // Color code based on condition category
            if (condition.contains('cardiovascular') || condition.contains('heart') || condition.contains('hypertension')) {
              chipColor = Colors.red.withOpacity(0.3);
              chipIcon = FontAwesomeIcons.heart;
            } else if (condition.contains('pain') || condition.contains('arthritis') || condition.contains('back') || condition.contains('knee')) {
              chipColor = Colors.orange.withOpacity(0.3);
              chipIcon = FontAwesomeIcons.bone;
            } else if (condition.contains('diabetes') || condition.contains('thyroid') || condition.contains('metabolic')) {
              chipColor = Colors.purple.withOpacity(0.3);
              chipIcon = FontAwesomeIcons.vial;
            } else if (condition.contains('anxiety') || condition.contains('depression') || condition.contains('stress')) {
              chipColor = Colors.pink.withOpacity(0.3);
              chipIcon = FontAwesomeIcons.brain;
            } else {
              chipColor = Colors.green.withOpacity(0.3);
              chipIcon = FontAwesomeIcons.notesMedical;
            }

            return Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: chipColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: chipColor.withOpacity(0.5),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    chipIcon,
                    size: 12,
                    color: Colors.white.withOpacity(0.9),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    condition.replaceAll('_', ' ').toUpperCase(),
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildMedicalReportSection() {
    if (_medicalReportPath == null) {
      return Column(
        children: [
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                FontAwesomeIcons.fileMedical,
                color: Colors.grey.shade400,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                'No medical report uploaded',
                style: GoogleFonts.poppins(
                  color: Colors.grey.shade400,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      );
    }

    String fileName = _medicalReportPath!.split('\\').last;
    return Column(
      children: [
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.green.withOpacity(0.4),
            ),
          ),
          child: Row(
            children: [
              Icon(
                FontAwesomeIcons.fileMedical,
                color: Colors.green.shade300,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Medical Report',
                      style: GoogleFonts.poppins(
                        color: Colors.green.shade300,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      fileName,
                      style: GoogleFonts.poppins(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 11,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                FontAwesomeIcons.checkCircle,
                color: Colors.green.shade300,
                size: 16,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAccountDetails() {
    if (_currentUser == null) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        _buildDetailRow('Account ID', _currentUser!.id.substring(0, 8) + '...', FontAwesomeIcons.fingerprint),
        _buildDetailRow('Member Since', _formatDate(_currentUser!.createdAt), FontAwesomeIcons.calendar),
        if (_currentUser!.updatedAt != null)
          _buildDetailRow('Last Updated', _formatDate(_currentUser!.updatedAt!), FontAwesomeIcons.clock),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            icon,
            size: 14,
            color: Colors.white.withOpacity(0.6),
          ),
          const SizedBox(width: 10),
          Text(
            '$label:',
            style: GoogleFonts.poppins(
              color: Colors.white.withOpacity(0.6),
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.poppins(
                color: Colors.white.withOpacity(0.9),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.blue.shade600,
              Colors.blue.shade800,
              Colors.indigo.shade900,
            ],
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? Center(
                  child: CircularProgressIndicator(
                    color: Colors.white,
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      // Header with back button
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(
                              Icons.arrow_back,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            'Profile',
                            style: GoogleFonts.poppins(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 32),
                      
                      // Profile Header
                      _buildProfileHeader(),
                      
                      const SizedBox(height: 32),
                      
                      // Medical Conditions Section
                      _buildInfoCard(
                        title: 'Medical Conditions',
                        icon: FontAwesomeIcons.notesMedical,
                        children: [_buildMedicalConditionsSection()],
                      ),
                      
                      // Medical Report Section
                      _buildInfoCard(
                        title: 'Medical Report',
                        icon: FontAwesomeIcons.fileMedical,
                        children: [_buildMedicalReportSection()],
                      ),
                      
                      // Account Details Section
                      _buildInfoCard(
                        title: 'Account Details',
                        icon: FontAwesomeIcons.userCircle,
                        children: [_buildAccountDetails()],
                      ),
                      
                      const SizedBox(height: 32),
                      
                      // Logout Button
                      Container(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final authService = AuthService();
                            await authService.logout();
                            if (mounted) {
                              Navigator.of(context).pushNamedAndRemoveUntil(
                                '/',
                                (route) => false,
                              );
                            }
                          },
                          icon: const Icon(
                            FontAwesomeIcons.signOutAlt,
                            size: 18,
                          ),
                          label: Text(
                            'Logout',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.withOpacity(0.8),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
