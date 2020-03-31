function varargout = sendToRemote(command, sshString, varargin)
% SENDTOREMOTE Run a script or function over SSH as though it was run locally.
%
%   SENDTOREMOTE is intended to work as a seamless way to run a script or
%   function on a remote server without the MATLAB Parallel Server or other
%   scheduling software as though it had been run locally. Given SSH access
%   to a powerful machine that is not specifically provisioned as a MATLAB
%   server or cluster, but nonetheless has a licensed version of MATLAB
%   available (as is often the case in a shared academic context),
%   SENDTOREMOTE provides a straightforward framework for executing code on
%   a shared resource without having to manually copy files back and forth,
%   all without leaving the MATLAB command line.
%
%   WARNING: This function uses Rsync to copy the ENTIRETY of the MATLAB
%   path to a remote machine. If your path contains large data files or
%   private information that should not be copied, DO NOT USE THIS PROJECT.
%   Furthermore, in order to improve the chances that the remote command
%   does not use shadowed or stale code, all extraneous files under the
%   remote execution directory (~/MATLAB/remoteExecution by default) WILL
%   BE DELETED every time the path is copied to the remote machine,
%   possibly leading to data loss if this folder is already in use.
%
%   INPUTS
%   command: The name of the script or function to run.
%   sshString: The hostname specified in your SSH Config, corresponding to
%       logging in with the command 'ssh sshString'.
%
%   OPTIONAL INPUTS (VARARGIN)
%   'inputArgs', argArray: Cell array of inputs corresponding to function
%       arguments. Required if command is a function, illegal if script.
%   'remExDir', dirPath: The directory to host the copied path using local
%       relative paths. Defaults to '~/MATLAB/remoteExecution'.
%   'noload': Prevents the resulting variables from being loaded back into
%       the local MATLAB environment. Useful when variables are very large.
%   'noreconnect': Prevents the SSH session from using GNU screen to
%       continue running the command remotely in the case of disconnection
%       or user interrupts (closing the CMD window). This allows the entire
%       session to be displayed in the MATLAB command window rather than
%       requiring a full terminal to be opened.
%
%   OUTPUTS 
%   varargout: Essentially, this function behaves as if the command was run
%       locally, giving the same outputs that the command would give
%       depending on how it was called. If the command given is a script,
%       for example, all generated variables will be loaded into the local
%       workspace. If it is a function, you may assign to variables as
%       usual, but more complicated evaluation / interaction may not work
%       as expected. The output and a transcript of the command line output
%       are synced back to a subfolder with the command's name below this
%       function's location.
%
%   See also: reconnectToRemote, runRemote, loadFromRemote
%
%   OTHER REQUIRED SOFTWARE / CONFIGURATION
%   Any data that is loaded in at runtime (not specifically passed with the
%   'inputArgs' option) must be on the path at time of execution. The
%   remote server should be running linux, with the command 'matlab'
%   available on the path. The client and server both require SSH and
%   Rsync. Unless using the 'noreconnect' flag, GNU screen is also
%   required. Since MATLAB cannot interact with the shell, no part of the
%   SSH login or MATLAB execution process can take any user input (such as
%   a password or runtime configuration). Additionally, all visual features
%   on the server are disabled, so any visualization must take place
%   locally after execution of the specified command. On a PC, this
%   requires Windows 10 with a WSL installation.
%
%   TEST VERSIONS / HARDWARE
%   Local MATLAB: R2019a
%   Local Operating System: Microsoft Windows 10 Build 18363
%   Local WSL1 Operating System: Ubuntu-18.04 LTS
%   Local WSL1 Kernel: Linux 4.4.0-18362-Microsoft
%   Remote MATLAB: R2018a
%   Remote Operating System: Debian GNU/Linux 9 (stretch)
%   Remote Kernel: Linux 4.9.0-8-amd64
%

%% Parse varargin

if any(strcmpi(varargin, 'noreconnect'))
    noreconnect = true;
else
    noreconnect = false;
    if ~ispc
        error(['Hi! You''ve tried to run the reconnectable version of the ' ...
            'utility under a non-Windows device. Unfortunately, I don''t ' ...
            'have a way to test this functionality, since I''ve had to use ' ...
            'a few hacks to spin up an external tty in order to run GNU ' ...
            'screen, as the MATLAB command window is not a full terminal. ' ...
            'If you want to help out with this, please submit an issue or ' ...
            'PR at <a href="https://github.com/1ceaham/sendToRemote">' ...
            'https://github.com/1ceaham/sendToRemote</a>. Sorry, and thanks!'])
    end
end

if any(strcmpi(varargin, 'noload')), noload = true; else, noload = false; end
inArgIdx = find(strcmpi(varargin, 'inputArgs'));
reExDirIdx = find(strcmpi(varargin, 'remExDir'));
if reExDirIdx
    remExRoot = varargin{reExDirIdx+1};
else
    remExRoot = '~/MATLAB/remoteExecution';
end

% Since varargin is a protected variable name, we want to save and refer to
% it by something else to differentiate it.
sentVarargin = varargin;

%% Check for correct pathing

if ~exist(command,'file')
    error('The specified file isn''t on the MATLAB path and therefore cannot be executed remotely.')
end

%% Check if input / output arguments dis/allowed

try
    [~] = nargin(command); % This will error out if it's a script
    isScript = false;
    nOutArgs = nargout;
    if noload
        error(['Assigning the output of a function to a variable requires ' ...
            'loading variables back into the MATLAB environment.'])
    end 
catch exception
    if strcmp(exception.identifier, 'MATLAB:nargin:isScript')
        isScript = true;
    else
        warning(['Either the specified command was not a script or a ' ...
            'function, or something else happened that prevented ' ...
            'sendToRemote''s ability to determine the type of command, ' ...
            'detailed in the error message to follow.'])
        error(exception.message)
    end
end

if isScript
    if inArgIdx
        error('Cannot pass input arguments to a script.')
    end
    if nargout
        error('Cannot request output arguments from a script.')
    end
    nOutArgs = [];
end

%% Create path list

pathCell = regexp(path, pathsep, 'split'); % Get path in a cell array
usrPath = pathCell(~cellfun(@any,strfind(pathCell,matlabroot))); % Select only folders outside of MATLAB root
localPWD = pwd; % Get the local present working directory
usrPath = [usrPath localPWD]; % Add it to the path
usrPath = unique(usrPath); % Eliminate duplicates
if ispc, usrPath = wslPath(usrPath); end % If on Windows, convert to unix-style paths for WSL
usrPath = cellfun(@(x) [x '/'], usrPath, 'uni', 0); % Add trailing slash to indicate folders

%% Write param file

% Get the path to this function's folder locally so we can locate the runRemote script on the remote machine
[remExPathNative,~,~] = fileparts(mfilename('fullpath'));
% If on Windows, convert to unix-style paths since that's what will be used on the remote machine
if ispc, remExPath = wslPath(remExPathNative); else, remExPath = remExPathNative; end

if ispc, localPWD = wslPath(localPWD); end
if exist([remExPathNative '/inputParams.mat'],'file'), delete([remExPathNative '/inputParams.mat']); end
% TODO: Pass workspace variables in the case of a script
save([remExPathNative '/inputParams.mat'], 'command', 'sshString', 'sentVarargin', ...
    'usrPath', 'localPWD', 'isScript', 'nOutArgs')

%% Rsync (entire MATLAB path + param file)

disp('Syncing path to remote machine.')

if ispc, winPrefix = 'wsl '; else, winPrefix = []; end

srcPaths = sprintf('%s ',usrPath{:}); % Reorganize paths for Rsync

% Rsync options: archive, verbose, compress, directories, prune-empty-dirs,
% relative-path-names, no-recursion, delete-extraneous-files
[~] = system([winPrefix 'rsync -avzdmR --no-r --delete ' srcPaths ...
    sshString ':' remExRoot]);

%% Shell in and run wrapper

disp('Running command remotely.')

matCommand = [' matlab -nodisplay -nosplash -nodesktop -sd "' ...
    remExRoot '/' remExPath '" -r "runRemote"'];

if noreconnect
    [~] = system([winPrefix 'ssh ' sshString matCommand]);
else
    % We have to use a .NET hack here to open a CMD prompt since MATLAB's
    % command window cannot interpret the output given by GNU screen.
    proc = System.Diagnostics.Process();
    proc.StartInfo.FileName = 'C:\\Windows\\system32\\cmd.exe';
    proc.StartInfo.Arguments = ['/c wsl ssh -t ' sshString ' screen ' matCommand];

    [~] = Start(proc);

    proc.WaitForExit();
    % TODO: Should be possible to make everything up to here non-blocking
    % so that one could send commands to multiple machines at once and
    % collect the results by checking from time to time.
    
    exitCode = proc.ExitCode; % 0 if normal, large neg number if stopped early
    if exitCode
        disp(['SSH was closed before completing; run ''reconnectToRemote'' '...
            'to continue the session.'])
        varargout = {};
        return
    end
end

%% Rsync files back and assign to outputs

% We can't call the function directly since then we would have to call
% evalin twice to get to the calling namespace of this function for
% scripts, and since nested evalin is prohibited, we have to use this hack
% to get variables to appear in the right place. For functions, we can call
% it normally and use the results in this function's varargout. We want to
% do this so that the code is defined in a single place, rather than
% repeated in the base function as well as the reconnecting function.
if isScript
    evalin('caller', 'loadFromRemote')
else
    varargout = loadFromRemote;
end

