# Regieplan Lead-Wettkämpfe

Interaktiver Zeit- und Personalplan für Kletterwettkämpfe im Lead.
Landesverband Sachsen des DAV · angelegt für den 4. Offenen Sächsischen Kidscup 2026
(Kletterhalle Quacke Zittau, 26.09.2026), aber für jeden Wettkampf verwendbar.

**Die Seite: [noelsimon.github.io/Organisation_Lead_Wettk-mpfe](https://noelsimon.github.io/Organisation_Lead_Wettk-mpfe/)**
(erreichbar, sobald GitHub Pages aktiviert ist – siehe unten)

Eine einzige HTML-Datei, kein eigener Server, kein Build-Schritt beim
Aufrufen. Alles rechnet im Browser; für Login, Freigabe und den gemeinsamen
Datenstand steht im Hintergrund ein Supabase-Projekt (siehe unten).

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

**Login und Freigabe.** Die Seite ist nur für angemeldete, von der Orga
freigegebene Personen sichtbar. Bei der Registrierung wählt man eine
Kategorie (Orga-Team, Sicherung, Ergebnisdienst, Routenbau, Buffet); die Orga
sieht neue Anmeldungen im Admin-Dashboard, gibt sie frei oder lehnt sie ab und
kann Kategorie und Admin-Rechte jederzeit ändern. Nur das Orga-Team darf den
Plan wirklich bearbeiten, Routenbau darf die Texte in „Routenplan" und
„Routenbau" ändern, alle anderen sehen nur zu. Details und Einrichtung siehe
Abschnitt „Login, Freigabe und Rechte einrichten" unten.

## GitHub Pages aktivieren

Einmalig, danach ist die Seite unter der Adresse oben erreichbar:

1. Im Repository auf **Settings** → links **Pages**
2. Bei *Build and deployment* → *Source*: **Deploy from a branch**
3. Branch: **main**, Ordner: **/ (root)** → **Save**

Nach ein bis zwei Minuten ist die Seite online. Jeder Push auf `main`
veröffentlicht die neue Fassung automatisch.

## Bearbeiten

`index.html` wird aus drei Quelldateien zusammengesetzt und sollte nicht
direkt bearbeitet werden:

| Datei | Inhalt |
|---|---|
| `src/config.part` | Supabase-Zugangsdaten (Project URL + anon key) |
| `src/head.part` | Titel, CSS und das gesamte Seiten-Markup |
| `src/script.part` | Plan-Engine, Login/Freigabe, Tabellen, Diagramme, PDF-Export |
| `src/build.py` | setzt alle drei zu `index.html` zusammen |

```bash
python3 src/build.py     # schreibt index.html neu
```

Das Skript erzeugt daneben `src/regieplan-fragment.html` – dieselbe Seite ohne
`<!doctype>`, `<head>` und `<body>`, die Form, die ein Claude-Artifact
braucht. Login und der gemeinsame Datenstand funktionieren dort nicht: die
Sandbox eines Claude-Artifacts blockiert Netzwerkzugriffe auf Supabase, die
Seite fällt in diesem Kontext automatisch auf „nur lokal" zurück.

## Login, Freigabe und Rechte einrichten

Die Seite ist erst nutzbar, sobald ein Supabase-Projekt angebunden ist – ohne
gültige Zugangsdaten in `src/config.part` bleibt sie auf der Anmeldemaske
stehen. Einmalig einzurichten:

1. **Datenbank anlegen.** Im Supabase-Projekt unter *SQL Editor* den Inhalt
   von [`supabase/schema.sql`](supabase/schema.sql) ausführen. Legt Profile,
   die geteilten Planungsdaten, Speicherstände und die Rechte-Policies an.
2. **E-Mail-Login aktivieren.** *Authentication → Providers → Email*
   einschalten (die „Confirm email"-Option nach Bedarf).
3. **Zugangsdaten eintragen.** In `src/config.part` `SUPABASE_URL` und
   `SUPABASE_ANON_KEY` aus *Project Settings → API* eintragen, danach
   `python3 src/build.py`. Der anon key ist bewusst öffentlich im Client
   sichtbar – die Absicherung passiert über die RLS-Policies aus Schritt 1.
4. **Dich selbst freischalten.** Einmal über die Seite registrieren (Kategorie
   „Orga-Team"), danach im SQL Editor:
   ```sql
   update public.profiles set is_admin = true, status = 'approved'
   where email = 'deine@mail.de';
   ```
   Ab jetzt siehst du im Admin-Dashboard („Anmeldungen freigeben …", nur im
   Orga-Bereich sichtbar) alle weiteren Registrierungen und kannst sie
   freigeben, ablehnen oder Kategorie/Admin-Rechte ändern.
5. **Resend-Benachrichtigung einrichten** (optional, aber empfohlen – sonst
   merkst du neue Anmeldungen nur beim Blick ins Dashboard):
   - Bei [resend.com](https://resend.com) einen API-Key erzeugen.
   - Edge Function deployen (Supabase CLI nötig):
     ```bash
     supabase functions deploy notify-signup
     supabase secrets set RESEND_API_KEY=re_xxxxxxxx
     supabase secrets set ADMIN_EMAIL=deine@mail.de
     ```
   - Im Dashboard unter *Database → Webhooks* einen neuen Hook anlegen:
     Tabelle `profiles`, Event `INSERT`, Typ „Supabase Edge Functions",
     Funktion `notify-signup`. Supabase übernimmt dabei die Authentifizierung
     des Aufrufs, es muss kein Secret von Hand verdrahtet werden.

**Rechte je Kategorie:** Orga-Team bearbeitet alles; Routenbau darf nur die
Texte in den Abschnitten „Routenplan" und „Routenbau" ändern; Sicherung,
Ergebnisdienst und Buffet sehen nur zu. Durchgesetzt wird das doppelt – als
Komfort blendet die Oberfläche nicht erlaubte Bedienelemente aus, wirklich
verbindlich sind die RLS-Policies in der Datenbank. Bekannte Einschränkung:
Die Trennung „Routenbau darf nur einzelne Textstellen ändern" ist nur
clientseitig durchgesetzt, weil alle Texte in einem einzigen JSON-Datensatz
liegen (siehe Kommentar in `supabase/schema.sql`).

## Was die Seite von außen lädt

* **Supabase** (`@supabase/supabase-js` von jsdelivr) – Login, Freigabe, der
  gemeinsame Planungsstand und die Speicherstände.
* **Google Fonts** (Oswald, Source Sans 3, IBM Plex Mono) – ohne sie greifen
  die im CSS hinterlegten Systemschriften.
* **jsPDF** von cdnjs, und zwar erst beim Klick auf *PDF herunterladen*.

Keine Analyse, keine Werbe- oder Tracking-Cookies. Ohne Login ist außer der
Anmeldemaske nichts von der Seite zu sehen; angemeldete Eingaben liegen im
Supabase-Projekt (siehe oben) plus als Offline-Zwischenspeicher im
`localStorage` des jeweils genutzten Browsers.

## Daten

Meldezahlen, Namen, Zeitplan und Speicherstände liegen zentral im
Supabase-Projekt und sind nur für freigegebene, angemeldete Personen sichtbar
und (je nach Kategorie) bearbeitbar. `localStorage` dient nur noch als
Offline-Zwischenspeicher des jeweiligen Browsers.

## Lizenz

Interne Arbeitsunterlage des Landesverbands Sachsen des DAV.
