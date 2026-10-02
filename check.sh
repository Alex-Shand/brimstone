#!/usr/bin/env bash

set -eu

nix flake check path:.
nix run github:astro/deadnix .