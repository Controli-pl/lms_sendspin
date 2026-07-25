#!/usr/bin/env bash
set -e

: "${LMS_HOST:?musisz ustawić LMS_HOST}"
: "${LMS_PORT:=3483}"
: "${PLAYER_NAME:=LMS Sendspin Bridge}"
: "${PLAYER_MAC:=02:00:00:00:00:01}"
: "${SAMPLE_RATE:=44100}"
: "${SENDSPIN_PORT:=8927}"
: "${SENDSPIN_NAME:=LMS via Sendspin}"

echo "[entrypoint] LMS ${LMS_HOST}:${LMS_PORT} -> squeezelite(${PLAYER_NAME}) -> aiosendspin(${SENDSPIN_NAME}:${SENDSPIN_PORT})"

# -o -        : audio na stdout zamiast na kartę dźwiękową (nic nie leci na dysk)
# -c pcm      : wymuszamy PCM
# -r RATE-RATE: sztywny sample rate, żeby glue.py nie musiał negocjować formatu
#
# UWAGA: dokładne flagi zweryfikuj przez `squeezelite -h` w kontenerze -
# różne buildy mają drobne różnice w dostępnych opcjach -o.
exec squeezelite \
    -s "${LMS_HOST}:${LMS_PORT}" \
    -n "${PLAYER_NAME}" \
    -m "${PLAYER_MAC}" \
    -o - \
    -c pcm \
    -r "${SAMPLE_RATE}-${SAMPLE_RATE}" \
    | python3 /glue.py \
        --sample-rate "${SAMPLE_RATE}" \
        --sendspin-port "${SENDSPIN_PORT}" \
        --sendspin-name "${SENDSPIN_NAME}"
