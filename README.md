# Desert Survival — Trainer Game

Gra survival na pustyni w estetyce Fallout, napędzana pedałowaniem na trenażerze rowerowym (Elite Suito / dowolny FTMS).

## Wymagania

### BLEBridge (komunikacja z trenażerem)
- [.NET 6 SDK](https://dotnet.microsoft.com/download/dotnet/6.0) (Windows 10/11)
- Bluetooth LE w komputerze
- Trenażer wspierający FTMS (np. Elite Suito)

### DesertSurvival (gra)
- [Unity 2022.3 LTS](https://unity.com/releases/editor/qa/lts-releases) z Universal Render Pipeline (URP)
- Windows 10/11

## Szybki start

### 1. BLEBridge

```powershell
cd BLEBridge
dotnet build
dotnet run
# Bridge skanuje BLE, łączy się z trenażerem i streamuje dane UDP na localhost:7878
```

### 2. Unity

1. Otwórz folder `DesertSurvival/` w Unity Hub jako istniejący projekt
2. Jeśli tworzysz nowy projekt Unity — wybierz **3D (URP)** template, potem skopiuj `Assets/Scripts/` do niego
3. Uruchom scenę `Desert` — pojazd reaguje na dane z trenażera lub klawiaturę (fallback)

### Sterowanie (fallback klawiaturowy)

| Klawisz | Akcja |
|---------|-------|
| ↑ / W | Pedałowanie (symuluje 150W / 80 RPM) |
| ← → / A D | Skręt |

## Architektura

```
Elite Suito (BLE FTMS)
    ↓ Bluetooth LE
[BLEBridge] — .NET 6 console app (localhost UDP:7878)
    ↓ JSON {power, cadence, speed, timestamp}
[Unity Game] — TrainerInputManager → VehicleController → World
```

## Struktura

```
BLEBridge/           — .NET 6 console app: BLE FTMS → UDP
DesertSurvival/      — Unity project
  Assets/Scripts/
    Trainer/         — Odczyt danych z trenażera
    Vehicle/         — Kontroler pojazdu + system energii
    World/           — Pickup zasobów, POI, Fog of War
    Progression/     — Ulepszenia, inwentarz, zapis
    Session/         — Pętla wyprawy, zagrożenia
    UI/              — HUD i menu bazy (Fallout style)
```
