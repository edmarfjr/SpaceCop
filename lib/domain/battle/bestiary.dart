import 'enemies.dart';

/// Where an enemy shows up, which sets how many fights unlock its entry.
enum FoeTier {
  common('Comum'),
  elite('Elite'),
  boss('Chefe');

  const FoeTier(this.label);

  final String label;

  /// Fights against the enemy that unlock its entry in the Compêndio.
  int get unlockFights => this == FoeTier.boss ? 1 : 5;
}

/// One enemy's entry in the Compêndio.
class FoeEntry {
  const FoeEntry(this.id, this.def, this.act, this.tier, this.description);

  /// Saved key: stays the same if the enemy is renamed.
  final String id;
  final EnemyDef def;

  /// The mission it fights in.
  final int act;
  final FoeTier tier;

  /// How it fights.
  final String description;
}

/// Every enemy fought in a run (summons and unused ones left out), by
/// mission and tier.
abstract final class Bestiary {
  static const all = [
    // Missão 1.
    FoeEntry(
      'gruntGun',
      Enemies.gruntGun,
      1,
      FoeTier.common,
      'Alinha com você e atira (10).',
    ),
    FoeEntry(
      'gruntDuck',
      Enemies.gruntDuck,
      1,
      FoeTier.common,
      'No fundo, rajadas de 3 tiros de 5.',
    ),
    FoeEntry(
      'gruntMelee',
      Enemies.gruntMelee,
      1,
      FoeTier.common,
      'Avança, corta e volta. Racha os painéis.',
    ),
    FoeEntry(
      'gruntGrenade',
      Enemies.gruntGrenade,
      1,
      FoeTier.common,
      'Granada no seu painel, que vira Lava.',
    ),
    FoeEntry(
      'gruntArtillery',
      Enemies.gruntArtillery,
      1,
      FoeTier.common,
      'Mísseis no seu painel. O aviso é longo.',
    ),
    FoeEntry(
      'sentry',
      Enemies.sentry,
      1,
      FoeTier.common,
      'Sobe do chão, atira na linha e afunda.',
    ),
    FoeEntry(
      'rooster',
      Enemies.rooster,
      1,
      FoeTier.common,
      'No fundo. Investe (15) se você ficar na linha.',
    ),
    FoeEntry(
      'brute',
      Enemies.brute,
      1,
      FoeTier.elite,
      'Escudo frontal. Investe pela sua linha.',
    ),
    FoeEntry(
      'digger',
      Enemies.digger,
      1,
      FoeTier.elite,
      'Cava, surge e fura seu painel.',
    ),
    FoeEntry(
      'prism',
      Enemies.prism,
      1,
      FoeTier.elite,
      'Em dupla. Reflete tiros fora de linha.',
    ),
    FoeEntry(
      'lavaGuard',
      Enemies.lavaGuard,
      1,
      FoeTier.elite,
      'Espalha Lava e varre sua linha com fogo.',
    ),
    FoeEntry(
      'twoHead',
      Enemies.twoHead,
      1,
      FoeTier.elite,
      'Na linha: rajada de 3. Fora: 2 granadas de Lava.',
    ),
    FoeEntry(
      'tank',
      Enemies.tank,
      1,
      FoeTier.boss,
      '2 painéis. Rajadas, morteiros e investidas.',
    ),
    FoeEntry(
      'colonel',
      Enemies.colonel,
      1,
      FoeTier.boss,
      'Com 2 Guarda-costas. Rajada, tiro de precisão e molotov.',
    ),
    FoeEntry(
      'argos',
      Enemies.argos,
      1,
      FoeTier.boss,
      'A IA da base. Com o núcleo aberto, Energia causa o triplo.',
    ),
    // Missão 2.
    FoeEntry(
      'etWarrior',
      Enemies.etWarrior,
      2,
      FoeTier.common,
      'Golpe de alcance 2. Foge depois.',
    ),
    FoeEntry(
      'etGunner',
      Enemies.etGunner,
      2,
      FoeTier.common,
      'Atira (10) e foge.',
    ),
    FoeEntry(
      'etTrap',
      Enemies.etTrap,
      2,
      FoeTier.common,
      'Enterrado: só Explosivo o atinge.',
    ),
    FoeEntry(
      'etShaman',
      Enemies.etShaman,
      2,
      FoeTier.common,
      'Deixa Esferas que soltam morteiros.',
    ),
    FoeEntry(
      'etShieldBearer',
      Enemies.etShieldBearer,
      2,
      FoeTier.common,
      'Protege um aliado com o escudo.',
    ),
    FoeEntry(
      'etHealer',
      Enemies.etHealer,
      2,
      FoeTier.common,
      'Cura o aliado mais ferido. Atordoe-o.',
    ),
    FoeEntry(
      'sentinel',
      Enemies.sentinel,
      2,
      FoeTier.common,
      'Varre suas fileiras com laser.',
    ),
    FoeEntry(
      'scarab',
      Enemies.scarab,
      2,
      FoeTier.common,
      'Em trio. Ao seu lado, pisca e explode em cruz.',
    ),
    FoeEntry(
      'leaper',
      Enemies.leaper,
      2,
      FoeTier.common,
      'Salta no seu painel (20). Saia dele.',
    ),
    FoeEntry(
      'etRider',
      Enemies.etRider,
      2,
      FoeTier.elite,
      '2 painéis. Só investe pela sua linha.',
    ),
    FoeEntry(
      'ruinGolem',
      Enemies.ruinGolem,
      2,
      FoeTier.elite,
      'Racha sua coluna. Acerte o punho.',
    ),
    FoeEntry(
      'priestess',
      Enemies.priestess,
      2,
      FoeTier.elite,
      'Teleporta e cria cópias frágeis.',
    ),
    FoeEntry(
      'portal',
      Enemies.portal,
      2,
      FoeTier.elite,
      'Solta guerreiros a cada poucos segundos.',
    ),
    FoeEntry(
      'tribeKing',
      Enemies.tribeKing,
      2,
      FoeTier.boss,
      'Invulnerável enquanto houver Totens.',
    ),
    FoeEntry(
      'highPriest',
      Enemies.highPriest,
      2,
      FoeTier.boss,
      'Runas no seu lado: pise nelas para apagar.',
    ),
    FoeEntry(
      'serpent',
      Enemies.serpent,
      2,
      FoeTier.boss,
      'Mergulha e surge sob você. Quebre os segmentos.',
    ),
    // Missão 3.
    FoeEntry(
      'shadowGun',
      Enemies.shadowGun,
      3,
      FoeTier.common,
      'Alinha com você e atira (10).',
    ),
    FoeEntry(
      'shadowFly',
      Enemies.shadowFly,
      3,
      FoeTier.common,
      'Teleporta e lança uma bola.',
    ),
    FoeEntry(
      'shadowJumper',
      Enemies.shadowJumper,
      3,
      FoeTier.common,
      'Sólida só durante o salto.',
    ),
    FoeEntry(
      'shadowNest',
      Enemies.shadowNest,
      3,
      FoeTier.common,
      'Choca Carrapatos que explodem.',
    ),
    FoeEntry(
      'predator',
      Enemies.predator,
      3,
      FoeTier.elite,
      'Some e corta sua coluna inteira.',
    ),
    FoeEntry(
      'stalker',
      Enemies.stalker,
      3,
      FoeTier.elite,
      'Investe pela sua linha, rachando o chão.',
    ),
    FoeEntry(
      'voidEye',
      Enemies.voidEye,
      3,
      FoeTier.boss,
      'Ao se partir, solta Hemisférios e fica invulnerável.',
    ),
  ];

  /// [def]'s entry, or null if it has none (summons, unused enemies).
  static FoeEntry? of(EnemyDef def) {
    for (final entry in all) {
      if (identical(entry.def, def)) return entry;
    }
    return null;
  }
}
