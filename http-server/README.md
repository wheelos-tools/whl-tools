# Internal Bazel Infrastructure

This repository provides a quick Docker-based setup to host an offline-capable Bazel dependency environment. It supports private module hosting, a local Bzlmod registry, and an HTTP/Squid caching proxy for external dependencies.

## 1. Layout

```bash
.
├── docker-compose.yml
├── init.sh                # Initialization and IP auto-configuration script
├── README.md
├── nginx-conf/
│   └── autoindex.conf     # Nginx directory listing configuration
├── squid/
│   └── squid.conf         # Squid cache configuration
├── share/                 # [auto] place source archives (.tar.gz) here
├── registry/              # [auto] Bzlmod metadata index
├── filebrowser/           # [auto] filebrowser database
└── squid/cache/           # [auto] squid cache data

```

---


## 3. Deployment & Startup

This repository includes a convenience manager script `manage.sh` which wraps
initialization and docker-compose operations. The script will detect whether
`docker-compose` or the Docker CLI's `docker compose` subcommand is available
and use the detected command.

### 3.1 Quick deploy (recommended)

From this directory run:

```bash
chmod +x manage.sh
sudo ./manage.sh deploy
```

`deploy` will:

- create necessary directories (`share`, `registry`, `filebrowser`, `squid/cache`)
- initialize the filebrowser database
- update registry `source.json` entries to point at the detected LAN IP
- start the compose stack (file-server, bazel-registry, squid-proxy, filebrowser)

After `deploy` completes it prints access instructions with the detected LAN
IP.

### 3.2 Troubleshooting & status

Check stack health and endpoints:

```bash
./manage.sh status
```

Restart a single service or the entire stack:

```bash
./manage.sh restart file-server
./manage.sh restart all
```

If you prefer to run compose manually the script supports `docker-compose` or
`docker compose` — it will auto-detect which command to use.

### 3.3 Optional: run initializer manually

If you wish to run the low-level initializer directly (not required when using
`manage.sh deploy`), you can run:

```bash
chmod +x init.sh
./init.sh
```

This fixes permissions and updates registry URLs, similar to what `deploy`
performs.

### 3.4 Verify access (endpoints)

- **File Browser (admin UI)**: `http://<IP>:8082` (default admin/admin) — upload files to `share/`.
- **File Server (downloads)**: `http://<IP>:8080` — serves `.tar.gz` source archives.
- **Bzlmod Registry**: `http://<IP>:8081` — hosts module metadata used by Bazel's registry feature.
- **Caching Proxy (Squid)**: `http://<IP>:3128` — caches downloads from external hosts like GitHub.

---

## 4. Client configuration (.bazelrc)

Add the following to your project's `.bazelrc` to use the local registry and proxy:

```bash
# 1. Prefer the internal Bzlmod registry
common --registry=http://<server-ip>:8081

# 2. Use the HTTP proxy for external fetches
common --repo_env=http_proxy=http://<server-ip>:3128
common --repo_env=https_proxy=http://<server-ip>:3128

# 3. Optional: enable local disk cache
common --disk_cache=~/.bazel-cache

```

---

## 5. Operations

### Adding a private module

1. Upload the module artifact (for example `my_module-1.0.tar.gz`) to `share/` using File Browser.
2. Create the module directory under `registry/modules/` with the correct layout.
3. Edit the module's `source.json` so that the `url` points to the file server, for example:

```json
{
  "url": "http://<server-ip>:8080/my_module-1.0.tar.gz",
  "integrity": "sha256-..."
}

```
