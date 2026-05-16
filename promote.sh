#!/bin/bash
# Promote dev → main (deploys to production)
set -e

echo "Promoting dev → main..."
git checkout main
git merge dev --no-edit
git push origin main
git checkout dev
echo "Done. Production deploy triggered on Render."
