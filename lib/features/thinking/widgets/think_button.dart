import 'package:flutter/material.dart';

/// The single most important visual element on the home screen — calm
/// but unmistakable, per docs/design.md.
class ThinkButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool loading;

  const ThinkButton({super.key, required this.onPressed, this.loading = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Think',
      hint: 'Start a thinking session',
      child: GestureDetector(
        onTap: onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 176,
          height: 176,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: onPressed == null
                ? scheme.primary.withValues(alpha: 0.4)
                : scheme.primary,
          ),
          alignment: Alignment.center,
          child: loading
              ? SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: scheme.onPrimary,
                  ),
                )
              : Text(
                  'Think',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: scheme.onPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
        ),
      ),
    );
  }
}
