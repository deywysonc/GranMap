# GranMap: mapa v12 e interface 1.6.3

## Base utilizada

O piso superior segue as proporções relativas de
`maps/references/PAV.SUPERIOR-Gran-Tiete-Layout1.pdf`. A fileira à direita,
com laboratório, laboratório de projeto e sala, tem profundidade menor que
as salas à esquerda. A circulação muda de alinhamento nesse trecho. O BWC
masculino fica acima do feminino na orientação da prancha. Arquivo separado
e portão na lateral esquerda são mantidos. A correção mais recente do autor
prevalece sobre a hipótese anterior da rampa no canto inferior esquerdo:
Agronomia fica abaixo da galeria, à esquerda da rampa, nas áreas marcadas.
O espaço entre a galeria e essas duas áreas foi confirmado como amplo e
caminhável: não é somente um corredor estreito.

Os nomes acadêmicos associados às salas continuam do catálogo existente;
a planta identifica usos, não esses nomes. Agronomia, rampa e seus acessos
seguem as posições relativas indicadas pelo autor, ainda sem levantamento
presencial. Não há alegação de escala métrica.

No térreo, as correções espaciais fornecidas pelo autor prevalecem:

- dois corredores paralelos, Gran acima e Tyto/Secretaria abaixo;
- entrando pela Gran em direção ao interior, salas no lado esquerdo;
- sala com rampa no lado direito da pequena curva;
- Secretaria junto da entrada Tyto, com salas dos dois lados do corredor;
- quadra após as duas terminações e serviços no lado oposto;
- lanchonete à esquerda e rampa logo à direita, ambas de frente à quadra,
  ao norte dela e com acessos voltados ao sul por uma frente compartilhada;
- dois conjuntos de Laboratórios de Química: acima da Entrada Gran e à
  esquerda da sala com rampa, preservando o Laboratório de Química existente.

O grafo contorna a quadra por áreas de circulação. Chegar à Quadra termina
na sua entrada, não no centro da área de jogo.

## Correções indicadas nas imagens

Os dois conjuntos de Química são áreas agrupadas, não um inventário de salas.
Não foram atribuídos números, quantidade ou nomes oficiais. Os rótulos são
descritivos e distintos para permitir busca e seleção do conjunto correto.
As zonas têm `verification: user_reported_approximate`; os acessos têm
`verification: access_unverified` e `type: provisional_access`, sem símbolos
de portas reais. Como a acessibilidade não foi aferida, esses novos acessos
aos laboratórios não são apresentados como rotas acessíveis confirmadas.

Na composição relativa do térreo, o conjunto da entrada ocupa x4–26/y83–91;
o conjunto ao lado da sala com rampa, x0–13/y54–64. A lanchonete ocupa
x115–125/y77–92 e a rampa fica logo à direita, x126–137/y77–92. Ambas estão
alinhadas à projeção da quadra (x115–137/y24–64), com uma frente compartilhada
ampla em x104–145/y64–77. Os acessos chegam pela borda sul, sem atravessar
a lanchonete para subir a rampa. Essa orientação foi informada pelo autor;
não constitui medição da posição ou largura real de portas.

No piso superior, Agronomia ocupa x84–109/y1–17 e a rampa, x117–144/y1–17.
O grande espaço caminhável ocupa x4–151,9/y17–48,8, continuando à direita
até y58,5 sob a galeria dos laboratórios. As antigas faixas estreitas foram
fundidas nessas superfícies. O Arquivo (x34–75,6/y8–13,1), as salas e suas
proporções não foram ampliados nem incorporados à circulação.

O grafo conserva os IDs dos nós, locais e ligações anteriores e acrescenta
caminhos pela esquerda, centro e direita do espaço amplo. Os atalhos têm
`type: open_area`, `verification: access_unverified` e `accessible: false`:
o usuário confirmou que se pode caminhar nessa área, mas não houve auditoria
de obstáculos ou acessibilidade. Rotas comuns podem usar os atalhos, enquanto
as ligações anteriores permanecem disponíveis às rotas acessíveis existentes.
Todas essas coordenadas e os custos das ligações são conceituais, não metros.

Os IDs existentes e a sequência da rampa entre os pisos foram preservados.
As posições dos lances foram ajustadas ao desenho; a observação em vídeo
confirma a sequência, não dimensões nem a localização exata de cada lance.
As novas ligações do piso superior também são acessos aproximados. Os XYZ
conceituais existentes não foram recalibrados para representar metros.

## Experiência no app

- Planta 2D com proporções uniformes, paredes, portas, salas e serviços.
- Pinça/arrasto, zoom por botões e enquadramento da planta.
- Nomes abreviados na visão geral; nome completo ao selecionar o local.
- Maquete 3D de um piso por padrão, giro, zoom e dois pisos opcionais.
  Em tela pequena, nomes de salas aparecem ao ampliar; rótulos não se sobrepõem.
- Seleção em 2D/3D abre detalhes e o botão “Ir para cá”.
- Rotas mantêm o grafo A*, os bloqueios, a referência de piso e os sensores.
- Street View/Walk foi removido da interface ativa e dos assets empacotados.
  Os arquivos originais não foram apagados.
- AR permanece opção de câmera, ainda sujeito a permissões e calibração.
- Esperas do GPS têm prazo real, inclusive quando o plugin não responde;
  a exploração do mapa continua disponível e a leitura pode ser repetida.

## Publicação e compatibilidade

Dados executáveis: `app/assets/maps/gran_tiete_floorplan_v12.json`.
Gerador reproduzível: `node scripts/build_map_v12.mjs`.
São 61 zonas, 104 nós, 117 conexões e 44 locais; todos continuam ligados às duas entradas
pelas rotas comuns, incluindo os dois novos conjuntos de laboratórios.

O backend local promove automaticamente somente o seed v11 intocado,
preservando usuários, grade e bloqueios. Uma publicação institucional alterada
mantém prioridade, e a v12 entra como rascunho. O app também reconhece apenas
o checksum exato do seed antigo ao usar a planta atualizada incluída no APK,
traduzindo os bloqueios dos segmentos reorganizados. Mapas personalizados
do Admin não são substituídos por esse mecanismo.

As alterações estão na hospedagem do próprio PC, incluindo web e APK.
Revisão publicada pela API: `pc-floorplan-v12-20261015-circulation`.
Não houve publicação no Coolify ou GitHub. O link HTTPS é temporário e consta
no arquivo privado `.secrets/pc-access.txt`; reiniciar o túnel muda o endereço.

## Validação

224 testes Flutter, 49 testes de backend/bootstrap, 3 do Admin e 4 de snapshot
passaram na entrega 1.6.3, com análise sem problemas. Além dos testes de
proporção, seleção e rotas entre pisos, há regressões do chão contínuo sem
emendas/tracejado, dos atalhos dentro da superfície caminhável, de toques no
chão vazio e da lanchonete como destino terminal, não passagem para a rampa.

Web e Android nas três arquiteturas compilados. Assinatura v2 e planta/URL
incluídas no APK verificadas; download público completo e Range 206 aprovados.
Evidências 2D/3D em `deliverables/GranMap-v1.6.3-*.png` e detalhes em
`docs/RELEASE_NOTES_V1_6_3.md`. A calibração física, instalação no celular e
conferência de acessibilidade continuam pendentes de teste presencial.
