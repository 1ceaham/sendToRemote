function varargout = reconnectToRemote
% Function to reconnect to a running (or finished) session started by
% sendToRemote. Needs to be a function such that varargout can be assigned
% to as with sendToRemote. Uses the last inputParams file to determine
% where to reconnect and load from, but may be modified in the future to
% accept arguments in order to manage multiple concurrent machines.

%% Get the path to this script's folder and load the inputParams

[remExPathNative,~,~] = fileparts(mfilename('fullpath'));
load(fullfile(remExPathNative, 'inputParams.mat'), 'sshString', 'isScript')

%% Shell in and reconnect to running session

disp('Reconnecting to remote command.')

proc = System.Diagnostics.Process();
proc.StartInfo.FileName = 'C:\\Windows\\system32\\cmd.exe';
proc.StartInfo.Arguments = ['/c wsl ssh -t ' sshString ' screen -r'];

[~] = Start(proc);

proc.WaitForExit();

exitCode = proc.ExitCode; % 0 if normal, 1 if finished, large neg number if stopped early
if ~any(exitCode == [0 1])
    disp(['SSH was closed before completing; run ''reconnectToRemote'' '...
        'to continue the session.'])
    return
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
