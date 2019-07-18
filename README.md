## AWS ECS Auditor

### Usage

#### Standalone
```
cd ./src
bundle install
AWS_REGION=us-east-1 CLUSTER_NAME=default ruby aws_ecs_auditor.rb
```

#### Docker
```
docker-compose build
AWS_ACCESS_KEY_ID=<key> AWS_SECRET_ACCESS_KEY=<secret> AWS_REGION=<region> CLUSTER_NAME=<cluster_name> docker-compose up
```
