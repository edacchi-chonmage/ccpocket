import 'package:flutter/foundation.dart';

enum SettingsFocusSection { claudeAuth }

class SettingsFocusController extends ChangeNotifier {
  SettingsFocusController._();

  static final SettingsFocusController instance = SettingsFocusController._();

  SettingsFocusSection? _pendingSection;

  SettingsFocusSection? get pendingSection => _pendingSection;

  void request(SettingsFocusSection section) {
    _pendingSection = section;
    notifyListeners();
  }

  void clear(SettingsFocusSection section) {
    if (_pendingSection != section) return;
    _pendingSection = null;
  }
}
