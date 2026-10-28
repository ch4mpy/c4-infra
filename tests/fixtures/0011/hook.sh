#!/bin/sh
# 0011 fixture: the provider of down-hook.yml; leaves a marker next to itself when compose runs it
id -un > "$(dirname "$0")/hook-ran"
