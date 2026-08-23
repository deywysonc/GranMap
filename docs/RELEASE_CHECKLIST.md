# GranMap — checklist de entrega

## Versão validada

- aplicativo: `1.3.2+8`;
- backend: `0.12.0`;
- Admin: `0.5.0`;
- API pública usada pelo APK da demo: `https://granmap.168.119.244.43.sslip.io/api`;
- APK recomendado: `deliverables/GranMap-Demo-v1.3.2-arm64-v8a.apk`;
- tamanho: 27.548.471 bytes (26,3 MB);
- SHA-256: `1324877EBAF4E1A448C60CD2E4262018BF2A7F6690B143DE913BF53CF1B14DFA`;
- download público estável: `https://granmap.168.119.244.43.sslip.io/baixar`.

O APK é assinado corretamente com APK Signature Scheme v2 e usa a chave de
debug apenas para instalação da demo. A loja exige a chave definitiva da
instituição e o flavor `production`.

## Verificações concluídas em 23/08/2026

- `flutter analyze`: aprovado;
- `flutter test`: 38 testes aprovados;
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
  -ApkUrl http://192.168.1.11:8090/GranMap-demo-v16-arm64.apk
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
