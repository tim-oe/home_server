# RustDesk

[RustDesk Server OSS](https://rustdesk.com/docs/en/self-host/rustdesk-server-oss/docker/) 1.1.16
(`rustdesk/rustdesk-server-s6`). One container runs both hbbs (ID / rendezvous)
and hbbr (relay). Clients on the LAN
and on WireGuard use `192.168.1.35`. Nothing is published on any other host address,
and Traefik does not route this stack.

## Deploy

```bash
./gradlew deployRustdesk
```

On the host:

```bash
cd /mnt/raid/services/rustdesk && sudo docker compose up -d
docker exec rustdesk cat /data/id_ed25519.pub
```

The first boot writes `id_ed25519` and `id_ed25519.pub` into `rustdesk-data`.
`ENCRYPTED_ONLY=1` rejects a client that does not have that public key.
Copy the public key into each client: **Settings → Network → ID server**
`192.168.1.35`, **Key** the contents of `id_ed25519.pub`. Leave **Relay server**
empty; hbbs tells clients to use `192.168.1.35` (port 21117).

A new key pair is only generated when both files are missing. Restoring
`rustdesk-data` keeps the same key, so existing clients keep working.

## Ports

Bound to `192.168.1.35`:

| Port | Use |
|---|---|
| 21115/tcp | NAT type test |
| 21116/tcp | TCP hole punching |
| 21116/udp | ID registration and heartbeat |
| 21117/tcp | Relay |
| 21118/tcp | Web client, hbbs |
| 21119/tcp | Web client, hbbr |

WireGuard (`10.9.0.0/24`) reaches these through OPNsense, same as Forgejo's SSH
port. A client on the internet needs an OPNsense forward of these ports to
`192.168.1.35`, and `RELAY` changed to an address that client can resolve.
