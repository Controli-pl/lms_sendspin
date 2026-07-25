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

cleanup() {
    echo "[entrypoint] Zatrzymuję squeezelite (PID ${SQUEEZELITE_PID:-?})"
    [ -n "${SQUEEZELITE_PID:-}" ] && kill "$SQUEEZELITE_PID" 2>/dev/null || true
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
    > "$FIFO" &
SQUEEZELITE_PID=$!

echo "[entrypoint] squeezelite wystartował (PID ${SQUEEZELITE_PID}), startuję sendspin serve..."

# Potwierdzone przez `sendspin serve --help`:
# - source to argument pozycyjny (nie --source)
# - --source-format s16le mówi ffmpeg/PyAV pod spodem, że to surowy
#   16-bit little-endian PCM (dokładnie to, co daje `squeezelite -a 16 -o -`),
#   bo z samego FIFO (bez rozszerzenia pliku) format nie jest wykrywalny.
exec sendspin serve "$FIFO" \
    --source-format s16le \
    --port "${SENDSPIN_PORT}" \
    --name "${SENDSPIN_NAME}"
