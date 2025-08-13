#!/usr/bin/env sh

export MIX_ENV=prod

echo "Building assets..."
echo
mix assets.build
echo
echo "Digesting..."
echo
mix phx.digest
echo
echo "Building release..."
echo
mix release --overwrite