function res = vl_contrib(command, module, varargin)
%VL_CONTRIB Contribution modules managemenr
%  VL_CONTRIB LIST
%    Prints a list of available modules.
%
%  VL_CONTRIB GET MODULE
%    Downloads a module MODULE.
%
%  VL_CONTRIB SETUP MODULE
%    Setups a module MODULE.
%
%   See also: VL_NNSETUP, VL_NNCOMPILE, VL_TESTNN.

% Copyright (C) 2017 Karel Lenc.
% All rights reserved.
%
% This file is part of the VLFeat library and is made available under
% the terms of the BSD license (see the COPYING file).
opts.contribUrl = 'github.com/lenck/matconvnet-contrib-test/';
opts.contribDir = fullfile(vl_rootnn(), 'contrib');
if has_git(), opts.method = 'git'; else, opts.method = 'zip'; end
opts.force = false;
opts.showlinks = usejava('desktop');
opts = vl_argparse(opts, varargin);
% Support for the script-like calls
if isstr(opts.force), opts.force = str2num(opts.force); end;

if nargin < 1, command = 'list'; end;
if nargin < 2, module = ''; end;

% Persistent to reduce the reads
persistent contribs;
if isempty(contribs)
  contrib_repo = repo_factory(opts.contribUrl);
  contribs_raw = webread(contrib_repo.readme_url);
  contribs = parse_contributions(contribs_raw);
end

% Setup a module structure
if nargin > 1
  [module_found, module_id] = ismember(module, {contribs.name});
  if ~module_found, error('Unknown module %s.'); end
  module = init_module(contribs(module_id), opts);
end

switch lower(command)
  case 'list'
    list_modules(contribs, opts);
  case {'install', 'update'}
    module_get(module, opts);
  case 'compile'
    module_compile(module);
  case 'setup'
    module_setup(module);
  case 'unload'
    module_unload(module);
  case 'url'
    res = module.repo.url;
  case 'path'
    res = module.path;
  otherwise
    error('Unknown command %s.', command);
end
end

function module = init_module(module, opts)
  module.path = fullfile(opts.contribDir, module.name);
  module.present = exist(module.path, 'dir');
  module.repo = repo_factory(module.url);
  module.setup_path = fullfile(module.path, ['setup_', module.name, '.m']);
  module.compile_path = fullfile(module.path, ['compile_', module.name, '.m']);
  module.sha_path = fullfile(module.path, '.sha');
end

function list_modules(contribs, opts)
  function pmodule_links(module)
    module = init_module(module, opts);
    fprintf('\t<a href="%s">%s</a>', module.url, module.name);
    fprintf('\t%s\n\t\t', module.desc);
    if exist(module.path, 'dir')
      fprintf('<a href="matlab: vl_contrib update %s">[Update]</a> ', module.name);
      if exist(module.setup_path, 'file')
        fprintf('<a href="matlab: vl_contrib setup %s">[Setup]</a> ', module.name);
      end
      if exist(module.compile_path, 'file')
        fprintf('<a href="matlab: vl_contrib compile %s">[Compile]</a> ', module.name);
      end
      if module_loaded(module)
        fprintf('<a href="matlab: vl_contrib unload %s">[Unload]</a> ', module.name);
      end
      fprintf('(%s)', get_module_type(module));
    else
      fprintf('<a href="matlab: vl_contrib install %s">[Install]</a> ', module.name);
    end
    fprintf('\n\n');
  end
fprintf('\nAvailable modules:\n\n');
if opts.showlinks
  print_module = @pmodule_links;
else
  print_module = @(s) fprintf('\t%s\t\t%s\n', s.name, s.desc);
end
arrayfun(@(s) print_module(s), contribs);

fprintf('\n');
end

function module_get(module, opts)
if exist(module.path, 'dir')
  method = get_module_type(module);
  if isempty(method)
    error('Module %s does not seem to be managed by vl_contrib.', ...
      module.name);
  end;
else
  method = opts.method;
end
switch method
  case 'git'
    get_module_git(module, opts);
  case 'zip'
    get_module_zip(module, opts);
  otherwise
    error('Unknown method %s.', opts.method);
end
end

function module_setup(module)
if exist(module.setup_path, 'file')
  run(module.setup_path);
end
end

function module_compile(module)
if exist(module.compile_path, 'file')
  run(module.compile_path);
end
end

function res = module_loaded(module)
paths = strsplit(path(), ':');
is_modpath = cellfun(@(s) ~isempty(strfind(s, module.path)), paths);
res = any(is_modpath);
end

function to_unload = module_unload(module)
paths = strsplit(path(), ':');
is_modpath = cellfun(@(s) ~isempty(strfind(s, module.path)), paths);
to_unload = any(is_modpath);
if to_unload
  modpaths = paths(is_modpath);
  rmpath(modpaths{:});
end
end

%% Parse contribution files
function contribs = parse_contributions(text)
pattern = '\*[\s]*\[(?<name>\w+)\][\s]*\((?<url>.*?)\)[\s]*(?<desc>.*?)\n';
contribs = regexp(text, pattern, 'lineanchors', 'names');
end

function method = get_module_type(module)
if is_git(module), method = 'git'; return; end;
if is_zip(module), method = 'zip'; return; end;
method = '';
end

function res = verify_user(question)
answer = input(question, 's');
res = ~(isempty(answer) || ismember(lower(answer), {'n', 'no'}));
end

%% GIT Downloader
% Basic GIT download
function get_module_git(module, opts)
  function ret = git(varargin)
    % TODO solve this issue better than just disabling the SSL
    cmd = [{'GIT_SSL_NO_VERIFY=true', 'git'}, varargin];
    cmd = strjoin(cmd, ' ');
    [ret, str] = system(cmd);
    if ret ~= 0
      error('Git failed:\n%s', str);
    end
  end

if exist(module.path, 'dir')
  if ~is_git(module)
    error('Module %s in %s is not a git repo. Change method?', ...
      module.name, module.path)
  end
  git('--git-dir', fullfile(module.path, '.git'), 'pull');
else
  fprintf('Initialising git repository %s.\n', module.path);
  git('clone', module.repo.git_url, module.path);
end
end

function res = is_git(module)
res = exist(fullfile(module.path, '.git'), 'dir');
end

function res = has_git()
[ret, ~] = system('which git');
res = ret == 0;
end


%% ZIP Downloader
function res = get_module_zip(module, opts)
  function download(module, sha, opts)
    if module.present && ~opts.force
      question = sprintf(...
        'Module `%s` seems to exist. Reinstall? Y/N [N]: ', ...
        module.name);
      if ~verify_user(question), return; end;
    end
    unloaded = module_unload(module);
    fprintf('Donwloading %s... ', module.name);
    tmp_p = tempname();
    mkdir(tmp_p);
    unzip(module.repo.tarball_url, tmp_p);
    if exist(module.path, 'dir')
      rmdir(module.path, 's');
    end
    mkdir(module.path);
    tmp_dir = fullfile(tmp_p, [module.name, '-master'], '*');
    movefile(tmp_dir, module.path, 'f');
    rmdir(tmp_p, 's');
    fd = fopen(module.sha_path, 'w');
    fprintf(fd, sha);
    fclose(fd);
    fprintf('Done\n');
    if unloaded, module_setup(module); end;
  end

sha = module.repo.get_master_sha();
if ~is_zip(module) || opts.force
  download(module, sha, opts);
  res = true;
  return;
end
sha_fd = fopen(module.sha_path, 'r');
sha_str = fgetl(sha_fd); fclose(sha_fd);
if ~strcmp(sha, sha_str)
  download(module, sha, opts);
else
  fprintf('Module `%s` is up to date.\n', module.name);
end
res = true;
end

function res = is_zip(module)
res = exist(module.sha_path, 'file');
end

%% Repository wrappers
function repo = repo_factory(url)
repo = github(url);
if ~isempty(repo), return; end;
error('Invalid repository %s.', url);
end

function obj = github(url)
  function sha = read_sha(match)
    master_sha_url = ...
      sprintf('https://api.github.com/repos/%s/%s/git/refs/heads/master',...
      match.user, match.repo);
    data = webread(master_sha_url);
    sha = data.object.sha;
  end

pattern = 'github\.com/(?<user>[\w]*)/(?<repo>[\w-]*)';
match = regexp(url, pattern, 'names');
if isempty(match), obj = []; return; end;
obj.url = url;
obj.git_url = [url, '.git'];
obj.readme_url = ...
  sprintf('https://raw.githubusercontent.com/%s/%s/master/README.md', ...
  match.user, match.repo);
obj.tarball_url = ...
  sprintf('https://github.com/%s/%s/archive/master.zip', ...
  match.user, match.repo);
obj.get_master_sha = @() read_sha(match);
end

% TODO implemented BitBucket wrapper