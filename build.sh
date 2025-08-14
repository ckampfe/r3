#!/usr/bin/env sh

export MIX_ENV=prod

echo "MIX_ENV=${MIX_ENV}"
echo
echo "Building assets..."
echo
mix assets.deploy
echo
echo "Building release..."
echo
mix release --overwrite