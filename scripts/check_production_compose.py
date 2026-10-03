"""Contrôle statique du manifeste d'exploitation, sans démarrage ni secret."""
from pathlib import Path
import re


def validate(path: Path) -> None:
    source = path.read_text(encoding="utf-8")
    for name in (
        "GAYLEMON_IMAGE_REFERENCE", "GAYLEMON_DATABASE_URL", "GAYLEMON_AGENT_PUBLIC_KEYS",
        "GAYLEMON_RESPONSE_PRIVATE_KEY", "GAYLEMON_GITHUB_CLIENT_ID",
        "GAYLEMON_GITHUB_CLIENT_SECRET",
    ):
        field = "image" if name == "GAYLEMON_IMAGE_REFERENCE" else name
        if not re.search(r"^\s+" + field + r":\s*\$\{" + name + r":\?[^}\r\n]+\}\s*$", source, re.M):
            raise ValueError(f"{field} doit être fourni explicitement par l'environnement, sans valeur sensible suivie")
    if not re.search(r'^\s+-\s+"127\.0\.0\.1:\$\{GAYLEMON_WEB_PORT:-\d+\}:8080"\s*$', source, re.M):
        raise ValueError("Le port du manifeste doit rester lié à la boucle locale")
    for contract in (r"read_only:\s*true", r"no-new-privileges:true", r"cap_drop:\s*\n\s*- ALL"):
        if not re.search(contract, source):
            raise ValueError("Une protection du manifeste d'exploitation manque")


if __name__ == "__main__":
    validate(Path(__file__).resolve().parents[1] / "compose.production.yaml")
    print("Manifeste d'exploitation : configuration sensible externe et protections statiques vérifiées.")
