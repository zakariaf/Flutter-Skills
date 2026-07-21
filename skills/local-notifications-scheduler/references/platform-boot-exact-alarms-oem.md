# Platform: boot re-arm, exact alarms, OEM survival

The honest per-platform reliability story. **App-foreground reconcile is the guaranteed path; everything below is best-effort.** With no server push there is no way to learn a reminder was dropped except the next foreground reconcile diff. Do not collapse the two platforms into one mechanism — that reasoning is factually wrong.

## Per-platform reboot re-arm

- **Android:** `BOOT_COMPLETED` fires **post-unlock** (not direct-boot). The plugin's `ScheduledNotificationBootReceiver` rehydrates pending notifications; the app-open reconcile corrects drift. Also handle `QUICKBOOT_POWERON` (some OEM ROMs). If the DB is encrypted, its key must be readable at the accessibility level the receiver-equivalent flow needs (e.g. after-first-unlock).
- **iOS:** the app runs **no boot code**. Scheduled notifications persist in the OS across reboot; re-arm happens **only on next foreground**. iOS has no OEM-killer problem, but the 64-cap is silent and permission is provisional — a wholly different survival story.

## Exact-alarm strategy

```dart
final androidImpl = plugin.resolvePlatformSpecificImplementation<
    AndroidFlutterLocalNotificationsPlugin>();
final canExact = await androidImpl?.canScheduleExactAlarms() ?? false;
final mode = canExact
    ? AndroidScheduleMode.exactAllowWhileIdle
    : AndroidScheduleMode.inexactAllowWhileIdle; // day-granular default
```

- Default is `inexactAllowWhileIdle` — permission-free and pierces Doze at day granularity.
- `SCHEDULE_EXACT_ALARM` is **user-revocable, NOT pre-granted on Android 13+ fresh installs, and denied after a backup-restore**. When revoked the plugin logs an error and exact reminders silently stop. Re-check on resume and reconcile with silent fallback to inexact. Re-request only from an explicit "precise reminders" opt-in, never silently.
- **Never** declare `USE_EXACT_ALARM`. It is auto-granted and non-revocable, but Google Play restricts it to alarm-clock/timer/calendar apps; declaring it elsewhere risks rejection.

## Android manifest & Gradle (survival prerequisites)

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/> <!-- optional opt-in -->
<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"/>
<!-- NEVER: android.permission.USE_EXACT_ALARM -->

<receiver android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
  <intent-filter>
    <action android:name="android.intent.action.BOOT_COMPLETED"/>
    <action android:name="android.intent.action.QUICKBOOT_POWERON"/>
  </intent-filter>
</receiver>
```

```gradle
android {
  compileSdk 35
  compileOptions { coreLibraryDesugaringEnabled true }  // REQUIRED or scheduling silently breaks
}
dependencies { coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4' }  // pin exact — never '2.+'; match the minimum from the FLN changelog
```

`coreLibraryDesugaringEnabled` is mandatory — omit it and the Android build fails or scheduled notifications silently break. Current FLN majors also need a recent AGP, Java 17, and compileSdk 35+; check the plugin's changelog for exact minimums.

## Background tick

Android-only, best-effort daily re-projection tick (e.g. WorkManager). **Not a delivery guarantee** — iOS `BGTaskScheduler` is opportunistic and frequently never runs; aggressive OEMs throttle the periodic job. It only re-triggers a reconcile when the app cannot come to foreground; it never replaces the foreground reconcile.

## Background isolate & tap handling

The `@pragma('vm:entry-point')` tap/action handler runs in a **separate isolate with no main-isolate state**. Do NOT write to the DB from it — concurrent access from two isolates risks corruption. Record a lightweight pending-action intent (or nothing) and act on the next foreground reconcile. Build any in-isolate infrastructure via plain top-level factory functions, with any key/config passed in from the main isolate. A tap payload must be a serializable string that maps to a `go_router` location reconstructed from the DB — never a non-serializable `extra`.

## OEM survival matrix (manual, never faked)

OEM battery-killers drop AlarmManager alarms, block the boot receiver, and kill background jobs. This **cannot be fully fixed in code** — autostart/battery exemption on some ROMs is user-settings-only. The only durable mitigation is guiding the user to the right settings screen. Foreground reconcile is the only dependable recovery.

| OEM family | Manufacturer strings | Guidance |
| --- | --- | --- |
| Xiaomi / MIUI | xiaomi, redmi, poco | autostart intent; text fallback + `openAppSettings()` |
| Huawei / EMUI | huawei, honor | protected-app / app-launch manager |
| OPPO / OnePlus / ColorOS | oppo, realme, oneplus | autostart copy; no reliable intent |
| Samsung | samsung | "Sleeping apps" / battery-usage copy |
| Stock / AOSP | others | the battery-optimization dialog is enough |

- Deep-link intents to OEM settings screens are version-fragile — **always** ship a localized text fallback and wrap the launch in try/catch degrading to `openAppSettings()` plus a pointer to `dontkillmyapp.com`.
- Battery-exemption granted ≠ background guaranteed; some OEMs re-enable optimization after an OS update. Re-surface a gentle nudge when the foreground reconcile diff suggests reminders were missed.
- **Emulators lie about survival.** Reboot/Doze/OEM-killer behavior is green-lit only on the real device matrix (Xiaomi/MIUI, Huawei, Samsung, OnePlus × battery-optimization ON/OFF × killed-from-recents × after reboot × after 24 h idle). Track "fired vs expected" during dogfooding as the real reliability metric.
