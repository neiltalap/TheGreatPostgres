# Roles: appuser and datagrip

This guide shows how to create two common Postgres roles for this stack using mTLS:
- appuser: your application’s DB role (least privilege)
- datagrip: a developer/client tool role (read-only by default)

Important
- Client certificate CN must equal the Postgres role name (e.g., CN=appuser).
- Authentication is via client certs only; no passwords are required/used.

## Open a psql shell

- Inside the running container as superuser:
  - `docker exec -it postgres-prod psql -U postgres`

## Generate client certs for roles

- Create client certificates (CNs must match):
  - `./generate-certs.sh --cn <your-public-db-host> --client appuser --client datagrip`
  - Outputs:
    - `client-certs/appuser/client.crt|client.key`
    - `client-certs/datagrip/client.crt|client.key`
    - `client-certs/ca.crt` (copy of CA)

## Create appuser (least privilege)

Below assumes a dedicated database `myapp` and schema `app` owned by `appuser`.

1) Create role and database
```
-- Connect as superuser (postgres) in psql
CREATE ROLE appuser LOGIN;
CREATE DATABASE myapp OWNER appuser;
```

2) Create and own a schema (optional if using public)
```
\c myapp
CREATE SCHEMA app AUTHORIZATION appuser;
ALTER ROLE appuser IN DATABASE myapp SET search_path = app, public;
```

3) Grant minimal privileges (if schema ownership differs)
```
-- If appuser is not owner, grant what it needs
GRANT USAGE ON SCHEMA app TO appuser;
GRANT CREATE ON SCHEMA app TO appuser;
GRANT CONNECT ON DATABASE myapp TO appuser;
```

4) Future object privileges (safety if objects created by other owners)
```
ALTER DEFAULT PRIVILEGES IN SCHEMA app GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO appuser;
ALTER DEFAULT PRIVILEGES IN SCHEMA app GRANT USAGE, UPDATE ON SEQUENCES TO appuser;
ALTER DEFAULT PRIVILEGES IN SCHEMA app GRANT EXECUTE ON FUNCTIONS TO appuser;
```

## Create datagrip (read-only)

Two common options: read-only on an app database, or read-write (less common).

Read-only on database `myapp` (covers existing and future objects in schema `app`):
```
-- Connect as superuser (postgres)
CREATE ROLE datagrip LOGIN;

-- Database + schema access
GRANT CONNECT ON DATABASE myapp TO datagrip;
\c myapp
GRANT USAGE ON SCHEMA app TO datagrip;

-- Existing objects
GRANT SELECT ON ALL TABLES IN SCHEMA app TO datagrip;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA app TO datagrip;

-- Future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA app GRANT SELECT ON TABLES TO datagrip;
ALTER DEFAULT PRIVILEGES IN SCHEMA app GRANT USAGE ON SEQUENCES TO datagrip;
```

Optional read-write variant (if desired):
```
GRANT INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app TO datagrip;
ALTER DEFAULT PRIVILEGES IN SCHEMA app GRANT INSERT, UPDATE, DELETE ON TABLES TO datagrip;
```

## Connect with these roles (mTLS)

psql example for appuser:
```
psql "host=<your-public-db-host> port=5432 dbname=myapp user=appuser \
      sslmode=verify-full sslrootcert=client-certs/ca.crt \
      sslcert=client-certs/appuser/client.crt sslkey=client-certs/appuser/client.key"
```

DataGrip
- Import `client-certs/ca.crt` as CA, and `client-certs/datagrip/client.crt|client.key` as the client cert/key.
- Hostname verification must match your server cert CN/SAN (use your public host).
- User: `datagrip`, Database: `myapp` (or whatever you use).

Notes
- If you use a different schema name, replace `app` above accordingly.
- If your app migrator runs as a separate role, grant it CREATE/ALTER as needed while keeping runtime role limited.

