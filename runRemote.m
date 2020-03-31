% Wrapper script corresponding to sendToRemote.

%% Read input file

% Note that MATLAB's starting directory is [remExRoot '/' remExPath], where
% this script and the input parameters have been copied to.
load('inputParams.mat')

%% Create path

reExDirIdx = find(strcmpi(sentVarargin, 'remExDir'));
if reExDirIdx
    remExRoot = sentVarargin{reExDirIdx+1};
else
    remExRoot = '~/MATLAB/remoteExecution';
end

remUsrPath = cellfun(@(x) [remExRoot x], usrPath, 'uni', 0);
addpath(remUsrPath{:})

%% Remove old output file

if exist(command,'dir'), rmdir(command,'s'); end
mkdir(command)

%% CD to the working directory

remExPath = pwd; % Save this folder's path to write back to it easily
cd([remExRoot localPWD])

%% Identify variables to save / set up function call

if isScript
    vListBefore = who; % List variables
    vListBefore = [vListBefore; 'vListBefore']; % Make sure to count yourself!
else
    inArgIdx = find(strcmpi(sentVarargin, 'inputArgs'));
    if inArgIdx
        inputArgs = sentVarargin{inArgIdx+1};
    else
        inputArgs = {};
    end
    commandHandle = str2func(command);
end

%% Run command
% TODO: Ensure parallel pool is started!

disp(['Running ' command])

try
    diary('off') % Reset diary
    diary(fullfile(remExPath, command, 'diary.txt'))
    if isScript
        run(command)
    else
        if nOutArgs
            outputCell = cell(1,nOutArgs);
            [outputCell{:}] = commandHandle(inputArgs{:});
        else
            outputCell = [];
            commandHandle(inputArgs{:});
            % TODO: How to handle assigning to "ans" here?
        end
    end
    diary('off')
catch exception
    % We have to do this in order to get the error in the diary as well as
    % save and quit, otherwise the process would hang
    disp(getReport(exception, 'extended', 'hyperlinks', 'on'))
    diary('off')
end

%% Save data

disp('Saving data')

if isScript
    vListAfter = who; % New list of variables
    createdVars = vListAfter(~ismember(vListAfter,vListBefore)); % See what changed
    save(fullfile(remExPath,command,'output.mat'),createdVars{:},'-v7.3') % Only save vars that are not part of the sendToRemote machinery
else
    save(fullfile(remExPath,command,'output.mat'),'outputCell','-v7.3') % Save the returned outputs
end

%% Quit

disp('Quitting')

quit