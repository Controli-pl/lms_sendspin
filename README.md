# LMS → Sendspin Bridge — wersja Portainer/Docker Compose

squeezelite rejestruje się w LMS jako wirtualny odtwarzacz i pisze surowy
PCM do FIFO (w pamięci, nie na dysk). `sendspin serve` (pakiet `sendspin`,
gotowe CLI, nie niskopoziomowy `aiosendspin`) czyta ten FIFO jako źródło
i sam obsługuje WebSocket, mDNS i parowanie klientów Sendspin (np.
ESP32/ESPHome). **Zero własnego kodu Python.**

## Historia zmian w tym projekcie (żeby było jasne, co się zmieniło i czemu)

1. Pierwsza wersja pisała własny `glue.py` wołający bezpośrednio
   `aiosendspin.server.SendspinServer`. Po realnym teście okazało się, że
   ta klasa jest niskopoziomowym obiektem protokołu (wymaga własnej
   infrastruktury `identity`/`pairing_store`/WebSocket/mDNS) — dużo więcej
   roboty niż "wrzuć PCM, dostań serwer".
2. Znaleźliśmy `sendspin` (PyPI) — wysokopoziomowe CLI z trybu `serve`,
   które tę infrastrukturę już ma w sobie (tzw. "Sendspin Party": serwer
   odgrywający wskazany plik/źródło audio dla podłączonych klientów).
   FIFO jest dla niego zwykłym plikiem do odczytu, więc podajemy go jako
   `source` i unikamy pisania czegokolwiek samodzielnie.

## Status

- `docker-compose.yml` — bez zmian, niezależny od wewnętrznej implementacji.
- `Dockerfile` — gotowy: Debian (squeezelite jest tam spakietowany) +
  `pip install sendspin`.
- `entrypoint.sh` — squeezelite w tle pisze do FIFO, `sendspin serve`
  czyta z FIFO na pierwszym planie. **Jedna rzecz do potwierdzenia**:
  dokładne flagi `sendspin serve` (`--source`, `--port`, `--name`) są moją
  najlepszą rekonstrukcją z dokumentacji, nie 1:1 potwierdzonym `--help`.
  Sprawdź w kontenerze:
  ```
  docker exec -it lms-sendspin-bridge sendspin serve --help
  ```
  i popraw wywołanie w `entrypoint.sh`, jeśli nazwy flag się różnią.

## Jak wdrożyć w Portainerze

Tak jak poprzednio — `build: .` wymaga dostępu do całego folderu:

- **Repository (Git)**: wrzuć te pliki do repo, w Portainerze
  `Stacks → Add stack → Repository`.
- **Ręczny build**: `docker build -t lms-sendspin-bridge:latest .` lokalnie,
  potem w compose zamień `build: .` na `image: lms-sendspin-bridge:latest`
  i wklej w edytorze web Portainera.

## Konfiguracja

Zmienne środowiskowe w `docker-compose.yml` — ustaw przynajmniej
`LMS_HOST`. `network_mode: host` zostaje: potrzebne dla mDNS (ogłaszanie
serwera Sendspin) i SlimProto discovery w LAN.

## Kroki testowe

1. `docker exec -it lms-sendspin-bridge sendspin serve --help` — potwierdź
   realne flagi, popraw `entrypoint.sh` jeśli trzeba.
2. `docker logs -f lms-sendspin-bridge` — sprawdź, czy squeezelite się
   połączyło z LMS i czy `sendspin serve` wystartował bez błędów.
3. Sprawdź w LMS, czy player o nazwie z `PLAYER_NAME` się pojawił.
4. Sprawdź na ESP32/ESPHome, czy serwer Sendspin jest widoczny i czy się
   łączy (mDNS) — zagraj coś w LMS na tym playerze i posłuchaj.
