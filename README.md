# Regieplan Lead-Wettkämpfe

Interaktiver Zeit- und Personalplan für Kletterwettkämpfe im Lead.
Landesverband Sachsen des DAV · angelegt für den 4. Offenen Sächsischen Kidscup 2026
(Kletterhalle Quacke Zittau, 26.09.2026), aber für jeden Wettkampf verwendbar.

**Die Seite: [noelsimon.github.io/Organisation_Lead_Wettk-mpfe](https://noelsimon.github.io/Organisation_Lead_Wettk-mpfe/)**
(erreichbar, sobald GitHub Pages aktiviert ist – siehe unten)

Eine einzige HTML-Datei, kein Server, kein Build-Schritt beim Aufrufen,
keine Anmeldung. Alles rechnet im Browser.

## Was die Seite kann

**Wertungsklassen frei definieren.** Name, beide Gruppenbezeichnungen
(U15 männlich/weiblich, U21 Herren/Damen), Teilnehmerzahlen, Toprope oder
Vorstieg und Farbe. Eine neue Klasse bekommt automatisch drei Qualirouten
(gemischt / Gruppe 1 / Gruppe 2) im Karussell plus zwei Finalrouten; das
Löschen räumt Routen, Gruppen und Balken wieder weg.

**Zeitplan als Werkzeug.** Balken verschieben, auf andere Routen ziehen,
Startgruppen teilen und zusammenführen, Routen anlegen und löschen,
Startzeiten minutengenau setzen. Zeitfenster für Quali und Finale sowie die
Dauer von Besichtigung und ISO sind einstellbar. Live mitgerechnet werden
Endzeiten, gleichzeitig belegte Routen, Personalbedarf, Pausen je Startgruppe
und Doppelbelegungen.

**Personal.** Frei definierbare Kategorien (Sicherung, Ergebnisdienst,
Routenbau, Orga, Buffet …) und Personen mit Kategorie, Team und Notiz. Der
Team-Zeitplan entsteht automatisch aus dem Plan; die zugeordneten Namen
stehen darin und im PDF.

**Rollenansichten.** Alles · Orga-Team · Routenbau · Routen-Teams/Sicherung ·
Trainer\*innen & Athlet\*innen. Blendet aus, was die jeweilige Rolle nicht braucht.

**Texte bearbeiten** wie in einem Textdokument – die Änderungen wandern ins PDF.

**PDF-Export**, im Browser gebaut (jsPDF): sechs Querformatseiten –
Kennzahlen und Tagesablauf · Quali-Zeitplan mit Laufkarte · Team-Zeitplan ·
Finale mit Quoten · Wegediagramm · Routenbau und offene Punkte.

**Speicherstände.** Der komplette Plan lässt sich als benannter Stand ablegen
und später wieder laden. In dieser Fassung liegen die Stände im Browser des
jeweiligen Geräts; zum Weitergeben gibt es **„Als Datei sichern"** (JSON) und
**„Datei laden"**.

## GitHub Pages aktivieren

Einmalig, danach ist die Seite unter der Adresse oben erreichbar:

1. Im Repository auf **Settings** → links **Pages**
2. Bei *Build and deployment* → *Source*: **Deploy from a branch**
3. Branch: **main**, Ordner: **/ (root)** → **Save**

Nach ein bis zwei Minuten ist die Seite online. Jeder Push auf `main`
veröffentlicht die neue Fassung automatisch.

## Bearbeiten

`index.html` wird aus zwei Quelldateien zusammengesetzt und sollte nicht
direkt bearbeitet werden:

| Datei | Inhalt |
|---|---|
| `src/head.part` | Titel, CSS und das gesamte Seiten-Markup |
| `src/script.part` | Plan-Engine, Tabellen, Diagramme, PDF-Export |
| `src/build.py` | setzt beides zu `index.html` zusammen |

```bash
python3 src/build.py     # schreibt index.html neu
```

Das Skript erzeugt daneben `src/regieplan-fragment.html` – dieselbe Seite ohne
`<!doctype>`, `<head>` und `<body>`, die Form, die ein Claude-Artifact braucht.

## Was die Seite von außen lädt

* **Google Fonts** (Oswald, Source Sans 3, IBM Plex Mono) – ohne sie greifen
  die im CSS hinterlegten Systemschriften.
* **jsPDF** von cdnjs, und zwar erst beim Klick auf *PDF herunterladen*.

Sonst nichts: keine Analyse, keine Cookies, keine Datenübertragung. Alle
Eingaben bleiben im `localStorage` des Browsers, in dem sie gemacht wurden.

## Daten

Meldezahlen, Namen und Zeitplan liegen ausschließlich lokal. Wer die Seite
aufruft, sieht den Ausgangsstand aus `index.html`, bis er oder sie selbst
etwas ändert oder einen Stand aus einer Datei lädt.

## Lizenz

Interne Arbeitsunterlage des Landesverbands Sachsen des DAV.
