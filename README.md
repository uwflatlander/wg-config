This script will help generate server and client configuration files to help manage a Wireguard installation.

Currently the script will not alter the Wireguard active state. It will only generate the configuration files for the clients and the server. You will need to manage the Wireguard installation manually by moving the config files to the appropriate location. 

Future versions will have some management options to update the running Wireguard server with the new state.

### Dependency

* wireguard
* qrencode

### Configuration
Sample files are provided for the overall settings (__wg.def.sample__), server config file (__server.conf.tpl.sample__), and client config file (__client.conf.tpl.sample__). Copy the files while dropping the .sample and edit to your desired state.

If you don't have a pre-generated public and private key, the script will create one for you. Otherwise, create yours ahead of time with:

`wg genkey | tee prikey | wg pubkey > pubkey`.

### Output

Utility should be run as a normal user. 

Server configuration will be saved in the _server/_ folder. It will have a Wireguard configuration file and the public/private key files that were optionally generated.

#### Init Wireguard Config

```bash
./user.sh -i
```

Creates the default server configuration file and creates an IP pool for clients. Files are in the _server/_ folder.

#### Add a User

```bash
./user.sh -a alice
```

Generates a configuration file, private key, public key, and QR code for the client. Files are in the _users/\<username\>/_ folder.

Server configuration file in _server/_ is updated with the new client settings.

#### Delete a User

```bash
./user.sh -d alice
```
Purges the user from the server configuration and removes all client files in _users/\<username\>/_.

#### Clear All Settings

```bash
./user.sh -c
```

Nukes your entire setup from orbit. Use with caution.
