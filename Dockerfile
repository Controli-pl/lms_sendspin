FROM python:3.12-slim

# squeezelite jest spakietowany dla Debiana/Ubuntu, NIE ma go w oficjalnych
# repo Alpine - stąd zmiana bazowego obrazu z alpine na slim (Debian).
RUN apt-get update \
    && apt-get install -y --no-install-recommends squeezelite \
    && rm -rf /var/lib/apt/lists/* \
    && pip install --no-cache-dir aiosendspin zeroconf Pillow

COPY entrypoint.sh /entrypoint.sh
COPY glue.py /glue.py
RUN chmod a+x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
