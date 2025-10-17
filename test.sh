#!/bin/bash

# ERP INTEROPERABILITY TEST SUITE

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

WAGONLITS_URL="http://localhost:3001"
DEVMATERIELS_URL="http://localhost:3002"
CONSTRUCTWAGONS_URL="http://localhost:3003"

WAGONLITS_TOKEN=""
DEVMATERIELS_TOKEN=""
CONSTRUCTWAGONS_TOKEN=""
ORDER_ID=""
DEVMATERIELS_ORDER_ID=""

print_header() {
    echo ""
    echo "========================================================================"
    echo " $1"
    echo "========================================================================"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

print_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

print_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    exit 1
}

print_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

check() {
    if [ $? -eq 0 ]; then
        print_pass "$1"
    else
        print_fail "$1"
    fi
}

# Check if containers are running
print_header "INITIALIZING"

if ! docker-compose ps | grep -q "Up"; then
    print_step "Starting containers"
    docker-compose up -d
    print_info "Waiting 35 seconds for full Kafka initialization"
    sleep 40
else
    print_step "Containers already running"
    
    print_step "Cleaning databases"
    docker-compose exec -T db-wagonlits psql -U admin -d wagonlits -c "DELETE FROM messages; DELETE FROM orders;" > /dev/null 2>&1
    docker-compose exec -T db-devmateriels psql -U admin -d devmateriels -c "DELETE FROM messages; DELETE FROM orders;" > /dev/null 2>&1
    docker-compose exec -T db-constructwagons psql -U admin -d constructwagons -c "DELETE FROM messages; DELETE FROM orders;" > /dev/null 2>&1
    print_pass "Databases cleaned"
    
    print_step "Restarting ERP services"
    docker-compose restart erp-wagonlits erp-devmateriels erp-constructwagons > /dev/null 2>&1
    print_info "Waiting 35 seconds for Kafka consumer group rebalancing"
    sleep 35
    print_pass "Services restarted"
fi

# Wait for services
print_step "Waiting for services"
for i in {1..30}; do
    if curl -s "$WAGONLITS_URL/api/health" > /dev/null 2>&1 && \
       curl -s "$DEVMATERIELS_URL/api/health" > /dev/null 2>&1 && \
       curl -s "$CONSTRUCTWAGONS_URL/api/health" > /dev/null 2>&1; then
        print_pass "All services ready"
        break
    fi
    sleep 1
done

# Health checks
print_header "HEALTH CHECKS"

curl -s "$WAGONLITS_URL/api/health" | grep -q "OK"
check "WagonLits"

curl -s "$DEVMATERIELS_URL/api/health" | grep -q "OK"
check "DevMateriels"

curl -s "$CONSTRUCTWAGONS_URL/api/health" | grep -q "OK"
check "ConstructWagons"

# Authentication
print_header "AUTHENTICATION"

WAGONLITS_RESPONSE=$(curl -s -X POST "$WAGONLITS_URL/api/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"email":"person1.WagonLits@gmail.com","password":"password"}')
echo "$WAGONLITS_RESPONSE" | grep -q "token"
check "WagonLits"
WAGONLITS_TOKEN=$(echo "$WAGONLITS_RESPONSE" | grep -o '"token":"[^"]*' | cut -d'"' -f4)

DEVMATERIELS_RESPONSE=$(curl -s -X POST "$DEVMATERIELS_URL/api/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"email":"person1.DevMateriels@gmail.com","password":"password"}')
echo "$DEVMATERIELS_RESPONSE" | grep -q "token"
check "DevMateriels"
DEVMATERIELS_TOKEN=$(echo "$DEVMATERIELS_RESPONSE" | grep -o '"token":"[^"]*' | cut -d'"' -f4)

CONSTRUCTWAGONS_RESPONSE=$(curl -s -X POST "$CONSTRUCTWAGONS_URL/api/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"email":"person1.ConstructWagons@gmail.com","password":"password"}')
echo "$CONSTRUCTWAGONS_RESPONSE" | grep -q "token"
check "ConstructWagons"
CONSTRUCTWAGONS_TOKEN=$(echo "$CONSTRUCTWAGONS_RESPONSE" | grep -o '"token":"[^"]*' | cut -d'"' -f4)

# Order flow
print_header "ORDER FLOW"

print_step "Step 1: WagonLits creates order"
ORDER_RESPONSE=$(curl -s -X POST "$WAGONLITS_URL/api/orders" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $WAGONLITS_TOKEN" \
    -d '{"description":"Brake failure wagon 45","urgency":"high","assigned_company":"DevMateriels"}')
echo "$ORDER_RESPONSE" | grep -q "order"
check "Order created"
ORDER_ID=$(echo "$ORDER_RESPONSE" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
print_info "Order ID: $ORDER_ID"

sleep 5

print_step "Step 2: DevMateriels receives order"
DEVMATERIELS_ORDERS=$(curl -s -H "Authorization: Bearer $DEVMATERIELS_TOKEN" "$DEVMATERIELS_URL/api/orders")
echo "$DEVMATERIELS_ORDERS" | grep -q "Brake failure"
check "Order received"
DEVMATERIELS_ORDER_ID=$(echo "$DEVMATERIELS_ORDERS" | grep -o '"id":[0-9]*' | tail -1 | cut -d':' -f2)
print_info "DevMateriels Order ID: $DEVMATERIELS_ORDER_ID"

print_step "Step 3: DevMateriels sends quote"
QUOTE_RESPONSE=$(curl -s -X POST "$DEVMATERIELS_URL/api/orders/$DEVMATERIELS_ORDER_ID/quote" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $DEVMATERIELS_TOKEN" \
    -d '{"estimatedCost":2300,"estimatedDelivery":"2025-10-18"}')
echo "$QUOTE_RESPONSE" | grep -q "Quote sent"
check "Quote sent"

sleep 5

print_step "Step 4: WagonLits receives quote"
WAGONLITS_ORDER=$(curl -s -H "Authorization: Bearer $WAGONLITS_TOKEN" "$WAGONLITS_URL/api/orders/$ORDER_ID")
echo "$WAGONLITS_ORDER" | grep -q "quoted"
check "Quote received"

print_step "Step 5: WagonLits confirms order"
CONFIRM_RESPONSE=$(curl -s -X POST "$WAGONLITS_URL/api/orders/$ORDER_ID/confirm" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $WAGONLITS_TOKEN")
echo "$CONFIRM_RESPONSE" | grep -q "Order confirmed"
check "Order confirmed"

sleep 5

print_step "Step 6: DevMateriels receives confirmation"
DEVMATERIELS_ORDER=$(curl -s -H "Authorization: Bearer $DEVMATERIELS_TOKEN" "$DEVMATERIELS_URL/api/orders/$DEVMATERIELS_ORDER_ID")
echo "$DEVMATERIELS_ORDER" | grep -q "confirmed"
check "Confirmation received"

print_step "Step 7: DevMateriels completes order"
COMPLETE_RESPONSE=$(curl -s -X POST "$DEVMATERIELS_URL/api/orders/$DEVMATERIELS_ORDER_ID/complete" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $DEVMATERIELS_TOKEN")
echo "$COMPLETE_RESPONSE" | grep -q "Order completed"
check "Order completed"

sleep 5

print_step "Step 8: WagonLits receives completion"
WAGONLITS_ORDER_FINAL=$(curl -s -H "Authorization: Bearer $WAGONLITS_TOKEN" "$WAGONLITS_URL/api/orders/$ORDER_ID")
echo "$WAGONLITS_ORDER_FINAL" | grep -q "completed"
check "Completion received"

print_header "CONSTRUCTWAGONS"

CONSTRUCT_ORDER=$(curl -s -X POST "$CONSTRUCTWAGONS_URL/api/orders" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $CONSTRUCTWAGONS_TOKEN" \
    -d '{"description":"Engine overhaul wagon 22","urgency":"medium","assigned_company":"DevMateriels"}')
echo "$CONSTRUCT_ORDER" | grep -q "order"
check "Order created"

print_header "RBAC"

COMMERCIAL_RESPONSE=$(curl -s -X POST "$WAGONLITS_URL/api/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"email":"commercial.wagonlits@gmail.com","password":"password"}')
COMMERCIAL_TOKEN=$(echo "$COMMERCIAL_RESPONSE" | grep -o '"token":"[^"]*' | cut -d'"' -f4)

COMMERCIAL_ORDER=$(curl -s -X POST "$WAGONLITS_URL/api/orders" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $COMMERCIAL_TOKEN" \
    -d '{"description":"Test commercial","assigned_company":"DevMateriels"}')
echo "$COMMERCIAL_ORDER" | grep -q "order"
check "Commercial permissions"

TECH_RESPONSE=$(curl -s -X POST "$DEVMATERIELS_URL/api/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"email":"technician.devmateriels@gmail.com","password":"password"}')
TECH_TOKEN=$(echo "$TECH_RESPONSE" | grep -o '"token":"[^"]*' | cut -d'"' -f4)

LATEST_ORDER=$(curl -s -H "Authorization: Bearer $TECH_TOKEN" "$DEVMATERIELS_URL/api/orders" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
TECH_COMPLETE=$(curl -s -X POST "$DEVMATERIELS_URL/api/orders/$LATEST_ORDER/complete" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TECH_TOKEN")
echo "$TECH_COMPLETE" | grep -q "Order completed"
check "Technician permissions"

print_header "VERIFICATION"

WAGONLITS_COUNT=$(curl -s -H "Authorization: Bearer $WAGONLITS_TOKEN" "$WAGONLITS_URL/api/orders" | grep -o '"id"' | wc -l)
DEVMATERIELS_COUNT=$(curl -s -H "Authorization: Bearer $DEVMATERIELS_TOKEN" "$DEVMATERIELS_URL/api/orders" | grep -o '"id"' | wc -l)
CONSTRUCTWAGONS_COUNT=$(curl -s -H "Authorization: Bearer $CONSTRUCTWAGONS_TOKEN" "$CONSTRUCTWAGONS_URL/api/orders" | grep -o '"id"' | wc -l)

print_info "WagonLits: $WAGONLITS_COUNT"
print_info "DevMateriels: $DEVMATERIELS_COUNT"
print_info "ConstructWagons: $CONSTRUCTWAGONS_COUNT"

if [ "$WAGONLITS_COUNT" -gt 0 ] && [ "$DEVMATERIELS_COUNT" -gt 0 ]; then
    print_header "ALL TESTS PASSED"
else
    print_fail "Tests failed"
fi