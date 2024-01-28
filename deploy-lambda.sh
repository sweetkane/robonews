#!/bin/bash

if [ $# -eq 0 ]; then
    echo "Usage:    $0 <lambda_name> <repo_name>(optional) <IAM role>(optional)"
    exit 1
fi
lambda_name=$1

repo_name=repo_$lambda_name
if [ $# -eq 2 ]; then
    repo_name=$2
fi

lambda_tag=latest
repo_tag=latest

role=lambda-admin
if [ $# -eq 3 ]; then
    role=$3
fi

if [ -z "$AWS_ACCOUNT_ID" ]; then
    echo "Err: AWS_ACCOUNT_ID environment variable is not set"
    exit 1
fi
if [ -z "$AWS_DEFAULT_REGION" ]; then
    echo "Err: AWS_DEFAULT_REGION environment variable is not set"
    exit 1
fi

# create image
echo "$0: creating image"
docker build --platform linux/amd64 -t $lambda_name:$lambda_tag .

# point docker at ECR
echo "$0: pointing docker at ECR"
aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com

#create repo
echo "$0: creating repo named $repo_name"
repo_uri=$(aws ecr create-repository \
    --repository-name "$repo_name" \
    --region "$AWS_DEFAULT_REGION" \
    --image-scanning-configuration scanOnPush=true \
    --image-tag-mutability MUTABLE \
    --query repository.repositoryUri \
    --output text \
    2>/dev/null \
)

if [[ $? -ne 0 ]]; then
    repo_uri=$(aws ecr describe-repositories \
        --repository-names $repo_name \
        --query repositories[0].repositoryUri \
        --output text \
    )
fi

# tag local image into ECR repo
echo "$0: tagging local image into ECR repo"
docker tag $lambda_name:$lambda_tag $repo_uri:$repo_tag

# push local to ECR
echo "$0: pushing to ECR repo"
docker push $repo_uri:$repo_tag

# create function
echo "$0: creating function named $lambda_name"
aws lambda delete-function --function-name "$lambda_name" 2>/dev/null
aws lambda create-function \
    --function-name "$lambda_name" \
    --package-type Image \
    --code ImageUri=$repo_uri:$repo_tag \
    --role arn:aws:iam::$AWS_ACCOUNT_ID:role/$role