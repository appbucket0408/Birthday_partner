import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logger.dart';
import '../../models/birthday.dart';

/// Days until the user's own birthday while the share-your-wall card shows,
/// or null when it is hidden.
class WallPromptCubit extends Cubit<int?> {
  WallPromptCubit({
    required Birthday? birthday,
    DateTime Function()? now,
  })  : _birthday = birthday,
        _now = now ?? DateTime.now,
        super(null);

  static const dismissedPref = 'wall_prompt_dismissed';

  final Birthday? _birthday;
  final DateTime Function() _now;

  /// Two prompts per birthday: from 7 days out, and again from 3.
  String? _stageKey() {
    final birthday = _birthday;
    if (birthday == null) return null;
    final days = _daysLeft(birthday);
    if (days > 7) return null;
    final next = birthday.nextOccurrence(_now());
    return '${next.year}-${days <= 3 ? 3 : 7}';
  }

  int _daysLeft(Birthday birthday) {
    final now = _now();
    final today = DateTime(now.year, now.month, now.day);
    return birthday.nextOccurrence(now).difference(today).inDays;
  }

  Future<void> load() async {
    final key = _stageKey();
    if (key == null) return emit(null);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(dismissedPref) == key) return emit(null);
    } catch (e, s) {
      Log.error('wall prompt read failed', e, s);
    }
    if (!isClosed) emit(_daysLeft(_birthday!));
  }

  /// Closed or shared: hidden until the next stage.
  Future<void> dismiss() async {
    final key = _stageKey();
    emit(null);
    if (key == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(dismissedPref, key);
    } catch (e, s) {
      Log.error('wall prompt write failed', e, s);
    }
  }
}
