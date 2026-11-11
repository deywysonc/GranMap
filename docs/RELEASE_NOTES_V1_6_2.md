# GranMap 1.6.2 — mapa corrigido e publicação no PC

Build Android 14; API 0.12.1. Publicação em 14/10/2026.

## Mapa

Dois conjuntos de laboratórios de Química perto da Entrada Gran, sem inventar
quantidade de salas, portas ou nomes oficiais. Lanchonete deslocada para o fim
do corredor, com rampa próxima à direita. No superior, Agronomia à esquerda da
rampa, abaixo da galeria. IDs anteriores e ligações entre pisos preservados.

O mapa tem 63 zonas, 100 nós, 100 conexões e 44 locais. Novos acessos de Química
são provisórios e não recebem garantia de acessibilidade. Distâncias, geometria
e localização indoor ainda precisam de levantamento/calibração presencial.
Revisão publicada pela API: `pc-floorplan-v12-20261014`.

## Hospedagem

Instalação própria no PC com Docker, PostgreSQL/PostGIS, API em modo produção,
web release, Admin, downloads com Range/Content-Length e backup diário.
Projeto isolado `granmap-pc`; nenhum container ou dado de outro projeto foi alterado.

A base pública foi inicializada por uma cópia consistente da demo local. O
SQLite original foi preservado; não foi importado o banco do servidor anterior.
Sessões e códigos antigos não são reaproveitados. Credenciais demo privilegiadas
foram rotacionadas somente na nova cópia. Acesso administrativo em arquivo local
privado `.secrets/pc-access.txt`, excluído do Git e inacessível pela web.

Túnel HTTPS temporário sem domínio próprio. O PC/Docker/internet devem permanecer
ativos. Reiniciar o túnel muda seu endereço e exige atualizar a URL do APK.
Não há garantia de uptime e este não é um endereço fixo de lançamento comercial.
Nenhum domínio foi adquirido, nenhuma conta criada e nenhum custo foi autorizado.
O Coolify, download GitHub antigo e repositório remoto não foram modificados.

## Verificação

- 215 testes Flutter, 49 de backend/bootstrap, 3 do Admin e 4 de snapshot passaram.
- Análise Flutter sem problemas; web, Admin e três arquiteturas Android compilados.
- PostgreSQL migrado até `20261014_0003`, importação idempotente conferida.
- Backup restaurado em banco isolado; ordenação/idempotência/concorrência de votos
  conferidas nesse PostgreSQL. Apenas a cópia temporária do teste foi removida.
- Jornada pública: mapa, login, grade, comunidade, Admin e proteções aprovados.
- Download completo público idêntico ao APK local; resposta Range 206 correta.
- Mapa 2D e 3D, troca de piso e página de instalação verificados no navegador.
- Nenhum telefone conectado: instalação real e sensores continuam pendentes.

APK ARM64: `deliverables/GranMap-Demo-v1.6.2-pc-arm64-v8a.apk`.
Tamanho: 27.834.276 bytes. SHA-256:
`8C401A0A8A42B89FD57FB149BD223DCE6C46AF4FA7C1750577F42530D4F6EAA8`.
Assinatura v2 validada, com o mesmo certificado de demo das versões anteriores.
O APK é destinado a demonstração; a loja exige a chave definitiva de produção.
