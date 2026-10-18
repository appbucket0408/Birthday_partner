import 'session_cubit.dart';
import 'session_state.dart';
Future<void> navigateWhenSessionResolves({
  required String route,
  required SessionCubit session,
  required void Function(String route) go,
}) async {
  if (session.state is! SessionUnknown) {
    go(route);
    return;
  }
  await session.stream.firstWhere((s) => s is! SessionUnknown);
  go(route);
}
