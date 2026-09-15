# Café no Notch

App de macOS, estilo Dynamic Island, que mostra a temperatura do seu café no
notch. Ao registrar um café, um halo colorido aparece em volta da câmera e vai
esfriando com o tempo (verde → âmbar → vermelho). Clicando no notch, a ilha
cresce num card com o estado atual e o histórico do dia.

Sem café, a borda fica num tom café com leite sólido. Com café, ela ganha a cor
da fase e um brilho suave.

## Requisitos

- macOS 14 ou superior (usa APIs de `SwiftUI` do macOS 14).
- Xcode ou apenas as Command Line Tools (`xcode-select --install`).

## Como rodar

```bash
./build.sh && open CafeNoNotch.app
```

O `build.sh` compila com `swiftc` direto e gera o `CafeNoNotch.app`. O app abre
sem ícone no Dock e sem item na barra de menus — ele vive no notch.

> Observação: este projeto evita o SwiftPM de propósito. Em algumas instalações
> só com Command Line Tools o `swift build`/`swift run` falha no link do
> manifesto; o `build.sh` contorna isso compilando os fontes diretamente. Com um
> Xcode completo, o `Package.swift` também funciona.

Para testar já com um café aceso (sem esperar o atalho):

```bash
./CafeNoNotch.app/Contents/MacOS/CafeNoNotch --brew
```

## Como usar

- Clique no notch para abrir ou fechar o card.
- O card tem três abas (Café, Foco, Sobre); troque com dois dedos no trackpad ou
  pelas bolinhas.
- Atalho global: nenhum por padrão. Dá para definir um na aba "Sobre" →
  "configurar" (funciona de qualquer app; deixe vazio para não usar).

## O que cada controle faz

- **Fiz um café** — registra um café recém-feito: zera o cronômetro, acende o
  halo (verde) e adiciona o horário à lista do dia.
- **Bolinhas** (canto inferior esquerdo) — trocam entre as abas. Também dá para
  trocar com swipe de dois dedos.
- **configurar** (aba Sobre) — abre as Configurações para definir ou remover o
  atalho global.
- **ver no GitHub** (aba Sobre) — abre o repositório no navegador.
- **Dormir** — descarta o café atual e volta ao estado sem café (borda café com
  leite, sem contagem de tempo).
- **Sair** — encerra o app.

## Visual

O card é uma peça de "vidro obsidiana" (gradiente escuro que funde com o notch) e
usa **mostradores circulares** — que ecoam o formato da câmera e do halo:

- **Café** — um arco de calor de 270° com a temperatura no centro (e uma
  fumacinha quando está quente) mostra o estado; rolando/abaixo vem o **histórico
  do dia** numa linha do tempo (manhã → agora), com um ponto por café e o mais
  recente em branco.
- **Foco** — um anel de progresso que drena com o tempo restante (`MM:SS`) no
  centro.

## Abas do card

- **Café** — estado do café (fase, dica, temperatura no mostrador, há quanto
  tempo foi feito e quanto falta pra esfriar) e, logo abaixo, o histórico do dia.
- **Foco** — cronômetro de pomodoro: tempo restante, iniciar/pausar/zerar e a
  duração configurável (chips de 15/25/30/45/50 min, salva automaticamente).
  Ao chegar a zero, dispara uma notificação do macOS e um som.
- **Sobre** — versão, status de atualização (checado no GitHub), atalho atual e
  os botões "configurar" e "ver no GitHub".

## Café + Foco no mesmo halo

O halo do notch é compartilhado entre café e foco. Com os dois ativos, o anel se
divide ao meio: **metade esquerda** na cor do café (fase de calor) e **metade
direita** na cor do foco (azul). Com só um ativo, aparece só a metade dele; a
outra funde com a ilha.

## Estados (conforme o café esfria)

| Tempo desde o café | Fase          | Cor do halo |
|--------------------|---------------|-------------|
| sem café           | Cadê o café?  | café com leite |
| 0–10 min           | Quentinho     | verde       |
| 10–20 min          | Ainda salva   | verde-amarelado |
| 20–28 min          | Tá esfriando  | âmbar       |
| 28+ min            | Frio          | vermelho    |

O tempo total até "frio" é de ~30 min (`CoffeeModel.coolMinutes`).

## Estrutura

- `Sources/CafeNoNotch/CoffeeModel.swift` — estado do café, curva de
  temperatura, cores por fase e textos.
- `Sources/CafeNoNotch/HaloView.swift` — a ilha: halo, morph de abrir/recolher e
  o conteúdo do card.
- `Sources/CafeNoNotch/NotchWindow.swift` — janela transparente ancorada no
  notch (`safeAreaInsets` / `auxiliaryTop*Area`), swipe de dois dedos e clique
  fora para recolher.
- `Sources/CafeNoNotch/HotKey.swift` — atalho global via Carbon (não precisa de
  permissão de Acessibilidade) e helpers de modificadores.
- `Sources/CafeNoNotch/Settings.swift` — janela de Configurações e o gravador de
  atalho.
- `Sources/CafeNoNotch/Version.swift` — versão do app e checagem de atualização.
- `build.sh` — compila e monta o `.app`.

## Notas

- Em Macs sem notch físico, o app desenha uma "pílula" preta no topo da tela.
- A janela é transparente, ignora cliques quando recolhida sobre o notch, fica
  no nível da barra de status e acompanha todos os Spaces.
