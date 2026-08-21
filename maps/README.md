# Mapas do GranMap

O mapa topológico canônico usado pelo aplicativo está em
`app/assets/maps/gran_tiete_user_corrected_v10.json`.

O inventário das gravações de levantamento em campo fica em
`maps/field_capture_catalog.json`. Ele vincula cada arquivo ao POI e ao Node de
origem sem incluir os vídeos brutos no repositório.

Ele preserva nomes reais, mas separa percursos filmados de posições não
localizadas; geometria, ordem das salas e custos do grafo são provisórios. Não
copie o JSON para esta pasta: manter uma única fonte
evita que o Navigation Engine e a interface usem versões diferentes.
