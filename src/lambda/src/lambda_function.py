import boto3
import os

from datetime import datetime

def lambda_handler(event, context):
    # Define the bucket name and file name
    bucket_name = 'cy-awsmgr-bucket'
    file_name = 'timestamp.txt'

    # Create an S3 client
    s3 = boto3.client('s3')

    iso_now = datetime.now().isoformat()

    # Write the updated number back to S3
    s3.put_object(Bucket=bucket_name, Key=file_name, Body=str(iso_now).encode('utf-8'))

    return {
        'statusCode': 200,
        'body': f"Updated date to {iso_now}"
    }