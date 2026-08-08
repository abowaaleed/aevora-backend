import 'package:shared_preferences/shared_preferences.dart';

class ModeManager {
  ModeManager({SharedPreferences? preferences}) : _preferences = preferences;

  static const String _selectedModeKey = 'selected_mode';

  final SharedPreferences? _preferences;

  String get selectedSkill => 'quick';

  Future<void> load() async {
    // No-op: Evora has a single mode
  }

  Future<void> selectMode(dynamic mode) async {
    // No-op: Evora has a single mode
  }

  Future<bool> hasSelectedMode() async {
    return true;
  }
}
