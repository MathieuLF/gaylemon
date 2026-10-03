#!/usr/bin/env python3
"""Développement et intégrations de Gaylémon, sans signature de release."""
from __future__ import annotations

import argparse
import contextlib
import hashlib
import json
import os
from pathlib import Path
import secrets
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "runtime" / ".tools"
ENV = os.environ.copy()
ENV.update(GOFLAGS="-mod=readonly", GOTOOLCHAIN="local", PYTHONDONTWRITEBYTECODE="1")
ENV["PATH"] = os.pathsep.join([str(TOOLS / "go/bin"), str(TOOLS / "node/bin"), ENV.get("PATH", "")])


def run(*args: str, capture: bool = False, env: dict[str, str] | None = None) -> str:
    command = [shutil.which(args[0], path=ENV["PATH"]) or args[0], *args[1:]]
    result = subprocess.run(command, cwd=ROOT, env=env or ENV, check=True,
                            text=True, stdout=subprocess.PIPE if capture else None)
    return result.stdout.strip() if capture else ""


def snapshot() -> dict[str, str]:
    paths = run("git", "ls-files", "-z", capture=True).split("\0")
    result = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest()
              if (ROOT / p).is_file() else "missing" for p in paths if p}
    result["git-status"] = run("git", "status", "--porcelain", "--untracked-files=all", capture=True)
    return result


def prerequisites() -> None:
    expected = json.loads((ROOT / "config/development-tools.json").read_text())
    if run("go", "env", "GOVERSION", capture=True) != "go" + expected["go"]:
        raise RuntimeError("Version Go différente du setup; relancer bash scripts/setup-cloud.sh.")
    if run("node", "--version", capture=True) != "v" + expected["node"]:
        raise RuntimeError("Version Node différente du setup; relancer bash scripts/setup-cloud.sh.")
    if not (ROOT / "node_modules/esbuild/package.json").is_file():
        raise RuntimeError("Dépendances Node absentes; exécuter le setup.")
    packages = json.loads((ROOT / "package.json").read_text())["devDependencies"]
    for name, version in packages.items():
        installed = ROOT / "node_modules" / name / "package.json"
        if not installed.is_file() or json.loads(installed.read_text())["version"] != version:
            raise RuntimeError("Dépendances Node différentes du manifeste; relancer le setup.")
    if sys.version_info < (3, 12):
        raise RuntimeError("Python 3.12 minimum est requis.")


def check_dev() -> None:
    prerequisites()
    print("Contrôle quotidien : unités, vet, format Go, contrats, actifs et compilation.\n"
          "PostgreSQL, navigateur, race, scans et release restent séparés.", flush=True)
    run("go", "test", "./...")
    run("go", "vet", "./...")
    if run("gofmt", "-l", "cmd", "internal", "db", capture=True):
        raise RuntimeError("Sources Go non formatées.")
    run(sys.executable, "-B", "-m", "unittest", "discover", "-s", "scripts/tests", "-p", "test_*.py")
    run("npm", "run", "build:check")
    run("npm", "test")
    output = ROOT / "runtime/development-build"
    output.mkdir(parents=True, exist_ok=True)
    for name in ("gaylemon", "gaylemon-web"):
        run("go", "build", "-o", str(output / (name + (".exe" if os.name == "nt" else ""))), "./cmd/" + name)
    run("git", "diff", "--check")


def local_port() -> int:
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


@contextlib.contextmanager
def postgres(backend: str):
    """Une base neuve par intégration; aucune URL distante ou base existante."""
    password = secrets.token_hex(24)
    name = "gaylemon-test-" + secrets.token_hex(8)
    if backend == "docker":
        container = run("docker", "run", "--detach", "--name", name, "--publish", "127.0.0.1::5432",
                        "--env", "POSTGRES_PASSWORD=" + password, "--env", "POSTGRES_DB=gaylemon_test",
                        "postgres:16.15-alpine", capture=True)
        try:
            port = int(run("docker", "port", container, "5432/tcp", capture=True).rsplit(":", 1)[1])
            ready = ["docker", "exec", container, "pg_isready", "-U", "postgres", "-d", "gaylemon_test"]
            wait_postgres(ready)
            yield f"postgresql://postgres:{password}@127.0.0.1:{port}/gaylemon_test?sslmode=disable"
        finally:
            run("docker", "rm", "--force", container, capture=True)
    else:
        binaries = Path("/usr/lib/postgresql/16/bin")
        if not (binaries / "initdb").is_file():
            raise RuntimeError("PostgreSQL 16 natif absent; exécuter le setup ou choisir --postgres docker.")
        with tempfile.TemporaryDirectory(prefix="gaylemon-postgres-") as directory:
            root = Path(directory)
            prefix: list[str] = []
            if os.geteuid() == 0:
                import pwd
                user = pwd.getpwnam("postgres")
                os.chown(root, user.pw_uid, user.pw_gid)
                prefix = ["runuser", "-u", "postgres", "--"]
            password_file = root / "password"
            password_file.write_text(password)
            password_file.chmod(0o600)
            if prefix:
                os.chown(password_file, user.pw_uid, user.pw_gid)
            port = local_port()
            def pg(tool: str, *args: str, capture: bool = False):
                return run(*prefix, str(binaries / tool), *args, capture=capture)
            pg("initdb", "-D", str(root / "data"), "-U", "postgres", "--auth-host=scram-sha-256",
               "--auth-local=trust", "--pwfile=" + str(password_file), capture=True)
            started = False
            try:
                pg("pg_ctl", "-D", str(root / "data"), "-l", str(root / "postgres.log"),
                   "-o", f"-h 127.0.0.1 -p {port} -k {root}", "-w", "start", capture=True)
                started = True
                pg("createdb", "-h", str(root), "-p", str(port), "-U", "postgres", "gaylemon_test")
                yield f"postgresql://postgres:{password}@127.0.0.1:{port}/gaylemon_test?sslmode=disable"
            finally:
                if started:
                    pg("pg_ctl", "-D", str(root / "data"), "-m", "fast", "-w", "stop", capture=True)


def wait_postgres(command: list[str]) -> None:
    for _ in range(60):
        try:
            run(*command, capture=True)
            return
        except subprocess.CalledProcessError:
            time.sleep(0.5)
    raise RuntimeError("PostgreSQL ne devient pas disponible.")


def integration(backend: str) -> None:
    prerequisites()
    with postgres(backend) as url:
        env = {**ENV, "GAYLEMON_TEST_DATABASE_URL": url}
        run("go", "test", "-tags=integration", "./internal/store", "./internal/background", "-count=1", "-v", env=env)


def start(backend: str, port: int, check: bool) -> None:
    prerequisites()
    root = ROOT / "runtime/local"
    root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="web-", dir=root) as temporary, postgres(backend) as url:
        directory = Path(temporary)
        keys = {}
        for name in ("agent", "response"):
            path = directory / (name + ".key")
            run("go", "run", "./cmd/gaylemon", "keygen", "--private", str(path), capture=True)
            keys[name] = path.read_text().strip()
        import base64
        public = base64.b64encode(base64.b64decode(keys["agent"])[32:]).decode()
        env = {**ENV, "GAYLEMON_DATABASE_URL": url, "GAYLEMON_WEB_LISTEN": f"127.0.0.1:{port}",
               "GAYLEMON_PUBLIC_BASE_URL": f"http://127.0.0.1:{port}", "GAYLEMON_AGENT_PUBLIC_KEYS": "local-agent:" + public,
               "GAYLEMON_RESPONSE_PRIVATE_KEY": keys["response"], "GAYLEMON_PORTAL_ROOT": str(ROOT / "portal"),
               "GAYLEMON_ASSET_ROOT": str(directory / "assets"), "GAYLEMON_ANALYTICS_BASE_URL": "",
               "GAYLEMON_LEGACY_HOSTS": "", "GAYLEMON_GITHUB_CLIENT_ID": "", "GAYLEMON_GITHUB_CLIENT_SECRET": "",
               "GAYLEMON_GITHUB_ALLOWED_USER_ID": "1"}
        binary = directory / ("gaylemon-web.exe" if os.name == "nt" else "gaylemon-web")
        run("go", "build", "-o", str(binary), "./cmd/gaylemon-web")
        with (directory / "web.log").open("w") as log:
            process = subprocess.Popen([str(binary)], cwd=ROOT, env=env, stdout=log, stderr=log)
            try:
                for _ in range(100):
                    if process.poll() is not None:
                        raise RuntimeError("Le service s'est arrêté : " + (directory / "web.log").read_text())
                    try:
                        with urllib.request.urlopen(f"http://127.0.0.1:{port}/health/ready", timeout=2) as response:
                            if response.status == 200:
                                break
                    except OSError:
                        time.sleep(0.3)
                else:
                    raise RuntimeError("Le service ne devient pas disponible.")
                with urllib.request.urlopen(f"http://127.0.0.1:{port}/offline.html", timeout=5) as response:
                    html = response.read().decode()
                    if "/assets/styles." not in html or "<style" in html:
                        raise RuntimeError("Actifs hors ligne invalides.")
                print(f"Gaylémon prêt : http://127.0.0.1:{port} (base temporaire, OAuth désactivé).", flush=True)
                if not check:
                    process.wait()
            finally:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=20)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["check-dev", "check-integration", "check-browser", "portal", "start"])
    parser.add_argument("--postgres", choices=["native", "docker"], default="docker" if os.name == "nt" else "native")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if not 1024 <= args.port <= 65535:
        parser.error("Le port doit être compris entre 1024 et 65535.")
    before = snapshot()
    try:
        if args.command == "check-dev":
            check_dev()
        elif args.command == "check-integration":
            integration(args.postgres)
        elif args.command == "check-browser":
            prerequisites()
            run("npm", "run", "test:browser")
        elif args.command == "portal":
            prerequisites()
            run("npm", "run", "build:check")
            run("node", "portal/tests/browser/serve.mjs")
        else:
            start(args.postgres, args.port, args.check)
        return 0
    finally:
        if snapshot() != before:
            raise RuntimeError("La commande a modifié les fichiers suivis ou l'état Git; aucune restauration automatique.")


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
    except subprocess.CalledProcessError as error:
        print(f"Échec de {Path(error.cmd[0]).name} (code {error.returncode}).", file=sys.stderr)
        sys.exit(1)
    except (RuntimeError, OSError) as error:
        print(f"Échec : {error}", file=sys.stderr)
        sys.exit(1)
