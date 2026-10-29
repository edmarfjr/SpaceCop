import '../../domain/battle/battle_state.dart';
import '../../domain/chips/battle_chip.dart';
import '../../domain/element.dart';
import '../audio.dart';

/// Turns what a battle tick reports ([BattleState.events],
/// [BattleState.hits]) into sound effects, each at most once per tick.
class BattleSounds {
  /// Units stunned after the previous tick, to hear only new stuns.
  final Set<Fighter> _stunned = {};

  void afterTick(BattleState battle) {
    final sounds = <Sfx>{};
    for (final event in battle.events) {
      final sfx = switch (event.kind) {
        BattleEventKind.chipUsed => _chip(event.chip!),
        BattleEventKind.chain => event.amount >= 3 ? Sfx.chain3 : Sfx.chain2,
        BattleEventKind.telegraph => Sfx.telegraph,
        BattleEventKind.enemyShot => Sfx.enemyShot,
        BattleEventKind.explosion => Sfx.explosion,
        BattleEventKind.slash => Sfx.slash,
        BattleEventKind.blocked => Sfx.block,
        BattleEventKind.death => Sfx.enemyDeath,
        BattleEventKind.newHand => Sfx.newHand,
        BattleEventKind.won => Sfx.win,
        BattleEventKind.lost => Sfx.lose,
      };
      sounds.add(sfx);
    }
    for (final hit in battle.hits) {
      sounds.add(hit.target is PlayerFighter ? Sfx.hitPlayer : Sfx.hitEnemy);
    }
    final stunned = battle.units.where((u) => u.has(Status.stunned)).toSet();
    if (stunned.difference(_stunned).isNotEmpty) sounds.add(Sfx.stun);
    _stunned
      ..clear()
      ..addAll(stunned);
    // A death covers the hit and the blast that caused it; the end of the
    // battle covers the rest of its last tick.
    if (sounds.contains(Sfx.enemyDeath)) {
      sounds.removeAll([Sfx.hitEnemy, Sfx.explosion, Sfx.stun]);
    }
    if (sounds.contains(Sfx.win) || sounds.contains(Sfx.lose)) {
      sounds.removeAll([Sfx.telegraph, Sfx.enemyShot, Sfx.newHand]);
    }
    sounds.forEach(GameAudio.instance.play);
  }

  static Sfx _chip(ChipDef def) => switch (def.type) {
    ChipType.recovery => Sfx.heal,
    ChipType.support => Sfx.support,
    ChipType.attack => switch (def.pose) {
      ChipPose.melee => Sfx.melee,
      ChipPose.toss => Sfx.toss,
      ChipPose.shoot => switch (def.element) {
        Element.fire => Sfx.shotFire,
        Element.aqua => Sfx.shotAqua,
        Element.elec => Sfx.shotElec,
        Element.wood => Sfx.shotWood,
        Element.neutral => Sfx.shot,
      },
    },
  };
}
