# GranMap — contrato do mapa conceitual v6

> Documento histórico. A versão atual está descrita em `MAPA_CAMPO_V7.md`.

## Fonte canônica

O aplicativo carregava `app/assets/maps/conceptual_campus_v6.json` nesta versão.

Os nomes das 27 salas são reais. Coordenadas, ordem das portas, dimensões,
custos das arestas e desenho são provisórios e não representam metros.

## Regras estruturais preservadas

- A Entrada Gran inicia o corredor 1 em linha reta, com uma pequena mudança de
  direção antes do trecho longo.
- A Entrada Tyto/Gran + Secretaria fica no começo do corredor 2.
- O corredor 2 possui portas dos dois lados.
- Os corredores 1 e 2 não possuem ligação lateral entre si.
- Ambos terminam na mesma região aberta da quadra.
- Lanchonete fica à esquerda da quadra; biblioteca, financeiro e banheiros
  ficam no setor de serviços à direita.
- Portão Superior pertence exclusivamente ao piso 1.
- Na versão conceitual, a conexão vertical era representada como rampa em
  caracol; o levantamento posterior mostrou uma rampa em lances.
- Área de agronomia e sala em construção são referências do piso superior.

## Garantias automatizadas

`app/test/map_contract_test.dart` valida catálogo, integridade do grafo,
separação dos corredores, encontro na quadra, portas dos dois lados, Portão
Superior, rampa entre pisos e ausência de métricas físicas falsas.

`backend/test_map_alignment.py` garante que o catálogo do backend usa os mesmos
POI IDs reais do mapa Flutter.
