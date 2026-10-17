import 'package:flutter/widgets.dart';

/// Which bottom-bar tab is showing, published by `HomeShell`.
///
/// The tabs live in an IndexedStack, so a tab's state survives while another
/// is on screen -- which also means it never notices that something changed
/// elsewhere (someone added or removed on the Dashboard). [RefreshWhenShown]
/// listens to this to catch the moment its tab comes back.
class ActiveTab extends InheritedWidget {
  const ActiveTab({super.key, required this.index, required super.child});

  final int index;

  static int? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ActiveTab>()?.index;

  @override
  bool updateShouldNotify(ActiveTab oldWidget) => oldWidget.index != index;
}

/// Calls [onShown] each time tab [tab] becomes the active one again -- not
/// on its first build, which loads on its own. Does nothing outside the
/// shell (a test, or a route opened full screen).
class RefreshWhenShown extends StatefulWidget {
  const RefreshWhenShown({
    super.key,
    required this.tab,
    required this.onShown,
    required this.child,
  });

  final int tab;
  final void Function(BuildContext context) onShown;
  final Widget child;

  @override
  State<RefreshWhenShown> createState() => _RefreshWhenShownState();
}

class _RefreshWhenShownState extends State<RefreshWhenShown> {
  bool? _wasActive;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = ActiveTab.maybeOf(context);
    if (active == null) return;
    final isActive = active == widget.tab;
    if (_wasActive == false && isActive) widget.onShown(context);
    _wasActive = isActive;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
