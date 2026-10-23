import 'dart:math';

import '../chips/battle_chip.dart';

/// Slay the Spire style piles for one battle.
///
/// The run's permanent deck ([RunState.deck]) is copied into a fresh [Deck]
/// at the start of each battle, so nothing here leaks between fights.
///
/// Flow: [draw] from the top into [hand]; each chip used in combat goes to
/// the discard pile through [discard].
class Deck {
  Deck(Iterable<ChipCard> cards, {Random? random})
    : _random = random ?? Random() {
    _drawPile
      ..addAll(cards)
      ..shuffle(_random);
  }

  final Random _random;
  final List<ChipCard> _drawPile = [];
  final List<ChipCard> _hand = [];
  final List<ChipCard> _discardPile = [];

  List<ChipCard> get drawPile => List.unmodifiable(_drawPile);
  List<ChipCard> get hand => List.unmodifiable(_hand);
  List<ChipCard> get discardPile => List.unmodifiable(_discardPile);

  /// Draws up to [count] cards into the hand. When the draw pile runs out the
  /// discard pile is shuffled back in. Returns the cards drawn.
  List<ChipCard> draw(int count) {
    final drawn = <ChipCard>[];
    for (var i = 0; i < count; i++) {
      if (_drawPile.isEmpty) {
        if (_discardPile.isEmpty) break;
        _drawPile
          ..addAll(_discardPile)
          ..shuffle(_random);
        _discardPile.clear();
      }
      drawn.add(_drawPile.removeLast());
    }
    _hand.addAll(drawn);
    return drawn;
  }

  /// The next [count] cards to be drawn, top first.
  List<ChipCard> peek(int count) =>
      _drawPile.reversed.take(count).toList(growable: false);

  /// Moves a draw-pile card to the bottom, so it is drawn last.
  void sendToBottom(ChipCard card) {
    if (_drawPile.remove(card)) _drawPile.insert(0, card);
  }

  void discard(ChipCard card) {
    _hand.remove(card);
    _discardPile.add(card);
  }

  /// Removes a single-use card from this battle (it stays in the run deck).
  void exhaust(ChipCard card) => _hand.remove(card);

  void discardHand() {
    _discardPile.addAll(_hand);
    _hand.clear();
  }
}
