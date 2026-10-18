import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'api/api_client.dart';
import 'core/app_colors.dart';
import 'core/app_strings.dart';
import 'repositories/auth_repository.dart';
import 'repositories/auth_repository_impl.dart';
import 'repositories/avatar_repository.dart';
import 'repositories/avatar_repository_impl.dart';
import 'repositories/gift_interest_repository.dart';
import 'repositories/gift_interest_repository_impl.dart';
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
import 'repositories/wish_repository.dart';
import 'repositories/wish_repository_impl.dart';
import 'router/app_router.dart';
import 'router/deep_link.dart';
import 'router/session_cubit.dart';

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
  late final ProfileRepository _profile =
      ProfileRepositoryImpl(ApiClient.instance);
  late final GraphRepository _graph = GraphRepositoryImpl(ApiClient.instance);
  late final GiftRepository _gift = GiftRepositoryImpl(ApiClient.instance);
  late final GiftInterestRepository _giftInterest =
      GiftInterestRepositoryImpl(ApiClient.instance);
  late final PushRepository _push =
      PushRepositoryImpl(ApiClient.instance, FirebaseMessaging.instance);
  late final SessionCubit _session = SessionCubit(_auth)..load();
  late final _router = buildRouter(_session);
  late final StreamSubscription<String> _tapSub;

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

  @override
  void dispose() {
    _tapSub.cancel();
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
        RepositoryProvider<ProfileRepository>.value(value: _profile),
        RepositoryProvider<GraphRepository>.value(value: _graph),
        RepositoryProvider<GiftRepository>.value(value: _gift),
        RepositoryProvider<GiftInterestRepository>.value(
          value: _giftInterest,
        ),
        RepositoryProvider<PushRepository>.value(value: _push),
      ],
      child: BlocProvider.value(
        value: _session,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          title: AppStrings.appName,
          theme: ThemeData(colorScheme: AppColors.light(), useMaterial3: true),
          darkTheme:
              ThemeData(colorScheme: AppColors.dark(), useMaterial3: true),
          routerConfig: _router,
        ),
      ),
    );
  }
}
