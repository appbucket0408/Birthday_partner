import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_spacing.dart';

/// A 6-digit code shown as six boxes.
///
/// One real [TextField] sits invisibly over the boxes and owns all input, so
/// paste, SMS autofill ([AutofillHints.oneTimeCode]) and backspace behave as
/// in any text field; the boxes only draw [controller]'s text. [onCompleted]
/// fires each time the sixth digit lands.
class CodeField extends StatelessWidget {
  const CodeField({
    super.key,
    required this.controller,
    required this.onCompleted,
    this.fieldKey,
    this.errorText,
    this.enabled = true,
    this.autofocus = true,
  });

  static const length = 6;

  final TextEditingController controller;
  final ValueChanged<String> onCompleted;

  /// Put on the inner [TextField], so a test can `enterText` into it.
  final Key? fieldKey;
  final String? errorText;
  final bool enabled;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          children: [
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                final text = value.text;
                return Row(
                  children: [
                    for (var i = 0; i < length; i++) ...[
                      if (i > 0) const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _Box(
                          digit: i < text.length ? text[i] : '',
                          // The box the next digit goes into.
                          active: enabled && i == text.length,
                          error: errorText != null,
                          scheme: scheme,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
            Positioned.fill(
              child: Opacity(
                opacity: 0,
                child: TextField(
                  key: fieldKey,
                  controller: controller,
                  enabled: enabled,
                  autofocus: autofocus,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  showCursor: false,
                  enableInteractiveSelection: false,
                  maxLength: length,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    counterText: '',
                    border: InputBorder.none,
                  ),
                  onChanged: (v) {
                    if (v.length == length) onCompleted(v);
                  },
                ),
              ),
            ),
          ],
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              errorText!,
              key: const Key('code_error'),
              style: TextStyle(color: scheme.error),
            ),
          ),
      ],
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({
    required this.digit,
    required this.active,
    required this.error,
    required this.scheme,
  });

  final String digit;
  final bool active;
  final bool error;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final color = error
        ? scheme.error
        : active
            ? scheme.primary
            : scheme.outlineVariant;
    return AspectRatio(
      aspectRatio: 0.8,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.md),
          border: Border.all(color: color, width: active ? 2 : 1),
        ),
        alignment: Alignment.center,
        child: Text(
          digit,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
