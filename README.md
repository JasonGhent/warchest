WarChest
---

This tooling creates a docker container (locally or remotely) and with a
directory that is encrypted on-the-fly with the encrypted directory mirrored to
an Amazon Cloud Drive account.

There is additional tooling to expose the decrypted data (from a docker volume)
to the docker host's filesystem.


### Setup
This script requires an Amazon Cloud Drive security oauth_data token.
It assumes we're using the [Simple Authorization](https://github.com/yadayada/acd_cli/blob/master/docs/authorization.rst#simple-appspot) methodology prescribed by the acd_cli tool. This requires an interactive browser. To retrieve your token:

Install acdcli via python pip, and initialize it via `acdcli sync`, ergo,

[OSX]  
`$ brew install python3 && pip3 install acdcli && acd_cli sync`

[DEB]  
`$ apt-get install -y python3-pip && pip install acdcli && acd_cli sync`

Place the resulting token in your import directory, i.e. ./import/oauth_token

### Requirements
[OSX]  
- docker

[Amazon Cloud Drive]  
- ./import/oauth_token

[Recovery]  
- ./import/ACD_DATA_KEY

### Install
[OSX]  
`make macos`  

[DEB]  
`$ ENC_PASSWORD=your_password ./import/infinite-data-backup.sh`

### Recovery
To recover data, place that data's ACD_DATA_KEY file into the import directory,
and provide the password via the `ENC_PASSWORD` variable or at the prompt.

### Environment Variables
| Variable          | Default            |
| -------------     |:-------------:     |
| NAME              | amazon-cloud-drive |
| ENC_PASSWORD      | test               |
| IMPORT_DIR        | /import            |
