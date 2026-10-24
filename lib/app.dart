import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'api/api_client.dart';
import 'core/analytics.dart';
import 'core/app_theme.dart';
import 'core/app_strings.dart';
import 'features/force_update/force_update_cubit.dart';
import 'features/force_update/force_update_screen.dart';
import 'features/force_update/soft_update_dialog.dart';
import 'repositories/app_update_repository.dart';
import 'repositories/app_update_repository_impl.dart';
import 'repositories/auth_repository.dart';
import 'repositories/auth_repository_impl.dart';
import 'repositories/avatar_repository.dart';
import 'repositories/avatar_repository_impl.dart';
import 'repositories/gift_interest_repository.dart';
import 'repositories/gift_interest_repository_impl.dart';
import 'repositories/notification_repository.dart';
import 'repositories/notification_repository_impl.dart';
import 'features/notifications/notification_badge_cubit.dart';
import 'repositories/gift_repository.dart';
import 'repositories/gift_repository_impl.dart';
import 'repositories/graph_repository.dart';
import 'repositories/graph_repository_impl.dart';
import 'repositories/person_repository.dart';
import 'repositories/person_repository_impl.dart';
import 'repositories/profile_repository.dart';
import 'repositories/push_repository.dart';
import 'repositories/push_repository_impl.dart';
import 'repositories/profile_repository_impl.dart';
import 'repositories/moderation_repository.dart';
import 'repositories/moderation_repository_impl.dart';
import 'repositories/wish_repository.dart';
import 'repositories/wish_repository_impl.dart';
import 'router/app_router.dart';
import 'router/deep_link.dart';
import 'router/session_cubit.dart';
import 'router/session_state.dart';

class BirthdayApp extends StatefulWidget {
  const BirthdayApp({super.key});

  @override
  State<BirthdayApp> createState() => _BirthdayAppState();
}

class _BirthdayAppState extends State<BirthdayApp> {
  late final AuthRepository _auth = AuthRepositoryImpl(ApiClient.instance);
  late final AvatarRepository _avatar =
      AvatarRepositoryImpl(ApiClient.instance);
  late final PersonRepository _person =
      PersonRepositoryImpl(ApiClient.instance);
  late final WishRepository _wish = WishRepositoryImpl(ApiClient.instance);
  late final ModerationRepository _moderation =
      ModerationRepositoryImpl(ApiClient.instance);
  late final ProfileRepository _profile =
      ProfileRepositoryImpl(ApiClient.instance);
  late final GraphRepository _graph = GraphRepositoryImpl(ApiClient.instance);
  late final GiftRepository _gift = GiftRepositoryImpl(ApiClient.instance);
  late final GiftInterestRepository _giftInterest =
      GiftInterestRepositoryImpl(ApiClient.instance);
  late final PushRepository _push =
      PushRepositoryImpl(ApiClient.instance, FirebaseMessaging.instance);
  late final NotificationRepository _notifications =
      NotificationRepositoryImpl(ApiClient.instance);
  // App-level, not in HomeShell: the bell lives in the tabs, but the
  // Notifications screen that clears it is a route above them.
  late final NotificationBadgeCubit _badge =
      NotificationBadgeCubit(_notifications);
  late final SessionCubit _session = SessionCubit(_auth)..load();
  // Checked alongside the session load, not before it: launch never waits
  // on Remote Config.
  late final ForceUpdateCubit _forceUpdate = ForceUpdateCubit(
    AppUpdateRepositoryImpl(FirebaseRemoteConfig.instance),
  )..check();
  late final _router = buildRouter(
    _session,
    observers: Analytics.navigatorObservers,
  );
  late final StreamSubscription<String> _tapSub;
  late final StreamSubscription<SessionState> _userSub;

  @override
  void initState() {
    super.initState();
    // A tap that launched the app from terminated happened before anything
    // could subscribe, so it is fetched rather than listened for -- and then
    // held until the session resolves. Navigating the moment it arrives
    // loses it: the session is still SessionUnknown, and the router bounces
    // everything but '/splash' there, then on to '/feed'.
    unawaited(_openInitialRoute());
    _tapSub = _push.notificationRoutes.listen((r) {
      if (mounted) _router.go(r);
    });
    _userSub = _session.stream.listen((s) {
      if (s is SessionReady) {
        Analytics.identify(
          AnalyticsUser.fromProfile(
            s.profile,
            phone: ApiClient.instance.auth.currentUser?.phone,
          ),
        ).ignore();
      }
      if (s is SessionSignedOut) Analytics.clearUser().ignore();
    });
  }

  /// Split out of initState so the await is expressible; see
  /// [navigateWhenSessionResolves] for why it must not navigate immediately.
  Future<void> _openInitialRoute() async {
    final route = await _push.initialRoute();
    if (route == null) return;
    await navigateWhenSessionResolves(
      route: route,
      session: _session,
      go: (r) {
        if (mounted) _router.go(r);
      },
    );
  }

  /// The optional-update prompt. Shown on the router's navigator: this
  /// widget sits above it, so its own context has no Navigator to push on.
  Future<void> _offerUpdate() async {
    final context = _router.routerDelegate.navigatorKey.currentContext;
    if (context == null) return;
    if (await showSoftUpdateDialog(context)) {
      await _forceUpdate.openStore();
    } else {
      await _forceUpdate.later();
    }
  }

  @override
  void dispose() {
    _tapSub.cancel();
    _userSub.cancel();
    _badge.close();
    _forceUpdate.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AuthRepository>.value(value: _auth),
        RepositoryProvider<AvatarRepository>.value(value: _avatar),
        RepositoryProvider<PersonRepository>.value(value: _person),
        RepositoryProvider<WishRepository>.value(value: _wish),
        RepositoryProvider<ModerationRepository>.value(value: _moderation),
        RepositoryProvider<ProfileRepository>.value(value: _profile),
        RepositoryProvider<GraphRepository>.value(value: _graph),
        RepositoryProvider<GiftRepository>.value(value: _gift),
        RepositoryProvider<GiftInterestRepository>.value(
          value: _giftInterest,
        ),
        RepositoryProvider<PushRepository>.value(value: _push),
        RepositoryProvider<NotificationRepository>.value(
          value: _notifications,
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: _session),
          BlocProvider.value(value: _badge),
          BlocProvider.value(value: _forceUpdate),
        ],
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          title: AppStrings.appName,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          routerConfig: _router,
          // Above the router, so no route, deep link or push tap gets past it.
          builder: (context, child) =>
              BlocConsumer<ForceUpdateCubit, UpdateStatus>(
            listenWhen: (prev, next) =>
                next == UpdateStatus.optional && prev != next,
            listener: (_, __) => unawaited(_offerUpdate()),
            builder: (context, status) => status == UpdateStatus.required
                ? const ForceUpdateScreen()
                : child!,
          ),
        ),
      ),
    );
  }
}
