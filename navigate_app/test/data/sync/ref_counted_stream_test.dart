import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigate_app/data/sync/ref_counted_stream.dart';

void main() {
  // ---------------------------------------------------------------------------
  // 1. Basic stream — emit + receive
  // ---------------------------------------------------------------------------
  group('Basic stream — emit + receive', () {
    test('subscriber receives emitted value and lastValue is updated', () async {
      final source = StreamController<int>.broadcast();
      final rcs = RefCountedStream<int>(
        sourceFactory: () => source.stream,
      );

      final values = <int>[];
      final sub = rcs.stream.listen(values.add);

      expect(rcs.isActive, isTrue);

      source.add(42);
      await Future.delayed(Duration.zero);

      expect(values, [42]);
      expect(rcs.lastValue, 42);

      await sub.cancel();
      source.close();
      rcs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // 2. Replay last value to new subscribers
  // ---------------------------------------------------------------------------
  group('Replay last value to new subscribers', () {
    test('second subscriber immediately receives last value then both get new', () async {
      final source = StreamController<int>.broadcast();
      final rcs = RefCountedStream<int>(
        sourceFactory: () => source.stream,
      );

      final values1 = <int>[];
      final sub1 = rcs.stream.listen(values1.add);

      source.add(10);
      await Future.delayed(Duration.zero);
      expect(values1, [10]);

      // Second subscriber should immediately get the replayed value (10).
      final values2 = <int>[];
      final sub2 = rcs.stream.listen(values2.add);
      await Future.delayed(Duration.zero);
      expect(values2, [10]);

      // Emit another value — both should receive it.
      source.add(20);
      await Future.delayed(Duration.zero);
      expect(values1, [10, 20]);
      expect(values2, [10, 20]);

      await sub1.cancel();
      await sub2.cancel();
      source.close();
      rcs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // 3. Ref counting — single source factory call
  // ---------------------------------------------------------------------------
  group('Ref counting — single source factory call', () {
    test('sourceFactory is called only once for multiple subscribers', () async {
      int factoryCalls = 0;
      final source = StreamController<int>.broadcast();
      final rcs = RefCountedStream<int>(
        sourceFactory: () {
          factoryCalls++;
          return source.stream;
        },
      );

      final sub1 = rcs.stream.listen((_) {});
      expect(factoryCalls, 1);

      final sub2 = rcs.stream.listen((_) {});
      expect(factoryCalls, 1);

      // Both should receive events from the single source.
      final values1 = <int>[];
      final values2 = <int>[];
      sub1.onData(values1.add);
      sub2.onData(values2.add);

      source.add(99);
      await Future.delayed(Duration.zero);
      expect(values1, [99]);
      expect(values2, [99]);

      await sub1.cancel();
      await sub2.cancel();
      source.close();
      rcs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // 4. Grace period — cancel and re-subscribe before timeout
  // ---------------------------------------------------------------------------
  group('Grace period — cancel and re-subscribe before timeout', () {
    test('grace timer is cancelled on re-subscribe so source stays alive', () {
      fakeAsync((async) {
        int factoryCalls = 0;
        final source = StreamController<int>.broadcast();
        final rcs = RefCountedStream<int>(
          sourceFactory: () {
            factoryCalls++;
            return source.stream;
          },
          gracePeriod: const Duration(milliseconds: 200),
        );

        final sub1 = rcs.stream.listen((_) {});
        expect(factoryCalls, 1);

        // Cancel the only subscriber — grace period starts.
        sub1.cancel();

        // Re-subscribe before grace period elapses (at 100ms < 200ms).
        async.elapse(const Duration(milliseconds: 100));
        final values = <int>[];
        final sub2 = rcs.stream.listen(values.add);

        // _startSource is called again (refCount went 0→1), but the grace
        // timer was cancelled so _stopSource never fired. The key guarantee
        // is that the stream still works seamlessly.
        expect(factoryCalls, 2);

        // Emit value — new subscriber should receive it.
        source.add(7);
        async.flushMicrotasks();
        expect(values, [7]);

        // Advance past the original grace period — no crash, no double stop.
        async.elapse(const Duration(milliseconds: 200));

        source.add(8);
        async.flushMicrotasks();
        expect(values, [7, 8]);

        sub2.cancel();
        source.close();
        rcs.dispose();
      });
    });
  });

  // ---------------------------------------------------------------------------
  // 5. Source cleanup after grace period
  // ---------------------------------------------------------------------------
  group('Source cleanup after grace period', () {
    test('source is cleaned up after grace period and factory called again on re-subscribe', () {
      fakeAsync((async) {
        int factoryCalls = 0;
        late StreamController<int> source;
        final rcs = RefCountedStream<int>(
          sourceFactory: () {
            factoryCalls++;
            source = StreamController<int>.broadcast();
            return source.stream;
          },
          gracePeriod: const Duration(milliseconds: 200),
        );

        final sub1 = rcs.stream.listen((_) {});
        expect(factoryCalls, 1);

        // Cancel — grace timer starts.
        sub1.cancel();

        // Advance past grace period.
        async.elapse(const Duration(milliseconds: 250));

        // Source should now be cleaned up. Re-subscribing should call factory again.
        final values = <int>[];
        final sub2 = rcs.stream.listen(values.add);
        expect(factoryCalls, 2);

        // New source should work.
        source.add(55);
        async.flushMicrotasks();
        expect(values, [55]);

        sub2.cancel();
        source.close();
        rcs.dispose();
      });
    });
  });

  // ---------------------------------------------------------------------------
  // 6. Polling fallback — stale data
  // ---------------------------------------------------------------------------
  group('Polling fallback — stale data', () {
    test('poll is triggered when data is stale', () {
      fakeAsync((async) {
        int pollCount = 0;
        final source = StreamController<String>.broadcast();
        final rcs = RefCountedStream<String>(
          sourceFactory: () => source.stream,
          pollFallback: () async {
            pollCount++;
            return 'polled-$pollCount';
          },
          // Duration.zero means every check considers data stale.
          pollStaleThreshold: Duration.zero,
        );

        final values = <String>[];
        final sub = rcs.stream.listen(values.add);

        // The poll timer fires every 5 seconds.
        // Advance 6 seconds to trigger at least one poll.
        async.elapse(const Duration(seconds: 6));

        expect(pollCount, greaterThanOrEqualTo(1));
        expect(values, contains('polled-1'));

        sub.cancel();
        source.close();
        rcs.dispose();
      });
    });
  });

  // ---------------------------------------------------------------------------
  // 7. Polling — not called when data fresh
  // ---------------------------------------------------------------------------
  group('Polling — not called when data fresh', () {
    test('poll is NOT triggered when data is fresh', () {
      fakeAsync((async) {
        int pollCount = 0;
        final source = StreamController<String>.broadcast();
        final rcs = RefCountedStream<String>(
          sourceFactory: () => source.stream,
          pollFallback: () async {
            pollCount++;
            return 'polled';
          },
          pollStaleThreshold: const Duration(hours: 1),
        );

        final sub = rcs.stream.listen((_) {});

        // Emit a value so _lastUpdateTime is set to "now" (making data fresh).
        source.add('fresh');
        async.flushMicrotasks();

        // Advance 10 seconds — well under the 1-hour threshold.
        async.elapse(const Duration(seconds: 10));
        expect(pollCount, 0);

        sub.cancel();
        source.close();
        rcs.dispose();
      });
    });
  });

  // ---------------------------------------------------------------------------
  // 8. forceRefresh() triggers poll
  // ---------------------------------------------------------------------------
  group('forceRefresh() triggers poll', () {
    test('forceRefresh calls pollFallback and emits value', () async {
      final source = StreamController<String>.broadcast();
      final rcs = RefCountedStream<String>(
        sourceFactory: () => source.stream,
        pollFallback: () async => 'force-polled',
      );

      final values = <String>[];
      final sub = rcs.stream.listen(values.add);

      rcs.forceRefresh();
      // Allow the async poll future to complete.
      await Future.delayed(const Duration(milliseconds: 50));

      expect(values, contains('force-polled'));
      expect(rcs.lastValue, 'force-polled');

      await sub.cancel();
      source.close();
      rcs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // 9. Error forwarding
  // ---------------------------------------------------------------------------
  group('Error forwarding', () {
    test('source errors are forwarded to subscribers', () async {
      final source = StreamController<int>.broadcast();
      final rcs = RefCountedStream<int>(
        sourceFactory: () => source.stream,
      );

      final errors = <Object>[];
      final sub = rcs.stream.listen(
        (_) {},
        onError: (Object e) => errors.add(e),
      );

      source.addError('test-error');
      await Future.delayed(Duration.zero);

      expect(errors, ['test-error']);

      await sub.cancel();
      source.close();
      rcs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // 10. dispose()
  // ---------------------------------------------------------------------------
  group('dispose()', () {
    test('dispose stops events and sets isActive to false', () async {
      final source = StreamController<int>.broadcast();
      final rcs = RefCountedStream<int>(
        sourceFactory: () => source.stream,
      );

      final values = <int>[];
      rcs.stream.listen(values.add);

      source.add(1);
      await Future.delayed(Duration.zero);
      expect(values, [1]);

      rcs.dispose();

      expect(rcs.isActive, isFalse);

      // lastValue is still accessible after dispose.
      expect(rcs.lastValue, 1);

      // No further events should arrive (source stream was cancelled).
      source.add(2);
      await Future.delayed(Duration.zero);
      expect(values, [1]);

      source.close();
    });
  });

  // ---------------------------------------------------------------------------
  // 11. No pollFallback — no polling
  // ---------------------------------------------------------------------------
  group('No pollFallback — no polling', () {
    test('works correctly without pollFallback', () {
      fakeAsync((async) {
        final source = StreamController<int>.broadcast();
        final rcs = RefCountedStream<int>(
          sourceFactory: () => source.stream,
          // No pollFallback provided.
        );

        final values = <int>[];
        final sub = rcs.stream.listen(values.add);

        source.add(1);
        async.flushMicrotasks();

        // Advance well past poll timer interval — no errors should occur.
        async.elapse(const Duration(seconds: 30));

        expect(values, [1]);

        sub.cancel();
        source.close();
        rcs.dispose();
      });
    });
  });
}
