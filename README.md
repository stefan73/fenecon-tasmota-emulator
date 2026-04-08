# FENECON Tasmota Emulator

Dieses Projekt emuliert die API Endpunkte eines `Shelly Plug S Gen3` auf einem ESP32 mit
`Tasmota32` und `Berry`-Scripting, damit ein FENECON-System lokale Leistungs-
und Energiewerte wie von einem Shelly-Geraet mit der Shelly-DIY App einlesen kann.

Die Werte kommen direkt aus einem Tasmota-Geraet mit aktivem Energiemodul.

Der ESP32 stellt daraus die fuer FENECON benoetigten Shelly-Endpunkte auf Port
`80` bereit, insbesondere:

- `GET /shelly`
- `GET /rpc/Shelly.GetDeviceInfo`
- `GET /rpc/Shelly.GetStatus`

Zusaetzlich werden weitere kompatible Shelly-Endpunkte bereitgestellt:

- `GET /rpc/Switch.GetStatus`
- `GET /status`
- `GET /meter/0`
- `GET /relay/0`

## Ziel und Zweck

Die Idee hinter dem Projekt ist:

- ein vorhandenes Tasmota-Energiegeraet liefert bereits Leistung und Energie
- Berry-Scripting emuliert darauf lokal die noetigen API Endpunkte eines Shelly Plug S Gen3
- FENECON bindet dieses Geraet dann wie einen echten Shelly ein

Damit kann ein vorhandenes FENECON-System mit Messwerten eines Tasmota-Geraets
arbeiten, ohne dass dafuer ein echter Shelly Plug vorhanden sein muss.

## Status

Der aktuelle Stand ist ein funktionierender Proof of Concept:

- FENECON akzeptiert das Geraet als `Shelly Plug S Gen3`
- Leistung und Energie werden ueber Shelly-kompatible Endpunkte bereitgestellt
- die Emulation laeuft auf ESP32 mit `Tasmota32` und `Berry`

## Hardware- und Firmware-Hinweis

Dieses Projekt ist fuer `ESP32` mit `Tasmota32` gedacht.

Voraussetzungen:

- ein ESP32-basiertes Tasmota-Geraet
- eine Tasmota-Firmware mit `Berry`-Scripting
- ein Geraet bzw. Setup, bei dem Tasmota Leistungs- und Energiewerte liefert

## Projektaufbau

- `berry/fenecon_shelly_emulator.be`
  Berry-Skript mit der Shelly-Emulation
- `berry/autoexec.be`
  Startskript fuer das automatische Laden beim Boot

## Installation auf Tasmota

In Tasmota unter `Consoles` -> `Manage File system` diese beiden Dateien in das
Dateisystem hochladen:

- `fenecon_shelly_emulator.be`
- `autoexec.be`

Danach das Geraet neu starten.

## Funktionstest im Browser

Nach dem Neustart sollten diese Aufrufe im Browser oder per `curl`/`wget`
antworten:

- `http://<ip-des-geraets>/shelly`
- `http://<ip-des-geraets>/rpc/Shelly.GetDeviceInfo`
- `http://<ip-des-geraets>/rpc/Shelly.GetStatus`

Optional koennen auch diese Zusatz-Endpunkte getestet werden:

- `http://<ip-des-geraets>/rpc/Switch.GetStatus`
- `http://<ip-des-geraets>/status`
- `http://<ip-des-geraets>/meter/0`
- `http://<ip-des-geraets>/relay/0`

Wenn diese Endpunkte JSON liefern, laeuft die Emulation grundsaetzlich.

## Einbindung in FENECON / FEMS Portal

Die Einbindung ist identisch zur ESPHome-Variante:

1. Im FENECON Portal im `FEMS App Center` die kostenfreie App `Shelly DIY`
   auswaehlen.
2. In FENECON keinen Autodetect verwenden, sondern die Einbindung per
   manueller IP ausfuehren.
3. Die IP des Tasmota-Geraets in FENECON als `Shelly Plug S Gen3` eintragen.
4. Sicherstellen, dass das Geraet im Heimnetz immer dieselbe IP bekommt,
   z. B. ueber eine DHCP-Reservierung im Router.

## Aktuelles Verhalten

- Port `80` liefert die Shelly-kompatible API
- die Emulation stellt Leistung und Energie aus Tasmota-Daten bereit
- die Antwortstruktur ist an einen `Shelly Plug S Gen3` angelehnt
- die Einbindung in FENECON erfolgt ueber manuelle Eingabe der IP-Adresse

## Rechtlicher Hinweis

Dieses Projekt ist eine unabhaengige Kompatibilitaetsimplementierung.

Es besteht keine Verbindung zu und keine Freigabe durch:

- FENECON GmbH
- Shelly Group / Allterco
- Tasmota / Theo Arends

Marken- und Produktnamen Dritter werden ausschliesslich zur Beschreibung von
Kompatibilitaet und Interoperabilitaet verwendet.
