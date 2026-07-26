#!/usr/bin/env bash
set -e

: "${LMS_HOST:?musisz ustawić LMS_HOST}"
: "${LMS_PORT:=3483}"
: "${PLAYER_NAME:=LMS Sendspin Bridge}"
: "${PLAYER_MAC:=02:00:00:00:00:01}"
: "${SAMPLE_RATE:=44100}"
: "${SENDSPIN_PORT:=8927}"
: "${SENDSPIN_NAME:=LMS via Sendspin}"

FIFO=/tmp/lms_pcm.fifo

# FIFO to specjalny plik - dane w nim żyją wyłącznie w buforze jądra,
# niezależnie od tego, na jakim systemie plików leży katalog /tmp.
# Nic z audio nie trafia na SSD.
rm -f "$FIFO"
mkfifo "$FIFO"

# Otwieramy FIFO w trybie read-write na deskryptorze 3 - to NIGDY się nie
# blokuje (proces trzyma jednocześnie "czytnika" i "pisarza"). Bez tego
# squeezelite (pisze) i `sendspin serve` (czyta dopiero gdy ktoś się
# faktycznie podłączy) wzajemnie się blokują w oczekiwaniu na otwarcie
# drugiej strony - i squeezelite nigdy realnie nie startuje.
exec 3<>"$FIFO"

cleanup() {
    echo "[entrypoint] Zatrzymuję squeezelite (PID ${SQUEEZELITE_PID:-?})"
    [ -n "${SQUEEZELITE_PID:-}" ] && kill "$SQUEEZELITE_PID" 2>/dev/null || true
    exec 3>&- 2>/dev/null || true
    rm -f "$FIFO"
}
trap cleanup EXIT TERM INT

echo "[entrypoint] LMS ${LMS_HOST}:${LMS_PORT} -> squeezelite(${PLAYER_NAME}) -> FIFO -> sendspin serve(${SENDSPIN_NAME}:${SENDSPIN_PORT})"

# squeezelite w tle: rejestruje się w LMS, dekoduje do PCM, pisze na stdout,
# co przekierowujemy do FIFO. Cały czas w RAM, nie na dysku.
#
# Flagi zweryfikowane przez `squeezelite -h` w tym obrazie:
# -o - (stdout), -a 16 (16-bit na stdout), -c pcm (wymuszony PCM),
# -r RATE-RATE (sztywny sample rate).
squeezelite \
    -s "${LMS_HOST}:${LMS_PORT}" \
    -n "${PLAYER_NAME}" \
    -m "${PLAYER_MAC}" \
    -o - \
    -a 16 \
    -c pcm \
    -r "${SAMPLE_RATE}-${SAMPLE_RATE}" \
    -d slimproto=info -d stream=info \
    2>/tmp/squeezelite.log \
    | ffmpeg -hide_banner -loglevel error \
        -f s16le -ar "${SAMPLE_RATE}" -ac 2 -i - \
        -f wav - \
    > "$FIFO" &
SQUEEZELITE_PID=$!

echo "[entrypoint] squeezelite wystartował (PID ${SQUEEZELITE_PID}), startuję sendspin serve..."

# Potwierdzone przez `sendspin serve --help`:
# - source to argument pozycyjny (nie --source)
# - --source-format wav: strumień w FIFO ma teraz nagłówek WAV (dodany przez
#   ffmpeg wyżej), więc sample rate/kanały/bitowość są deklarowane w danych,
#   a nie zgadywane przez demuxer - to naprawia spowolnione/trzeszczące audio
#   sprzed tej zmiany (gdy używaliśmy gołego s16le bez podania rate/channels).
exec sendspin serve "$FIFO" \
    --source-format wav \
    --port "${SENDSPIN_PORT}" \
    --name "${SENDSPIN_NAME}"
