# sendToRemote
Run a MATLAB script or function over SSH as though it was run locally.

[![View sendToRemote on File Exchange](https://www.mathworks.com/matlabcentral/images/matlab-file-exchange.svg)](https://www.mathworks.com/matlabcentral/fileexchange/74801-sendtoremote)

SENDTOREMOTE is intended to work as a seamless way to run a script or function on a remote server without the MATLAB Parallel Server or other scheduling software as though it had been run locally. 
Given SSH access to a powerful machine that is not specifically provisioned as a MATLAB server or cluster, but nonetheless has a licensed version of MATLAB available (as is often the case in a shared academic context), SENDTOREMOTE provides a straightforward framework for executing code on a shared resource without having to manually copy files back and forth, all without leaving the MATLAB command line.

WARNING: This function uses Rsync to copy the ENTIRETY of the MATLAB path to a remote machine. 
If your path contains large data files or private information that should not be copied, DO NOT USE THIS PROJECT. 
Furthermore, in order to improve the chances that the remote command does not use shadowed or stale code, all extraneous files under the remote execution directory (~/MATLAB/remoteExecution by default) WILL BE DELETED every time the path is copied to the remote machine, possibly leading to data loss if this folder is already in use.

At the moment, development has occurred entirely under the Windows Subsystem for Linux (WSL).
If you are interested in helping out with updating it to work with true Unix-based systems, please leave an issue or a pull request!

## Usage

First, set up your SSH Config and verify that you can login to the server you want with `ssh hostname`.
That will probably require a `~/.ssh/config` (or whatever you use) that looks something like this:
```
Host myserver
    HostName myserver.myorg.com
    User myusername
    IdentityFile ~/.ssh/id_rsa
```

Also, make sure that running `matlab` on the server works.

Then, from your MATLAB command window (or in a script or function), issue a command to be executed on the server.
```
result = sendToRemote('magic','myserver','inputArgs',{4});
```
The above is the same as running `result = magic(4)` locally, but it happened somewhere else!

Please note that this is entirely experimental, and as mentioned above, could lead to data loss.
That said, this has been a pretty convenient and not super brittle way to make a thin client feel a little more beefy in a way that more-or-less matches how scripts and functions behave in MATLAB already.
Suggestions welcomed!
