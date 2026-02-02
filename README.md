# AWS Automated Booking Notifier

A serverless email notification system that automatically sends booking confirmations using AWS Lambda, DynamoDB, and SES.

## 🎯 What It Does

- Stores booking records in DynamoDB
- Automatically checks for new bookings every 5 minutes
- Sends email confirmations to customers
- Updates booking status to prevent duplicate notifications
- Runs 100% serverless with no infrastructure to manage

## 🏗️ Architecture

```
EventBridge (every 5 min) → Lambda → DynamoDB (scan bookings)
                             ↓
                           SES (send emails)
                             ↓
                        Customer's Inbox
```

## ⚡ Quick Start

### Prerequisites

- Docker & Docker Compose installed
- Linux/macOS/WSL environment
- 5 minutes of your time

### Run It Now

```bash
# 1. Clone the repository
git clone <your-repo-url>
cd AWS_Email

# 2. Start LocalStack (AWS emulation)
docker-compose up -d

# 3. Wait for LocalStack to be ready (~30 seconds)
sleep 30

# 4. Run the setup script
chmod +x setup-localstack.sh
./setup-localstack.sh

# 5. Trigger the notification function
aws --endpoint-url=http://localhost:4566 lambda invoke \
    --function-name BookingNotifierFunction \
    --region us-east-1 \
    response.json

# 6. Check the result
cat response.json
```

**Done!** The system is now running and checking for bookings every 5 minutes.

## 📁 Project Structure

```
.
├── README.md              # This file
├── lambda_function.py     # Lambda function code
├── docker-compose.yml     # LocalStack configuration
└── setup-localstack.sh    # Automated setup script
```

## 🔍 How It Works

1. **EventBridge** triggers Lambda every 5 minutes
2. **Lambda** scans DynamoDB for bookings with `status="pending"`
3. For each pending booking:
   - Sends email via **SES**
   - Updates status to `"notified"` in **DynamoDB**
4. Customer receives booking confirmation

## 📊 Sample Data

The setup script creates 2 sample bookings:

```json
{
  "bookingId": "BOOK-001",
  "customerName": "John Doe",
  "customerEmail": "john@example.com",
  "serviceType": "Hotel Reservation",
  "bookingDate": "2026-03-15",
  "status": "pending"
}
```

## 🧪 Testing

### Manual Trigger
```bash
aws --endpoint-url=http://localhost:4566 lambda invoke \
    --function-name BookingNotifierFunction \
    --region us-east-1 \
    response.json && cat response.json
```

### Check Emails (LocalStack)
```bash
# List sent emails
docker exec localstack-booking-notifier ls -la /tmp/localstack/state/ses/

# View email content
docker exec localstack-booking-notifier cat /tmp/localstack/state/ses/<MESSAGE_ID>.json | python3 -m json.tool
```

### Verify DynamoDB Status
```bash
aws --endpoint-url=http://localhost:4566 dynamodb scan \
    --table-name Bookings \
    --region us-east-1
```

## 🔧 Customization

### Change Check Frequency

Edit [setup-localstack.sh](setup-localstack.sh) line with EventBridge schedule:

```bash
# From: rate(5 minutes)
# To: rate(1 minute)  or  cron(0 * * * ? *)
```

### Modify Email Template

Edit [lambda_function.py](lambda_function.py) function `send_booking_notification()`:

```python
subject = f"Your Custom Subject - {booking_id}"
body_text = """Your custom email template here"""
```

### Add More Fields

Update DynamoDB item structure in [setup-localstack.sh](setup-localstack.sh):

```json
{
  "bookingId": {"S": "BOOK-003"},
  "phoneNumber": {"S": "+1234567890"},
  "specialRequests": {"S": "Late checkout"}
}
```

## 🐛 Troubleshooting

**LocalStack not starting?**
```bash
docker-compose down
docker-compose up -d
docker logs -f localstack-booking-notifier
```

**Setup script fails?**
```bash
# Check AWS CLI configuration
aws configure get region
# Should be: us-east-1

# Verify LocalStack is running
curl http://localhost:4566/_localstack/health
```

**Lambda not finding DynamoDB?**
```bash
# Verify table exists
aws --endpoint-url=http://localhost:4566 dynamodb list-tables --region us-east-1
```

## 🚀 Deploying to Real AWS

To deploy this to production AWS:

1. **Create DynamoDB table** named "Bookings"
2. **Create IAM role** with policies:
   - AWSLambdaBasicExecutionRole
   - AmazonDynamoDBFullAccess
   - AmazonSESFullAccess
3. **Verify email** in SES console
4. **Create Lambda function** (Python 3.11) and upload [lambda_function.py](lambda_function.py)
5. **Set environment variables**:
   - `SENDER_EMAIL`: your-email@domain.com
   - `DYNAMODB_TABLE`: Bookings
6. **Create EventBridge rule** with target Lambda (rate: 5 minutes)

**Note:** The code is identical; only remove `--endpoint-url` from AWS CLI commands.

## 📚 AWS Services Used

- **Lambda**: Serverless compute
- **DynamoDB**: NoSQL database
- **SES**: Email service
- **EventBridge**: Event scheduler
- **IAM**: Permission management
- **CloudWatch**: Logging (automatic)

## 💰 Cost (Real AWS)

Free Tier includes:
- Lambda: 1M requests/month
- DynamoDB: 25GB storage
- SES: 62,000 emails/month

**Expected**: $0/month for testing

## 📝 License

MIT License - Feel free to modify and use.

---

**Need help?** Check logs: `docker logs -f localstack-booking-notifier`

**Need Help?** 
- Check [AWS_CONCEPTS.md](AWS_CONCEPTS.md) for service explanations
- Follow [DEPLOYMENT_STEPS.md](DEPLOYMENT_STEPS.md) step-by-step
- Use [TESTING_GUIDE.md](TESTING_GUIDE.md) to debug issues

**Ready to Start?** 
👉 Open [DEPLOYMENT_STEPS.md](DEPLOYMENT_STEPS.md) and begin your AWS journey!
