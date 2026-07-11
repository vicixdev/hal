#!/bin/sh

set -e

odin build src -collection:shared=shared -out:build/out -debug -strict-style -vet -warnings-as-errors
