import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thaal/features/reader/presentation/swipe_page_turner.dart';

/// Stands in for the engine's platform view: it never claims a gesture
/// itself and only gets one when every other recognizer gives way.
class _EngineStandIn extends OneSequenceGestureRecognizer {
  _EngineStandIn(this.log);

  final List<String> log;

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void acceptGesture(int pointer) => log.add('engine');

  @override
  void rejectGesture(int pointer) => log.add('blocked');

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'engine stand-in';
}

void main() {
  late List<String> log;

  setUp(() => log = []);

  Future<void> pump(WidgetTester tester, {bool enabled = true}) {
    return tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SwipePageTurner(
          enabled: enabled,
          onNext: () => log.add('next'),
          onPrevious: () => log.add('previous'),
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: {
              _EngineStandIn:
                  GestureRecognizerFactoryWithHandlers<_EngineStandIn>(
                    () => _EngineStandIn(log),
                    (_) {},
                  ),
            },
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }

  Future<void> drag(WidgetTester tester, Offset by) async {
    final gesture = await tester.startGesture(const Offset(400, 300));
    for (var i = 1; i <= 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveTo(const Offset(400, 300) + by * (i / 10));
    }
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pump();
  }

  testWidgets('swiping left turns to the next page; nothing pans', (
    tester,
  ) async {
    await pump(tester);
    await drag(tester, const Offset(-200, 30));
    expect(log, ['blocked', 'next']);
  });

  testWidgets('swiping right turns to the previous page', (tester) async {
    await pump(tester);
    await drag(tester, const Offset(200, -30));
    expect(log, ['blocked', 'previous']);
  });

  testWidgets('a quick flick turns the page', (tester) async {
    await pump(tester);
    await tester.flingFrom(const Offset(400, 300), const Offset(-40, 0), 1500);
    await tester.pump();
    expect(log, ['blocked', 'next']);
  });

  testWidgets('vertical and short drags are absorbed without turning', (
    tester,
  ) async {
    await pump(tester);
    await drag(tester, const Offset(20, -200));
    await drag(tester, const Offset(-30, 0));
    expect(log, ['blocked', 'blocked']);
  });

  testWidgets('a tap reaches the engine', (tester) async {
    await pump(tester);
    await tester.tapAt(const Offset(400, 300));
    expect(log, ['engine']);
  });

  testWidgets('a second finger hands the gesture to the engine', (
    tester,
  ) async {
    await pump(tester);
    final first = await tester.startGesture(const Offset(400, 300));
    final second = await tester.startGesture(
      const Offset(400, 400),
      pointer: 2,
    );
    await first.moveTo(const Offset(400, 200));
    await second.moveTo(const Offset(400, 500));
    await first.up();
    await second.up();
    expect(log, ['engine', 'engine']);
  });

  testWidgets('when off, drags reach the engine', (tester) async {
    await pump(tester, enabled: false);
    await drag(tester, const Offset(-200, 0));
    expect(log, ['engine']);
  });
}
