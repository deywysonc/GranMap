# Implantação gratuita: Render + Neon

Esta configuração publica dois serviços pelo `render.yaml`:

- `granmap-api-deywyson`: API FastAPI em um Web Service Free do Render;
- `granmap-admin-deywyson`: painel React em um Static Site Free do Render.

O banco PostgreSQL é criado separadamente no Neon Free. Durante a criação do
Blueprint no Render, informe a connection string do Neon no segredo
`GRANMAP_DATABASE_URL`. A string deve usar TLS (`sslmode=require`).

URLs previstas:

- API: `https://granmap-api-deywyson.onrender.com`
- Admin: `https://granmap-admin-deywyson.onrender.com`
- Saúde da API: `https://granmap-api-deywyson.onrender.com/health`

O aplicativo Android de nuvem deve ser compilado com:

```powershell
flutter build apk --release --dart-define=GRANMAP_API_URL=https://granmap-api-deywyson.onrender.com
```

O serviço gratuito da API pode suspender após inatividade; o primeiro acesso
depois desse período pode levar cerca de um minuto. O painel estático não dorme.
