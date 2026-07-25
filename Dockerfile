FROM python:3.12-alpine

# squeezelite: klient SlimProto, rejestruje się w LMS jako player
# (jeśli w Twojej wersji Alpine go brak w repo "community", odkomentuj
# poniższą linię, żeby dołączyć repo edge/community)
# RUN echo "http://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories
RUN apk add --no-cache squeezelite bash \
    && pip install --no-cache-dir aiosendspin zeroconf

COPY entrypoint.sh /entrypoint.sh
COPY glue.py /glue.py
RUN chmod a+x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
