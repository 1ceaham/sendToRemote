function outputCell = loadFromRemote
% Function to finish loading files from remote command started by
% sendToRemote. Needs to be a function in order to not pollute the caller
% namespace. Currently only uses the inputParams to determine where to load
% from but may be modified in the future to accept arguments in order to
% manage multiple concurrent machines.

%% Get the path to this script's folder and load the inputParams

[remExPathNative,~,~] = fileparts(mfilename('fullpath'));
if ispc, remExPath = wslPath(remExPathNative); else, remExPath = remExPathNative; end
load(fullfile(remExPathNative, 'inputParams.mat'), 'command', 'sshString', ...
    'isScript', 'sentVarargin')

%% Parse options from sentVarargin

if any(strcmpi(sentVarargin, 'noload')), noload = true; else, noload = false; end
reExDirIdx = find(strcmpi(sentVarargin, 'remExDir'));
if reExDirIdx
    remExRoot = sentVarargin{reExDirIdx+1};
else
    remExRoot = '~/MATLAB/remoteExecution';
end

%% Rsync files back

disp('Syncing output files locally.')

if ispc, winPrefix = 'wsl '; else, winPrefix = []; end

[~] = system([winPrefix 'cd ' remExPath '; rsync -avz ' ...
    sshString ':' remExRoot '/' remExPath '/' command ' .']);

%% Treat outputs based on if command is script or function

loadPath = fullfile(remExPathNative, command, 'output.mat');

if ~noload
    disp('Loading variables.')
    if isScript
        % Load results in calling workspace
        loadStr = ['load(''' loadPath ''')'];
        evalin('caller', loadStr) % TODO: This needs to work 2 levels up???
    else
        % Pass result to calling function (can't use varargout since that
        % automatically converts cell arrays into multiple variables)
        outputData = load(loadPath);
        if isempty(outputData.outputCell)
            outputCell = {};
        else
            outputCell = outputData.outputCell;
        end
    end
else
%     disp(['Not loading variables locally; find output at <a href="' ...
%         loadPath '">' loadPath '</a>'])
    disp(['Not loading variables locally; find output at ' loadPath])
end

disp('Done!')