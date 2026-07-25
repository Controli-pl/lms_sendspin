FROM python:3.12-slim

# squeezelite jest spakietowany dla Debiana/Ubuntu, nie ma go w Alpine.
#
# "sendspin" (nie mylić z niskopoziomowym aiosendspin) to gotowe CLI z trybem
# serwerowym `sendspin serve`, które samo ogłasza się przez mDNS, obsługuje
# WebSocket i parowanie klientów - nie musimy tego pisać sami.
RUN apt-get update \
    && apt-get install -y --no-install-recommends squeezelite procps \
    && rm -rf /var/lib/apt/lists/* \
    && pip install --no-cache-dir sendspin

COPY entrypoint.sh /entrypoint.sh
RUN chmod a+x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
