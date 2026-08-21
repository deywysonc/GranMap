# GranMap — mapa topológico de evidências v8

> Versão histórica, substituída pela v9 após as correções espaciais desenhadas
> diretamente pelo autor do projeto.

## Por que esta versão existe

Os quatro vídeos de 20/08/2026 não permitem reconstruir uma planta baixa com
escala, ângulos, adjacências ou ordem completa das salas. A v8 abandona essa
pretensão e representa somente o que a evidência disponível sustenta.

## Convenção visual

- traço contínuo e caixa sólida: percurso ou área observada em vídeo;
- traço interrompido: relação informada, mas não filmada de ponta a ponta;
- caixa pontilhada e `?`: local real cujo posicionamento ainda não foi obtido;
- coordenadas `displayX/displayY`: composição topológica independente das
  coordenadas `X/Y/Z` usadas pelo simulador e pelo grafo A*.

## Evidências mapeadas

- Entrada Gran: circulação larga, coberta e parcialmente aberta;
- Entrada Tyto: corredor interno longo, com a entrada numa extremidade e a
  Secretaria informada no mesmo trecho;
- rampa: vários lances entre térreo e piso superior;
- piso superior: galeria coberta na chegada da rampa;
- Agronomia: área externa registrada, ainda sem ligação métrica levantada.

## O que permanece propositalmente não localizado

Ordem e lado das salas, quadra, lanchonete, biblioteca, financeiro, banheiros,
portão superior e conexões entre os trechos filmados. Todos continuam no
catálogo e no grafo da demo, mas não são apresentados como geometria real.

## Próximo levantamento

Para promover a topologia a planta navegável real, é necessário filmar cada
ligação sem cortes, registrar portas em sequência, medir pontos de controle e
validar o percurso no local. Uma planta autorizada ou varredura LiDAR acelera
o processo, mas não é obrigatória.
