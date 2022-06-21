# 개요

테라폼으로 흔히 개발 환경, 스테이징 환경, 프로덕션 환경으로 구분하여 인프라를 구성합니다. 환경을 분리하여 개발을 진행할 때, 개발 환경의 인프라가 프로덕션 환경의 인프라로 배포되는 상황을 피하고자 다음 두 가지 Best Practice를 사용하였습니다.

1. 모듈 디렉터리와 개발 환경별로 디렉터리들로 나누어 환경을 분리하며 개발
2. terraform workspace 로 환경을 분리하며 개발

do-terraform 스크립트는 두 가지 방법을 혼용하여 인프라 환경을 분리하는 방법을 사용합니다.

do-terraform 스크립트를 사용하여 적용된 모든 커맨드는 logs 디렉터리에 logging 됩니다. github actions 과 함께 사용하기 위해 `-l <BUCKET NAME>` 옵션을 주어 AWS S3 Bucket 에 로그를 저장 할 수 있습니다.

1. 기본적으로 사용한 모든 커맨드는 `./logs/tf.log` 에 저장
2. apply, destroy 를 사용하여 인프라에 적용되는 커맨드는 `./logs/dev-infra.log` 형식으로 저장

## 가능한 문제 상황

```bash
/
|- modules
|
|- live
    |- database
    |- backend
```

modules 디렉터리에 있는 테라폼 모듈을 live 디렉터리에서 모듈을 불러와서 인프라를 구성하는 상황

```bash
cd ./live/backend
terraform apply
```

1. 환경 분리가 명확하게 되어 있지 않음
2. terraform workspace 로 환경 분리시 매번 workspace 를 확인하기 어려움 → dev 환경의 인프라를 prod 에 apply 하는 상황이 발생할 수 있음

## 해결 방안

```bash
/
|- modules
|
|- dev
    |- database
    |- backend
|- prod
    |- database
    |- backend
```

1. 개발 환경별로 디렉터리를 구조화하여 환경 분리를 명확하게 함

```bash
cd ./dev/backend
terraform workspace select dev
terraform apply
```

2. 현재 개발환경에서 인프라를 적용하기 위해 terraform workspace 와 함께 사용하여 모듈 내에서 `terraform.workspace` 값을 사용하여 인프라 배포
3. 디렉터리 내의 `tfvars` 파일을 `-var-file` 옵션과 함께 일괄 적용
4. 인프라에 반영되는 `apply` 와 `destroy` 커맨드를 logging 을 통해 추적

이 시나리오를 일관성 있게 적용하기 위해 do-terraform 스크립트를 작성하였습니다.

# 개발환경

- Linux
- BASH

# 설치 및 삭제

## 설치

```bash
git clone https://github.com/heechankim/do-terraform.git
cd ./do-terraform
bash ./install.sh
```

## 삭제

```bash
cd ./do-terraform
bash ./uninstall.sh
```

# 사용 방법

## 동작 방식
![do-terraform](https://user-images.githubusercontent.com/96629089/174828340-47f76505-45d6-4144-af78-434c70463e29.png)
- 현재 프로젝트에서 글로벌하게 사용할 tfvars 파일을 import
- Target Path 내에 있는 `*.tfvars` 파일은 커맨드 실행시 자동으로 `-var-file=./*.tfvars` 로 포함됨
- Target Path, 워크스페이스, 커맨드는 필수 인자

## 커맨드

```bash
do-terraform [OPTIONS] TARGET_PATH WORKSPACE COMMAND
```

## 옵션 사용 예

1. `./prod/backend` 내의 테라폼 코드를 plan, 프로젝트 전체에 적용되는 tfvars 파일 있음
    
    ```bash
    do-terraform -g ./global/g.tfvars ./prod/backend prod plan
    ```
    
2. `./dev/database` 내의 테라폼 코드 apply, 프로젝트 전체에 적용되는 tfvars 파일 없음, autoapprove 적용
    
    ```bash
    do-terraform -y ./dev/database dev apply
    ```
    
3. do-terraform 스크립트를 사용하여 적용한 모든 커맨드를 AWS S3 bucket에 logging
    
    ```bash
    do-terraform -l my-logging-bucket ./dev/database dev apply
    ```

# 이슈

## Workspace

- 현재 사용 가능한 workspace : dev, prod
- 설정 파일로 사용 가능한 workspace 를 지정하는 방식 구현 필요

## Terraform Command

- 현재 사용 가능한 command : plan, apply, destroy, output, init

## logging

- 인프라 구성에 반영되는 apply, destroy 커맨드는 do-terraform 스크립트를 통해 사용하는 대로 누적 logging 됨
    
    ```bash
    2022-06-17T01:06:36KST [APPLY]$ ./do-terraform.sh -g global/g.tfvars -y -l autosql-infra-terraform-state dev/vpc/ dev apply
    2022-06-17T01:13:43KST [APPLY]$ ./do-terraform.sh -g global/g.tfvars -y -l autosql-infra-terraform-state dev/vpc/ dev apply
    2022-06-17T01:55:27KST [APPLY]$ ./do-terraform.sh -g global/g.tfvars -y -l autosql-infra-terraform-state dev/vpc/ dev apply
    2022-06-17T01:55:38KST [APPLY]$ ./do-terraform.sh -g global/g.tfvars -y -l autosql-infra-terraform-state dev/frontend/ dev apply
    2022-06-17T01:59:17KST [APPLY]$ ./do-terraform.sh -g global/g.tfvars -y -l autosql-infra-terraform-state dev/backend/ dev apply
    ```
    
- 최종 반영된 인프라의 모습을 중복 없이 logging 하는 방법 필요
    
    ```bash
    2022-06-17T01:55:27KST [APPLY]$ ./do-terraform.sh -g global/g.tfvars -y -l autosql-infra-terraform-state dev/vpc/ dev apply
    2022-06-17T01:55:38KST [APPLY]$ ./do-terraform.sh -g global/g.tfvars -y -l autosql-infra-terraform-state dev/frontend/ dev apply
    2022-06-17T01:59:17KST [APPLY]$ ./do-terraform.sh -g global/g.tfvars -y -l autosql-infra-terraform-state dev/backend/ dev apply
    ```
