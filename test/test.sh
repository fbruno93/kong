#!/bin/bash

http POST :8001/plugins name=opentelemetry

# mockbin
http PUT :8001/services/mockbin host=mockbin.org
http PUT :8001/services/mockbin/routes/mockbin hosts:='["mockbin.local.shoujo.io"]'

# admin api
http PUT :8001/services/admin host=127.0.0.1 port:=8001
http PUT :8001/services/admin/routes/admin hosts:='["admin.local.shoujo.io"]'