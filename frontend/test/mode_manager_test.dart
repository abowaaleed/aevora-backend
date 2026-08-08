import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mustafeed/models/mode_option.dart';
import 'package:mustafeed/services/mode_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ModeManager persists selected mode and returns it on reload', () async {
    SharedPreferences.setMockInitialValues({});

    final manager = ModeManager();
    expect(await manager.hasSelectedMode(), isFalse);

    final mode = ModeOption.quick();
    await manager.selectMode(mode);

    expect(await manager.hasSelectedMode(), isTrue);
    expect(manager.currentMode?.id, mode.id);

    final reloaded = ModeManager();
    await reloaded.load();

    expect(await reloaded.hasSelectedMode(), isTrue);
    expect(reloaded.currentMode?.id, mode.id);
  });
}
