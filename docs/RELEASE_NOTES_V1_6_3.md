# GranMap 1.6.3 — circulação ampla e frente da quadra

Build Android 15; API 0.12.1. Publicação em 15/10/2026.

## Planta e navegação

- O espaço abaixo da galeria superior agora é uma área ampla caminhável,
  com continuidade sob a galeria dos laboratórios da direita. As salas,
  Arquivo, Agronomia e rampa não foram incorporados à área aberta.
- Quinze ligações novas distribuem a navegação pela esquerda, centro e direita
  dessa área, sem atravessar salas. São aproximadas e não têm acessibilidade
  aferida; as ligações anteriores permanecem disponíveis.
- No térreo, lanchonete à esquerda e rampa à direita estão alinhadas de frente
  à quadra, com uma circulação ampla compartilhada. A lanchonete é um destino
  terminal, não um atalho para chegar à rampa.
- Áreas abertas não recebem paredes internas nem eixo tracejado em 2D.
  As novas ligações de navegação não viram linhas físicas na maquete 3D;
  continuam disponíveis para o desenho da rota selecionada.

Mapa: 61 zonas, 104 nós, 117 conexões e 44 locais. Coordenadas, dimensões e
custos continuam conceituais, não metros levantados em campo. A confirmação
do espaço caminhável não equivale a uma auditoria de obstáculos/acessibilidade.

Revisão publicada: `pc-floorplan-v12-20261015-circulation`.
Checksum canônico:
`5dad892fc46fe908e094aa42162ce8343dee3ea43baa44cced551253b34eaa47`.
A revisão anterior foi preservada no histórico, assim como os dados acadêmicos.

## Publicação no PC

Web e APK incluem a mesma planta. O túnel reiniciou junto com o ambiente entre
as sessões, invalidando o endereço anterior. O endereço atual foi recuperado
dos logs, conferido e aplicado à origem permitida e ao APK; o túnel não foi
reiniciado durante esta atualização. Links atuais em `.secrets/pc-access.txt`.

O link continua temporário e depende do PC/Docker/internet. Se o túnel mudar,
o APK precisará de outra atualização de endereço. Nenhum domínio ou serviço
pago foi contratado; Coolify e GitHub permanecem sem alterações.

Backup anterior à mudança e backup da versão em `.secrets/pc-backups`, com
catálogo verificado por `pg_restore --list`. Nenhum banco ativo foi restaurado
ou apagado nesta atualização.

## Verificação desta versão

- 224 testes Flutter, 49 de backend/bootstrap, 3 do Admin e 4 de snapshot:
  todos passaram. Análise Flutter sem problemas.
- Testes cobrem continuidade visual do piso, emendas sem paredes/tracejado,
  seleção de salas sem capturar chão vazio, cobertura dos novos caminhos e
  ausência de atalho pelo interior da lanchonete.
- Web release e Android ARM64, ARM 32 bits e x86_64 compilados.
- Planta 2D dos dois pisos e maquete superior conferidas na prévia local;
  planta superior também aberta e conferida no endereço HTTPS público.
  Evidências em `deliverables/GranMap-v1.6.3-*.png`.
- API pública serve a revisão correta e anuncia build 15; origem permitida
  atualizada. Download público completo idêntico ao APK local e Range 206.
- Assinatura v2, versão, pacote, SDK, URL pública e planta embutida conferidos.
- Sem aparelho conectado: instalação e sensores reais ainda dependem de teste
  no celular, e a geometria exige conferência presencial.

APK ARM64: `deliverables/GranMap-Demo-v1.6.3-pc-arm64-v8a.apk`.
Tamanho: 27.834.576 bytes. SHA-256:
`B905042EE65E2D14E826D2885AF2D24AA892EFEECE24121D9F48708C2BD29736`.
Mesmo certificado de demo da versão anterior; não é a chave definitiva da loja.
