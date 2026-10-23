# Prompt — Implementação da Fase 2 (StarCop)

> Documento histórico, anterior à troca de tema. Termos antigos e os de hoje:
> chip = carta, RAM = Energia, Zenny = Créditos, Mettaur = Canhão Móvel (fora
> do sorteio), Navi não existe mais. Valores de cartas e inimigos atuais estão
> em `lib/domain`.

> Fonte: GDD "mmnbw — GDD: Próxima Fase do Protótipo" (https://claude.ai/artifact/CqyTuraxbPWd542jfeM5RQ).
> Uso: cole a seção **Contexto e regras** + **uma** fase por sessão (ou por turno). Não peça todas as fases de uma vez.

---

## Contexto e regras (vale para todas as fases)

Você está implementando a fase 2 do protótipo StarCop (pacote `starcop`, Flutter 3.38 + Flame 1.35.1), em `D:\projetosFlutter\mmnbw`. É um roguelike de cartas com mapa no estilo Slay the Spire e combate em grade 6×3 em tempo real.

**Arquitetura atual (respeite):**

- `lib/domain/`: Dart puro, sem import de Flame nem de Flutter. Toda regra de jogo fica aqui.
  - `grid.dart`: `GridPos` e `Team`. A grade tem 6×3; as colunas 0–2 são do jogador e as 3–5 do inimigo.
  - `chips/battle_chip.dart`: `ChipDef`, `ChipEffect` (sealed), `ChipCard`.
  - `chips/chip_library.dart`: o catálogo `Chips`.
  - `deck/deck.dart`: pilhas de compra, mão e descarte.
  - `battle/battle_state.dart`: simulação determinística em ticks (30/s). O ponto de entrada é `tick(PlayerInput)`.
  - `battle/enemies.dart`: `EnemyDef`, `Encounter`, `Encounters`.
  - `map/run_map.dart`, `run/run_state.dart`.
- `lib/game/`: Flame. Só desenha e repassa input. `BattleWorld` roda com timestep fixo; `GridComponent`, `FighterComponent` e `ProjectileLayer` cuidam da renderização; `sprites.dart` guarda `SheetRects` e `GameSprites`.
- `lib/ui/`: overlays Flutter (HUD, mapa, telas de nó) e widgets (`ChipCardView`, `SheetSprite`).

**Regras de trabalho:**

1. Toda mecânica nova entra primeiro em `lib/domain/`, com teste em `test/`. Os testes são de domínio: montam um `BattleState` e chamam `tick()`, como os testes atuais.
2. Ao fim de cada fase, `flutter analyze` deve retornar 0 issues e `flutter test` deve passar.
3. Siga o estilo do código existente: comentários de doc em inglês, nomes em inglês, textos de jogo em português.
4. Não crie README nem outros `.md`. Não adicione abstração, configuração ou tratamento de erro além do pedido.
5. Sprites: chips, inimigos e painéis novos ainda não têm arte. Use um sprite existente da sheet como placeholder e marque com `// TODO(art)`. Não desenhe arte nova.
6. Antes de qualquer decisão de arquitetura que esta especificação não cobre (ex.: unidades que ocupam 2 células), pare e pergunte.
7. Ao terminar a fase, liste o que foi feito, o que ficou de fora e os valores de balanceamento que você teve de inventar.

**Constantes globais (já decididas):**

| Item | Valor |
| --- | --- |
| Tick | 30/s; 1 s = 30 ticks |
| Gauge | 300 ticks (10 s) |
| Mão | 5 chips do topo do deck. A cada gauge cheio, a mão inteira vai para o descarte e saem 5 novos |
| RAM base | 4 por mão, restaurada a cada gauge. A RAM não usada não acumula |
| Custo de chip | 0 a 3 RAM (campo `cost` existente) |
| Fraqueza de atributo | Fogo > Madeira > Elétrico > Aqua > Fogo. Dano ×2 |

---

## Fase 0 — Mão de 5 e RAM

**Objetivo:** substituir a regra atual (mão de 3, recarga só quando a mão está vazia) pela regra nova.

- `handSize = 5`.
- `_refillHand` dispara a cada gauge cheio: `deck.discardHand()`, `deck.draw(5)`, RAM restaurada, gauge zerado. A primeira mão sai no primeiro tick, porque o gauge começa cheio.
- `BattleState` ganha:
  - `int ramMax`: começa em 4 + bônus da run.
  - `int ram`: RAM disponível na mão atual.
  - `int ramBonus`: bônus temporário da mão, zerado a cada recarga.
- `_useChip` só executa se `cost <= ram`; ao executar, desconta o custo. Um chip que não cabe na RAM é ignorado e não sai da mão.
- Custos dos chips atuais: Tiro Simples 0; Tiro em V, Shotgun, Recuperar e Ataque +10 custam 1.
- Novos `ChipEffect` e chips:
  - `RamBurstEffect(amount)` → chip **Cache**: custo 0, Neutro, +2 RAM só na mão atual.
  - `RamMaxEffect(amount, cap)` → chip **Expansão de RAM**: custo 3, Neutro, +1 de `ramMax` até o fim da luta, acumulando até +3.
- HUD (`battle_hud.dart`):
  - Barra de RAM (atual/máx) ao lado do gauge.
  - O badge de custo volta ao `ChipCardView`.
  - Chips que não cabem na RAM aparecem com `dimmed: true`.

**Aceite (testes):**

- Ao encher o gauge, a mão antiga vai inteira para o descarte e 5 novos chips são comprados.
- Um chip com custo maior que a RAM não é usado e continua na mão.
- O Cache permite usar um chip que antes não cabia, e o bônus some na mão seguinte.
- A Expansão aumenta `ramMax` em 1 e para de acumular em +3.

---

## Fase 1 — Atributos e status

- Enum `Element { neutral, fire, aqua, elec, wood }` em `domain/`. Adicione o campo `element` em `ChipDef` e em `EnemyDef`; o padrão é `neutral`.
- O projétil carrega o elemento do chip. Em `_impact`, aplique a fraqueza: dano ×2 quando o elemento do ataque vence o do alvo.
- `Fighter.statuses`: `Map<Status, int>` com os ticks restantes, decrementado a cada tick.

| Status | Origem | Efeito | Duração |
| --- | --- | --- | --- |
| Queimando | 3º chip de uma corrente Fogo | 3 de dano/s | 3 s |
| Molhado | 3º chip de uma corrente Aqua; chip Bolha Empurradora | O próximo acerto Elétrico causa ×2 e remove o status | 5 s |
| Atordoado | 3º chip de uma corrente Elétrico; colisões | Não move, não ataca, não usa chip | Varia |
| Enraizado | 3º chip de uma corrente Madeira | Não move | 2 s |

- O jogador e os inimigos respeitam Atordoado e Enraizado: inimigos pausam o estado da IA; o jogador ignora o input correspondente.

**Aceite:** um teste por status e um teste de fraqueza.

---

## Fase 2 — Estados de painel

- `PanelState { normal, cracked, hole, ice, grass, lava }`. `BattleState.panels[x][y]` guarda o estado e um timer de retorno.

| Estado | Regra | Volta a Normal |
| --- | --- | --- |
| Rachado | Vira Buraco quando a unidade que está nele sai | Após 15 s vazio |
| Buraco | Ninguém entra (jogador, inimigo, obstáculo). Projéteis passam | Após 10 s |
| Gelo | Quem se move nele desliza na direção do movimento até a borda do lado ou até um obstáculo. Elétrico em unidade no Gelo atordoa 1 s | Após 8 s |
| Grama | Cura 1 HP/s de quem está nela. Chip Madeira usado de cima dela: +30% de dano. Fogo em quem está nela: ×2, e o painel volta a Normal | Após 15 s |
| Lava | 5 de dano/s para quem não é Fogo. Unidade Fogo sobre ela: +30% de dano. Aqua apaga na hora | Não volta sozinha |

- O movimento do jogador (`_tryMovePlayer`) e dos inimigos passa a checar se o painel é caminhável.
- `GridComponent` pinta o painel pelo estado. Use cores por enquanto (`// TODO(art)`).

**Aceite:** um teste para cada linha da tabela.

---

## Fase 3 — Deslocamento, colisão e obstáculos

- Introduza o conceito de ocupante. `_fighterAt` passa a considerar também obstáculos e invocações, que têm HP e time próprios ou neutros.
- Crie `_displace(unit, dx, dy, steps)`, que resolve célula a célula:

| A próxima célula é… | Resultado |
| --- | --- |
| Livre e do mesmo lado | A unidade entra e continua, se ainda restarem passos |
| Ocupada (unidade ou obstáculo) | Colisão: os dois levam 10 de dano e ficam Atordoados 0,5 s. O deslocamento para |
| Borda ou fronteira entre lados | Colisão contra a parede: 10 de dano e 0,5 s Atordoado, só na unidade empurrada |
| Buraco | Queda: 20 de dano, 1 s Atordoado, e a unidade volta ao painel de origem |
| Gelo | A unidade desliza até parar e resolve a célula final por esta mesma tabela |

- Nunca desloque uma unidade para o lado adversário.
- Novos `ChipEffect`: `PushEffect(steps)`, `PullEffect()` (traz o alvo até `(3, y)`; se ele já estiver na coluna 3, fica Atordoado 1 s) e `SpawnObstacleEffect(...)`.

**Aceite:** um teste por linha da tabela, mais o pull.

---

## Fase 4 — Os 12 chips novos

Implemente em `chip_library.dart`. `U` = célula do usuário; `I` = primeiro alvo atingido na linha.

| Chip | RAM | Atributo | Efeito | Alcance |
| --- | --- | --- | --- | --- |
| Rachador | 2 | Neutro | 20 de dano; o painel do alvo fica Rachado | Primeiro alvo da linha |
| Bolha Empurradora | 1 | Aqua | 10 de dano, aplica Molhado 5 s, empurra 1 | `I`, e desloca para `I+(1,0)` |
| Chama Cruzada | 2 | Fogo | 15 de dano em cruz; queima Grama | `I`, `I+(±1,0)`, `I+(0,±1)` |
| Lança Trovão | 3 | Elétrico | 15 de dano em cada alvo (×2 se Molhado) | Colunas 3, 4 e 5 da linha de `U` |
| Barreira | 1 | Neutro | Absorve 30 de dano, dura no máximo 5 s | `U` |
| Espelho | 2 | Neutro | Janela de 0,5 s: um projétil que acerte nela é anulado e devolvido pela linha com o dobro do dano | `U` |
| Semear Grama | 1 | Madeira | Os 9 painéis do jogador viram Grama por 15 s | Colunas 0–2 |
| Roubo de Área | 3 | Neutro | A coluna 3 vira do jogador por 10 s. Se houver inimigo nela, causa 10 de dano e o roubo falha | Coluna 3 |
| Rocha | 1 | Neutro | Obstáculo de 40 HP que bloqueia projéteis e pode ser empurrado (colisão de 30) | `U+(1,0)` |
| Mina | 1 | Neutro | Mina invisível para o inimigo; explode quando alguém pisa, 40 de dano | Painel vazio aleatório, colunas 3–5 |
| Torreta | 3 | Elétrico | Torre de 20 HP por 10 s; atira 5 de dano Elétrico por segundo na própria linha | `(0, y de U)` |
| Gancho | 1 | Neutro | Pull (Fase 3) | Primeiro alvo da linha |

- **Roubo de Área** exige que o dono da coluna seja dinâmico. Hoje `GridPos.owner` é fixo: mova a regra de dono para o `BattleState`.
- **Shotgun e Tiro em V:** mantenha o comportamento atual.

**Aceite:** um teste por chip, cobrindo o efeito principal.

---

## Fase 5 — Inimigos

- Hoje a IA é um `switch` fixo no `BattleState`, que só cobre o Mettaur. Troque por um comportamento por inimigo (ex.: `EnemyBehavior` com `tick(enemy, battle)`), referenciado pelo `EnemyDef`.
- **Telegrafia:**
  - Todo ataque registra os painéis que vai atingir com antecedência. Use uma lista de `Telegraph(pos, kind, ticksLeft)` no `BattleState`.
  - A `ProjectileLayer` desenha o contorno: vermelho para dano, azul para alteração de terreno.
  - O aviso dura no mínimo 0,5 s; nos inimigos básicos, 1 s.

**Básicos**

| Inimigo | HP | Atributo | IA | Ataque |
| --- | --- | --- | --- | --- |
| Mettaur (existente) | 30 | Neutro | Igual ao atual | Igual ao atual + telegrafia de 1 s |
| Raiz | 40 | Madeira | Parado | Mira a coluna do jogador: 15 de dano nos 3 painéis dela |
| Bolhador | 35 | Aqua | Fica nas colunas 4–5 | Bolha no painel do jogador: 10 de dano; o painel vira Gelo 8 s |
| Canhão Fixo | 50 | Neutro | Parado na coluna 5 | Se o jogador fica 1 s na linha dele, feixe instantâneo de 20 de dano. A Rocha bloqueia o feixe |

**Elites**

| Elite | HP | Atributo | Mecânica |
| --- | --- | --- | --- |
| Brute (revisado) | 80 | Neutro | Escudo frontal que bloqueia projéteis retos (não bloqueia diagonais nem dano por trás). Investida pela linha do jogador a cada 4 s: 25 de dano, aviso de 1,5 s. Uma colisão, ou a própria investida, derruba o escudo por 2 s |
| Escavador | 70 | Madeira | Afunda (invulnerável) e emerge em outro painel a cada 3 s; fica vulnerável por 1 s ao emergir. A picareta deixa um painel do jogador Rachado e, num segundo arremesso, Buraco. Se emergir num painel Rachado, cai |
| Dupla Prisma | 2 × 40 | Neutro | Duas unidades em linhas diferentes, que espelham o movimento uma da outra. Refletem projéteis retos e só tomam dano quando estão na mesma linha ou por dano de área |
| Guardião de Lava | 90 | Fogo | Cria 1 painel de Lava a cada 3 s, alternando o próprio lado e o lado do jogador. Lança-chamas nas colunas 1–2 da linha do jogador: 20 de dano |

**Chefes**

| Chefe | HP | Fase 1 | Fase 2 (abaixo de 50% do HP) |
| --- | --- | --- | --- |
| Colosso Sísmico | 300 | Martelada na coluna do jogador: 20 de dano, painéis Rachados; uma segunda martelada vira os Rachados em Buraco. O punho fica preso na coluna 3 por 2 s e recebe dano ×2 | Rouba a coluna 2 do jogador. Buracos voltam em 20 s. Ataques 25% mais rápidos. Roubo de Área recupera a coluna 2 e atordoa o Colosso 1 s |
| Maestro Elemental | 350 | Troca de atributo a cada 10 s (Fogo → Madeira → Elétrico → Aqua) e converte o próprio lado no painel correspondente. Aviso de 2 s antes de trocar | Invoca 2 Notas (20 HP) na coluna 3 e fica invulnerável enquanto alguma estiver viva. As Notas atingem 6 painéis do jogador em sequência (15 de dano cada); 3 ficam seguros. As Notas voltam após 15 s |

- O Colosso ocupa 2 células (`(4,y)` e `(4,y+1)`) e o punho é um ponto fraco separado. Antes de implementar, **pare e proponha** como representar unidades multi-célula.
- Atualize `Encounters`:
  - Batalhas normais sorteiam entre os 4 básicos, em grupos de 1 a 2.
  - Elites sorteiam entre as 4 elites.
  - O chefe é sorteado entre os 2.

**Aceite:** um teste de IA por inimigo (ex.: Raiz ataca a coluna certa; Canhão não dispara através da Rocha).

---

## Fase 6 — Zenny, loja e relíquias

**Valores que não estão no GDD (provisórios, ajustar em playtest):**

| Item | Valor |
| --- | --- |
| Zenny por luta | Normal 20, elite 40 |
| Preço na loja | Chip 50, remoção de chip 75, relíquia 150 |
| Itens da loja | 3 chips e 1 relíquia |
| Recompensa de elite | 1 relíquia aleatória |

- `RunState` ganha `zenny`, `ramBaseBonus` e `List<RelicDef> relics`.
- `RelicDef` tem ganchos opcionais, chamados pelo `BattleState` e pelo `RunState`: `onBattleStart`, `modifyDamage`, `onCollision`, `onChainComplete`, `onHandRefill`.

| Relíquia | Tipo | Efeito |
| --- | --- | --- |
| Pente de RAM | Global | +1 de RAM base |
| Pasta Ordenada | Global | Na recarga, mostra os 2 próximos chips do topo; o jogador pode mandar 1 para o fundo do deck |
| Cartão de Sócio | Global | Loja 25% mais barata; a primeira remoção em cada loja é grátis |
| Radar de Rede | Global | Revela os nós "?" e as elites até 2 andares à frente; 1 vez por run, permite pular para um nó vizinho |
| Linha de Frente | Combate | Chip usado na coluna 2: +20% de dano |
| Núcleo de Colisão | Combate | Colisão causada pelo jogador: +20 de dano e +1 s de atordoamento |
| Gatilho de Corrente | Combate | Corrente de 3 completa: o próximo gauge enche 50% mais rápido |
| Botas de Gelo | Combate | Imune a deslizar no Gelo; Rachado não vira Buraco quando o jogador sai |

- A tela de loja substitui o stub de loja em `node_screens.dart`.
- A Pasta Ordenada precisa de UI na recarga: um pop-up do HUD que pausa a luta até o jogador mandar um chip ao fundo ou manter a ordem.

**Aceite:** um teste por relíquia de combate e testes de compra e remoção na loja.

---

## Fase 7 — Eventos

- `EventDef(title, text, options)`; cada `EventOption` tem `label`, `cost` e `apply(RunState)`. Substitua o stub de evento.

**Servidor Corrompido**

| Opção | Custo | Recompensa |
| --- | --- | --- |
| Extrair os dados | Recebe o chip Bug: custo 0, sem efeito ao usar, ocupa uma vaga da mão | 1 chip aleatório de custo 3 |
| Depurar o servidor | −15 HP | Remove 1 chip à escolha + 1 relíquia de combate aleatória |
| Desconectar | — | — |

**Arena Clandestina**

| Opção | Custo | Recompensa |
| --- | --- | --- |
| Aceitar o duelo | Luta imediata contra uma elite aleatória, sem a recompensa normal de chip | 1 relíquia entre 2 + 100 Zenny |
| Apostar memória | −1 de RAM base, permanente | 1 entre 2 pares de fusão (os 2 chips vão para o deck) |
| Treinar com o Navi | −10 HP | Duplica 1 chip do deck |

- "Remove 1 chip à escolha" e "Duplica 1 chip" precisam de uma tela de escolha de chip do deck. Crie um único widget de seleção reutilizável.

**Aceite:** testes de `apply` para cada opção.

---

## Fase 8 — Corrente e fusão

**Corrente de atributo:**

- Usar um chip do mesmo atributo do anterior em até 2 s mantém a corrente. Neutro não inicia nem mantém corrente.
- O 2º chip da corrente causa +50% de dano; o 3º, +100%, e aplica o status do atributo (Fase 1).
- O HUD mostra o contador de corrente.

**Fusão:**

- `PlayerInput.holdUse`: o jogador segura Usar por 0,5 s (15 ticks) com o chip selecionado.
- Se o par do chip selecionado estiver na mão, os dois são consumidos. A fusão custa a soma da RAM dos dois.
- Durante a carga, o jogador fica parado.

| Par | Resultado | Efeito |
| --- | --- | --- |
| Bolha Empurradora + Lança Trovão | Tempestade | Molhado em todo o lado inimigo + 20 de dano Elétrico em cada painel (40 com Molhado) |
| Rachador + Rocha | Avalanche | Rocha rola pela linha: 40 de dano + empurrão 1. Painéis atravessados ficam Rachados |
| Gancho + Mina | Armadilha Magnética | Puxa o primeiro inimigo da linha para a coluna 3 e detona 50 de dano |

**Aceite:**

- A corrente aumenta o dano corretamente.
- A fusão consome os dois chips e cobra a RAM.
- Soltar Usar antes de 0,5 s usa o chip normal.
