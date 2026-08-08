import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config.dart';

class UserBrainScreen extends StatefulWidget {
  const UserBrainScreen({super.key});

  @override
  State<UserBrainScreen> createState() => _UserBrainScreenState();
}

class _UserBrainScreenState extends State<UserBrainScreen> {
  final _displayNameController = TextEditingController();
  final _newGoalController = TextEditingController();
  final _newMemoryController = TextEditingController();
  
  String _expertiseLevel = 'intermediate';
  String _communicationStyle = 'supportive';
  List<String> _goals = [];
  List<dynamic> _memories = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Load Profile
      final profileRes = await http.get(Uri.parse('$backendUrl/user_brain/profile'));
      if (profileRes.statusCode == 200) {
        final data = jsonDecode(profileRes.body);
        setState(() {
          _displayNameController.text = data['display_name'] ?? '';
          _expertiseLevel = data['expertise_level'] ?? 'intermediate';
          _communicationStyle = data['communication_style'] ?? 'supportive';
          _goals = List<String>.from(data['goals'] ?? []);
        });
      }

      // Load Memories
      final memoryRes = await http.get(Uri.parse('$backendUrl/memory/'));
      if (memoryRes.statusCode == 200) {
        setState(() {
          _memories = jsonDecode(memoryRes.body);
        });
      }
    } catch (e) {
      _showSnackbar('Error loading data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _isLoading = true);
    try {
      final res = await http.post(
        Uri.parse('$backendUrl/user_brain/profile'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': 'default_user',
          'display_name': _displayNameController.text.trim(),
          'expertise_level': _expertiseLevel,
          'communication_style': _communicationStyle,
          'goals': _goals,
        }),
      );
      if (res.statusCode == 200) {
        _showSnackbar('Profile saved successfully!');
      } else {
        _showSnackbar('Failed to save profile');
      }
    } catch (e) {
      _showSnackbar('Error saving profile: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addMemory() async {
    final text = _newMemoryController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final res = await http.post(
        Uri.parse('$backendUrl/memory/?content=${Uri.encodeComponent(text)}'),
      );
      if (res.statusCode == 200) {
        _newMemoryController.clear();
        _loadData();
      }
    } catch (e) {
      _showSnackbar('Error adding memory: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteMemory(String id) async {
    setState(() => _isLoading = true);
    try {
      final res = await http.delete(Uri.parse('$backendUrl/memory/$id'));
      if (res.statusCode == 200) {
        _loadData();
      }
    } catch (e) {
      _showSnackbar('Error deleting memory: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSnackbar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF070B14),
        elevation: 0,
        title: const Text('User Brain & Memory', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // User Profile Section
                  _buildSectionHeader('Personal Identity', Icons.person_rounded),
                  const SizedBox(height: 12),
                  _buildProfileForm(),
                  const SizedBox(height: 24),

                  // Goals Section
                  _buildSectionHeader('Long-term Goals', Icons.flag_rounded),
                  const SizedBox(height: 12),
                  _buildGoalsSection(),
                  const SizedBox(height: 24),

                  // Memory Section
                  _buildSectionHeader('Long-term Memories', Icons.psychology_alt_rounded),
                  const SizedBox(height: 12),
                  _buildMemoriesSection(),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF5B8DEF), size: 22),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _buildProfileForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131A2B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          TextField(
            controller: _displayNameController,
            decoration: const InputDecoration(
              labelText: 'Display Name',
              labelStyle: TextStyle(color: Colors.white60),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            ),
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _expertiseLevel,
            dropdownColor: const Color(0xFF131A2B),
            decoration: const InputDecoration(
              labelText: 'Expertise Level',
              labelStyle: TextStyle(color: Colors.white60),
            ),
            items: const [
              DropdownMenuItem(value: 'beginner', child: Text('Beginner', style: TextStyle(color: Colors.white))),
              DropdownMenuItem(value: 'intermediate', child: Text('Intermediate', style: TextStyle(color: Colors.white))),
              DropdownMenuItem(value: 'advanced', child: Text('Advanced', style: TextStyle(color: Colors.white))),
            ],
            onChanged: (val) => setState(() => _expertiseLevel = val!),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _communicationStyle,
            dropdownColor: const Color(0xFF131A2B),
            decoration: const InputDecoration(
              labelText: 'Communication Style',
              labelStyle: TextStyle(color: Colors.white60),
            ),
            items: const [
              DropdownMenuItem(value: 'supportive', child: Text('Supportive', style: TextStyle(color: Colors.white))),
              DropdownMenuItem(value: 'concise', child: Text('Concise', style: TextStyle(color: Colors.white))),
              DropdownMenuItem(value: 'academic', child: Text('Academic', style: TextStyle(color: Colors.white))),
            ],
            onChanged: (val) => setState(() => _communicationStyle = val!),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _saveProfile,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5B8DEF),
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Save Profile', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildGoalsSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131A2B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          ..._goals.map((g) => ListTile(
                title: Text(g, style: const TextStyle(color: Colors.white70)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  onPressed: () => setState(() => _goals.remove(g)),
                ),
              )),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newGoalController,
                  decoration: const InputDecoration(
                    hintText: 'Add new goal...',
                    hintStyle: TextStyle(color: Colors.white30),
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle, color: Color(0xFF3DAA7A)),
                onPressed: () {
                  final text = _newGoalController.text.trim();
                  if (text.isNotEmpty) {
                    setState(() {
                      _goals.add(text);
                      _newGoalController.clear();
                    });
                  }
                },
              )
            ],
          )
        ],
      ),
    );
  }

  Widget _buildMemoriesSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131A2B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          ..._memories.map((m) => ListTile(
                title: Text(m['content'] ?? '', style: const TextStyle(color: Colors.white70)),
                subtitle: Text(m['timestamp']?.split('T')?.first ?? '', style: const TextStyle(color: Colors.white30, fontSize: 11)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  onPressed: () => _deleteMemory(m['id']),
                ),
              )),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newMemoryController,
                  decoration: const InputDecoration(
                    hintText: 'Write a new memory...',
                    hintStyle: TextStyle(color: Colors.white30),
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle, color: Color(0xFF3DAA7A)),
                onPressed: _addMemory,
              )
            ],
          )
        ],
      ),
    );
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _newGoalController.dispose();
    _newMemoryController.dispose();
    super.dispose();
  }
}
