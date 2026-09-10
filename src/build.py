#!/usr/bin/env python3
"""Baut aus config.part + head.part + den script-*.part-Modulen die beiden
   Auslieferungen:
   ../index.html            – vollständige, eigenständige Seite (GitHub Pages)
   regieplan-fragment.html  – Fragment für das Claude-Artifact (ohne doctype/head/body)

   Aufruf:  python3 src/build.py
"""
import io, os, re, sys

P = os.path.dirname(os.path.abspath(__file__))
config = io.open(os.path.join(P, "config.part"), encoding="utf-8").read()
head = io.open(os.path.join(P, "head.part"), encoding="utf-8").read()

# script.part war eine einzelne ~3300-Zeilen-Datei ohne Modultrennung; jetzt
# in thematische Teile aufgeteilt (Issue #4), unverändert in ihrer bisherigen
# Reihenfolge zu einem einzigen <script> zusammengefügt - reines Aufteilen,
# keine Verhaltensänderung. script-core.part öffnet das <script>-Tag und die
# gemeinsame IIFE, ui-misc.part schließt sie wieder; die Module dazwischen
# sind reine Anweisungsfolgen innerhalb dieser einen Closure (dieselbe
# gemeinsame Variablen wie CFG/pq/pf/TXT bleiben so nach wie vor über alle
# Module hinweg sichtbar, ganz ohne globale window-Zuweisungen).
SCRIPT_MODULES = [
    "script-core.part",     # Konstanten, CFG/CFG0, Stammdaten (QROWS/FROWS/…), ffix
    "plan-engine.part",     # Plan-Engine, Teams, Wege-Diagramm, Meldezahlen/Finalquoten, Zeitfenster
    "personal.part",        # Personal: Kategorien und Personen, Instanzen (pq/pf, Formulare)
    "texte.part",           # Texte bearbeiten (Textbausteine, Formatierungsleiste)
    "auth.part",            # Login und Freigabe (Supabase), Wettkämpfe, Sync
    "aufgaben-chat.part",   # Aufgaben, Chat, Speicherstände
    "pdf-export.part",      # PDF-Export, Auszahlung & Verpflegung
    "ui-misc.part",         # Abschnitte einklappen, Sprungnavigation, Skript-Ende
]
script = "".join(
    io.open(os.path.join(P, name), encoding="utf-8").read() for name in SCRIPT_MODULES
)
body = config + head + script

# --- Artifact-Fragment -------------------------------------------------
assert "<!doctype" not in body.lower(), "Fragment darf keinen doctype haben"
assert "<body" not in body.lower(), "Fragment darf kein <body> haben"
io.open(os.path.join(P, "regieplan-fragment.html"), "w", encoding="utf-8").write(body)

# --- Eigenstaendige Seite ----------------------------------------------
title = re.search(r"<title>(.*?)</title>", body).group(1)
# <title> und <link rel=stylesheet> wandern in den <head>
htitle = re.search(r"<title>.*?</title>\s*", body, re.S).group(0)
hlink = re.search(r'<link rel="stylesheet"[^>]*>\s*', body).group(0)
rest = body.replace(htitle, "", 1).replace(hlink, "", 1)

SKELETON = """<!doctype html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="description" content="Interaktiver Regieplan für Kletterwettkämpfe: Wertungsklassen, Zeitplan, Personal und PDF-Export. Landesverband Sachsen des DAV.">
<meta name="color-scheme" content="light dark">
<title>{title}</title>
{link}<style>
/* Grundlage, die im Claude-Artifact die Laufzeit mitbringt */
html{{-webkit-text-size-adjust:100%}}
body{{margin:0}}
img{{max-width:100%}}
[hidden]{{display:none !important}}
</style>
{rest}
</body>
</html>
"""

site = SKELETON.format(title=title, link=hlink, rest=rest.replace(
    "<style>", "</style>\n<style>", 1) if False else rest)

# rest beginnt mit <style> ... </style> gefolgt von <header>: der Body-Start
# muss direkt vor <header class="masthead"> liegen.
i = site.index('<header class="masthead">')
site = site[:i] + "</head>\n<body>\n" + site[i:]

root = os.path.dirname(P)
io.open(os.path.join(root, "index.html"), "w", encoding="utf-8").write(site)

# --- Testfassung --------------------------------------------------------


print("index.html %d Bytes geschrieben" % len(site))
