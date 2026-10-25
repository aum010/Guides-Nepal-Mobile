import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../shared/models/city_update.dart';
import '../experiences/experience_repository.dart';
import '../explore/explore_controller.dart' show kCities;

/// The traveller's "my city": which city's local updates they see on Home.
///
/// Defaults to [kCities.first] (Kathmandu) so Home always resolves to a
/// valid municipal city with zero setup. Persisted in secure storage —
/// like [TokenStorage]'s session values this is a one-line preference, and
/// keeping it here means no second storage channel to manage. The provider
/// never throws: a storage failure just falls back to the default for the
/// session instead of breaking Home.
class HomeCityStore extends StateNotifier<String> {
  HomeCityStore({FlutterSecureStorage? storage, String? initial})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            ),
        super(initial ?? kCities.first) {
    _restore();
  }

  static const _kHomeCity = 'gn_home_city';

  final FlutterSecureStorage _storage;

  Future<void> _restore() async {
    try {
      final saved = await _storage.read(key: _kHomeCity);
      if (saved != null && kCities.contains(saved)) {
        state = saved;
      }
    } on Exception {
      // Best effort only — keep the default.
    }
  }

  Future<void> setCity(String city) async {
    if (!kCities.contains(city) || city == state) return;
    state = city;
    try {
      await _storage.write(key: _kHomeCity, value: city);
    } on Exception {
      // Preference persistence is non-critical.
    }
  }
}

final homeCityProvider = StateNotifierProvider<HomeCityStore, String>(
  (ref) => HomeCityStore(),
);

/// Home feed key, differentiated per city so Riverpod caches each city's
/// feed independently and a city flip re-fetches without a manual reload.
final cityUpdatesFeedProvider = FutureProvider.autoDispose
    .family<List<CityUpdate>, String>((ref, city) {
  return ref.watch(experienceRepositoryProvider).fetchCityUpdates(city);
});