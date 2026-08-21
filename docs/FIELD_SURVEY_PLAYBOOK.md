# GranMap — playbook de levantamento da Gran Tietê

Este é o trabalho que falta para trocar o mapa conceitual por um mapa fiel da faculdade.
Ele depende de presença física e autorização; o software para receber os dados
já existe.

## 1. Geometria e acessibilidade

- obtenha a planta autorizada ou faça levantamento métrico/LiDAR por piso;
- escolha origem e eixos X/Y/Z comuns e meça a elevação real dos pisos;
- registre portas, largura útil, sentido de acesso, rampas, escadas, elevadores,
  obstáculos, inclinação e rotas acessíveis;
- mantenha IDs estáveis ao mover Nodes e POIs no editor versionado;
- publique primeiro como rascunho e valide cada rota crítica presencialmente.

## 2. Entradas e GPS

- meça latitude/longitude das entradas em área aberta;
- registre o ponto X/Y/Z e a direção correspondente de cada entrada;
- use GPS somente para escolher/reancorar uma entrada, nunca para prometer
  precisão dentro do prédio.

## 3. Placas QR

- instale QR em entradas, mudanças de piso e pontos de decisão;
- o conteúdo deve ser apenas um código opaco como `GRAN-RAMPA-TERREO`;
- cadastre o código no Admin com Node, piso, coordenadas e orientação;
- teste leitura em diferentes alturas, luzes e aparelhos.

## 4. Campanha magnética

- use o GranMap Lab com a versão correta do mapa;
- em cada Node/trecho, capture várias amostras parado e caminhando, em quatro
  orientações, com modelos Android/iPhone diferentes;
- nunca colete identidade, áudio, imagem ou posição fora da faculdade;
- descarte leituras com baixa qualidade e repita após grandes reformas ou
  mudanças de estruturas metálicas.

## 5. Street View e conteúdo 360°

Para um Street View fotográfico real, sim: é necessário gravar/fotografar a
faculdade. Use câmera 360° em rota contínua ou panoramas espaçados em pontos de
decisão. Faça a captura fora do horário cheio, sinalize a atividade, evite
rostos/documentos e aplique desfoque antes de publicar. Cada panorama precisa
de Node, piso, direção inicial e licença/autorização.

O Walk View atual não depende dessas imagens: ele navega pelo Digital Twin.
Os panoramas podem ser acrescentados depois como outra visualização da mesma
`NavigationSession`.

## 6. Validação

- crie uma matriz de origem/destino incluindo todos os pisos e POIs críticos;
- teste com pessoas novas na faculdade e com usuários de mobilidade reduzida;
- compare caminho sugerido, caminho realizado, erro de posição e tempo;
- registre divergências como issues ou contribuições e publique uma nova versão;
- só marque geometria/distância como validada após aprovação institucional.
