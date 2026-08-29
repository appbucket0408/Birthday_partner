import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'api/api_client.dart';
import 'core/app_colors.dart';
import 'core/app_strings.dart';
import 'repositories/auth_repository.dart';
import 'repositories/auth_repository_impl.dart';
import 'repositories/person_repository.dart';
import 'repositories/person_repository_impl.dart';
import 'router/app_router.dart';
import 'router/session_cubit.dart';

class BirthdayApp extends StatefulWidget {
  const BirthdayApp({super.key});

  @override
  State<BirthdayApp> createState() => _BirthdayAppState();
}

class _BirthdayAppState extends State<BirthdayApp> {
  late final AuthRepository _auth = AuthRepositoryImpl(ApiClient.instance);
  late final PersonRepository _person =
      PersonRepositoryImpl(ApiClient.instance);
  late final SessionCubit _session = SessionCubit(_auth)..load();
  late final _router = buildRouter(_session);

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AuthRepository>.value(value: _auth),
        RepositoryProvider<PersonRepository>.value(value: _person),
      ],
      child: BlocProvider.value(
        value: _session,
        child: MaterialApp.router(
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
