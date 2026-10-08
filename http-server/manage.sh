#!/usr/bin/env bash
set -euo pipefail

# manage.sh - manage the local Bazel HTTP infrastructure
# Usage: manage.sh deploy | status | restart [service]

COMPOSE_SERVICES=(file-server bazel-registry squid-proxy filebrowser)

compose_cmd() {
  if command -v docker-compose >/dev/null 2>&1; then
    echo "docker-compose"
  elif command -v docker >/dev/null 2>&1; then
    echo "docker compose"
  else
    echo ""
  fi
}

get_linux_ip() {
  ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}'
}

detect_lan_ip_or_fail() {
  if command -v ip >/dev/null 2>&1; then
    LAN_IP=$(get_linux_ip || true)
  else
    LAN_IP=""
  fi
  if [ -z "${LAN_IP:-}" ]; then
    echo "Unable to detect LAN IP automatically on Linux. Ensure 'ip' command is available."
    exit 1
  fi
  echo "$LAN_IP"
}

deploy() {
  LAN_IP=$(detect_lan_ip_or_fail)

  mkdir -p share registry filebrowser squid/cache
  touch ./filebrowser/database.db
  chmod 666 ./filebrowser/database.db || true
  chmod -R 777 ./squid/cache || true

  if [ -d ./registry ]; then
    find ./registry -name "source.json" -print0 | while IFS= read -r -d '' file; do
      tmpfile=$(mktemp)
      sed "s|http://[^:]*:8080|http://$LAN_IP:8080|g" "$file" > "$tmpfile" && mv "$tmpfile" "$file"
    done
  fi

  cmd=$(compose_cmd)
  if [ -z "$cmd" ]; then
    echo "docker-compose or 'docker compose' not found. Please install Docker or docker-compose."
    exit 1
  fi

  echo "Starting services with: $cmd up -d"
  $cmd up -d

  echo "========================================"
  echo "Services started. Access instructions:"
  echo "1. File Browser (admin): http://$LAN_IP:8082"
  echo "2. File Server (downloads): http://$LAN_IP:8080"
  echo "3. Bzlmod Registry: http://$LAN_IP:8081"
  echo "4. Squid Proxy: http://$LAN_IP:3128"
  echo "========================================"
}

status() {
  LAN_IP=""
  if command -v ip >/dev/null 2>&1; then
    LAN_IP=$(get_linux_ip || true)
  fi

  cmd=$(compose_cmd)
  if [ -n "$cmd" ]; then
    echo "Compose status ($cmd):"
    $cmd ps || true
  else
    echo "docker-compose not found; fallback to 'docker ps' listing relevant containers"
    docker ps --filter "name=bazel" --filter "name=filebrowser" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' || true
  fi

  echo
  echo "Endpoint checks (curl)"
  for p in 8082 8080 8081 3128; do
    target="http://localhost:$p"
    if [ -n "${LAN_IP}" ]; then
      target_lan="http://$LAN_IP:$p"
    else
      target_lan=""
    fi
    echo -n "- Port $p: "
    if curl -sS --max-time 3 "$target" >/dev/null 2>&1; then
      echo "ok (localhost)"
    elif [ -n "$target_lan" ] && curl -sS --max-time 3 "$target_lan" >/dev/null 2>&1; then
      echo "ok ($LAN_IP)"
    else
      echo "no response"
    fi
  done

  echo
  echo "Squid cache dir check:"
  if [ -d squid/cache ]; then
    if [ -w squid/cache ]; then
      echo "- squid/cache exists and is writable"
    else
      echo "- squid/cache exists but is not writable"
    fi
  else
    echo "- squid/cache does not exist"
  fi
}

restart() {
  svc=${1:-all}
  cmd=$(compose_cmd)
  if [ -z "$cmd" ]; then
    echo "docker-compose or 'docker compose' not found. Cannot restart services."
    exit 1
  fi

  if [ "$svc" = "all" ]; then
    echo "Restarting all services via: $cmd restart"
    $cmd restart || true
    return
  fi

  # validate service
  ok=false
  for s in "${COMPOSE_SERVICES[@]}"; do
    if [ "$s" = "$svc" ]; then ok=true; break; fi
  done
  if [ "$ok" = false ]; then
    echo "Unknown service: $svc"
    echo "Known services: ${COMPOSE_SERVICES[*]} or 'all'"
    exit 1
  fi

  echo "Restarting service: $svc"
  $cmd restart "$svc" || true
}

usage() {
  cat <<EOF
Usage: $0 <command>

Commands:
  deploy        Initialize directories, update registry URLs, and start containers
  status        Show container status and check endpoints
  restart [svc] Restart a single service (file-server|bazel-registry|squid-proxy|filebrowser) or 'all'

Examples:
  $0 deploy
  $0 status
  $0 restart file-server
  $0 restart all
EOF
}

if [ $# -lt 1 ]; then
  usage
  exit 1
fi

case "$1" in
  deploy)
    deploy
    ;;
  status)
    status
    ;;
  restart)
    restart "$2" || true
    ;;
  *)
    usage
    exit 1
    ;;
esac
