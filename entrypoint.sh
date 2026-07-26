#!/usr/bin/env bash
set -e

: "${LMS_HOST:?musisz ustawić LMS_HOST}"
: "${LMS_PORT:=3483}"
: "${PLAYER_NAME:=LMS Sendspin Bridge}"
: "${PLAYER_MAC:=02:00:00:00:00:01}"
: "${SAMPLE_RATE:=44100}"
: "${SENDSPIN_PORT:=8927}"
: "${SENDSPIN_NAME:=LMS via Sendspin}"

PCM_FIFO=/tmp/lms_pcm_raw.fifo   # surowy PCM: squeezelite -> ffmpeg
WAV_FIFO=/tmp/lms_pcm.fifo       # PCM owinięty w WAV: ffmpeg -> sendspin serve

# FIFO to specjalny plik - dane w nim żyją wyłącznie w buforze jądra,
# niezależnie od tego, na jakim systemie plików leży katalog /tmp.
# Nic z audio nie trafia na SSD.
rm -f "$PCM_FIFO" "$WAV_FIFO"
mkfifo "$PCM_FIFO"
mkfifo "$WAV_FIFO"

# Otwieramy oba FIFO w trybie read-write na własnych deskryptorach - to
# NIGDY się nie blokuje (proces trzyma jednocześnie "czytnika" i "pisarza").
# Bez tego producent i konsument każdej rury wzajemnie się blokują w
# oczekiwaniu na otwarcie drugiej strony.
exec 3<>"$PCM_FIFO"
exec 4<>"$WAV_FIFO"

cleanup() {
    echo "[entrypoint] Zatrzymuję squeezelite (PID ${SQUEEZELITE_PID:-?}) i ffmpeg (PID ${FFMPEG_PID:-?})"
    [ -n "${SQUEEZELITE_PID:-}" ] && kill "$SQUEEZELITE_PID" 2>/dev/null || true
    [ -n "${FFMPEG_PID:-}" ] && kill "$FFMPEG_PID" 2>/dev/null || true
    exec 3>&- 2>/dev/null || true
    exec 4>&- 2>/dev/null || true
    rm -f "$PCM_FIFO" "$WAV_FIFO"
}
trap cleanup EXIT TERM INT

echo "[entrypoint] LMS ${LMS_HOST}:${LMS_PORT} -> squeezelite(${PLAYER_NAME}) -> PCM_FIFO -> ffmpeg -> WAV_FIFO -> sendspin serve(${SENDSPIN_NAME}:${SENDSPIN_PORT})"

# squeezelite w tle: rejestruje się w LMS, dekoduje do PCM, pisze na stdout,
# co przekierowujemy do PCM_FIFO.
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
    > "$PCM_FIFO" \
    2>/tmp/squeezelite.log &
SQUEEZELITE_PID=$!
echo "[entrypoint] squeezelite wystartował (PID ${SQUEEZELITE_PID})"

# ffmpeg w tle: czyta surowy PCM z PCM_FIFO, owija w nagłówek WAV
# (deklarujący sample rate/kanały/bitowość wprost, żeby sendspin niczego
# nie musiał zgadywać), i pisze do WAV_FIFO. Stderr NIE jest ukrywany -
# błędy lecą do głównego logu kontenera (`docker logs`).
ffmpeg -hide_banner -loglevel error \
    -f s16le -ar "${SAMPLE_RATE}" -ac 2 -i "$PCM_FIFO" \
    -f wav "$WAV_FIFO" &
FFMPEG_PID=$!
echo "[entrypoint] ffmpeg wystartował (PID ${FFMPEG_PID}), startuję sendspin serve..."

# Potwierdzone przez `sendspin serve --help`:
# - source to argument pozycyjny (nie --source)
# - --source-format wav: WAV_FIFO ma nagłówek WAV, więc sample rate/kanały/
#   bitowość są deklarowane w danych, a nie zgadywane przez demuxer.
exec sendspin serve "$WAV_FIFO" \
    --source-format wav \
    --port "${SENDSPIN_PORT}" \
    --name "${SENDSPIN_NAME}"
