import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/server_profile.dart';
import '../services/secure_storage.dart';

/// Controller for managing multiple Navidrome server profiles.
///
/// This controller uses [SecureStorage] to persist the list of profiles and the active profile ID.
class ServerProfilesController extends ChangeNotifier {
  late final Future<void> _loadFuture;

  ServerProfilesController() {
    _loadFuture = _load();
  }

  Future<void> ensureLoaded() => _loadFuture;

  static const _kProfilesKey = 'crotowave.server_profiles';
  static const _kActiveProfileIdKey = 'crotowave.active_profile_id';

  final _profiles = <ServerProfile>[];
  String? _activeProfileId;

  List<ServerProfile> get profiles => List.unmodifiable(_profiles);
  String? get activeProfileId => _activeProfileId;

  ServerProfile? get activeProfile {
    if (_activeProfileId == null) return null;
    return _profiles.firstWhere(
      (p) => p.id == _activeProfileId,
      orElse: () =>
          throw StateError('Active profile not found: $_activeProfileId'),
    );
  }

  /// Adds a new profile and sets it as active.
  Future<void> addProfile(ServerProfile profile) async {
    _profiles.add(profile);
    _activeProfileId = profile.id;
    await _save();
    notifyListeners();
  }

  /// Updates an existing profile. If the updated profile is the active one, notifications are sent.
  Future<void> updateProfile(ServerProfile profile) async {
    final index = _profiles.indexWhere((p) => p.id == profile.id);
    if (index == -1) {
      throw StateError('Profile not found: ${profile.id}');
    }
    _profiles[index] = profile;
    await _save();
    notifyListeners();
  }

  /// Removes a profile. If the removed profile was active, clears the active profile.
  Future<void> removeProfile(String profileId) async {
    final index = _profiles.indexWhere((p) => p.id == profileId);
    if (index == -1) return;

    _profiles.removeAt(index);
    if (_activeProfileId == profileId) {
      _activeProfileId = null;
    }
    await _save();
    notifyListeners();
  }

  /// Sets the active profile by ID.
  Future<void> setActiveProfile(String profileId) async {
    if (!_profiles.any((p) => p.id == profileId)) {
      throw StateError('Profile not found: $profileId');
    }
    _activeProfileId = profileId;
    await _save();
    notifyListeners();
  }

  /// Loads profiles and active profile ID from secure storage.
  Future<void> _load() async {
    try {
      bool hasProfiles = false;
      final profilesJson = await SecureStorage.secureRead(_kProfilesKey);
      if (profilesJson != null) {
        final List<dynamic> decoded = jsonDecode(profilesJson);
        if (decoded.isNotEmpty) {
          _profiles.clear();
          _profiles.addAll(decoded
              .map((e) => ServerProfile.fromJson(e as Map<String, dynamic>)));
          hasProfiles = true;
        }
      }

      final activeId = await SecureStorage.secureRead(_kActiveProfileIdKey);
      _activeProfileId = activeId;

      // Migration from old single-credential system
      if (!hasProfiles) {
        final legacy = await SecureStorage.getAll();
        if (legacy.serverUrl != null &&
            legacy.username != null &&
            legacy.password != null) {
          final profile = ServerProfile(
            url: legacy.serverUrl!,
            username: legacy.username!,
            password: legacy.password!,
            nickname: 'Mi Servidor',
          );
          _profiles.add(profile);
          _activeProfileId = profile.id;
          await _save();
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to load server profiles: $e');
      }
    }
    notifyListeners();
  }

  /// Saves profiles and active profile ID to secure storage.
  Future<void> _save() async {
    try {
      final profilesJson =
          jsonEncode(_profiles.map((p) => p.toJson()).toList());
      await SecureStorage.secureWrite(_kProfilesKey, profilesJson);
      if (_activeProfileId != null) {
        await SecureStorage.secureWrite(
            _kActiveProfileIdKey, _activeProfileId!);
      } else {
        await SecureStorage.secureDelete(_kActiveProfileIdKey);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to save server profiles: $e');
      }
    }
  }

  /// Clears all profiles and the active profile (used for full reset).
  Future<void> clear() async {
    _profiles.clear();
    _activeProfileId = null;
    await SecureStorage.secureDelete(_kProfilesKey);
    await SecureStorage.secureDelete(_kActiveProfileIdKey);
    notifyListeners();
  }

  /// Disconnects the current active profile without deleting it.
  Future<void> logout() async {
    _activeProfileId = null;
    await SecureStorage.secureDelete(_kActiveProfileIdKey);
    notifyListeners();
  }
}

/// Extension on SecureStorage to support String get/set.
