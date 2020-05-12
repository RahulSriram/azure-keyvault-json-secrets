# azure-keyvault-json-secrets

A shell script I wrote to automate loading secrets to azure keyvault from a json file.

##Pre-requisites
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/?view=azure-cli-latest)
- [Python 3.x](https://www.python.org/downloads/) (Normally installed along with azure-cli)

##Usage
```bash
chmod +x ./az-kv-json-load.sh
```

```
./az-kv-json-load.sh [OPTIONS]

Options:
-n or --vault-name <vault-name>     Name of the azure keyvault.

-f or --file <path-to-file>         Path to the json file to read secrets from.

-y or --yes                         Skip user confirmation before uploading discovered secrets.

-s or --sensitive                   Assume all values are sensitive in nature,
                                      and dont display them.

-h or --help                        Print help text and exit.
```

##Examples
```json
{
    "Key1": "Value1",
    "Key2": {
        "Key21": "Value21",
        "Key22": "Value22"
    },
    "Key3": {
        "Key31": "Value31",
        "Key32": {
            "Key321": "Value321"
        }
    }
}
```

this json is uploaded to the keyvault in the following format,
```
Key1 -> Value1
Key2--Key21 -> Value21
Key2--Key22 -> Value22
Key3--Key31 -> Value31
Key3--Key32--Key321 -> Value321
```
