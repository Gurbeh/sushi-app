import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/screens/home_screen.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout_model.dart';
import 'package:fladder/util/poster_defaults.dart';
import 'package:fladder/widgets/shared/focus_row.dart';

Widget _tvHost({required Widget child}) {
  return MaterialApp(
    home: AdaptiveLayout(
      data: const AdaptiveLayoutModel(
        viewSize: ViewSize.television,
        layoutMode: LayoutMode.dual,
        inputDevice: InputDevice.dPad,
        platform: TargetPlatform.android,
        isDesktop: false,
        posterDefaults: PosterDefaults(size: 350, ratio: 0.55),
        controller: <HomeTabs, ScrollController>{},
        sideBarWidth: 80,
        topBarHeight: 0,
      ),
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('d-pad down leaves FocusRow for the widget below', (tester) async {
    await tester.pumpWidget(
      _tvHost(
        child: Column(
          children: [
            FocusRow(
              child: FilledButton(
                autofocus: true,
                onPressed: () {},
                child: const Text('Play'),
              ),
            ),
            const SizedBox(height: 48),
            FilledButton(
              onPressed: () {},
              child: const Text('Episodes'),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(Focus.of(tester.element(find.text('Play'))).hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(
      Focus.of(tester.element(find.text('Episodes'))).hasPrimaryFocus,
      isTrue,
      reason: 'down from the action row must reach content below',
    );
  });

  testWidgets('d-pad down inside a Wrap moves to the next visual row first', (tester) async {
    await tester.pumpWidget(
      _tvHost(
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 220,
            child: FocusRow(
              child: Wrap(
                spacing: 8,
                runSpacing: 24,
                children: [
                  for (final label in ['Play', 'Audio', 'Follow', 'More'])
                    SizedBox(
                      width: 100,
                      height: 40,
                      child: FilledButton(
                        autofocus: label == 'Play',
                        onPressed: () {},
                        child: Text(label),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(Focus.of(tester.element(find.text('Play'))).hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(Focus.of(tester.element(find.text('Follow'))).hasPrimaryFocus, isTrue);
  });
}
