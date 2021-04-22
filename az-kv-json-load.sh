#!/bin/bash

#Setup global variables
delimiter="--"
separator=$'\t'
filename=
vault=
subscription=
READ_MODE=0
EXEC_MODE=1
SUCCESS_CODE=0
FAIL_CODE=1
skip_confirmation=false
sensitive_info=false

#Print usage information
usage() {
    echo "azure-keyvault-json-secrets v1.0"
    echo "Rahul Sriram, https://github.com/RahulSriram/azure-keyvault-json-secrets"
    echo
    echo "Loads secrets stored in json to azure keyvault using the azure-cli."
    echo
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "-n or --vault-name <vault-name>         Name of the azure keyvault."
    echo "-s or --subscription <subscription>     Name or ID of the azure subscription."
    echo "                                          Uses default subscription if not set."
    echo "-f or --file <path-to-file>             Json file to read secrets from."
    echo "-y or --yes                             Skip user confirmation before uploading discovered secrets."
    echo "--sensitive                             Assume all values are sensitive in nature,"
    echo "                                          and dont display them."
    echo "-h or --help                            Print Help (this message) and exit."
    echo
}

abort() {
    echo "Aborting."
    exit $1
}

#If no arguments supplied, print usage command and exit
if [ "$1" == "" ]; then
    echo >&2 "Invalid arguments supplied. Use --help for details"
    abort $FAIL_CODE
fi

#Handle user options
while [ "$1" != "" ]; do
    case $1 in
        -f | --file)
            shift
            filename=$1
            ;;
        -n | --vault-name)
            shift
            vault=$1
            ;;
        -s | --subscription)
            shift
            subscription=$1
            ;;
        -y | --yes)
            skip_confirmation=true
            ;;
        --sensitive)
            sensitive_info=true
            ;;
        -h | --help)
            usage
            abort $SUCCESS_CODE
            ;;
    esac
    shift
done

#Check if azure-cli exists
az --version > /dev/null || {
    echo >&2 "This script requires azure-cli to run."
    abort $FAIL_CODE
}

#Check if python 3 exists. This should be available, since azure-cli requires python 3
python3 --version > /dev/null || {
    echo >&2 "This script requires python 3 to run."
    abort $FAIL_CODE
}

#Python script to validate json file
validateJsonPyScript=$(cat <<EOF
import sys, json, distutils.util
def validate_json(obj, root=True):
    if root and isinstance(obj, dict):
        for key, value in obj.items():
            validate_json(value, False)
    elif not root and obj is not None and (isinstance(obj, dict) or isinstance(obj, str)):
        if isinstance(obj, dict):
            for key, value in obj.items():
                validate_json(value, False)
    else:
        if bool(distutils.util.strtobool('$sensitive_info')):
            raise Exception('Unsupported json format. All values need to be of type string or object.')
        else:
            raise Exception('Unsupported json format at ' + str(obj) + '. Value needs to be of type string or object, not ' + type(obj).__name__ + '.')

try:
    jsonObj = None
    try:
        jsonObj = json.load(sys.stdin)
    except:
        raise Exception('Invalid json file format')
    validate_json(jsonObj)
    print($SUCCESS_CODE)
except Exception as e:
    print(str(e))
EOF
)

#Python script to flatten json into key value pairs
flatJsonKeyValuesPyScript=$(cat <<EOF
import sys, json
def flat_json_path(obj, path=''):
    result = []
    for key, value in obj.items():
        new_path = path + '$delimiter' + key if path else key
        if isinstance(value, dict):
            result.extend(flat_json_path(value, path=new_path))
        else:
            result.append(new_path + '$separator' + value)
    return result

for jsobj in flat_json_path(json.load(sys.stdin)):
    print(jsobj)
EOF
)

#Read secrets from json, and output them, or set them in keyvault based on the first param's value
loadKeyVaultSecrets() {
    if [ "$1" == "" ]; then
        abort $FAIL_CODE
    fi

    #Ensure no erros while attempting to flatten json
    flatJsonResult=$(cat $filename | python3 -c "$flatJsonKeyValuesPyScript") || {
        abort $FAIL_CODE
    }

    #Read flattened json and output values/upload to keyvault based on requested action
    while read line; do
        IFS=$separator read -r key val <<< "$line"
        printVal=''
        if [ "$sensitive_info" != true ]; then
            printVal=" -> $val"
        fi

        if [ "$1" == "$READ_MODE" ]; then
            echo "${key}${printVal}"
        elif [ $1 == "$EXEC_MODE" ]; then
            echo "Adding ${key}${printVal}"
            if [ "$subscription" == "" ]; then
                az keyvault secret set --vault-name "$vault" --name "$key" --value "$val" > /dev/null || {
                    echo >&2 "ERROR: Failed to load secret $key"
                    abort $FAIL_CODE
                }
            else
                az keyvault secret set --subscription "$subscription" --vault-name "$vault" --name "$key" --value "$val" > /dev/null || {
                    echo >&2 "ERROR: Failed to load secret $key"
                    abort $FAIL_CODE
                }
            fi
        fi
    done <<< "$flatJsonResult"
}

#Ensure filename and vault are not empty
if [ "$filename" == "" ]; then
    echo >&2 "File name cannot be empty. Use --help for details"
    abort $FAIL_CODE
fi

if [ "$vault" == "" ]; then
    echo >&2 "Vault name cannot be empty. Use --help for details"
    abort $FAIL_CODE
fi

#Ensure file exists
stat $filename > /dev/null || {
    abort $FAIL_CODE
}

validateResult=$(cat $filename | python3 -c "$validateJsonPyScript")
if [ "$validateResult" != "$SUCCESS_CODE" ]; then
    echo "ERROR: $validateResult"
    abort $FAIL_CODE
fi

#Ensure keyvault exists
az keyvault show --name "$vault" > /dev/null || {
    abort $FAIL_CODE
}

confirmation=
if [ "$skip_confirmation" != true ]; then
    #Read from json, and print all discovered secrets
    loadKeyVaultSecrets $READ_MODE
    echo
    #Confirm if the displayed secrets are good to add
    read -p "The above secrets will be added to the vault: $vault. Continue? [Y/n]:" confirmation
fi

if [ "$confirmation" == "y" ] || [ "$confirmation" == "Y" ] || [ "$skip_confirmation" == true ]; then
    #Load secrets from json to keyvault
    loadKeyVaultSecrets $EXEC_MODE
    echo "Done"
else
    abort $SUCCESS_CODE
fi