#!/bin/bash

# Automated Setup Script for LocalStack Booking Notifier
# This script sets up the complete AWS infrastructure on LocalStack

echo "========================================"
echo "LocalStack Booking Notifier Setup"
echo "========================================"
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if LocalStack is running
echo -e "${YELLOW}[1/8] Checking LocalStack status...${NC}"
if curl -s http://localhost:4566/_localstack/health > /dev/null 2>&1; then
    echo -e "${GREEN}✓ LocalStack is running${NC}"
else
    echo -e "${RED}✗ LocalStack is not running!${NC}"
    echo "Please start LocalStack first: docker-compose up -d"
    exit 1
fi
echo ""

# Create DynamoDB Table
echo -e "${YELLOW}[2/8] Creating DynamoDB table 'Bookings'...${NC}"
awslocal dynamodb create-table \
    --table-name Bookings \
    --attribute-definitions AttributeName=bookingId,AttributeType=S \
    --key-schema AttributeName=bookingId,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ DynamoDB table created${NC}"
else
    echo -e "${YELLOW}⚠ Table might already exist, continuing...${NC}"
fi
echo ""

# Skip adding sample data here - will add at the end to ensure fresh bookings
echo -e "${YELLOW}[3/8] Preparing sample booking data (will add after setup)...${NC}"
echo -e "${GREEN}✓ Ready${NC}"
echo ""

# Verify SES email
echo -e "${YELLOW}[4/8] Verifying SES email addresses...${NC}"
awslocal ses verify-email-identity --email-address test@example.com > /dev/null 2>&1
awslocal ses verify-email-identity --email-address noreply@example.com > /dev/null 2>&1
echo -e "${GREEN}✓ Email addresses verified${NC}"
echo ""

# Create IAM role
echo -e "${YELLOW}[5/8] Creating IAM role...${NC}"
cat > /tmp/trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

awslocal iam create-role \
    --role-name LambdaBookingNotifierRole \
    --assume-role-policy-document file:///tmp/trust-policy.json > /dev/null 2>&1

awslocal iam attach-role-policy \
    --role-name LambdaBookingNotifierRole \
    --policy-arn arn:aws:iam::aws:policy/AWSLambdaBasicExecutionRole > /dev/null 2>&1

awslocal iam attach-role-policy \
    --role-name LambdaBookingNotifierRole \
    --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess > /dev/null 2>&1

awslocal iam attach-role-policy \
    --role-name LambdaBookingNotifierRole \
    --policy-arn arn:aws:iam::aws:policy/AmazonSESFullAccess > /dev/null 2>&1

echo -e "${GREEN}✓ IAM role created with policies attached${NC}"
echo ""

# Create Lambda deployment package
echo -e "${YELLOW}[6/8] Creating Lambda deployment package...${NC}"
zip -q lambda_function.zip lambda_function.py
echo -e "${GREEN}✓ Deployment package created${NC}"
echo ""

# Create Lambda function
echo -e "${YELLOW}[7/8] Creating Lambda function...${NC}"
awslocal lambda create-function \
    --function-name BookingNotifierFunction \
    --runtime python3.11 \
    --role arn:aws:iam::000000000000:role/LambdaBookingNotifierRole \
    --handler lambda_function.lambda_handler \
    --zip-file fileb://lambda_function.zip \
    --timeout 30 \
    --environment Variables="{SENDER_EMAIL=noreply@example.com,DYNAMODB_TABLE=Bookings,AWS_REGION_NAME=us-east-1}" > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Lambda function created${NC}"
else
    echo -e "${YELLOW}⚠ Function might already exist, updating...${NC}"
    awslocal lambda update-function-code \
        --function-name BookingNotifierFunction \
        --zip-file fileb://lambda_function.zip > /dev/null 2>&1
    echo -e "${GREEN}✓ Lambda function updated${NC}"
fi
echo ""

# Create EventBridge rule
echo -e "${YELLOW}[8/8] Setting up EventBridge schedule...${NC}"
awslocal events put-rule \
    --name BookingCheckSchedule \
    --schedule-expression "rate(5 minutes)" > /dev/null 2>&1

awslocal events put-targets \
    --rule BookingCheckSchedule \
    --targets "Id"="1","Arn"="arn:aws:lambda:us-east-1:000000000000:function:BookingNotifierFunction" > /dev/null 2>&1

awslocal lambda add-permission \
    --function-name BookingNotifierFunction \
    --statement-id EventBridgeInvoke \
    --action lambda:InvokeFunction \
    --principal events.amazonaws.com > /dev/null 2>&1

echo -e "${GREEN}✓ EventBridge schedule configured${NC}"
echo ""

# Test Lambda function
echo "========================================"
echo -e "${GREEN}Setup Complete!${NC}"
echo "========================================"
echo ""
echo "Testing Lambda function..."
echo ""

# Create test event
cat > /tmp/test-event.json <<EOF
{
  "booking": {
    "bookingId": "TEST-001",
    "customerName": "Test User",
    "customerEmail": "test@example.com",
    "bookingDate": "2026-03-25",
    "serviceType": "Test Booking",
    "status": "pending"
  }
}
EOF

# Invoke Lambda
awslocal lambda invoke \
    --function-name BookingNotifierFunction \
    --payload file:///tmp/test-event.json \
    /tmp/lambda-response.json > /dev/null 2>&1

echo -e "${GREEN}Lambda Response:${NC}"
cat /tmp/lambda-response.json | python3 -m json.tool
echo ""

echo "========================================"
echo -e "${YELLOW}Adding fresh sample bookings for testing...${NC}"
echo "========================================"
echo ""

# Add sample booking data NOW (after EventBridge setup)
# This ensures bookings are fresh and pending when user tests
awslocal dynamodb put-item \
    --table-name Bookings \
    --item '{
        "bookingId": {"S": "BOOK-001"},
        "customerName": {"S": "John Doe"},
        "customerEmail": {"S": "john@example.com"},
        "bookingDate": {"S": "2026-03-15"},
        "serviceType": {"S": "Hotel Reservation"},
        "status": {"S": "pending"},
        "createdAt": {"N": "1738483200"}
    }' > /dev/null 2>&1

awslocal dynamodb put-item \
    --table-name Bookings \
    --item '{
        "bookingId": {"S": "BOOK-002"},
        "customerName": {"S": "Jane Smith"},
        "customerEmail": {"S": "jane@example.com"},
        "bookingDate": {"S": "2026-03-20"},
        "serviceType": {"S": "Flight Booking"},
        "status": {"S": "pending"},
        "createdAt": {"N": "1738483300"}
    }' > /dev/null 2>&1

echo -e "${GREEN}✓ Added 2 pending bookings ready for testing!${NC}"
echo ""

echo "========================================"
echo "Summary of Created Resources:"
echo "========================================"
echo "• DynamoDB Table: Bookings (with 2 FRESH pending bookings)"
echo "• IAM Role: LambdaBookingNotifierRole"
echo "• Lambda Function: BookingNotifierFunction"
echo "• EventBridge Rule: BookingCheckSchedule (every 5 minutes)"
echo "• SES: test@example.com, noreply@example.com (verified)"
echo ""

echo "========================================"
echo -e "${GREEN}✓ Setup Complete! Test immediately:${NC}"
echo "========================================"
echo ""
echo "Run this command now to see notifications in action:"
echo ""
echo -e "${YELLOW}  awslocal lambda invoke --function-name BookingNotifierFunction --payload '{}' response.json && cat response.json${NC}"
echo ""
echo "You should see: \"Checked bookings, sent 2 notifications\""
echo ""
echo "========================================"
echo "Additional Commands:"
echo "========================================"
echo "# View all bookings:"
echo "  awslocal dynamodb scan --table-name Bookings"
echo ""
echo "# Check sent emails:"
echo "  docker exec localstack-booking-notifier ls -la /tmp/localstack/state/ses/"
echo ""
echo "# View email content:"
echo "  docker exec localstack-booking-notifier cat /tmp/localstack/state/ses/<MESSAGE_ID>.json | python3 -m json.tool"
echo ""
echo "========================================"
echo -e "${GREEN}All set! Your LocalStack environment is ready.${NC}"
echo "========================================"
