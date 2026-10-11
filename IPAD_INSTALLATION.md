# 📱 Anleitung: iSweep auf dem iPad installieren

Diese Anleitung erklärt Schritt für Schritt, wie du **iSweep** auf deinem physischen iPad oder im iPad-Simulator installierst und startest.

---

## 📋 Voraussetzungen

- **Ein Mac** mit macOS 13 (Ventura) oder neuer
- **Xcode 15** (oder neuer) aus dem Mac App Store
- **Ein iPad** mit iPadOS 16.0 oder neuer (z. B. iPad, iPad Air, iPad mini, iPad Pro)
- Ein passendes Verbindungskabel (USB-C bzw. Lightning auf USB/USB-C)
- Eine kostenlose **Apple-ID** (ein kostenpflichtiger Apple Developer Account ist **nicht** zwingend erforderlich)

---

## 🚀 Methode 1: Direkt über Xcode auf dein iPad installieren (Empfohlen)

Dies ist der schnellste, sicherste und stabilste Weg.

### Schritt 1: Entwicklermodus auf dem iPad aktivieren
1. Öffne auf deinem iPad die **Einstellungen**.
2. Scrolle zu **Datenschutz & Sicherheit** -> ganz nach unten zu **Entwicklermodus**.
3. Schalte den Entwicklermodus ein.
4. Das iPad startet neu. Nach dem Neustart entsperrst du das iPad und bestätigst mit **Aktivieren** und deinem Entsperrcode.

### Schritt 2: iPad mit dem Mac verbinden
1. Schließe dein iPad per Kabel an deinen Mac an.
2. Bestätige auf beiden Geräten die Meldung **„Diesem Computer vertrauen?“** mit deinem Entsperrcode.

### Schritt 3: Projekt in Xcode öffnen
1. Öffne die Projektdatei `iSweep.xcodeproj` auf deinem Mac:
   ```bash
   open iSweep.xcodeproj
   ```

### Schritt 4: Apple-ID & Signing einstellen
1. Klicke in Xcode ganz links im Projekt-Navigator auf das oberste blaue Symbol **iSweep**.
2. Wähle unter **TARGETS** das Target **`iSweep iPad`** aus.
3. Klicke oben auf den Reiter **Signing & Capabilities**.
4. Wähle bei **Team** dein persönliches Team aus (deine Apple-ID).
   * *Falls noch keine Apple-ID hinterlegt ist:* Klicke auf *Add Account…* und melde dich mit deiner Apple-ID an.
5. Sollte eine Fehlermeldung bezüglich des Bundle Identifiers erscheinen, ändere `com.isweep.app.mac` bzw. `iSweep` einfach leicht ab (z. B. `com.deinname.isweep`).

### Schritt 5: Als Zielgerät dein iPad auswählen & starten
1. Klicke ganz oben in der Xcode-Titelleiste auf das Scheme-Menü (neben dem Play-Button).
2. Wähle **`iSweep iPad`** und als Ziel dein angeschlossenes **iPad** (z. B. *„Dein iPad“*).
3. Drücke auf den **Play-Button (⌘R)**.
4. Xcode kompiliert die App und überträgt sie direkt auf dein iPad.

### Schritt 6: Entwickler-Zertifikat am iPad vertrauen (Einmalig)
Beim ersten Start erscheint am iPad der Hinweis *„Nicht vertrauenswürdiger Entwickler“*:
1. Öffne am iPad **Einstellungen** -> **Allgemein** -> **VPN und Geräteverwaltung**.
2. Tippe unter *Entwickler-App* auf deine Apple-ID / dein Zertifikat.
3. Tippe auf **„[Deine Apple-ID] vertrauen“** und bestätige.
4. Fertig! Du kannst **iSweep** jetzt jederzeit auf deinem iPad öffnen!

---

## 🎨 iPad-Exklusive Funktionen in iSweep

Wenn du iSweep auf dem iPad ausführst, stehen dir spezielle iPad-Features zur Verfügung:
- **✏️ Apple Pencil Integration:**
  - Floating Notizen-Button & Notizen-Canvas (`PencilKit`) zum Festhalten von Aufräum-Notizen oder Markierungen.
  - Double-Tap Unterstützung für den Apple Pencil 2 & Apple Pencil Pro.
- **📱 Volle Touch- & Gesten-Unterstützung:**
  - Langes Drücken (*Long-Press*) zum schnellen Vorab-Prüfen von Dateien.
  - Wischgesten zur Mehrfachauswahl.
- **📊 Adaptive iPad-Layouts:**
  - Vollständige Split-View & Stage Manager Unterstützung auf dem iPad.

---

## 📲 Methode 2: Installation über Sideloading (.IPA mit AltStore / Sideloadly)

Wenn du die App ohne ständige Kabelverbindung aktualisieren möchtest:

1. **IPA-Datei exportieren:**
   - In Xcode: Scheme auf `iSweep iPad` -> Menü **Product** -> **Archive**.
   - Nach Fertigstellung im Organizer auf **Distribute App** -> **Custom** -> **Ad Hoc** oder **Development** klicken und die `.ipa` Datei auf dem Mac speichern.
2. **Über Sideloadly oder AltStore installieren:**
   - Öffne [Sideloadly](https://sideloadly.io/) oder [AltStore](https://altstore.io/) auf deinem Mac.
   - Ziehe die erzeugte `iSweep iPad.ipa` in das Fenster und gib deine Apple-ID ein.
   - Die App wird kabellos auf dein iPad installiert.

---

## 💻 Methode 3: Im iPad-Simulator auf dem Mac testen

Falls du gerade kein physisches iPad zur Hand hast:
1. Öffne `iSweep.xcodeproj` in Xcode.
2. Wähle oben das Scheme **`iSweep iPad`**.
3. Wähle als Zielgerät einen Simulator, z. B. **iPad Pro 13-inch (M4)** oder **iPad Air 11-inch**.
4. Drücke **⌘R**. Der macOS iPadOS-Simulator öffnet sich und startet iSweep in voller Auflösung.
