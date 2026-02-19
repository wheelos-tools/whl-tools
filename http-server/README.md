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

### 3.1 Run the initializer

The `init.sh` script fixes directory permissions and updates any `source.json` entries in the `registry/` to point at the detected LAN IP.

```bash
chmod +x init.sh
./init.sh

```

### 3.2 Verify access

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
