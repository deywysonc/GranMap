# GranMap no Cloudflare

## Pages — painel administrativo

- diretório raiz: `admin_web`;
- comando de build: `npm ci && npm run build`;
- diretório de saída: `dist`;
- Node.js: 22;
- `VITE_GRANMAP_API_URL`: URL HTTPS retornada pelo Cloud Run;
- `VITE_GRANMAP_ADMIN_AUTH_MODE`: `bearer`.

Configure uma regra de SPA para que caminhos do painel retornem `index.html`.
Depois da publicação, inclua o domínio final do Pages em
`GRANMAP_PUBLIC_ORIGINS` no Cloud Run.

## R2 — APK, vídeos e modelos 3D

Use um bucket privado chamado `granmap-assets` e exponha somente os objetos de
distribuição por um domínio próprio. O APK e os vídeos não devem fazer parte do
contêiner da API nem do build do Pages.

Ative CORS apenas para os domínios do aplicativo e do painel. Nunca envie
credenciais do R2 para o Flutter ou para o JavaScript do navegador; uploads
administrativos devem usar URLs assinadas geradas pelo backend.
