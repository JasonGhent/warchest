Infinite/Unlimited Encrypted Amazon Cloud Drive Backup
---

### Setup
This script requires an Amazon Cloud Drive security oauth_data token.
It assumes we're using the [Simple Authorization](https://github.com/yadayada/acd_cli/blob/master/docs/authorization.rst#simple-appspot) methodology prescribed by the acd_cli tool. This requires an interactive browser. To retrieve your token:

Install acdcli via python pip, and initialize it

[OSX]  
`$ brew install python3 && pip3 install acdcli && acd_cli sync`

[DEB]  
`$ apt-get install -y python3-pip && pip install acdcli && acd_cli sync`

Place the resulting token in your import directory, i.e. ./import/oauth_token

### Requirements
[OSX]  
- sshfs
- docker

[ALL]  
- ./import/oauth_token

[Recovery]  
- ./import/ACD_DATA_KEY

### Install
[OSX]  
`$ ENC_PASSWORD=your_password ./osx-layer.sh <optional_host_system_symlink>`
`optional_host_system_symlink` defaults to ~/Desktop/$NAME

[DEB]  
`$ ENC_PASSWORD=your_password ./import/infinite-data-backup.sh`

### Recovery
To recover data, place that data's ACD_DATA_KEY file into the import directory,
and provide the password via the `ENC_PASSWORD` variable

### Environment Variables
| Variable        | Default            |
| -------------   |:-------------:     |
| NAME            | amazon-cloud-drive |
| ENC_PASSWORD    | test               |
| IMPORT_DIR      | /import            |
