import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/sushi/sushi_app_update.dart';
import 'package:fladder/sushi/sushi_app_update_pb.dart';

void main() {
  tearDown(() {
    sushiLatestApp.value = null;
  });

  test('sushiUpdateHomeRouteName matches generated DashboardRoute', () {
    expect(sushiUpdateHomeRouteName, DashboardRoute.name);
  });

  test('sushiIsUpdateHomeRoute is dashboard only', () {
    expect(sushiIsUpdateHomeRoute('DashboardRoute'), isTrue);
    expect(sushiIsUpdateHomeRoute(DetailsRoute.name), isFalse);
    expect(sushiIsUpdateHomeRoute(FavouritesRoute.name), isFalse);
    expect(sushiIsUpdateHomeRoute(null), isFalse);
    expect(sushiIsUpdateHomeRoute(''), isFalse);
  });

  test('sushiShouldRecheckUpdateOnResume needs a long enough pause', () {
    final now = DateTime.utc(2026, 9, 16, 12);
    expect(
      sushiShouldRecheckUpdateOnResume(pausedAt: null, now: now),
      isFalse,
    );
    expect(
      sushiShouldRecheckUpdateOnResume(
        pausedAt: now.subtract(const Duration(minutes: 4, seconds: 59)),
        now: now,
      ),
      isFalse,
    );
    expect(
      sushiShouldRecheckUpdateOnResume(
        pausedAt: now.subtract(sushiUpdateResumeRecheckAfter),
        now: now,
      ),
      isTrue,
    );
    expect(
      sushiShouldRecheckUpdateOnResume(
        pausedAt: now.subtract(const Duration(hours: 2)),
        now: now,
      ),
      isTrue,
    );
  });

  test('sushiShouldOfferUpdate skips a version the user dismissed', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    sushiNoteLatestApp(const SushiLatestApp(platform: 'android_tv', version: '2.0.0'));

    expect(await sushiShouldOfferUpdate(currentVersion: '1.9.0', prefs: prefs), isTrue);

    await sushiSkipAppVersion(prefs, '2.0.0');
    expect(await sushiShouldOfferUpdate(currentVersion: '1.9.0', prefs: prefs), isFalse);

    sushiNoteLatestApp(const SushiLatestApp(platform: 'android_tv', version: '2.1.0'));
    expect(await sushiShouldOfferUpdate(currentVersion: '1.9.0', prefs: prefs), isTrue);
  });
}
