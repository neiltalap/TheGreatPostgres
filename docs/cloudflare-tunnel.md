# Cloudflare Tunnel for Postgres (TCP)

Expose Postgres safely via Cloudflare Tunnel without opening any public ports.

Server-side (Cloudflare Dashboard)
- Zero Trust → Networks → Tunnels → your tunnel → Public Hostnames → Add a public hostname
  - Hostname: db.ozinozi.com (or your domain)
  - Type: TCP
  - Service: tcp://postgres:5432 (Docker service name + port)
  - Optional: add an Access policy (SSO) to control who can connect

Client-side
- Install cloudflared on the client machine.
- Start a local TCP listener that proxies to your DB over Cloudflare:

  cloudflared access tcp --hostname db.ozinozi.com --url 127.0.0.1:15432

- Then point your database client to 127.0.0.1:15432.
  - With mTLS enabled on Postgres, include sslcert/sslkey/sslrootcert (see docs/tls-mtls.md).
