# DESIGN — StarCop's Raid

Jogo para celular em **paisagem**, controlado por toque e gestos, sem
controles na tela. Tudo usa a paleta do **Picotron**, a mesma das artes.

## Ambientação e termos

A jogadora é uma policial espacial em missões. A primeira missão é contra
uma organização criminosa: os capangas são os inimigos das lutas normais e o
Tanque de Guerra é o chefe.

Nos textos do jogo:
- **carta**, nunca "chip" (no código as classes continuam `ChipDef`,
  `ChipCard`, `Chips`);
- **Energia** (`EN` no HUD), nunca "RAM";
- **Créditos** (`C` nos preços), com o ícone `chips/cred.png`.

Não existe parceiro: a policial luta sozinha.

Os tokens ficam em `lib/ui/theme.dart` (`Pico`, `GbText`). Não escreva cores
ou tamanhos direto nos widgets: crie um token.

## Layout

- Só paisagem. O `GameWidget` ocupa a tela inteira dentro de uma `SafeArea`,
  sobre fundo preto. A tela virtual é centralizada e as sobras ficam pretas.
- `SafeArea` vale só em volta do `GameWidget`, nunca dentro da tela virtual.

## Tela virtual

- Os menus (descanso, recompensa...) são desenhados num espaço virtual de
  **384×192** (`virtualScreen`).
- A batalha e o mapa usam um espaço largo, **384×192** (`wideScreen`, 2:1), o
  mesmo da câmera do Flame. O HUD, a pausa e o deck usam esse tamanho, para
  ficarem alinhados com a grade. A loja e os eventos também, para usar a
  largura toda.
- Evento (como no Slay the Spire): título numa faixa em cima, imagem
  quadrada à esquerda (placeholder até ter arte), texto à direita e as
  opções embaixo dele: `[rótulo]`, o ganho em verde e o custo em coral.
- Loja (como no Slay the Spire): 5 cartas em cima e o serviço de remoção à
  direita; embaixo, Sair, 3 relíquias (só o ícone), uma caixa com a
  descrição do item selecionado e Comprar (Remover, no serviço). Tocar só
  seleciona (borda amarela); Comprar compra. Sem Créditos bastantes, o
  botão fica desabilitado e a caixa diz "Faltam N C" em `Pico.coral`.
- Espólios: o título conta os restantes ("Espólios · 2 restantes"); o que
  já foi pego fica na lista, riscado e apagado, com "PEGO". "Pular
  restantes" com espólios sobrando pede confirmação, listando o que se
  perde, com o foco em "Voltar".
- Fim de run: faixa com o resultado (MISSÃO CUMPRIDA `Pico.green`, FALHOU
  `Pico.red`, ABANDONADA `Pico.orange`), o relatório (ato e andar,
  batalhas vencidas, inimigos derrotados, Créditos ganhos, relíquias,
  carta mais usada) e o deck final, em janelas PET; Nova run e Menu.
- Os overlays usam `VirtualScreen`, que os escala com `FittedBox`.
- Dentro da tela, os tamanhos são px virtuais, não dp.
- A escala de fonte do sistema é ignorada dentro da tela
  (`TextScaler.noScaling`), para o layout não quebrar.
- A grade da batalha fica em (72, 40), centralizada, com 240×96 px.
- A coluna à esquerda da grade (x 2–66) tem três janelas PET (`petWindow`:
  fundo `Pico.midnight`, borda `Pico.royal`, dois cantos cortados):
  - em cima, o status: HP grande, Energia embaixo e o gauge com o rótulo
    "CARGA"; cheio, ele pisca amarelo e branco. Ao tomar dano, o HP treme
    em vermelho, a borda fica vermelha (`petAlert`) e o HP perdido sobe
    sobre a janela ("-30") por 1 s. Abaixo de 1/4 do HP máximo, o número
    pisca vermelho e a borda da tela pulsa vermelha;
  - no meio (y 41), a carta selecionada por inteiro: arte, nome em
    amarelo, custo, dano, família na cor dela e descrição. Na mão, a
    mesma carta tem contorno amarelo;
  - embaixo, as pilhas de compra e descarte; quando a próxima mão vai
    embaralhar o descarte, diz "Embaralha na próxima mão".
- Com a mão vazia, o lugar dela mostra "MÃO VAZIA · nova mão quando a
  CARGA encher", em amarelo.
- A corrente fica numa linha acima da grade
  (y 3), longe dos sprites; enquanto a batalha espera a jogadora, a mesma
  linha mostra "AGUARDANDO · mova ou use uma carta" em `Pico.yellow`.
- À direita da grade, abaixo dos ícones, cada inimigo tem nome, tipo
  (Máquina, Orgânico, Etéreo, em `Pico.lightGray`) e barra de vida
  (vermelha, borda branca); nomes repetidos são numerados ("Prisma 2").
- Um Etéreo em fase (balas e golpes o atravessam) é desenhado com metade
  da opacidade.
  O HP não aparece mais sobre os inimigos, só sobre os obstáculos.
- A mão fica numa linha embaixo, encostada à direita. Os ícones de deck e
  pausa ficam no canto superior direito.
- O mapa ocupa a largura toda e é mais alto que a tela: 28 px por andar, nós
  de 20 px. Ele abre rolado até o andar que pode ser escolhido, e o resto se
  vê arrastando (o mouse também arrasta). Nos nós que podem ser escolhidos
  só a borda pisca (amarelo e branco); o nó atual tem borda branca e os
  outros ficam a 45% de opacidade. O caminho já feito é uma linha sólida
  `Pico.blue`; do nó atual aos escolhíveis, sólida `Pico.yellow`; o resto,
  tracejado branco. A policial fica à direita do nó atual, com a
  etiqueta "VOCÊ". O cabeçalho, uma janela PET (selo do ato em
  `Pico.orange`, barra de HP, deck, créditos, relíquias), fica fixo em
  cima. O botão "?", ao lado da pausa, abre a legenda dos nós; segurar
  um nó mostra o que ele é e o que dá.

## Cor

Use só as 32 cores de `Pico`, a paleta do Picotron (as 16 do PICO-8 mais
16 próprias), inclusive no que o Flame desenha:
- Fundo dos menus: `Pico.darkBlue` com scanlines (`Scanlines`: uma linha
  `Pico.midnight` a 35% a cada 2 px). O fim de run usa `Pico.midnight`.
- Títulos de tela (`_Panel`) ficam numa barra `Pico.royal`, em maiúsculas.
- O menu principal põe as opções numa janela PET ("> MENU") e a policial
  (3×) à esquerda, sobre uma plataforma `Pico.royal`.
- O mapa tem fundo preto com uma grade `Pico.royal` a 35% a cada 16 px;
  os nós têm fundo preto para a grade não cruzar o ícone.
- Jack-in: ao entrar numa batalha, 12 faixas em duas cores cobrem a tela
  com a palavra no meio (0,36 s) e recuam para lados alternados em 8
  passos (0,54 s). Batalha: `Pico.blue`/`Pico.royal`, "JACK IN"; elite:
  `Pico.orange`/`Pico.pumpkin`, "ELITE"; chefe: `Pico.red`/`Pico.burgundy`,
  o nome do chefe. Toques são ignorados durante; com "reduzir movimento"
  no sistema, não aparece.
- Texto: `Pico.white`.
- Destaque: `Pico.yellow`. Foco: `focusFill` (`Pico.blue`).
- Ataque: `Pico.red`. Suporte: `Pico.orange`. Recuperação: `Pico.green`.
- Energia: `Pico.blue`.
- Raridade (`rarityColor`): Comum `Pico.lightGray`, Incomum `Pico.blue`,
  Raro `Pico.orange`.
- Família da carta (`familyColor`), sobre a caixa cinza da descrição:
  Projétil `Pico.peach`, Explosivo `Pico.orange`, Energia `Pico.blue`,
  Corpo-a-corpo `Pico.red`, Equipamento `Pico.lightGray`, Consumível
  `Pico.green`, Tático `Pico.pink`.

## Sprites

- Painéis: o sprite do estado (`panels/panel_panel*.png`) e, por cima, a
  moldura do lado dono do painel: `panels/panel-panelPlr.png` (jogadora) ou
  `panels/panel-panelEnemy.png` (inimigo). A moldura troca junto com o dono
  (Avanço, Colosso). Não há mais cor de fundo por lado.
- Personagens têm frames quadrados lado a lado: 16×16 na arte antiga, 24×24
  na nova (jogadora, capangas, Torreta, Colosso, Maestro) e 40×40 no Tanque
  de Guerra (`actors/Tank.png`), que ocupa 2 painéis lado a lado e é
  desenhado centrado entre eles. Inimigos usam 2 frames
  (parado, ataque); a jogadora usa 3 (parada, tiro, golpe/arremesso).
- Na batalha, tudo (painéis, unidades, obstáculos, projéteis, efeitos) é
  desenhado na mesma escala, 2×, para o pixel da arte ter o mesmo tamanho em
  todo lugar. Não escale um sprite para caber: quem precisa ser maior ou
  menor muda na própria arte.
- Escudo de energia (Escudo de Energia da jogadora, escudo frontal do
  Brute): `projeteis/eShld.png` em loop, 0,1 s por frame, centrado na
  unidade. O tamanho do frame é a altura do arquivo.
- Sinal de ataque: `actors/sign.png` (2 frames de 16×16, piscando a cada
  0,1 s) sobre a cabeça do inimigo no último 0,5 s antes de um ataque dele
  cair; some quando o ataque acontece. Os painéis em vermelho continuam
  avisando pelo tempo todo.
- Cartas melhoradas na fogueira têm "+" no nome, usam a mesma arte da
  carta base e são desenhadas no frame `chips/chipEvo.png` em vez do
  `chips/chip.png`.
- A carta é um retângulo 2:3: o frame `chips/chip.png` tem 32×48 e a carta
  é desenhada com a largura pedida e altura 1,5× ela. Na mão da batalha
  as cartas têm 36 de largura (54 de altura), para caber entre a grade e a
  borda de baixo.
- A arte das cartas cabe na janela preta do frame (22×13 px do frame):
  ícones de 8 px saem a 1,25×, artes maiores (32 ou 40 px) são reduzidas
  para caber. O custo fica no círculo azul, o dano no vermelho e o ícone do
  elemento entre os dois. A descrição começa com a família da carta
  (Projétil, Explosivo...), na cor dela.
- Cartas incomuns e raras têm uma borda na barra do nome, na cor da
  raridade; as comuns ficam com o frame original.

## Tipografia

Tamanhos em px virtuais, dentro da tela:

| Token | Tamanho | Uso |
| --- | --- | --- |
| `GbText.small` | 7 | legendas, preços, pilhas |
| `GbText.body` | 8 | texto normal, botões |
| `GbText.title` | 11 | título da tela |

- Nada menor que 7.
- Todo texto usa a fonte pixel `assets/fonts/pixel.ttf` (família `Pixel`,
  constante `pixelFont`), inclusive os textos desenhados pelo Flame.

## Foco e input

- Todo menu é jogado por toque. Teclado (setas, Enter, Esc) também funciona
  pelo foco do Flutter: as setas movem o foco, Enter confirma e Esc volta,
  onde houver para onde voltar.
- Botões são PET: fundo `Pico.midnight`, borda `Pico.lavender` de 0,5 px e
  dois cantos cortados. O foco é o cursor do Battle Network: o botão
  preenchido de `Pico.blue`, texto `Pico.midnight` e borda branca de 1,5 px.
  Cartas e nós do mapa seguem com a borda `Pico.yellow`. O overlay de foco
  do Material não aparece nessa escala e não é usado.
- Na batalha:
  - Deslizar o dedo em qualquer lugar fora da mão e dos ícones move uma casa na direção dominante.
    Continuar arrastando sem soltar move mais uma casa a cada ~18 px
    virtuais, com no mínimo 0,3 s entre um passo e o próximo.
  - Tocar numa carta a usa.
  - Swipe e toque que caem durante um cooldown ficam guardados por alguns
    ticks, em vez de se perderem.
  - Os ícones no topo pausam ou mostram o deck. No mapa, o botão "Deck"
    mostra o deck. Tocar em qualquer lugar fecha a pausa ou o deck. Na
    batalha, o deck tem abas: Compra (agrupada, sem revelar a ordem), Mão,
    Descarte e Deck; tocar fora das abas fecha.
  - A pausa tem Continuar, Ver deck, Manual (por cima da run; "Voltar"
    volta à pausa), Configurações e Abandonar run, que pede confirmação
    e termina a run com o relatório.
  - Teclado (desktop): setas/WASD movem, X/K usa a carta, Z/J passa para a
    próxima.
- Swipe e cartas usam `Listener` puro, sem arena de gestos, para segurar uma
  carta com um dedo e deslizar com o outro.
- Vibração (`lib/ui/feedback.dart`):
  - toque em botão, carta, nó do mapa ou ícone: `tapFeedback` (leve,
    `lightImpact`). Botões novos passam o callback por `withTap`;
  - cada passo do swipe: `HapticFeedback.selectionClick`;
  - a jogadora toma dano: `hurtFeedback` (`heavyImpact`).
- Quem toma dano pisca em branco: 3 ticks branco, 3 normal, duas vezes
  (`hurtFlashTicks`).
