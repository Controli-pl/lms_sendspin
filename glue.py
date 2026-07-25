#!/usr/bin/env python3
"""
Klej LMS -> Sendspin.

squeezelite (-o -) pisze surowy PCM na swój stdout; run.sh łączy to potokiem
z tym skryptem. Ten skrypt czyta PCM ze swojego stdin (cały czas w RAM,
zero zapisu na dysk) i wystawia je jako serwer Sendspin, do którego
podłączają się klienci (np. ESP32/ESPHome).

*** WAŻNE - DO ZWERYFIKOWANIA PRZED URUCHOMIENIEM ***
Poniższe wywołania `aiosendspin.server.SendspinServer(...)` /
`server.start()` / `server.push_audio(...)` to SZKIELET pokazujący
docelowy przepływ danych, a NIE zweryfikowane 1:1 z aktualnym API
biblioteki - nie miałem dostępu do pełnej dokumentacji/źródeł aiosendspin
w momencie pisania tego pliku. Po zainstalowaniu paczki w kontenerze
sprawdź faktyczne nazwy klas/metod, np.:

    python3 -c "import aiosendspin; help(aiosendspin)"
    python3 -c "import aiosendspin.server as s; print(dir(s))"

albo przejrzyj katalog `site-packages/aiosendspin/server/` i porównaj
z tym, jak z tej biblioteki korzysta Music Assistant:
https://github.com/music-assistant/server/tree/dev/music_assistant/providers/sendspin/playback.py
(to najbardziej wiarygodny, produkcyjny przykład użycia aiosendspin
jako serwera, jaki na razie znam). Dopasuj wywołania poniżej do tego,
co tam zobaczysz.
"""
import argparse
import asyncio
import logging
import sys

# TODO: potwierdź faktyczną ścieżkę importu w zainstalowanej wersji
from aiosendspin.server import SendspinServer  # placeholder - do weryfikacji

logging.basicConfig(level=logging.INFO, stream=sys.stderr)
log = logging.getLogger("lms-sendspin-glue")

CHANNELS = 2
BITS_PER_SAMPLE = 16
CHUNK_FRAMES = 1024  # ile "ramek" audio na jeden kawałek wysyłany dalej - do strojenia


async def read_pcm_chunks(loop: asyncio.AbstractEventLoop, chunk_bytes: int):
    """Asynchronicznie czyta PCM ze stdin w stałych kawałkach, bez dotykania dysku."""
    reader = asyncio.StreamReader()
    protocol = asyncio.StreamReaderProtocol(reader)
    await loop.connect_read_pipe(lambda: protocol, sys.stdin.buffer.raw)

    while True:
        try:
            chunk = await reader.readexactly(chunk_bytes)
        except asyncio.IncompleteReadError as exc:
            # squeezelite się zatrzymał / koniec strumienia - dogrywamy resztę i kończymy
            if exc.partial:
                yield exc.partial
            break
        if not chunk:
            break
        yield chunk


async def main(sample_rate: int, sendspin_port: int, sendspin_name: str) -> None:
    loop = asyncio.get_event_loop()
    bytes_per_frame = CHANNELS * (BITS_PER_SAMPLE // 8)
    chunk_bytes = CHUNK_FRAMES * bytes_per_frame

    log.info(
        "Startuję serwer Sendspin '%s' na porcie %s (%s Hz, %s kanałów, %s-bit)",
        sendspin_name, sendspin_port, sample_rate, CHANNELS, BITS_PER_SAMPLE,
    )

    # --- PLACEHOLDER: dopasuj do realnego API aiosendspin ---
    server = SendspinServer(
        name=sendspin_name,
        port=sendspin_port,
        sample_rate=sample_rate,
        channels=CHANNELS,
        bits_per_sample=BITS_PER_SAMPLE,
    )
    await server.start()  # powinno też uruchomić ogłaszanie mDNS, do potwierdzenia
    # ---------------------------------------------------------

    log.info("Serwer wystartował, czekam na PCM ze stdin (squeezelite)...")

    try:
        async for pcm_chunk in read_pcm_chunks(loop, chunk_bytes):
            # --- PLACEHOLDER: dopasuj nazwę metody wysyłki audio ---
            await server.push_audio(pcm_chunk)
            # ---------------------------------------------------------
    except Exception:
        log.exception("Błąd w pętli przesyłania audio")
        raise
    finally:
        log.info("Zatrzymuję serwer Sendspin")
        await server.stop()  # do potwierdzenia w realnym API


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--sample-rate", type=int, default=44100)
    parser.add_argument("--sendspin-port", type=int, default=8927)
    parser.add_argument("--sendspin-name", default="LMS via Sendspin")
    args = parser.parse_args()

    asyncio.run(main(args.sample_rate, args.sendspin_port, args.sendspin_name))
