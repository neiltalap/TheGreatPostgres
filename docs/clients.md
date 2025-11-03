# Client Connections (mTLS)

All client connections must use TLS with client certificates (mTLS). No passwords are accepted. The Common Name (CN) in the client certificate must match the Postgres username.

Place these files on the client machine (structured):

- client-certs/ca.crt — copy of the CA that signed the server and client certs
- client-certs/<user>/client.crt — the client certificate for your DB user
- client-certs/<user>/client.key — the client private key (chmod 600)

Flat copies are also created for convenience:
- client-certs/<user>.crt and client-certs/<user>.key

## psql / libpq

Connection string:

```
psql "host=db.ozinozi.com port=5432 dbname=postgres user=dbuser \
      sslmode=verify-full sslrootcert=client-certs/ca.crt \
      sslcert=client-certs/dbuser/client.crt sslkey=client-certs/dbuser/client.key"
```

Environment variables (alternative):

```
export PGHOST=db.ozinozi.com
export PGPORT=5432
export PGDATABASE=postgres
export PGUSER=dbuser
export PGSSLMODE=verify-full
export PGSSLROOTCERT=/path/to/client-certs/ca.crt
export PGSSLCERT=/path/to/client-certs/dbuser/client.crt
export PGSSLKEY=/path/to/client-certs/dbuser/client.key
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
    ca: fs.readFileSync('client-certs/ca.crt').toString(),
    cert: fs.readFileSync('client-certs/dbuser/client.crt').toString(),
    key: fs.readFileSync('client-certs/dbuser/client.key').toString(),
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
  caCert, _ := ioutil.ReadFile("client-certs/ca.crt")
  rootCAs.AppendCertsFromPEM(caCert)

  cert, _ := tls.LoadX509KeyPair("client-certs/dbuser/client.crt", "client-certs/dbuser/client.key")
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
