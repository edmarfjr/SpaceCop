/// Enemy attribute (Fire units shrug off lava, enemy Fire burns grass...).
/// Cards have none: [ChipDef.tint] only picks their color and sound.
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
}
