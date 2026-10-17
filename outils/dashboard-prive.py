#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Dashboard privé BYM Classic — serveur local + proxy.

Pourquoi un serveur local ?
  Le dashboard va chercher tes statistiques via l'API GoatCounter et
  l'API GitHub. Si on le faisait directement depuis un fichier HTML
  ouvert avec « double-clic », le navigateur bloquerait les requêtes
  (protection CORS) et on ne pourrait pas joindre les services.
  Ce petit serveur tourne UNIQUEMENT sur ta machine (127.0.0.1),
  n'écoute pas sur Internet, et relaie les requêtes. Ton jeton API
  ne quitte jamais ta machine.

Usage :
    python dashboard-prive.py
    puis ouvre dans ton navigateur :  http://127.0.0.1:8787

Ctrl+C dans le terminal pour arrêter.
"""

import json
import sys
import urllib.request
import urllib.error
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path

# Windows utilise cp1252 pour le terminal : sans cela, les caractères
# accentués ou les flèches font planter le serveur au premier print().
try:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
except Exception:
    pass

PORT = 8787
HERE = Path(__file__).resolve().parent
INDEX = HERE / "dashboard-prive.html"
GITHUB_REPO = "victordiaz1000/bym-classic"


class Handler(BaseHTTPRequestHandler):
    # --- petits utilitaires -------------------------------------
    def _send(self, status, body, ctype="application/json; charset=utf-8"):
        data = body if isinstance(body, bytes) else body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def _json(self, status, obj):
        self._send(status, json.dumps(obj, ensure_ascii=False))

    # --- routes --------------------------------------------------
    def do_GET(self):
        path = self.path.split("?", 1)[0]

        if path in ("/", "/index.html"):
            self._send(200, INDEX.read_bytes(), "text/html; charset=utf-8")
            return

        # /gc/...  →  https://CODE.goatcounter.com/api/v0/...
        if path.startswith("/gc/"):
            self._proxy_goatcounter(path[len("/gc/"):])
            return

        # /github/...  →  https://api.github.com/...
        if path.startswith("/github/"):
            self._proxy_github(path[len("/github/"):])
            return

        self._json(404, {"error": "Route inconnue : " + path})

    # --- proxy GoatCounter --------------------------------------
    def _proxy_goatcounter(self, sub):
        code = (self.headers.get("X-Goat-Code") or "").strip()
        auth = (self.headers.get("Authorization") or "").strip()
        if not code or not auth:
            self._json(400, {"error": "Code du site ou jeton API manquant."})
            return

        url = f"https://{code}.goatcounter.com/api/v0/{sub}"
        req = urllib.request.Request(url, headers={
            "Authorization": auth,          # déjà au format "Bearer xxx"
            "Content-Type": "application/json",
            "Accept": "application/json",
        })
        self._forward(req)

    # --- proxy GitHub -------------------------------------------
    def _proxy_github(self, sub):
        url = f"https://api.github.com/{sub.lstrip('/')}"
        req = urllib.request.Request(url, headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "bym-dashboard-prive",
        })
        self._forward(req)

    def _forward(self, req):
        try:
            with urllib.request.urlopen(req, timeout=25) as resp:
                self._send(resp.status, resp.read())
        except urllib.error.HTTPError as e:
            # On renvoie tel quel le statut et le message d'erreur.
            self._send(e.code, e.read())
        except Exception as e:  # réseau coupé, DNS, etc.
            self._json(502, {"error": f"Erreur réseau : {e}"})

    # On reste silencieux dans le terminal (une ligne par requête).
    def log_message(self, *args):
        pass


def main():
    server = HTTPServer(("127.0.0.1", PORT), Handler)
    print("Dashboard privé BYM Classic")
    print(f"  → http://127.0.0.1:{PORT}")
    print("  (accessible uniquement sur cette machine)")
    print("Ctrl+C pour arrêter.\n")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nArrêté.")


if __name__ == "__main__":
    main()
