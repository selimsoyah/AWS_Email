"""
AWS Lambda Function - Booking Notifier
This function sends email notifications for new bookings stored in DynamoDB
"""

import json
import boto3
import os
from datetime import datetime
from botocore.exceptions import ClientError

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
ses_client = boto3.client('ses')

# Get environment variables
TABLE_NAME = os.environ.get('DYNAMODB_TABLE', 'Bookings')
SENDER_EMAIL = os.environ.get('SENDER_EMAIL', 'your-email@example.com')
AWS_REGION = os.environ.get('AWS_REGION_NAME', 'us-east-1')

def lambda_handler(event, context):
    """
    Main Lambda handler function
    
    This function can be triggered by:
    1. EventBridge schedule (to check for new bookings)
    2. API Gateway (manual trigger)
    3. DynamoDB Stream (real-time notifications)
    """
    
    print(f"Event received: {json.dumps(event)}")
    
    try:
        # Check if this is a direct booking creation event (API Gateway or manual test)
        if 'booking' in event:
            # Process single booking from event
            booking = event['booking']
            result = send_booking_notification(booking)
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Notification sent successfully',
                    'result': result
                })
            }
        
        # Check if this is a DynamoDB Stream event
        elif 'Records' in event:
            results = []
            for record in event['Records']:
                if record['eventName'] in ['INSERT', 'MODIFY']:
                    # Extract booking data from DynamoDB stream
                    booking = parse_dynamodb_record(record)
                    result = send_booking_notification(booking)
                    results.append(result)
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': f'Processed {len(results)} bookings',
                    'results': results
                })
            }
        
        # EventBridge scheduled trigger - check for new bookings
        else:
            results = check_and_notify_new_bookings()
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': f'Checked bookings, sent {len(results)} notifications',
                    'results': results
                })
            }
            
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }


def check_and_notify_new_bookings():
    """
    Check DynamoDB for bookings that need notifications
    This is called when triggered by EventBridge schedule
    """
    results = []
    table = dynamodb.Table(TABLE_NAME)
    
    try:
        # Scan table for bookings with status 'pending' or 'new'
        response = table.scan(
            FilterExpression='#status = :status',
            ExpressionAttributeNames={'#status': 'status'},
            ExpressionAttributeValues={':status': 'pending'}
        )
        
        bookings = response.get('Items', [])
        print(f"Found {len(bookings)} pending bookings")
        
        for booking in bookings:
            result = send_booking_notification(booking)
            results.append(result)
            
            # Update booking status to 'notified'
            table.update_item(
                Key={'bookingId': booking['bookingId']},
                UpdateExpression='SET #status = :status, notifiedAt = :timestamp',
                ExpressionAttributeNames={'#status': 'status'},
                ExpressionAttributeValues={
                    ':status': 'notified',
                    ':timestamp': int(datetime.now().timestamp())
                }
            )
        
        return results
        
    except ClientError as e:
        print(f"DynamoDB error: {e.response['Error']['Message']}")
        raise


def send_booking_notification(booking):
    """
    Send email notification for a booking
    
    Args:
        booking: Dictionary containing booking details
    """
    customer_email = booking.get('customerEmail')
    customer_name = booking.get('customerName', 'Customer')
    booking_id = booking.get('bookingId')
    booking_date = booking.get('bookingDate', 'Not specified')
    service_type = booking.get('serviceType', 'Service')
    
    if not customer_email:
        print("No customer email provided")
        return {'success': False, 'reason': 'No email provided'}
    
    # Create email content
    subject = f"Booking Confirmation - {booking_id}"
    
    body_text = f"""
    Dear {customer_name},
    
    Your booking has been confirmed!
    
    Booking Details:
    - Booking ID: {booking_id}
    - Service: {service_type}
    - Date: {booking_date}
    
    Thank you for your booking!
    
    Best regards,
    Booking Team
    """
    
    body_html = f"""
    <html>
    <head></head>
    <body>
        <h2>Booking Confirmation</h2>
        <p>Dear {customer_name},</p>
        <p>Your booking has been confirmed!</p>
        
        <h3>Booking Details:</h3>
        <ul>
            <li><strong>Booking ID:</strong> {booking_id}</li>
            <li><strong>Service:</strong> {service_type}</li>
            <li><strong>Date:</strong> {booking_date}</li>
        </ul>
        
        <p>Thank you for your booking!</p>
        
        <p>Best regards,<br>Booking Team</p>
    </body>
    </html>
    """
    
    try:
        # Send email using SES
        response = ses_client.send_email(
            Source=SENDER_EMAIL,
            Destination={
                'ToAddresses': [customer_email]
            },
            Message={
                'Subject': {
                    'Data': subject,
                    'Charset': 'UTF-8'
                },
                'Body': {
                    'Text': {
                        'Data': body_text,
                        'Charset': 'UTF-8'
                    },
                    'Html': {
                        'Data': body_html,
                        'Charset': 'UTF-8'
                    }
                }
            }
        )
        
        print(f"Email sent successfully to {customer_email}")
        print(f"Message ID: {response['MessageId']}")
        
        return {
            'success': True,
            'messageId': response['MessageId'],
            'recipient': customer_email
        }
        
    except ClientError as e:
        error_message = e.response['Error']['Message']
        print(f"Error sending email: {error_message}")
        return {
            'success': False,
            'error': error_message
        }


def parse_dynamodb_record(record):
    """
    Parse DynamoDB stream record to extract booking data
    
    Args:
        record: DynamoDB stream record
        
    Returns:
        Dictionary with booking data
    """
    new_image = record['dynamodb'].get('NewImage', {})
    
    # Convert DynamoDB format to regular dict
    booking = {}
    for key, value in new_image.items():
        # Extract the actual value based on type
        if 'S' in value:
            booking[key] = value['S']
        elif 'N' in value:
            booking[key] = value['N']
        elif 'BOOL' in value:
            booking[key] = value['BOOL']
    
    return booking


# For local testing
if __name__ == "__main__":
    # Test event
    test_event = {
        'booking': {
            'bookingId': 'TEST123',
            'customerName': 'John Doe',
            'customerEmail': 'test@example.com',
            'bookingDate': '2026-02-15',
            'serviceType': 'Hotel Reservation',
            'status': 'pending'
        }
    }
    
    # Mock context
    class Context:
        def __init__(self):
            self.function_name = "test"
            self.memory_limit_in_mb = 128
            self.invoked_function_arn = "arn:aws:lambda:test"
            self.aws_request_id = "test-request-id"
    
    result = lambda_handler(test_event, Context())
    print(json.dumps(result, indent=2))
