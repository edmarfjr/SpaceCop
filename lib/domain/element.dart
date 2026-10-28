/// Chip and enemy attribute. Only drives terrain and statuses (Elec on Wet,
/// Fire on grass...); damage by enemy type goes by card family instead.
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
