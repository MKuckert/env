#!/usr/bin/env bash

mkdir -p ~/env/manifest/backup
cd ~/repos/manifest/docker
nerdctl compose exec -T postgres pg_dump -U manifest manifest > ~/env/manifest/backup/manifest-$(date +%F).sql
