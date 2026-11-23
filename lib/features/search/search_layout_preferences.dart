import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SearchPanelPosition { top, bottom }

abstract interface class SearchPanelPositionStore {
  Future<SearchPanelPosition> read();
  Future<void> write(SearchPanelPosition position);
}

final class SharedPreferencesSearchPanelPositionStore
    implements SearchPanelPositionStore {
  SharedPreferencesSearchPanelPositionStore({
    SharedPreferencesAsync? preferences,
  }) : _preferences = preferences ?? SharedPreferencesAsync();

  static const _key = 'layout.search_panel_position.v1';

  final SharedPreferencesAsync _preferences;

  @override
  Future<SearchPanelPosition> read() async {
    final value = await _preferences.getString(_key);

    return value == SearchPanelPosition.bottom.name
        ? SearchPanelPosition.bottom
        : SearchPanelPosition.top;
  }

  @override
  Future<void> write(SearchPanelPosition position) {
    return _preferences.setString(_key, position.name);
  }
}

final searchPanelPositionStoreProvider = Provider<SearchPanelPositionStore>(
  (ref) => SharedPreferencesSearchPanelPositionStore(),
);
