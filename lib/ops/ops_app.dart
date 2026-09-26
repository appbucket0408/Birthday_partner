import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../api/api_client.dart';
import '../core/app_colors.dart';
import '../core/app_strings.dart';
import '../repositories/ops_repository.dart';
import '../repositories/ops_repository_impl.dart';
import '../repositories/staff_auth_repository.dart';
import '../repositories/staff_auth_repository_impl.dart';
import 'ops_router.dart';
import 'signin/signin_cubit.dart';

/// The ops console app. A separate entry point from [BirthdayApp], sharing
/// its models, repositories, colours and strings but none of its routing or
/// session handling.
class OpsApp extends StatefulWidget {
  const OpsApp({super.key});

  @override
  State<OpsApp> createState() => _OpsAppState();
}

class _OpsAppState extends State<OpsApp> {
  // `.value` providers with no `?? ConcreteImpl(...)` fallback, the house
  // rule: a fallback turns a missing registration into a silently different
  // object instead of a loud failure.
  late final StaffAuthRepository _auth =
      StaffAuthRepositoryImpl(ApiClient.instance);
  late final OpsRepository _ops = OpsRepositoryImpl(ApiClient.instance);
  late final SignInCubit _session = SignInCubit(_auth);
  late final _router = buildOpsRouter(_session);

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<StaffAuthRepository>.value(value: _auth),
        RepositoryProvider<OpsRepository>.value(value: _ops),
      ],
      child: BlocProvider.value(
        value: _session,
        child: MaterialApp.router(
          title: AppStrings.opsTitle,
          theme: ThemeData(colorScheme: AppColors.light(), useMaterial3: true),
          darkTheme:
              ThemeData(colorScheme: AppColors.dark(), useMaterial3: true),
          routerConfig: _router,
        ),
      ),
    );
  }
}
