import 'dart:math';

/// How often a card or relic is offered, and how much it costs in the shop.
enum Rarity {
  common,
  uncommon,
  rare;

  /// Name shown in game.
  String get label => switch (this) {
    Rarity.common => 'Comum',
    Rarity.uncommon => 'Incomum',
    Rarity.rare => 'Raro',
  };

  /// Chance, in percent, of this rarity on a roll. Elite rewards roll
  /// better.
  int weight({bool elite = false}) => switch (this) {
    Rarity.common => elite ? 40 : 60,
    Rarity.uncommon => elite ? 40 : 30,
    Rarity.rare => elite ? 20 : 10,
  };
}

/// Picks up to [count] distinct items of [pool]. Each pick first rolls a
/// rarity (among those still left, by [Rarity.weight]), then takes a random
/// item of it, so a rarity's chance doesn't depend on how many items it has.
List<T> pickByRarity<T>(
  Iterable<T> pool,
  Rarity Function(T item) rarityOf,
  int count,
  Random random, {
  bool elite = false,
}) {
  final left = List.of(pool);
  final picked = <T>[];
  while (picked.length < count && left.isNotEmpty) {
    final rarities = {for (final item in left) rarityOf(item)};
    var roll = random.nextInt(
      rarities.fold(0, (sum, r) => sum + r.weight(elite: elite)),
    );
    final rarity = rarities.firstWhere((r) {
      roll -= r.weight(elite: elite);
      return roll < 0;
    });
    final options = [
      for (final item in left)
        if (rarityOf(item) == rarity) item,
    ];
    final item = options[random.nextInt(options.length)];
    left.remove(item);
    picked.add(item);
  }
  return picked;
}
