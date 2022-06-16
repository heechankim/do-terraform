#!/bin/bash

######################################################################################
# Program settings
######################################################################################
# Set Color Constant
# -----------------------------------
ERROR='\033[1;91m' # Red
RESULT='\033[0;101m' # Background Red
INFO='\033[4;36m' # Cyan
EOC='\033[0m' # End of Color

# Set Flags
# -----------------------------------
F_GLOBAL_TFVARS=0
F_AUTO_APPROVE=0
F_REMOTE_LOGGING=0
# Set Variables
# -----------------------------------
GLOBAL_TFVARS=""
ORIGINAL_DIR=`realpath ./`
LOG_DIR="$ORIGINAL_DIR/logs"
LOG_BUCKET=""

LOG_FILE="tf.log"
LOG_PATH="$LOG_DIR/$LOG_FILE"
DEV_LOG_FILE="dev-infra.log"
DEV_LOG_PATH="$LOG_DIR/$DEV_LOG_FILE"
PROD_LOG_FILE="prod-infra.log"
PROD_LOG_PATH="$LOG_DIR/$PROD_LOG_FILE"

ORIGINAL_COMMAND="$0 $@"

if [[ ! -d $LOG_DIR ]]; then
  mkdir -p $LOG_DIR
fi

######################################################################################
# Option settings
######################################################################################
while getopts "yg:l:" opt;
do
  case $opt in
    g)
      F_GLOBAL_TFVARS=1
      ls $OPTARG 1> /dev/null
      if [[ $? -ne 0 ]]; then exit -1; fi
      GLOBAL_TFVARS=`realpath $OPTARG`
      ;;
    y)
      F_AUTO_APPROVE=1
      ;;
    l)
      F_REMOTE_LOGGING=1
      LOG_BUCKET=$OPTARG
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
  esac
done

shift $((OPTIND-1))


######################################################################################
# Exit Conditions
######################################################################################
# Check Input Arguments
# -----------------------------------
if [[ -z $1 || -z $2 || -z $3 ]]; then
  echo -e "${ERROR}Use: $0 <OPTIONS> <PATH DIR> <TERRAFORM WORKSPACE> <TERRAFORM COMMAND>${EOC}"
  echo -e "${INFO}Example: $0 -g global/g.tfvars -y -l logging-bucket live/stage/vpc dev plan${EOC}"
  echo -e "${INFO}Options: ${EOC}"
  echo -e "\t\t${INFO}-g <.tfvars PATH>${EOC}"
  echo -e "\t\t\t${INFO}Specify the global .tfvars path${EOC}"
  echo -e ""
  echo -e "\t\t${INFO}-y${EOC}"
  echo -e "\t\t\t${INFO}Auto Approval option enable${EOC}"
  echo -e ""
  echo -e "\t\t${INFO}-l${EOC}"
  echo -e "\t\t\t${INFO}S3 Bucket name for saving logs${EOC}"
  echo -e "\t\t\t${INFO}This Option needs aws credential by \'aws configure\'${EOC}"
  echo -e "\t\t\t${INFO}And Account need to be allowed GetObject, PutObject action to this bucket resource${EOC}"
  exit -1
fi


# Check Directory path
# -----------------------------------
cd $1
if [[ $? -ne 0 ]]; then
  exit -1
fi
WORKING_DIR=$1

# Check Workspace restriction
# -----------------------------------
T_WORKSPACES=('dev' 'prod')

if [[ " ${T_WORKSPACES[*]} " =~ " $2 " ]]; then
  WORKSPACE=$2
else
  echo -e "${ERROR}Workspace $WORKSPACE is not available${EOC}"
  echo -e "${INFO}Available Workspaces are: ${T_WORKSPACES[@]} ${EOC}"
  exit -1
fi

# Check Terraform command
# -----------------------------------
T_COMMANDS=('plan' 'apply' 'destroy' 'output' 'init')

if [[ " ${T_COMMANDS[*]} " =~ " $3 " ]]; then
  COMMAND="terraform $3"
  T_COMMAND=$3
else
  echo -e "${ERROR}Command $T_COMMAND is not available${EOC}"
  echo -e "${INFO}Available Commands are: ${T_COMMANDS[@]} ${EOC}"
  exit -1
fi

# Check Terraform file exists
# -----------------------------------
T_FILES=`find . -type f -name "*.tf"`
if [[ ${#T_FILES[@]} -le 0 ]]; then
  echo "${ERROR}There is no terraform file${EOC}"
  exit -1
fi

# Print pwd message
# -----------------------------------
echo -e "${INFO}Current Directory: ${RESULT}`pwd`${EOC}"


######################################################################################
# If Command is init
######################################################################################
if [[ "$T_COMMAND" == "init" ]]; then
  COMMAND="terraform $T_COMMAND"
  eval $COMMAND
  exit 0
fi

######################################################################################
# Create Command to be execute 
######################################################################################
# Create Workspace If doesn't exist 
# -----------------------------------
terraform workspace select $WORKSPACE
if [[ $? -ne 0 ]]; then
  echo -e "${INFO}There is no workspace $WORKSPACE, So Create workspace $WORKSPACE ${EOC}"
  EXISTING_WORKSPACE=`terraform workspace show`
  terraform workspace new $WORKSPACE
  terraform workspace select $WORKSPACE
fi
echo -e "${INFO}Current Workspace: ${RESULT}`terraform workspace show`${EOC}"

# Create -var-file Options with files inside working directory
# -----------------------------------
T_VARS=`find . -type f -name "*.tfvars"`
if [[ ${#T_VARS[@]} -gt 0 ]]; then
  for vars in "${T_VARS[@]}"; do
    if [[ -n $vars ]]; then
      COMMAND="$COMMAND -var-file=$vars"
    fi
  done
fi

if [[ $F_GLOBAL_TFVARS -eq 1 ]]; then
  COMMAND="$COMMAND -var-file=$GLOBAL_TFVARS"
fi

if [[ $F_AUTO_APPROVE -eq 1 && "$T_COMMAND" == "apply" || "$T_COMMAND" == "destroy" ]]; then
  COMMAND="$COMMAND -auto-approve"
fi

#if [[ "$T_COMMAND" == "console" ]]; then
#  COMMAND="$COMMAND -state=./terraform.tfstate.d/$WORKSPACE/terraform.tfstate"
#fi

######################################################################################
# Show Final command
######################################################################################
echo ""
echo -e "${INFO}The command will be execute: ${RESULT}$COMMAND ${EOC}"

######################################################################################
# Wait User answer
######################################################################################
if [[ $F_AUTO_APPROVE -eq 1 ]]; then
  yn=y
else
  read -p "Continue (y or n): " yn
fi

case $yn in
  [yY] )
    eval $COMMAND

    ##################################################################################
    # Logging
    ##################################################################################
    if [[ $? -eq 0 ]]; then

      # Get log files from S3 Bucket
      if [[ $F_REMOTE_LOGGING -eq 1 ]]; then
        aws s3 cp s3://$LOG_BUCKET/logs  $LOG_DIR --recursive
      fi

      # Logging All Command
      UTC=`TZ='Asia/Seoul' date +%Y-%m-%dT%H:%M:%S%Z`
      COMMAND_LOG="$UTC [COMMAND]\$ $ORIGINAL_COMMAND"
      echo $COMMAND_LOG >> $LOG_PATH

      # Logging Apply and Destroy Command by environment
      if [[ "$T_COMMAND" == "apply" || "$T_COMMAND" == "destroy" ]]; then
        COMMAND_LOG="$UTC [`echo $T_COMMAND | tr [:lower:] [:upper:]`]\$ $ORIGINAL_COMMAND"

        if [[ "$T_WORKSPACES" == "dev" ]]; then
          echo $COMMAND_LOG >> $DEV_LOG_PATH
        fi

        if [[ "$T_WORKSPACES" == "prod" ]]; then
          echo $COMMAND_LOG >> $PROD_LOG_PATH
        fi
      fi

      # Sync log files to S3 Bucket
      if [[ $F_REMOTE_LOGGING -eq 1 ]]; then
        aws s3 sync $LOG_DIR s3://$LOG_BUCKET/logs
      fi

    fi
    ;;
  [nN] )
    ##################################################################################
    # Clean Up
    ##################################################################################
    if [[ -n $EXISTING_WORKSPACE ]]; then
      echo -e "${INFO}Delete created workspace: $WORKSPACE ${EOC}"
      terraform workspace select $EXISTING_WORKSPACE
      terraform workspace delete $WORKSPACE
    fi
    exit 0
    ;;
  * )
    echo -e "${INFO}Invalid Keyword${EOC}"
    ;;
esac

