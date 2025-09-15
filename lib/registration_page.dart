// lib/registration_page.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RegistrationPage extends StatefulWidget {
  const RegistrationPage({super.key});

  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage> {
  // Controllers for text fields
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _teacherSubjectsController = TextEditingController();
  final _studentIdController = TextEditingController(); // New controller for student ID

  // Firebase service instances
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  // State variables for UI logic
  bool _isLoading = false;
  String _selectedRole = 'Student'; // Default role
  List<String> _availableSubjects = []; // To store all subjects from Firestore
  List<String> _selectedStudentSubjects = []; // To store subjects selected by a student

  @override
  void initState() {
    super.initState();
    _fetchSubjects();
  }

  /// Helper: Safely convert Firestore doc.data() to Map<String, dynamic>.
  /// This avoids runtime cast errors when Firestore returns Map<dynamic, dynamic>.
  Map<String, dynamic> _asMap(dynamic raw) {
    if (raw == null) return <String, dynamic>{};
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return Map<String, dynamic>.fromEntries(
        raw.entries.map((entry) => MapEntry(entry.key.toString(), entry.value)),
      );
    }
    return <String, dynamic>{};
  }

  /// Fetches subject names from the 'subjects' collection in Firestore.
  Future<void> _fetchSubjects() async {
    try {
      final snapshot = await _firestore.collection('subjects').get();
      // You can use doc.id (document id) or a field inside the document.
      // We'll prefer doc.id but if you later store 'name' inside the doc, this also supports it.
      final subjects = snapshot.docs.map((doc) {
        // If you ever stored metadata inside the subject doc, handle it safely:
        final data = _asMap(doc.data());
        // Use 'code' or 'name' field if present, else fallback to doc.id
        if (data.containsKey('name') && data['name'] is String && (data['name'] as String).isNotEmpty) {
          return data['name'] as String;
        }
        return doc.id;
      }).toList();

      if (mounted) {
        setState(() {
          _availableSubjects = subjects;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load subjects: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showSubjectSelectionDialog() async {
    final List<String>? results = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return MultiSelectDialog(
          items: _availableSubjects,
          selectedItems: _selectedStudentSubjects,
        );
      },
    );

    if (results != null) {
      setState(() {
        _selectedStudentSubjects = results;
      });
    }
  }

  Future<void> _register() async {
    if (!mounted) return;

    if (_nameController.text.isEmpty || _emailController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all the required fields.'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      User? user = userCredential.user;
      if (user == null) {
        throw FirebaseAuthException(code: 'user-not-found', message: 'User creation failed unexpectedly.');
      }

      final String name = _nameController.text.trim();
      final String email = _emailController.text.trim();
      final String uid = user.uid;

      if (_selectedRole == 'Student') {
        await _registerStudent(name: name, email: email, uid: uid);
      } else {
        await _registerTeacher(name: name, email: email, uid: uid);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Registration successful! Please login.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } on FirebaseAuthException catch (e) {
      final snackBar = SnackBar(
        content: Text(e.message ?? 'Registration failed. Please try again.'),
        backgroundColor: Colors.red,
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(snackBar);
    } catch (e) {
      final snackBar = SnackBar(
        content: Text('An error occurred: ${e.toString()}'),
        backgroundColor: Colors.red,
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(snackBar);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Creates a document for the new student in the 'student' collection.
  Future<void> _registerStudent({required String name, required String email, required String uid}) async {
    if (_studentIdController.text.isEmpty) {
      throw Exception('Student ID/Roll Number is required');
    }

    // Create subjects map with explicit typing
    final Map<String, dynamic> subjectsMap = Map<String, dynamic>.fromEntries(
      _selectedStudentSubjects.asMap().entries.map(
            (entry) => MapEntry('sub${entry.key + 1}', entry.value as dynamic),
          ),
    );

    // Create student data with explicit typing
    final Map<String, dynamic> studentData = Map<String, dynamic>.from({
      'name': name,
      'email': email,
      'id': _studentIdController.text.trim(), // Use student ID instead of uid
    })..addAll(subjectsMap);

    await _firestore.collection('student').doc(name).set(studentData);
  }

  /// Creates a document for the new teacher and adds their subjects to the 'subjects' collection.
  Future<void> _registerTeacher({required String name, required String email, required String uid}) async {
    final subjectsList = _teacherSubjectsController.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    // Create subjects map with explicit typing
    final Map<String, dynamic> subjectsMap = Map<String, dynamic>.fromEntries(
      subjectsList.asMap().entries.map(
            (entry) => MapEntry('sub${entry.key + 1}', entry.value as dynamic),
          ),
    );

    // Create teacher data with explicit typing
    final Map<String, dynamic> teacherData = Map<String, dynamic>.from({
      'name': name,
      'email': email,
      'id': uid,
    })..addAll(subjectsMap);

    final WriteBatch batch = _firestore.batch();

    final DocumentReference teacherRef = _firestore.collection('teacher').doc(name);
    batch.set(teacherRef, teacherData);

    for (String subject in subjectsList) {
      final DocumentReference subjectRef = _firestore.collection('subjects').doc(subject);
      
      // Set an empty document for the subject with explicit Map<String, dynamic> type
      final Map<String, dynamic> emptySubjectData = Map<String, dynamic>.from({});
      batch.set(subjectRef, emptySubjectData);

      // Create the dates collection with explicit Map<String, dynamic> type
      final DocumentReference datesDoc = subjectRef.collection('dates').doc('placeholder');
      final Map<String, dynamic> emptyDatesData = Map<String, dynamic>.from({});
      batch.set(datesDoc, emptyDatesData);
    }

    await batch.commit();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _teacherSubjectsController.dispose();
    _studentIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Register Account'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              DropdownButtonFormField<String>(
                value: _selectedRole,
                items: ['Student', 'Teacher'].map((String role) {
                  return DropdownMenuItem<String>(
                    value: role,
                    child: Text(role),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    if (newValue != null) _selectedRole = newValue;
                  });
                },
                decoration: const InputDecoration(
                  labelText: 'I am a...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              if (_selectedRole == 'Student')
                Column(
                  children: [
                    TextField(
                      controller: _studentIdController,
                      decoration: const InputDecoration(
                        labelText: 'Student ID/Roll Number',
                        hintText: 'This will be used as your ID',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              if (_selectedRole == 'Student')
                _buildStudentFields()
              else
                _buildTeacherFields(),
              const SizedBox(height: 20),
              _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _register,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                        minimumSize: const Size(double.infinity, 50),
                      ),
                      child: const Text('Register'),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStudentFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.school_outlined),
          label: const Text('Select Your Subjects'),
          onPressed: _showSubjectSelectionDialog,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 50),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
        ),
        const SizedBox(height: 8),
        if (_selectedStudentSubjects.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
            child: Wrap(
              spacing: 8.0,
              runSpacing: 4.0,
              children: _selectedStudentSubjects
                  .map((subject) => Chip(
                        label: Text(subject),
                        onDeleted: () {
                          setState(() {
                            _selectedStudentSubjects.remove(subject);
                          });
                        },
                      ))
                  .toList(),
            ),
          )
        else
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: Text('No subjects selected.', style: TextStyle(color: Colors.grey)),
          ),
      ],
    );
  }

  Widget _buildTeacherFields() {
    return TextField(
      controller: _teacherSubjectsController,
      decoration: const InputDecoration(
        labelText: 'Subjects You Teach',
        hintText: 'Enter subjects, separated by commas',
        border: OutlineInputBorder(),
      ),
    );
  }
}

/// Multi-select dialog for students to pick subjects.
class MultiSelectDialog extends StatefulWidget {
  final List<String> items;
  final List<String> selectedItems;
  const MultiSelectDialog({Key? key, required this.items, required this.selectedItems}) : super(key: key);

  @override
  State<MultiSelectDialog> createState() => _MultiSelectDialogState();
}

class _MultiSelectDialogState extends State<MultiSelectDialog> {
  late final List<String> _tempSelectedItems;

  @override
  void initState() {
    super.initState();
    _tempSelectedItems = List<String>.from(widget.selectedItems);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Subjects'),
      content: SingleChildScrollView(
        child: ListBody(
          children: widget.items.map((item) {
            return CheckboxListTile(
              value: _tempSelectedItems.contains(item),
              title: Text(item),
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (bool? value) {
                setState(() {
                  if (value == true) {
                    if (!_tempSelectedItems.contains(item)) _tempSelectedItems.add(item);
                  } else {
                    if (_tempSelectedItems.contains(item)) _tempSelectedItems.remove(item);
                  }
                });
              },
            );
          }).toList(),
        ),
      ),
      actions: <Widget>[
        TextButton(child: const Text('Cancel'), onPressed: () => Navigator.of(context).pop()),
        ElevatedButton(child: const Text('Done'), onPressed: () => Navigator.of(context).pop(_tempSelectedItems)),
      ],
    );
  }
}
