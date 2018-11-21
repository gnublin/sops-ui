# sops-ui [![Build Status](https://travis-ci.org/gnublin/sops-ui.svg?branch=master)](https://travis-ci.org/gnublin/sops-ui)

Sops-ui is an open-source software to manage [mozilla/sops#aws-kms-encryption-context](https://github.com/mozilla/sops#aws-kms-encryption-context) secrets

This interface encode your credential in base64 before to encrypt with sops command.

##### *Sops-ui manage only KMS keys.*

# Install

### Requirement
 * bundler (gem install bundler)
 * [npm](https://www.npmjs.com/get-npm)

### Prepare
* Clone this repository
 ```
git clone https://github.com/gnublin/sops-ui.git
 ```
* Install ruby Gems
 ```
bundle install
 ```
* Install node modules
 ```
npm install
 ```

### Configure

You should to create a `config/RACK_ENV.yml` configuration.

Ex: `config/development.yml`

---
###### Warn: This configuration file is required to run this app.
---

```yaml
---
sops_config:
  sops_binary: '/home/gauth/go/bin/sops'
  sops_folders:
    dev:
      path: /home/user/secrets-profile-1
      aws_profile: aws-profile-1
      kms_arn: arn:aws:kms:REGION:000111999222:key/DD4488X0-66UU-77YY-88TT-44OO33OO00AA
    staging-de:
      path: /home/user/secrets-profile-1
      aws_profile: aws-profile-2
      kms_arn: arn:aws:kms:REGION:000111999333:key/HH4488X0-77UU-66YY-99TT-44OO33OO00BB
  templates_dir:
    tpl1: /home/user/code/git/sops-ui/templates #absolute path
    tpl2: templates #relative path from repository
```

### Run app
```
bundle exec rackup -p 8080
```
or
```
./run
```

# Contribution

## Commit convention ##

* feat(#issue): description* when issue is a feature
* card(#issue): description* when issue is a card
* bug(#issue): description* when issue is a bug
* test(card name): description* when you add more commits into issue
* doc(readme): description* when you want to update readme or other doc


*feel free to add more details in multi-line list of your commit description*

## License and Author

Author: Gauthier FRANCOIS (<gauthier@openux.org>)

```text
MIT License
Copyright (c) 2018 Gauthier FRANCOIS
```
