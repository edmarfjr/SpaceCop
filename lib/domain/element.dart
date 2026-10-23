/// Chip and enemy attribute.
///
/// Kept out of `battle_chip.dart` exports: Flutter also has an `Element`.
enum Element {
  neutral,
  fire,
  aqua,
  elec,
  wood;

  /// Name shown in game.
  String get label => switch (this) {
    Element.neutral => 'Neutro',
    Element.fire => 'Fogo',
    Element.aqua => 'Aqua',
    Element.elec => 'Elétrico',
    Element.wood => 'Madeira',
  };

  /// Fire > Wood > Elec > Aqua > Fire. Neutral beats and loses to nothing.
  bool beats(Element other) => switch (this) {
    Element.fire => other == Element.wood,
    Element.wood => other == Element.elec,
    Element.elec => other == Element.aqua,
    Element.aqua => other == Element.fire,
    Element.neutral => false,
  };
}

/// Damage multiplier when the attack's element [beats] the target's.
const int weaknessMultiplier = 2;
