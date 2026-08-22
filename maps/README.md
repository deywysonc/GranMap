# Mapas do GranMap

O mapa topológico canônico usado pelo aplicativo está em
`app/assets/maps/gran_tiete_upper_floorplan_v11.json`.

A prancha usada para redesenhar o piso superior está preservada em
`maps/references/PAV.SUPERIOR-Gran-Tiete-Layout1.pdf`; as decisões de modelagem e
os pontos ainda provisórios estão descritos em `docs/PLANTA_SUPERIOR_V11.md`.

O inventário das gravações de levantamento em campo fica em
`maps/field_capture_catalog.json`. Ele vincula cada arquivo ao POI e ao Node de
origem sem incluir os vídeos brutos no repositório.

Ele preserva nomes reais, mas separa percursos filmados de posições não
localizadas; geometria, ordem das salas e custos do grafo são provisórios. Não
copie o JSON para esta pasta: manter uma única fonte
evita que o Navigation Engine e a interface usem versões diferentes.
