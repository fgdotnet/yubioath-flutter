/*
 * Copyright (C) 2022-2025 Yubico.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *       http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/models.dart';
import '../app/state.dart';
import '../core/state.dart';
import '../management/models.dart';
import 'app_methods.dart';
import 'devices.dart';
import 'models.dart';

const _contextChannel = MethodChannel('android.state.appContext');

final androidAllowScreenshotsProvider =
    StateNotifierProvider<AllowScreenshotsNotifier, bool>(
      (ref) => AllowScreenshotsNotifier(),
    );

class DeviceInfoComparator {
  /// Compares two instances of DeviceInfo and determines whether they
  /// belong the the same physical device.
  static bool customCompare(DeviceInfo? prev, DeviceInfo? next) {
    if (prev != null && next != null) {
      if (prev.serial == null && next.serial == null) {
        // compare without config
        final simpleConfig = DeviceConfig({}, 0, 0, 0);
        return next.copyWith(config: simpleConfig) ==
            prev.copyWith(config: simpleConfig);
      } else {
        // serial number based comparison
        return prev.serial == next.serial;
      }
    }
    return prev == null && next == null;
  }
}

class AllowScreenshotsNotifier extends StateNotifier<bool> {
  AllowScreenshotsNotifier() : super(false);

  void setAllowScreenshots(bool value) async {
    final result = await appMethodsChannel.invokeMethod(
      'allowScreenshots',
      value,
    );
    if (mounted) {
      state = result;
    }
  }
}

final androidClipboardProvider = Provider<AppClipboard>(
  (ref) => _AndroidClipboard(ref),
);

class _AndroidClipboard extends AppClipboard {
  final Ref<AppClipboard> _ref;

  const _AndroidClipboard(this._ref);

  @override
  bool platformGivesFeedback() {
    return _ref.read(androidSdkVersionProvider) >= 33;
  }

  @override
  Future<void> setText(String toClipboard, {bool isSensitive = false}) async {
    await setPrimaryClip(toClipboard, isSensitive);
  }
}

class NfcAdapterState extends StateNotifier<bool> {
  NfcAdapterState() : super(false);

  void enable(bool value) {
    state = value;
  }
}

enum NfcState {
  disabled,
  idle,
  ongoing,
  success,
  failure,
  usbActivityOngoing,
  usbActivitySuccess,
  usbActivityFailure,
}

class NfcStateNotifier extends StateNotifier<NfcState> {
  NfcStateNotifier() : super(NfcState.disabled);

  void set(int stateValue) {
    var newState = switch (stateValue) {
      0 => NfcState.disabled,
      1 => NfcState.idle,
      2 => NfcState.ongoing,
      3 => NfcState.success,
      4 => NfcState.failure,
      5 => NfcState.usbActivityOngoing,
      6 => NfcState.usbActivitySuccess,
      7 => NfcState.usbActivityFailure,
      _ => NfcState.disabled,
    };

    state = newState;
  }
}

final androidSectionPriority = Provider<List<Section>>((ref) => []);

final androidSdkVersionProvider = Provider<int>((ref) => -1);

final androidNfcSupportProvider = Provider<bool>((ref) => false);

final androidNfcAdapterState = StateNotifierProvider<NfcAdapterState, bool>(
  (ref) => NfcAdapterState(),
);

final androidNfcState = StateNotifierProvider<NfcStateNotifier, NfcState>(
  (ref) => NfcStateNotifier(),
);

final androidSupportedThemesProvider = StateProvider<List<ThemeMode>>((ref) {
  if (ref.read(androidSdkVersionProvider) < 29) {
    // the user can select from light or dark theme of the app
    return [ThemeMode.light, ThemeMode.dark];
  } else {
    // the user can also select system theme on newer Android versions
    return ThemeMode.values;
  }
});

class AndroidAppContextHandler {
  Future<void> switchAppContext(Section section) async {
    await _contextChannel.invokeMethod('setContext', {'index': section.index});
  }
}

final androidAppContextHandler = Provider<AndroidAppContextHandler>(
  (ref) => AndroidAppContextHandler(),
);

final androidCurrentSectionNotifierProvider = Provider(
  (ref) => AndroidCurrentSectionNotifier(
    ref.watch(androidAppContextHandler),
    ref.watch(prefProvider),
    ref.watch(supportedSectionsProvider),
  ),
);

CurrentSectionNotifier androidCurrentSectionNotifier(Ref ref) {
  return ref.read(androidCurrentSectionNotifierProvider);
}

class AndroidCurrentSectionNotifier extends CurrentSectionNotifier {
  final AndroidAppContextHandler _appContextHandler;
  final SharedPreferences _prefs;

  static const String _key = 'APP_STATE_LAST_SECTION';

  AndroidCurrentSectionNotifier(
    this._appContextHandler,
    this._prefs,
    final List<Section> supportedSections,
  ) : super(_fromName(_prefs.getString(_key), supportedSections));

  @override
  void setCurrentSection(Section section, {bool notify = true}) {
    if (section != Section.home) {
      _prefs.setString(_key, section.name);
    }
    if (notify) {
      _appContextHandler.switchAppContext(section);
    }
    state = section;
  }

  static Section _fromName(String? name, List<Section> supportedSections) =>
      supportedSections.firstWhere(
        (element) => element.name == name,
        orElse: () => supportedSections.first,
      );
}

class AndroidAttachedDevicesNotifier extends AttachedDevicesNotifier {
  @override
  List<DeviceNode> build() => ref
      .watch(androidDeviceDataProvider)
      .maybeWhen(data: (data) => [data.node], orElse: () => []);
}

final androidDeviceDataProvider = Provider<AsyncValue<YubiKeyData>>((ref) {
  return ref
      .watch(androidYubikeyProvider)
      .when(
        data: (d) {
          if (d.name == 'restricted-nfc' ||
              d.name == 'unknown-device' ||
              d.name == 'no-scp11b-nfc-support') {
            return AsyncError(d.name, StackTrace.current);
          }
          return AsyncData(d);
        },
        error: (Object error, StackTrace stackTrace) {
          return AsyncError(error, stackTrace);
        },
        loading: () {
          return const AsyncLoading();
        },
      );
});

class AndroidCurrentDeviceNotifier extends CurrentDeviceNotifier {
  @override
  DeviceNode? build() =>
      ref.watch(androidYubikeyProvider).whenOrNull(data: (data) => data.node);

  @override
  setCurrentDevice(DeviceNode? device) {
    state = device;
  }
}

final androidNfcTapActionProvider =
    StateNotifierProvider<NfcTapActionNotifier, NfcTapAction>(
      (ref) => NfcTapActionNotifier(ref.watch(prefProvider)),
    );

class NfcTapActionNotifier extends StateNotifier<NfcTapAction> {
  static const _prefNfcOpenApp = 'prefNfcOpenApp';
  static const _prefNfcCopyOtp = 'prefNfcCopyOtp';
  final SharedPreferences _prefs;

  NfcTapActionNotifier._(this._prefs, super._state);

  factory NfcTapActionNotifier(SharedPreferences prefs) {
    final launchApp = prefs.getBool(_prefNfcOpenApp) ?? true;
    final copyOtp = prefs.getBool(_prefNfcCopyOtp) ?? false;
    final NfcTapAction action;
    if (launchApp && copyOtp) {
      action = NfcTapAction.launchAndCopy;
    } else if (copyOtp) {
      action = NfcTapAction.copy;
    } else if (launchApp) {
      action = NfcTapAction.launch;
    } else {
      action = NfcTapAction.noAction;
    }
    return NfcTapActionNotifier._(prefs, action);
  }

  Future<void> setTapAction(NfcTapAction value) async {
    if (state != value) {
      state = value;
      await _prefs.setBool(
        _prefNfcOpenApp,
        value == NfcTapAction.launch || value == NfcTapAction.launchAndCopy,
      );
      await _prefs.setBool(
        _prefNfcCopyOtp,
        value == NfcTapAction.copy || value == NfcTapAction.launchAndCopy,
      );
    }
  }
}

// TODO: Get these from Android
final androidNfcSupportedKbdLayoutsProvider = Provider<List<String>>(
  (ref) => ['US', 'DE', 'DE-CH'],
);

final androidNfcKbdLayoutProvider =
    StateNotifierProvider<NfcKbdLayoutNotifier, String>(
      (ref) => NfcKbdLayoutNotifier(ref.watch(prefProvider)),
    );

class NfcKbdLayoutNotifier extends StateNotifier<String> {
  static const String _defaultClipKbdLayout = 'US';
  static const _prefClipKbdLayout = 'prefClipKbdLayout';
  final SharedPreferences _prefs;

  NfcKbdLayoutNotifier(this._prefs)
    : super(_prefs.getString(_prefClipKbdLayout) ?? _defaultClipKbdLayout);

  Future<void> setKeyboardLayout(String value) async {
    if (state != value) {
      state = value;
      await _prefs.setString(_prefClipKbdLayout, value);
    }
  }
}

final androidNfcBypassTouchProvider =
    StateNotifierProvider<NfcBypassTouchNotifier, bool>(
      (ref) => NfcBypassTouchNotifier(ref.watch(prefProvider)),
    );

class NfcBypassTouchNotifier extends StateNotifier<bool> {
  static const _prefNfcBypassTouch = 'prefNfcBypassTouch';
  final SharedPreferences _prefs;

  NfcBypassTouchNotifier(this._prefs)
    : super(_prefs.getBool(_prefNfcBypassTouch) ?? false);

  Future<void> setNfcBypassTouch(bool value) async {
    if (state != value) {
      state = value;
      await _prefs.setBool(_prefNfcBypassTouch, value);
    }
  }
}

final androidNfcSilenceSoundsProvider =
    StateNotifierProvider<NfcSilenceSoundsNotifier, bool>(
      (ref) => NfcSilenceSoundsNotifier(ref.watch(prefProvider)),
    );

class NfcSilenceSoundsNotifier extends StateNotifier<bool> {
  static const _prefNfcSilenceSounds = 'prefNfcSilenceSounds';
  final SharedPreferences _prefs;

  NfcSilenceSoundsNotifier(this._prefs)
    : super(_prefs.getBool(_prefNfcSilenceSounds) ?? false);

  Future<void> setNfcSilenceSounds(bool value) async {
    if (state != value) {
      state = value;
      await _prefs.setBool(_prefNfcSilenceSounds, value);
    }
  }
}

final androidUsbLaunchAppProvider =
    StateNotifierProvider<UsbLaunchAppNotifier, bool>(
      (ref) => UsbLaunchAppNotifier(ref.watch(prefProvider)),
    );

class UsbLaunchAppNotifier extends StateNotifier<bool> {
  static const _prefUsbOpenApp = 'prefUsbOpenApp';
  final SharedPreferences _prefs;

  UsbLaunchAppNotifier(this._prefs)
    : super(_prefs.getBool(_prefUsbOpenApp) ?? false);

  Future<void> setUsbLaunchApp(bool value) async {
    if (state != value) {
      state = value;
      await _prefs.setBool(_prefUsbOpenApp, value);
    }
  }
}
