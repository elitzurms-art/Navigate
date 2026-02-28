import 'package:flutter_test/flutter_test.dart';
import 'package:navigate_app/services/routes_distribution_service.dart';

void main() {
  // =========================================================================
  // autoGroupNavigators — guard composition
  // =========================================================================
  group('autoGroupNavigators - guard', () {
    test('4 navigators → 2 groups of 2', () {
      final groups = RoutesDistributionService.autoGroupNavigators(
        navigators: ['n1', 'n2', 'n3', 'n4'],
        baseGroupSize: 2,
        compositionType: 'guard',
      );

      expect(groups.length, equals(2));
      final allMembers = groups.values.expand((m) => m).toList();
      expect(allMembers.length, equals(4));
      expect(allMembers.toSet(), equals({'n1', 'n2', 'n3', 'n4'}));

      for (final group in groups.values) {
        expect(group.length, equals(2));
      }
    });

    test('3 navigators → 1 group of 2 + 1 solo group', () {
      final groups = RoutesDistributionService.autoGroupNavigators(
        navigators: ['n1', 'n2', 'n3'],
        baseGroupSize: 2,
        compositionType: 'guard',
      );

      expect(groups.length, equals(2));
      final allMembers = groups.values.expand((m) => m).toList();
      expect(allMembers.length, equals(3));
      expect(allMembers.toSet(), equals({'n1', 'n2', 'n3'}));

      final sizes = groups.values.map((g) => g.length).toList()..sort();
      expect(sizes, equals([1, 2]));
    });

    test('5 navigators → 2 groups of 2 + 1 solo group', () {
      final groups = RoutesDistributionService.autoGroupNavigators(
        navigators: ['n1', 'n2', 'n3', 'n4', 'n5'],
        baseGroupSize: 2,
        compositionType: 'guard',
      );

      expect(groups.length, equals(3));
      final allMembers = groups.values.expand((m) => m).toList();
      expect(allMembers.length, equals(5));

      final sizes = groups.values.map((g) => g.length).toList()..sort();
      expect(sizes, equals([1, 2, 2]));
    });

    test('2 navigators → 1 group of 2', () {
      final groups = RoutesDistributionService.autoGroupNavigators(
        navigators: ['n1', 'n2'],
        baseGroupSize: 2,
        compositionType: 'guard',
      );

      expect(groups.length, equals(1));
      expect(groups.values.first.length, equals(2));
    });

    test('1 navigator → 1 solo group', () {
      final groups = RoutesDistributionService.autoGroupNavigators(
        navigators: ['n1'],
        baseGroupSize: 2,
        compositionType: 'guard',
      );

      expect(groups.length, equals(1));
      expect(groups.values.first.length, equals(1));
    });
  });

  // =========================================================================
  // autoGroupNavigators — pair composition
  // =========================================================================
  group('autoGroupNavigators - pair', () {
    test('3 navigators → 1 group of 3 (remainder joins last group)', () {
      final groups = RoutesDistributionService.autoGroupNavigators(
        navigators: ['n1', 'n2', 'n3'],
        baseGroupSize: 2,
        compositionType: 'pair',
      );

      expect(groups.length, equals(1));
      final allMembers = groups.values.expand((m) => m).toList();
      expect(allMembers.length, equals(3));
    });

    test('5 navigators → 2 groups: one of 2 and one of 3', () {
      final groups = RoutesDistributionService.autoGroupNavigators(
        navigators: ['n1', 'n2', 'n3', 'n4', 'n5'],
        baseGroupSize: 2,
        compositionType: 'pair',
      );

      expect(groups.length, equals(2));
      final allMembers = groups.values.expand((m) => m).toList();
      expect(allMembers.length, equals(5));

      final sizes = groups.values.map((g) => g.length).toList()..sort();
      expect(sizes, equals([2, 3]));
    });
  });

  // =========================================================================
  // Guard split logic — simulated (tests the count-based split algorithm)
  // =========================================================================
  group('Guard split logic', () {
    // Simulate the split algorithm from _expandForComposition
    Map<String, dynamic> simulateGuardSplit({
      required List<String> checkpointIds,
      required List<String> sequence,
      required String? swapId,
    }) {
      // --- Same logic as the new _expandForComposition ---
      // Sort checkpoints by sequence order
      final orderedCps = List<String>.from(checkpointIds);
      orderedCps.sort((a, b) {
        final ai = sequence.indexOf(a);
        final bi = sequence.indexOf(b);
        return (ai < 0 ? 999999 : ai).compareTo(bi < 0 ? 999999 : bi);
      });

      final half = orderedCps.length ~/ 2;
      final firstHalfCps = orderedCps.sublist(0, half);
      final secondHalfCps = orderedCps.sublist(half);

      // Find split position
      final lastFirstInSeq = sequence.indexOf(firstHalfCps.last);
      final firstSecondInSeq = sequence.indexOf(secondHalfCps.first);
      final swapInSeq = swapId != null ? sequence.indexOf(swapId) : -1;

      final splitIdx = (swapInSeq > lastFirstInSeq && swapInSeq <= firstSecondInSeq)
          ? swapInSeq
          : lastFirstInSeq;

      // Build half sequences
      final firstHalfSeq = sequence.sublist(0, splitIdx + 1).toList();
      if (swapId != null && !firstHalfSeq.contains(swapId)) {
        firstHalfSeq.add(swapId);
      }

      final secondHalfSeq = <String>[];
      if (swapId != null) secondHalfSeq.add(swapId);
      for (int i = splitIdx + 1; i < sequence.length; i++) {
        if (sequence[i] != swapId) secondHalfSeq.add(sequence[i]);
      }

      return {
        'firstHalfCps': firstHalfCps,
        'secondHalfCps': secondHalfCps,
        'firstHalfSeq': firstHalfSeq,
        'secondHalfSeq': secondHalfSeq,
        'splitIdx': splitIdx,
      };
    }

    test('swap point in sequence → equal split at swap', () {
      // 6 checkpoints + swap point in the middle of sequence
      final result = simulateGuardSplit(
        checkpointIds: ['cp1', 'cp2', 'cp3', 'cp4', 'cp5', 'cp6'],
        sequence: ['cp1', 'cp2', 'cp3', 'SWAP', 'cp4', 'cp5', 'cp6'],
        swapId: 'SWAP',
      );

      expect(result['firstHalfCps'], equals(['cp1', 'cp2', 'cp3']));
      expect(result['secondHalfCps'], equals(['cp4', 'cp5', 'cp6']));
      expect(result['firstHalfSeq'], equals(['cp1', 'cp2', 'cp3', 'SWAP']));
      expect(result['secondHalfSeq'], equals(['SWAP', 'cp4', 'cp5', 'cp6']));
    });

    test('swap point NOT in sequence → still splits evenly by count', () {
      // This is the main bug scenario: swap point not found
      final result = simulateGuardSplit(
        checkpointIds: ['cp1', 'cp2', 'cp3', 'cp4', 'cp5', 'cp6'],
        sequence: ['cp1', 'cp2', 'cp3', 'cp4', 'cp5', 'cp6'],
        swapId: 'SWAP',
      );

      // Must still split evenly!
      expect(result['firstHalfCps'].length, equals(3));
      expect(result['secondHalfCps'].length, equals(3));
      expect(result['firstHalfCps'], equals(['cp1', 'cp2', 'cp3']));
      expect(result['secondHalfCps'], equals(['cp4', 'cp5', 'cp6']));

      // Swap point added at boundaries
      final firstSeq = result['firstHalfSeq'] as List<String>;
      final secondSeq = result['secondHalfSeq'] as List<String>;
      expect(firstSeq.last, equals('SWAP'));
      expect(secondSeq.first, equals('SWAP'));
    });

    test('swap point at position 0 → still splits evenly by count', () {
      final result = simulateGuardSplit(
        checkpointIds: ['cp1', 'cp2', 'cp3', 'cp4', 'cp5', 'cp6'],
        sequence: ['SWAP', 'cp1', 'cp2', 'cp3', 'cp4', 'cp5', 'cp6'],
        swapId: 'SWAP',
      );

      expect(result['firstHalfCps'].length, equals(3));
      expect(result['secondHalfCps'].length, equals(3));
    });

    test('swap point at end → still splits evenly by count', () {
      final result = simulateGuardSplit(
        checkpointIds: ['cp1', 'cp2', 'cp3', 'cp4', 'cp5', 'cp6'],
        sequence: ['cp1', 'cp2', 'cp3', 'cp4', 'cp5', 'cp6', 'SWAP'],
        swapId: 'SWAP',
      );

      expect(result['firstHalfCps'].length, equals(3));
      expect(result['secondHalfCps'].length, equals(3));
    });

    test('null swap point → splits evenly by count', () {
      final result = simulateGuardSplit(
        checkpointIds: ['cp1', 'cp2', 'cp3', 'cp4', 'cp5', 'cp6'],
        sequence: ['cp1', 'cp2', 'cp3', 'cp4', 'cp5', 'cp6'],
        swapId: null,
      );

      expect(result['firstHalfCps'].length, equals(3));
      expect(result['secondHalfCps'].length, equals(3));
    });

    test('8 checkpoints → 4 per side', () {
      final result = simulateGuardSplit(
        checkpointIds: ['c1', 'c2', 'c3', 'c4', 'c5', 'c6', 'c7', 'c8'],
        sequence: ['c1', 'c2', 'c3', 'c4', 'SWAP', 'c5', 'c6', 'c7', 'c8'],
        swapId: 'SWAP',
      );

      expect(result['firstHalfCps'].length, equals(4));
      expect(result['secondHalfCps'].length, equals(4));
      expect(result['firstHalfCps'], equals(['c1', 'c2', 'c3', 'c4']));
      expect(result['secondHalfCps'], equals(['c5', 'c6', 'c7', 'c8']));
    });

    test('odd number of checkpoints → roughly even split', () {
      final result = simulateGuardSplit(
        checkpointIds: ['c1', 'c2', 'c3', 'c4', 'c5'],
        sequence: ['c1', 'c2', 'SWAP', 'c3', 'c4', 'c5'],
        swapId: 'SWAP',
      );

      // 5 ~/ 2 = 2 first, 3 second
      expect(result['firstHalfCps'].length, equals(2));
      expect(result['secondHalfCps'].length, equals(3));
    });

    test('sequence with waypoints between checkpoints → correct split', () {
      // Sequence includes waypoints (wp1, wp2) mixed with checkpoints
      final result = simulateGuardSplit(
        checkpointIds: ['c1', 'c2', 'c3', 'c4', 'c5', 'c6'],
        sequence: ['c1', 'wp1', 'c2', 'c3', 'SWAP', 'c4', 'wp2', 'c5', 'c6'],
        swapId: 'SWAP',
      );

      expect(result['firstHalfCps'].length, equals(3));
      expect(result['secondHalfCps'].length, equals(3));
      expect(result['firstHalfCps'], equals(['c1', 'c2', 'c3']));
      expect(result['secondHalfCps'], equals(['c4', 'c5', 'c6']));

      // First half sequence should include wp1 and SWAP
      final firstSeq = result['firstHalfSeq'] as List<String>;
      expect(firstSeq, contains('wp1'));
      expect(firstSeq.last, equals('SWAP'));

      // Second half sequence should include wp2
      final secondSeq = result['secondHalfSeq'] as List<String>;
      expect(secondSeq, contains('wp2'));
      expect(secondSeq.first, equals('SWAP'));
    });

    test('OLD BUG: swap not in sequence would give full axis to both — now fixed', () {
      // This is the exact bug scenario:
      // - Algorithm runs, produces sequence WITHOUT swap point
      // - Old code: indexOf returns -1, fallback gives both navigators the SAME full axis
      // - New code: splits evenly by checkpoint count regardless
      final result = simulateGuardSplit(
        checkpointIds: ['a', 'b', 'c', 'd', 'e', 'f'],
        sequence: ['a', 'b', 'c', 'd', 'e', 'f'], // NO swap point
        swapId: 'MISSING_SWAP',
      );

      final first = result['firstHalfCps'] as List<String>;
      final second = result['secondHalfCps'] as List<String>;

      // MUST be different (the old bug gave identical axes)
      expect(first, isNot(equals(second)));
      // Equal count
      expect(first.length, equals(3));
      expect(second.length, equals(3));
      // No overlap
      expect(first.toSet().intersection(second.toSet()), isEmpty);
    });
  });
}
