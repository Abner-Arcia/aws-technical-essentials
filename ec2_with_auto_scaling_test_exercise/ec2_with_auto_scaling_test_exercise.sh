#!/bin/bash
export AWS_PROFILE=abner-1

key_pair_name=abner-web-server-key-pair-auto-scaling
web_content_bucket_name=abnerarcia-web-content
cloudformation_create_script=ec2_with_auto_scaling_test_exercise_create.yml
cloudformation_import_script=ec2_with_auto_scaling_test_exercise_import.yml
cloudformation_bucket_name=cf-templates-1klm480sv15ci-us-east-1
stack_name=ec2-auto-scaling
change_set_name=${stack_name}-import

# Create the key pair for SSH
aws ec2 describe-key-pairs --key-name $key_pair_name

key_pair_output=$?

if [ $key_pair_output -gt 0 ]; then
    echo "****** KEY DOESN'T EXIST. CREATING IT... ******"
    aws ec2 create-key-pair \
        --key-name $key_pair_name \
        --key-type rsa \
        --key-format pem \
        --query "KeyMaterial" \
        --output text > $key_pair_name.pem
    chmod 600 $key_pair_name.pem
else
    echo "****** KEY ALREADY EXISTS. USING IT... ******"
fi

# Create the web content bucket and upload the files
aws s3 mb s3://$web_content_bucket_name
local_path="Auto Scaling Demo for Section 5-9 Configure Auto Scaling - Lab Part 1 & 2/Auto Scaling Demo"
aws s3 cp "$local_path/index.html" s3://$web_content_bucket_name
aws s3 cp "$local_path/health.html" s3://$web_content_bucket_name

# Create cloudformation stack
aws s3 cp $cloudformation_create_script s3://$cloudformation_bucket_name

aws cloudformation create-stack \
    --stack-name $stack_name \
    --template-url https://$cloudformation_bucket_name.s3.amazonaws.com/$cloudformation_create_script \
    --parameters ParameterKey=KeyPairNameParameter,ParameterValue=$key_pair_name ParameterKey=WebContentBucketNameParameter,ParameterValue=$web_content_bucket_name \
    --capabilities CAPABILITY_NAMED_IAM \
    --tags Key=Stack-Name,Value=$stack_name

wait_until_completion() {
    local command_name=$1
    local status=$2
    local sleep_time=$3
    local stack_name=$4
    local change_set_name=$5

    local current_status=$status
    while [ $current_status == $status ]; do
        echo "****** $current_status... ******"
        sleep $sleep_time
        if [ $command_name == "describe-stacks" ]; then
            current_status=$(aws cloudformation describe-stacks \
                --stack-name $stack_name | \
                python3 -c "import sys, json; print(json.load(sys.stdin)['Stacks'][0]['StackStatus'])")
        else # describe-change-set
            current_status=$(aws cloudformation describe-change-set \
                --change-set-name $change_set_name \
                --stack-name $stack_name | \
                python3 -c "import sys, json; print(json.load(sys.stdin)['Status'])")
        fi
    done
}

wait_until_completion describe-stacks CREATE_IN_PROGRESS 15 $stack_name $change_set_name

echo "****** STACK CREATION FINISHED ******"

# Import the key pair and bucket into the stack
aws s3 cp $cloudformation_import_script s3://$cloudformation_bucket_name

aws cloudformation create-change-set \
    --stack-name $stack_name \
    --change-set-name $change_set_name \
    --change-set-type IMPORT \
    --resources-to-import "[{\"ResourceType\":\"AWS::S3::Bucket\",\"LogicalResourceId\":\"WebContentBucket\",\"ResourceIdentifier\":{\"BucketName\":\"$web_content_bucket_name\"}}, \
        {\"ResourceType\":\"AWS::EC2::KeyPair\",\"LogicalResourceId\":\"KeyPair\",\"ResourceIdentifier\":{\"KeyName\":\"$key_pair_name\"}}]" \
    --template-url https://$cloudformation_bucket_name.s3.amazonaws.com/$cloudformation_import_script \
    --parameters ParameterKey=KeyPairNameParameter,ParameterValue=$key_pair_name ParameterKey=WebContentBucketNameParameter,ParameterValue=$web_content_bucket_name \
    --capabilities CAPABILITY_NAMED_IAM

wait_until_completion describe-change-set CREATE_IN_PROGRESS 5 $stack_name $change_set_name

echo "****** CHANGE SET CREATION FINISHED ******"

aws cloudformation execute-change-set \
    --change-set-name $change_set_name \
    --stack-name $stack_name

wait_until_completion describe-stacks IMPORT_IN_PROGRESS 10 $stack_name $change_set_name

echo "****** KEY PAIR AND BUCKET IMPORTED INTO STACK ******"