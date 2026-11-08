import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// While [enabled], one-finger drags over [child] never reach it: the page
/// cannot pan in any direction. A mainly sideways swipe or fling turns the
/// page instead, through [onNext] (towards the left) and [onPrevious]
/// (towards the right), assuming left-to-right reading. Taps and
/// multi-finger gestures (pinch zoom) still reach [child].
///
/// This relies on [child] being an engine platform view that only receives
/// gestures no Flutter recognizer claims, which is how flutter_readium 0.9.0
/// creates its view (an empty `gestureRecognizers` set). Re-check this when
/// upgrading the plugin.
class SwipePageTurner extends StatelessWidget {
  const SwipePageTurner({
    super.key,
    required this.enabled,
    required this.onNext,
    required this.onPrevious,
    required this.child,
  });

  final bool enabled;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // The detector stays in the tree either way, so toggling it does not
    // recreate (and reload) the engine view below it.
    return RawGestureDetector(
      // Catches touches over the whole reading area, even where the engine
      // view draws nothing.
      behavior: HitTestBehavior.translucent,
      gestures: {
        if (enabled)
          PageSwipeRecognizer:
              GestureRecognizerFactoryWithHandlers<PageSwipeRecognizer>(
                PageSwipeRecognizer.new,
                (recognizer) =>
                    recognizer.onSwipe = (forward) =>
                        forward ? onNext() : onPrevious(),
              ),
      },
      child: child,
    );
  }
}

/// Claims every one-finger drag past the touch slop and reports a page
/// swipe when the finger lifts; rejects taps and multi-finger gestures.
/// Visible for testing.
class PageSwipeRecognizer extends OneSequenceGestureRecognizer {
  PageSwipeRecognizer({super.debugOwner});

  /// A sideways move at least this long turns the page.
  static const double minSwipeDistance = 48;

  /// Called with true for the next page, false for the previous one.
  void Function(bool forward)? onSwipe;

  int? _pointer;
  Offset _start = Offset.zero;
  bool _claimed = false;
  VelocityTracker? _velocity;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (_pointer != null) {
      // A second finger: hand the gesture to the engine (pinch zoom).
      _release(_pointer!);
      return;
    }
    super.addAllowedPointer(event);
    _pointer = event.pointer;
    _start = event.position;
    _claimed = false;
    _velocity = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer != _pointer) return;
    if (event is PointerMoveEvent) {
      _velocity?.addPosition(event.timeStamp, event.position);
      final distance = (event.position - _start).distance;
      if (!_claimed && distance > computeHitSlop(event.kind, gestureSettings)) {
        _claimed = true;
        resolvePointer(event.pointer, GestureDisposition.accepted);
      }
    } else if (event is PointerUpEvent) {
      if (_claimed) {
        _reportSwipe(event.position - _start);
        stopTrackingPointer(event.pointer);
        _reset();
      } else {
        _release(event.pointer);
      }
    } else if (event is PointerCancelEvent) {
      _release(event.pointer);
    }
  }

  void _reportSwipe(Offset delta) {
    final velocity = _velocity?.getVelocity().pixelsPerSecond ?? Offset.zero;
    final sideways = delta.dx.abs() > delta.dy.abs();
    final far = delta.dx.abs() >= minSwipeDistance;
    final fling =
        velocity.dx.abs() >= kMinFlingVelocity &&
        velocity.dx.abs() > velocity.dy.abs();
    if (!sideways || !(far || fling)) return;
    final dx = far ? delta.dx : velocity.dx;
    onSwipe?.call(dx < 0);
  }

  void _release(int pointer) {
    resolvePointer(pointer, GestureDisposition.rejected);
    stopTrackingPointer(pointer);
    _reset();
  }

  void _reset() {
    _pointer = null;
    _claimed = false;
    _velocity = null;
  }

  @override
  void rejectGesture(int pointer) {
    stopTrackingPointer(pointer);
    if (pointer == _pointer) _reset();
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'page swipe';
}
