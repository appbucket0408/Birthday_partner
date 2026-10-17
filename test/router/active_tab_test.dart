import 'package:birthday_app/router/active_tab.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('fires when its tab comes back, never on first show',
      (tester) async {
    var shown = 0;
    Future<void> at(int index) => tester.pumpWidget(
          ActiveTab(
            index: index,
            child: RefreshWhenShown(
              tab: 1,
              onShown: (_) => shown++,
              child: const SizedBox(),
            ),
          ),
        );

    await at(1); // first build: loads on its own
    expect(shown, 0);

    await at(0); // user leaves
    expect(shown, 0);

    await at(1); // and comes back
    expect(shown, 1);

    await at(1); // a rebuild while showing is not a return
    expect(shown, 1);

    await at(2);
    await at(1);
    expect(shown, 2);
  });

  testWidgets('does nothing outside the tab shell', (tester) async {
    var shown = 0;
    await tester.pumpWidget(
      RefreshWhenShown(tab: 1, onShown: (_) => shown++, child: const SizedBox()),
    );
    expect(shown, 0);
  });
}
