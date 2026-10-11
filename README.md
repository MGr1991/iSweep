# iSweep 🧹✨

> Die moderne, native Reinigungs- & Optimierungs-Suite für **macOS** und **iPadOS**, entwickelt mit 100% purem SwiftUI.

![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg?style=flat)
![Platform](https://img.shields.io/badge/Platforms-macOS%2013%2B%20%7C%20iPadOS%2016%2B-blue.svg?style=flat)
![License](https://img.shields.io/badge/License-MIT-green.svg?style=flat)

---

## 🌟 Hauptfunktionen

### 1. ⚡️ 1-Klick Smart-Bereinigung (`SmartCleanerView`)
- Vollautomatischer Komplett-Check des Macs in Sekunden.
- Bereinigt Benutzer- & App-Caches (`~/Library/Caches`), Xcode DerivedData, System-Logs, Mail-Downloads und den Papierkorb.
- Detaillierte Aufklappkarten mit Vorschau einzelner Dateien und Gesamtfreigabe.

### 2. 👯‍♂️ Intelligenter Duplikate-Finder (`DuplicateScannerView`)
- 2-Stufen-Scan: Schneller Byte-Größenfilter gefolgt von kryptografischen SHA-256 Prüfsummen (`CryptoKit`).
- Gruppiert Duplikate übersichtlich mit Hervorhebung des **Originals** (grün) und der **Duplikate** (orange).
- 1-Klick-Aktion: *„Duplikate markieren (Originale behalten)“* mit sicherer Papierkorb-Verschiebung.

### 3. 🔍 Verwaiste App-Reste (`OrphanScannerView`)
- Erkennt übrig gebliebene Konfigurations-, Cache- und Support-Dateien von Programmen, die bereits deinstalliert wurden.
- Direkte Batch-Bereinigung und Freigabe-Zähler.

### 4. 📦 Vollständiger App-Deinstaller (`AppCleanerView`)
- Listet alle installierten Programme übersichtlich auf.
- Findet automatisch alle verknüpften Dateien in `~/Library/Application Support`, `~/Library/Caches`, `~/Library/Preferences`, etc.
- **Sicherheits-Whitelist:** Schütze wichtige System- und Entwicklertools vor versehentlichem Löschen per Schutzschild-Badge.

### 5. 📁 Visueller Speicher-Scanner (`FolderScannerMainView`)
- Interaktive visuelle Diagramme: Kreis- und Balkendiagramme nach Dateikategorien (Videos, Bilder, Entwicklerdateien, etc.).
- 4 native Finder-Ansichten: **Liste**, **Symbole**, **Spalten** und **Galerie**.
- Smart-Filter: Riesen-Dateien (> 500 MB), Große Dateien (> 100 MB), Alte Dateien (> 6 Monate).

### 6. 🧠 Live-RAM & SSD System-Monitor
- **Echtzeit-Festplattenauslastung** mit iSweep-Gesamtfreigabe-Zähler.
- **Darwin Mach-Kernel RAM Monitor:** Anzeige des belegten und freien Arbeitsspeichers mit 1-Klick-Button *„RAM freigeben“*.

### 7. 🌓 3-Wege Theme-Umschalter & Papierkorb überall
- Schneller Wechsel zwischen **System**, **Hell** und **Dunkel** (inklusive Menüleisten-Steuerung).
- Papierkorb-Verwaltung und Mehrfachauswahl-Modus in jedem einzelnen Tab verfügbar.

---

## 📱 iPad Version installieren

Eine detaillierte Schritt-für-Schritt-Anleitung mit allen Schritten zum Aktivieren des Entwicklermodus auf dem iPad, Apple-ID Code-Signing und Sideloading findest du hier:

👉 **[Ausführliche iPad Installationsanleitung (IPAD_INSTALLATION.md)](IPAD_INSTALLATION.md)**

---

## 🛠 Voraussetzungen & Bauen

- **macOS:** macOS Ventura 13.0 oder neuer
- **iPadOS:** iPadOS 16.0 oder neuer (mit Apple Pencil Notizen-Canvas Integration)
- **Xcode:** Xcode 15 oder neuer

### Projekt mit Xcode kompilieren:
```bash
# Repository klonen
git clone https://github.com/MGr1991/iSweep.git
cd iSweep

# In Xcode öffnen
open iSweep.xcodeproj
```

---

## 📄 Lizenz
Dieses Projekt steht unter der [MIT License](LICENSE).
