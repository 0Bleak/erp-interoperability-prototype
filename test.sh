#!/bin/bash

echo "=================================================="
echo "ERP INTEROPERABILITY SYSTEM - COMPLETE TEST SCRIPT"
echo "=================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Base URLs
WAGONLITS_URL="http://localhost:3001"
DEVMATERIELS_URL="http://localhost:3002"
CONSTRUCTWAGONS_URL="http://localhost:3003"
KAFKA_UI_URL="http://localhost:8080"

# Global variables
WAGONLITS_TOKEN=""
DEVMATERIELS_TOKEN=""
CONSTRUCTWAGONS_TOKEN=""
ORDER_ID=""

# Function to print status
print_status() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ $1${NC}"
    else
        echo -e "${RED}✗ $1${NC}"
        exit 1
    fi
}

# Wait for services to be ready
wait_for_service() {
    local url=$1
    local service=$2
    echo -e "${YELLOW}Waiting for $service to be ready...${NC}"
    
    for i in {1..30}; do
        if curl -s "$url/api/health" > /dev/null; then
            echo -e "${GREEN}$service is ready!${NC}"
            return 0
        fi
        sleep 2
    done
    echo -e "${RED}$service failed to start${NC}"
    return 1
}

# Test health endpoints
test_health_endpoints() {
    echo -e "\n${YELLOW}Testing Health Endpoints...${NC}"
    
    curl -s "$WAGONLITS_URL/api/health" | grep -q "OK"
    print_status "WagonLits health check"
    
    curl -s "$DEVMATERIELS_URL/api/health" | grep -q "OK"
    print_status "DevMateriels health check"
    
    curl -s "$CONSTRUCTWAGONS_URL/api/health" | grep -q "OK"
    print_status "ConstructWagons health check"
}

# Test authentication
test_authentication() {
    echo -e "\n${YELLOW}Testing Authentication...${NC}"
    
    # Test WagonLits login
    WAGONLITS_RESPONSE=$(curl -s -X POST "$WAGONLITS_URL/api/auth/login" \
        -H "Content-Type: application/json" \
        -d '{"email":"person1.WagonLits@gmail.com","password":"password"}')
    
    echo "$WAGONLITS_RESPONSE" | grep -q "token"
    print_status "WagonLits login"
    WAGONLITS_TOKEN=$(echo "$WAGONLITS_RESPONSE" | grep -o '"token":"[^"]*' | cut -d'"' -f4)
    
    # Test DevMateriels login
    DEVMATERIELS_RESPONSE=$(curl -s -X POST "$DEVMATERIELS_URL/api/auth/login" \
        -H "Content-Type: application/json" \
        -d '{"email":"person1.DevMateriels@gmail.com","password":"password"}')
    
    echo "$DEVMATERIELS_RESPONSE" | grep -q "token"
    print_status "DevMateriels login"
    DEVMATERIELS_TOKEN=$(echo "$DEVMATERIELS_RESPONSE" | grep -o '"token":"[^"]*' | cut -d'"' -f4)
    
    # Test ConstructWagons login
    CONSTRUCTWAGONS_RESPONSE=$(curl -s -X POST "$CONSTRUCTWAGONS_URL/api/auth/login" \
        -H "Content-Type: application/json" \
        -d '{"email":"person1.ConstructWagons@gmail.com","password":"password"}')
    
    echo "$CONSTRUCTWAGONS_RESPONSE" | grep -q "token"
    print_status "ConstructWagons login"
    CONSTRUCTWAGONS_TOKEN=$(echo "$CONSTRUCTWAGONS_RESPONSE" | grep -o '"token":"[^"]*' | cut -d'"' -f4)
    
    # Test token validation
    curl -s -H "Authorization: Bearer $WAGONLITS_TOKEN" "$WAGONLITS_URL/api/auth/me" | grep -q "user"
    print_status "WagonLits token validation"
    
    curl -s -H "Authorization: Bearer $DEVMATERIELS_TOKEN" "$DEVMATERIELS_URL/api/auth/me" | grep -q "user"
    print_status "DevMateriels token validation"
    
    curl -s -H "Authorization: Bearer $CONSTRUCTWAGONS_TOKEN" "$CONSTRUCTWAGONS_URL/api/auth/me" | grep -q "user"
    print_status "ConstructWagons token validation"
}

# Test order creation and Kafka flow
test_order_flow() {
    echo -e "\n${YELLOW}Testing Complete Order Flow...${NC}"
    
    # Step 1: WagonLits creates order for DevMateriels
    echo -e "${YELLOW}Step 1: WagonLits → DevMateriels (order.request)${NC}"
    ORDER_RESPONSE=$(curl -s -X POST "$WAGONLITS_URL/api/orders" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $WAGONLITS_TOKEN" \
        -d '{
            "description": "Brake system failure on wagon #45 - URGENT",
            "urgency": "high",
            "assigned_company": "DevMateriels"
        }')
    
    echo "$ORDER_RESPONSE" | grep -q "order"
    print_status "WagonLits created order"
    ORDER_ID=$(echo "$ORDER_RESPONSE" | grep -o '"id":[0-9]*' | cut -d':' -f2)
    echo -e "${GREEN}Order ID: $ORDER_ID${NC}"
    
    # Wait for Kafka message to be processed
    echo -e "${YELLOW}Waiting for Kafka message processing...${NC}"
    sleep 5
    
    # Step 2: Check if DevMateriels received the order
    echo -e "${YELLOW}Step 2: Verify DevMateriels received order${NC}"
    DEVMATERIELS_ORDERS=$(curl -s -H "Authorization: Bearer $DEVMATERIELS_TOKEN" "$DEVMATERIELS_URL/api/orders")
    echo "$DEVMATERIELS_ORDERS" | grep -q "Brake system failure"
    print_status "DevMateriels has the order in database"
    
    # Step 3: DevMateriels sends quote
    echo -e "${YELLOW}Step 3: DevMateriels → WagonLits (order.quote)${NC}"
    QUOTE_RESPONSE=$(curl -s -X POST "$DEVMATERIELS_URL/api/orders/1/quote" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $DEVMATERIELS_TOKEN" \
        -d '{
            "estimatedCost": 2300,
            "estimatedDelivery": "2025-10-18"
        }')
    
    echo "$QUOTE_RESPONSE" | grep -q "Quote sent"
    print_status "DevMateriels sent quote"
    
    # Wait for Kafka message to be processed
    sleep 5
    
    # Step 4: Check if WagonLits received the quote
    echo -e "${YELLOW}Step 4: Verify WagonLits received quote${NC}"
    WAGONLITS_ORDER=$(curl -s -H "Authorization: Bearer $WAGONLITS_TOKEN" "$WAGONLITS_URL/api/orders/$ORDER_ID")
    echo "$WAGONLITS_ORDER" | grep -q "quoted"
    print_status "WagonLits order status updated to 'quoted'"
    
    # Step 5: WagonLits confirms order
    echo -e "${YELLOW}Step 5: WagonLits → DevMateriels (order.confirmation)${NC}"
    CONFIRM_RESPONSE=$(curl -s -X POST "$WAGONLITS_URL/api/orders/$ORDER_ID/confirm" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $WAGONLITS_TOKEN")
    
    echo "$CONFIRM_RESPONSE" | grep -q "Order confirmed"
    print_status "WagonLits confirmed order"
    
    # Wait for Kafka message to be processed
    sleep 5
    
    # Step 6: Check if DevMateriels received confirmation
    echo -e "${YELLOW}Step 6: Verify DevMateriels received confirmation${NC}"
    DEVMATERIELS_ORDER=$(curl -s -H "Authorization: Bearer $DEVMATERIELS_TOKEN" "$DEVMATERIELS_URL/api/orders/1")
    echo "$DEVMATERIELS_ORDER" | grep -q "confirmed"
    print_status "DevMateriels order status updated to 'confirmed'"
    
    # Step 7: DevMateriels completes order
    echo -e "${YELLOW}Step 7: DevMateriels → WagonLits (order.status.update)${NC}"
    COMPLETE_RESPONSE=$(curl -s -X POST "$DEVMATERIELS_URL/api/orders/1/complete" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $DEVMATERIELS_TOKEN")
    
    echo "$COMPLETE_RESPONSE" | grep -q "Order completed"
    print_status "DevMateriels completed order"
    
    # Wait for Kafka message to be processed
    sleep 5
    
    # Step 8: Check if WagonLits received completion
    echo -e "${YELLOW}Step 8: Verify WagonLits received completion${NC}"
    WAGONLITS_ORDER_FINAL=$(curl -s -H "Authorization: Bearer $WAGONLITS_TOKEN" "$WAGONLITS_URL/api/orders/$ORDER_ID")
    echo "$WAGONLITS_ORDER_FINAL" | grep -q "completed"
    print_status "WagonLits order status updated to 'completed'"
}

# Test ConstructWagons flow
test_constructwagons_flow() {
    echo -e "\n${YELLOW}Testing ConstructWagons Flow...${NC}"
    
    # ConstructWagons creates order for DevMateriels
    CONSTRUCT_ORDER_RESPONSE=$(curl -s -X POST "$CONSTRUCTWAGONS_URL/api/orders" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $CONSTRUCTWAGONS_TOKEN" \
        -d '{
            "description": "Engine overhaul for construction wagon #22",
            "urgency": "medium",
            "assigned_company": "DevMateriels"
        }')
    
    echo "$CONSTRUCT_ORDER_RESPONSE" | grep -q "order"
    print_status "ConstructWagons created order"
    
    # Verify order appears in orders list
    CONSTRUCT_ORDERS=$(curl -s -H "Authorization: Bearer $CONSTRUCTWAGONS_TOKEN" "$CONSTRUCTWAGONS_URL/api/orders")
    echo "$CONSTRUCT_ORDERS" | grep -q "Engine overhaul"
    print_status "ConstructWagons order visible in list"
}

# Test role-based access
test_role_based_access() {
    echo -e "\n${YELLOW}Testing Role-Based Access...${NC}"
    
    # Login as commercial user
    COMMERCIAL_RESPONSE=$(curl -s -X POST "$WAGONLITS_URL/api/auth/login" \
        -H "Content-Type: application/json" \
        -d '{"email":"commercial.wagonlits@gmail.com","password":"password"}')
    
    COMMERCIAL_TOKEN=$(echo "$COMMERCIAL_RESPONSE" | grep -o '"token":"[^"]*' | cut -d'"' -f4)
    
    # Commercial should be able to create orders
    COMMERCIAL_ORDER_RESPONSE=$(curl -s -X POST "$WAGONLITS_URL/api/orders" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $COMMERCIAL_TOKEN" \
        -d '{
            "description": "Test order from commercial user",
            "assigned_company": "DevMateriels"
        }')
    
    echo "$COMMERCIAL_ORDER_RESPONSE" | grep -q "order"
    print_status "Commercial user can create orders"
    
    # Login as technician user
    TECH_RESPONSE=$(curl -s -X POST "$DEVMATERIELS_URL/api/auth/login" \
        -H "Content-Type: application/json" \
        -d '{"email":"technician.devmateriels@gmail.com","password":"password"}')
    
    TECH_TOKEN=$(echo "$TECH_RESPONSE" | grep -o '"token":"[^"]*' | cut -d'"' -f4)
    
    # Technician should be able to complete orders
    TECH_COMPLETE_RESPONSE=$(curl -s -X POST "$DEVMATERIELS_URL/api/orders/1/complete" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $TECH_TOKEN")
    
    echo "$TECH_COMPLETE_RESPONSE" | grep -q "Order completed"
    print_status "Technician user can complete orders"
}

# Test Kafka UI
test_kafka_ui() {
    echo -e "\n${YELLOW}Testing Kafka UI...${NC}"
    
    if curl -s "$KAFKA_UI_URL" > /dev/null; then
        echo -e "${GREEN}✓ Kafka UI is accessible${NC}"
        echo -e "${YELLOW}Kafka UI available at: http://localhost:8080${NC}"
    else
        echo -e "${YELLOW}⚠ Kafka UI not accessible (might still be starting)${NC}"
    fi
}

# Final verification
final_verification() {
    echo -e "\n${YELLOW}=== FINAL VERIFICATION ===${NC}"
    
    # Check all services have orders
    WAGONLITS_ORDERS_COUNT=$(curl -s -H "Authorization: Bearer $WAGONLITS_TOKEN" "$WAGONLITS_URL/api/orders" | grep -o '"id"' | wc -l)
    DEVMATERIELS_ORDERS_COUNT=$(curl -s -H "Authorization: Bearer $DEVMATERIELS_TOKEN" "$DEVMATERIELS_URL/api/orders" | grep -o '"id"' | wc -l)
    CONSTRUCTWAGONS_ORDERS_COUNT=$(curl -s -H "Authorization: Bearer $CONSTRUCTWAGONS_TOKEN" "$CONSTRUCTWAGONS_URL/api/orders" | grep -o '"id"' | wc -l)
    
    echo -e "${GREEN}WagonLits orders: $WAGONLITS_ORDERS_COUNT${NC}"
    echo -e "${GREEN}DevMateriels orders: $DEVMATERIELS_ORDERS_COUNT${NC}"
    echo -e "${GREEN}ConstructWagons orders: $CONSTRUCTWAGONS_ORDERS_COUNT${NC}"
    
    if [ "$WAGONLITS_ORDERS_COUNT" -gt 0 ] && [ "$DEVMATERIELS_ORDERS_COUNT" -gt 0 ]; then
        echo -e "\n${GREEN}🎉 ALL SYSTEMS GO! ERP INTEROPERABILITY PROTOTYPE IS WORKING! 🎉${NC}"
        echo -e "\n${YELLOW}Summary:${NC}"
        echo -e "${GREEN}✓ All services running${NC}"
        echo -e "${GREEN}✓ Authentication working${NC}"
        echo -e "${GREEN}✓ Kafka messaging flowing${NC}"
        echo -e "${GREEN}✓ Database updates via events${NC}"
        echo -e "${GREEN}✓ Role-based access control${NC}"
        echo -e "${GREEN}✓ Complete business flow implemented${NC}"
    else
        echo -e "\n${RED}❌ Some issues detected - check the logs above${NC}"
        exit 1
    fi
}

# Main execution
main() {
    echo -e "${YELLOW}Starting comprehensive system test...${NC}"
    
    # Wait for services
    wait_for_service "$WAGONLITS_URL" "WagonLits ERP"
    wait_for_service "$DEVMATERIELS_URL" "DevMateriels ERP" 
    wait_for_service "$CONSTRUCTWAGONS_URL" "ConstructWagons ERP"
    
    # Run all tests
    test_health_endpoints
    test_authentication
    test_order_flow
    test_constructwagons_flow
    test_role_based_access
    test_kafka_ui
    final_verification
}

# Run the tests
main
