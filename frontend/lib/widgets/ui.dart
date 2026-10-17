import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Building blocks for the app's animated look, shared by every page.

/// Fades and slides its child up into place, staggered by [index].
class Entrance extends StatefulWidget {
  const Entrance({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance> with SingleTickerProviderStateMixin {
  static const _stagger = 70;
  static const _length = 500;

  late final int _delay = _stagger * math.min(widget.index, 8);
  late final _controller = AnimationController(
      vsync: this, duration: Duration(milliseconds: _delay + _length));
  late final _curve = CurvedAnimation(
    parent: _controller,
    curve: Interval(_delay / (_delay + _length), 1, curve: Curves.easeOutCubic),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else if (_controller.isDismissed) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) => Opacity(
        opacity: _curve.value,
        child: Transform.translate(
            offset: Offset(0, 24 * (1 - _curve.value)), child: child),
      ),
      child: widget.child,
    );
  }
}

/// Shakes its child side to side each time [animation] runs from 0 to 1.
class ShakeTransition extends AnimatedWidget {
  const ShakeTransition(
      {super.key, required Animation<double> animation, required this.child})
      : super(listenable: animation);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = (listenable as Animation<double>).value;
    return Transform.translate(
      offset: Offset(math.sin(t * math.pi * 8) * 10 * (1 - t), 0),
      child: child,
    );
  }
}

/// Full-width pill button. Glows when [glow] is set and swaps to a spinner
/// while [busy].
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.busy = false,
    this.busyLabel,
    this.glow = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool busy, glow;
  final String? busyLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: glow && !busy ? 0.35 : 0),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape: const StadiumBorder(),
          // Busy isn't "disabled": stay in color instead of going grey.
          disabledBackgroundColor: busy ? scheme.primary : null,
          disabledForegroundColor: busy ? scheme.onPrimary : null,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: busy
              ? Row(
                  key: const ValueKey('busy'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: scheme.onPrimary)),
                    if (busyLabel != null) ...[
                      const SizedBox(width: 12),
                      Text(busyLabel!),
                    ],
                  ],
                )
              : Row(
                  key: ValueKey(label),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 18),
                    const SizedBox(width: 10),
                    Text(label),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Rounded card that dips slightly while pressed. Not tappable when [onTap]
/// is null.
class PressableCard extends StatefulWidget {
  const PressableCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  State<PressableCard> createState() => _PressableCardState();
}

class _PressableCardState extends State<PressableCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(18);
    final onTap = widget.onTap;
    return AnimatedScale(
      scale: _pressed ? 0.98 : 1,
      duration: const Duration(milliseconds: 120),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: _pressed ? scheme.surfaceContainerHigh : scheme.surfaceContainerLowest,
          borderRadius: radius,
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap == null
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onTap();
                  },
            onHighlightChanged: (v) => setState(() => _pressed = v),
            child: Padding(padding: widget.padding, child: widget.child),
          ),
        ),
      ),
    );
  }
}

/// Small rounded label, optionally with an icon. Defaults to the secondary
/// container colors.
class Pill extends StatelessWidget {
  const Pill({super.key, this.icon, required this.label, this.color, this.onColor});

  final IconData? icon;
  final String label;
  final Color? color, onColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = onColor ?? theme.colorScheme.onSecondaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color ?? theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(color: fg)),
          ),
        ],
      ),
    );
  }
}

/// Soft glow around [child] while anything inside it has focus.
class FocusGlow extends StatefulWidget {
  const FocusGlow({super.key, required this.child});

  final Widget child;

  @override
  State<FocusGlow> createState() => _FocusGlowState();
}

class _FocusGlowState extends State<FocusGlow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (v) => setState(() => _focused = v),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: scheme.primary.withValues(alpha: _focused ? 0.18 : 0),
              blurRadius: _focused ? 18 : 0,
              spreadRadius: _focused ? 1 : 0,
            ),
          ],
        ),
        child: widget.child,
      ),
    );
  }
}

/// Rounded, filled text field look. Pair with [FocusGlow].
InputDecoration softInputDecoration(
  BuildContext context, {
  String? labelText,
  String? hintText,
  Widget? prefixIcon,
  Widget? suffixIcon,
}) {
  final scheme = Theme.of(context).colorScheme;
  final radius = BorderRadius.circular(14);
  OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
      borderRadius: radius, borderSide: BorderSide(color: color, width: width));
  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: scheme.surfaceContainerLow,
    enabledBorder: border(scheme.outlineVariant),
    focusedBorder: border(scheme.primary, 2),
    errorBorder: border(scheme.error),
    focusedErrorBorder: border(scheme.error, 2),
  );
}

/// Closes the keyboard; use as a text field's `onTapOutside`.
void unfocusOnTapOutside(PointerDownEvent _) =>
    FocusManager.instance.primaryFocus?.unfocus();
