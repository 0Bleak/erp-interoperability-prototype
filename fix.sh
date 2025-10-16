#!/bin/bash

echo "Fixing all shared module paths..."

# Fix server.js files
for service in erp-wagonlits erp-devmateriels erp-constructwagons; do
  echo "Fixing $service server.js..."
  sed -i 's|../../shared/database|/app/shared/database|g' services/$service/server.js
  sed -i 's|../../shared/kafka|/app/shared/kafka|g' services/$service/server.js
done

# Fix route files
for service in erp-wagonlits erp-devmateriels erp-constructwagons; do
  for route in auth orders; do
    if [ -f "services/$service/routes/$route.js" ]; then
      echo "Fixing $service routes/$route.js..."
      sed -i 's|../../../shared/database|/app/shared/database|g' services/$service/routes/$route.js
      sed -i 's|../../../shared/auth|/app/shared/auth|g' services/$service/routes/$route.js
      sed -i 's|../../../shared/kafka|/app/shared/kafka|g' services/$service/routes/$route.js
    fi
  done
done

echo "Path fixing complete!"
