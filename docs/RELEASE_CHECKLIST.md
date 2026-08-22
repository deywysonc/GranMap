# GranMap — checklist de entrega

## Versão validada

- aplicativo: `1.3.0+6`;
- backend: `0.12.0`;
- Admin: `0.5.0`;
- API local usada pelo APK da demo: `http://192.168.1.11:8100`;
- APK recomendado: `deliverables/GranMap-Demo-v1.3.0-arm64-v8a.apk`;
- tamanho: 27.547.938 bytes (26,3 MB);
- SHA-256: `2D8C892A1666341C3348E2AB52817EE3606869134CFEBEEB86FA08874C4EE838`.

O APK é assinado corretamente com APK Signature Scheme v2 e usa a chave de
debug apenas para instalação da demo. A loja exige a chave definitiva da
instituição e o flavor `production`.

## Verificações concluídas em 22/08/2026

- `flutter analyze`: aprovado;
- `flutter test`: 35 testes aprovados;
- backend: 22 testes aprovados;
- Admin: 3 testes aprovados;
- `npm audit --omit=dev`: nenhuma vulnerabilidade;
- build de produção do Admin: aprovado;
- build Android separado em ARM64, ARM 32 bits e x86_64: aprovado;
- assinatura, pacote, SDK e presença dos assets de mapa/walkthrough: aprovados.

## Demonstração na rede local

Execute:

```powershell
cd C:\GranMap
.\scripts\start_demo.ps1 -Lan
```

O script agora prefere a rede privada real a adaptadores VPN. O telefone e o
computador precisam estar na mesma rede, e o computador precisa permanecer
ligado. Para validar todos os serviços e o download:

```powershell
.\scripts\verify_demo.ps1 `
  -ApiBase http://192.168.1.11:8100 `
  -AppUrl http://192.168.1.11:8088 `
  -AdminUrl http://192.168.1.11:5174 `
  -ApkUrl http://192.168.1.11:8090/GranMap-demo-v14-arm64.apk
```

## Antes do lançamento público

- substituir o endereço local por uma API HTTPS pública;
- cadastrar domínio, TLS, PostgreSQL gerenciado, backup e alertas;
- configurar SMTP, SSO/ERP e push, ou manter as chaves desativadas;
- criar e guardar a chave Android definitiva em cofre seguro;
- executar teste em aparelhos físicos e teste de carga;
- aprovar planta, escala, acessibilidade e campanha de posicionamento em campo;
- preencher os formulários de privacidade e conteúdo da loja.

Esses itens dependem de credenciais, medições ou decisões institucionais. O
backend bloqueia `GRANMAP_COMMERCIAL_LAUNCH=true` enquanto a configuração
obrigatória estiver incompleta.
