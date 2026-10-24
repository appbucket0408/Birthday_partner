import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_strings.dart';

/// Opens [url] in the browser; a snackbar if nothing can handle it.
Future<void> openLink(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  final opened = await launchUrl(
    Uri.parse(url),
    mode: LaunchMode.externalApplication,
  ).catchError((_) => false);
  if (!opened) {
    messenger.showSnackBar(
      const SnackBar(content: Text(AppStrings.linkOpenFailed)),
    );
  }
}
