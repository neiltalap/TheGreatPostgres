# Client Connections (mTLS)

All client connections must use TLS with client certificates (mTLS). No passwords are accepted. The Common Name (CN) in the client certificate must match the Postgres username.

Place these files on the client machine:

- ca.crt — the CA that signed the server and client certs
- client.crt — the client certificate for your DB user
- client.key — the client private key (chmod 600)

## psql / libpq

Connection string:

```
psql "host=db.ozinozi.com port=5432 dbname=postgres user=dbuser \
      sslmode=verify-full sslrootcert=ca.crt sslcert=client.crt sslkey=client.key"
```

Environment variables (alternative):

```
export PGHOST=db.ozinozi.com
export PGPORT=5432
export PGDATABASE=postgres
export PGUSER=dbuser
export PGSSLMODE=verify-full
export PGSSLROOTCERT=/path/to/ca.crt
export PGSSLCERT=/path/to/client.crt
export PGSSLKEY=/path/to/client.key
psql
```

## Python (psycopg)

```python
import psycopg
conn = psycopg.connect(
    host="db.ozinozi.com",
    port=5432,
    dbname="production_db",
    user="dbuser",
    sslmode="verify-full",
    sslrootcert="/path/to/ca.crt",
    sslcert="/path/to/client.crt",
    sslkey="/path/to/client.key",
)
```

## Node.js (pg)

```js
const { Client } = require('pg');
const fs = require('fs');

const client = new Client({
  host: 'db.ozinozi.com',
  port: 5432,
  database: 'postgres',
  user: 'dbuser',
  ssl: {
    ca: fs.readFileSync('ca.crt').toString(),
    cert: fs.readFileSync('client.crt').toString(),
    key: fs.readFileSync('client.key').toString(),
    rejectUnauthorized: true,
    servername: 'db.ozinozi.com',
  },
});
await client.connect();
```

## Go (pgx)

```go
package main
import (
  "crypto/tls"
  "crypto/x509"
  "io/ioutil"
  "github.com/jackc/pgx/v5"
  "context"
)
func main() {
  rootCAs := x509.NewCertPool()
  caCert, _ := ioutil.ReadFile("ca.crt")
  rootCAs.AppendCertsFromPEM(caCert)

  cert, _ := tls.LoadX509KeyPair("client.crt", "client.key")
  tlsConfig := &tls.Config{RootCAs: rootCAs, Certificates: []tls.Certificate{cert}, ServerName: "db.ozinozi.com"}

  conn, _ := pgx.Connect(context.Background(),
    "host=db.ozinozi.com port=5432 dbname=postgres user=dbuser sslmode=verify-full")
  // Attach tlsConfig via pgx ConnConfig if needed
  _ = conn
}
```

Notes

- The certificate CN must equal the Postgres username; otherwise configure pg_ident mapping.
- Ensure client.key has permissions 600.
- Use verify-full to validate both the server certificate and hostname (CN/SAN must match db.ozinozi.com or your chosen name).
