import 'package:chetz_core/generator.dart';
import 'package:test/test.dart';

void main() {
  // 70 bits: spans three 32-bit words, the last one partial.
  Bitset of(Iterable<int> bits, [int length = 70]) {
    final b = Bitset(length);
    for (final i in bits) {
      b.set(i);
    }
    return b;
  }

  final a = of([0, 1, 5, 31, 32, 33, 40, 63, 64, 69]);
  final not = of([1, 33, 69, 2]);
  final and = of([0, 1, 5, 33, 40, 64, 69, 68]);

  test('set difference and its cardinality', () {
    expect(a.andNot(not).toList(), [0, 5, 31, 32, 40, 63, 64]);
    expect(a.cardinalityAndNot(not), 7);
    expect(a.cardinalityAndAndNot(and, not), 4); // 0, 5, 40, 64
    expect(a.cardinality, 10);
  });

  test('forEachSetAndNot walks the difference in order', () {
    final seen = <int>[];
    a.forEachSetAndNot(not, seen.add);
    expect(seen, [0, 5, 31, 32, 40, 63, 64]);
    final none = <int>[];
    Bitset(70).forEachSetAndNot(not, none.add);
    expect(none, isEmpty);
  });

  test('nextSetBit and full sets respect the length', () {
    expect(a.nextSetBit(0), 0);
    expect(a.nextSetBit(6), 31);
    expect(a.nextSetBit(34), 40);
    expect(a.nextSetBit(65), 69);
    expect(a.nextSetBit(70), -1);
    final full = Bitset.full(70);
    expect(full.cardinality, 70);
    expect(full.nextSetBit(69), 69);
    full.clearAll();
    expect(full.isEmpty, isTrue);
  });
}
