import 'package:flutter/material.dart';

import '../../../core/theme/app_motion.dart';

/// The single most important visual element on the home screen — calm
/// but unmistakable, per docs/design.md. Presses give a subtle scale-down
/// so it feels responsive without being flashy.
class ThinkButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final bool loading;

  const ThinkButton({super.key, required this.onPressed, this.loading = false});

  @override
  State<ThinkButton> createState() => _ThinkButtonState();
}

class _ThinkButtonState extends State<ThinkButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onPressed == null) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Reduced motion: collapse to instant rather than skip — curve/scale
    // targets stay identical, so the end state is unaffected either way.
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return Semantics(
      button: true,
      label: 'Think',
      hint: 'Start a thinking session',
      child: GestureDetector(
        onTap: widget.onPressed,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        child: AnimatedScale(
          scale: _pressed ? AppMotion.pressedScale : 1.0,
          duration: reduceMotion ? Duration.zero : AppMotion.fast,
          curve: AppMotion.enter,
          child: AnimatedContainer(
            duration: reduceMotion ? Duration.zero : AppMotion.medium,
            width: 176,
            height: 176,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.onPressed == null
                  ? scheme.primary.withValues(alpha: 0.4)
                  : scheme.primary,
            ),
            alignment: Alignment.center,
            child: widget.loading
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
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
