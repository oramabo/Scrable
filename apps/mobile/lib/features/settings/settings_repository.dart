import '../../core/storage/json_store.dart';
import 'settings_model.dart';

abstract class SettingsRepository {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
}

class JsonSettingsRepository implements SettingsRepository {
  JsonSettingsRepository(this.store, {this.key = 'settings'});

  final JsonStore store;
  final String key;

  @override
  Future<AppSettings> load() async {
    final j = await store.read(key);
    return j == null ? const AppSettings() : AppSettings.fromJson(j);
  }

  @override
  Future<void> save(AppSettings settings) => store.write(key, settings.toJson());
}
