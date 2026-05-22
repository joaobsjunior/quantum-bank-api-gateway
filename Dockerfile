FROM krakend:2.13.4

WORKDIR /etc/krakend

COPY krakend.json krakend-bootstrap.json krakend-banking.json ./

EXPOSE 8080 8443
