unit Main;

interface

uses
  Winapi.Windows, Winapi.Messages, Winapi.PsAPI, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls, System.Win.Registry, System.RegularExpressions,
  System.IOUtils, System.Generics.Collections, Options, TlHelp32, Vcl.Menus, ShellApi, DiscordFolders;

type
  TVersion = array [0 .. 3] of integer;

  TfrmMain = class(TForm)
    chkTempTorMode: TCheckBox;
    lWarmupSeconds: TLabel;
    editWarmupSeconds: TEdit;
    chkNotifyOnDirectMode: TCheckBox;
    chkAutoInstallTor: TCheckBox;
    lTorPath: TLabel;
    editTorPath: TEdit;
    btnBrowseTor: TButton;
    btnInstall: TButton;
    btnUninstall: TButton;
    MainMenu: TMainMenu;
    miAbout: TMenuItem;
    OpenDialogTor: TOpenDialog;
    OpenDialogDiscord: TOpenDialog;
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure btnInstallClick(Sender: TObject);
    procedure btnUninstallClick(Sender: TObject);
    procedure miAboutClick(Sender: TObject);
    procedure btnBrowseTorClick(Sender: TObject);
    procedure chkAutoInstallTorClick(Sender: TObject);
    procedure chkTempTorModeClick(Sender: TObject);
  private
    currentProcessDir: string;
    messageCaption: PChar;

    function FindMostSuitableOptionsPath: string;
    procedure FindDiscordBaseDirs(list: TStringList);
    procedure FindDiscordDirs(list: TStringList);
    function RequestManualDiscordDir(list: TStringList): boolean;
    function SelectTargetDiscordDirs(list: TStringList): boolean;
    function GetNewestDiscordDir(list: TStringList): string;
    function FindRunningDiscordProcesses(const targetDirs: TStringList = nil): TArray<DWORD>;
    function FindRunningTorProcesses: TArray<DWORD>;
    function CloseDiscordGracefully(const targetDirs: TStringList; timeoutMs: DWORD): boolean;
    function EnsureProcessesClosed(const targetDirs: TStringList = nil): boolean;
    procedure UpdateTorVisibility;
    procedure UpdateWarmupVisibility;
    function SafeCopyTorBundle(const srcDir, dstDir: string): boolean;
  public
    { Public declarations }
  end;

var
  frmMain: TfrmMain;

const
  DISCORD_CLOSE_TIMEOUT_MS = 8000;

implementation

{$R *.dfm}

function EnumWindowsCloseCallback(hWnd: HWND; lParam: LPARAM): BOOL; stdcall;
var
  pid: DWORD;
begin
  GetWindowThreadProcessId(hWnd, @pid);
  if pid = DWORD(lParam) then
    PostMessage(hWnd, WM_CLOSE, 0, 0);
  result := True;
end;

procedure EnumWindowsAndCloseByPid(pid: DWORD);
begin
  EnumWindows(@EnumWindowsCloseCallback, LPARAM(pid));
end;

function GetProcessImagePath(pid: DWORD): string;
var
  hProcess: THandle;
  pathBuf: array[0..MAX_PATH] of Char;
begin
  result := '';
  hProcess := OpenProcess(PROCESS_QUERY_INFORMATION or PROCESS_VM_READ, false, pid);
  if hProcess <> 0 then
  begin
    try
      if GetModuleFileNameEx(hProcess, 0, pathBuf, MAX_PATH) > 0 then
        result := pathBuf;
    finally
      CloseHandle(hProcess);
    end;
  end;
end;

function IsProcessInTargetDirs(pid: DWORD; targetDirs: TStringList): boolean;
var
  exePath, dir: string;
begin
  if (targetDirs = nil) or (targetDirs.Count = 0) then
    exit(true);

  exePath := LowerCase(GetProcessImagePath(pid));
  if exePath = '' then
    exit(true);

  for dir in targetDirs do
  begin
    if Pos(LowerCase(ExcludeTrailingPathDelimiter(dir)), exePath) = 1 then
      exit(true);
  end;

  result := false;
end;

function TfrmMain.FindRunningDiscordProcesses(const targetDirs: TStringList = nil): TArray<DWORD>;
var
  snapshot: THandle;
  pe: TProcessEntry32;
  list: TList<DWORD>;
begin
  list := TList<DWORD>.Create;
  try
    snapshot := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if snapshot = INVALID_HANDLE_VALUE then
      exit(list.ToArray);

    try
      pe.dwSize := SizeOf(TProcessEntry32);
      if Process32First(snapshot, pe) then
      begin
        repeat
          if IsDiscordExecutable(pe.szExeFile) then
          begin
            if IsProcessInTargetDirs(pe.th32ProcessID, targetDirs) then
              list.Add(pe.th32ProcessID);
          end;
        until not Process32Next(snapshot, pe);
      end;
    finally
      CloseHandle(snapshot);
    end;

    result := list.ToArray;
  finally
    list.Free;
  end;
end;

function TfrmMain.FindRunningTorProcesses: TArray<DWORD>;
var
  snapshot: THandle;
  pe: TProcessEntry32;
  list: TList<DWORD>;
begin
  list := TList<DWORD>.Create;
  try
    snapshot := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if snapshot = INVALID_HANDLE_VALUE then
      exit(list.ToArray);

    try
      pe.dwSize := SizeOf(TProcessEntry32);
      if Process32First(snapshot, pe) then
      begin
        repeat
          if SameText(pe.szExeFile, 'tor.exe') then
            list.Add(pe.th32ProcessID);
        until not Process32Next(snapshot, pe);
      end;
    finally
      CloseHandle(snapshot);
    end;

    result := list.ToArray;
  finally
    list.Free;
  end;
end;

function TfrmMain.CloseDiscordGracefully(const targetDirs: TStringList; timeoutMs: DWORD): boolean;
var
  pids, torPids: TArray<DWORD>;
  pid: DWORD;
  hProcess: THandle;
  startTick: DWORD;
begin
  pids := FindRunningDiscordProcesses(targetDirs);
  torPids := FindRunningTorProcesses;

  if (Length(pids) = 0) and (Length(torPids) = 0) then
    exit(true);

  // Termina Tor imediatamente (processo de fundo sem janela)
  for pid in torPids do
  begin
    hProcess := OpenProcess(PROCESS_TERMINATE, false, pid);
    if hProcess <> 0 then
    begin
      TerminateProcess(hProcess, 0);
      CloseHandle(hProcess);
    end;
  end;

  // Envia WM_CLOSE para janelas do Discord
  for pid in pids do
    EnumWindowsAndCloseByPid(pid);

  startTick := GetTickCount;
  while (GetTickCount - startTick) < timeoutMs do
  begin
    if (Length(FindRunningDiscordProcesses(targetDirs)) = 0) and (Length(FindRunningTorProcesses) = 0) then
      exit(true);
    Sleep(250);
    Application.ProcessMessages;
  end;

  // Força encerramento se ainda restarem processos
  pids := FindRunningDiscordProcesses(targetDirs);
  for pid in pids do
  begin
    hProcess := OpenProcess(PROCESS_TERMINATE, false, pid);
    if hProcess <> 0 then
    begin
      TerminateProcess(hProcess, 0);
      CloseHandle(hProcess);
    end;
  end;

  torPids := FindRunningTorProcesses;
  for pid in torPids do
  begin
    hProcess := OpenProcess(PROCESS_TERMINATE, false, pid);
    if hProcess <> 0 then
    begin
      TerminateProcess(hProcess, 0);
      CloseHandle(hProcess);
    end;
  end;

  Sleep(300);
  result := (Length(FindRunningDiscordProcesses(targetDirs)) = 0) and (Length(FindRunningTorProcesses) = 0);
end;

function TfrmMain.EnsureProcessesClosed(const targetDirs: TStringList = nil): boolean;
var
  discordCount, torCount: integer;
begin
  discordCount := Length(FindRunningDiscordProcesses(targetDirs));
  torCount := Length(FindRunningTorProcesses);

  if (discordCount = 0) and (torCount = 0) then
    exit(true);

  if Application.MessageBox('O Discord e/ou Tor est'#227'o em execu'#231#227'o. '#201' necess'#225'rio fech'#225'-los para continuar.'#13#10#13#10'Deseja fechar agora?',
    messageCaption, MB_ICONQUESTION or MB_YESNO) <> IDYES then
    exit(false);

  if not CloseDiscordGracefully(targetDirs, DISCORD_CLOSE_TIMEOUT_MS) then
  begin
    Application.MessageBox('N'#227'o foi poss'#237'vel fechar os processos automaticamente. Feche o Discord e Tor manualmente e tente novamente.',
      messageCaption, MB_ICONERROR);
    exit(false);
  end;

  result := true;
end;

function TfrmMain.SafeCopyTorBundle(const srcDir, dstDir: string): boolean;
var
  src, dst, tmpDst, item, relPath, dstFile: string;
  files: TArray<string>;
  torExePath: string;
  torExeSize: Int64;
  searchRec: TSearchRec;
begin
  result := false;
  src := IncludeTrailingPathDelimiter(srcDir);
  dst := IncludeTrailingPathDelimiter(dstDir);
  tmpDst := ExcludeTrailingPathDelimiter(dst) + '.tmp\';

  if not DirectoryExists(src) then
    exit;

  if DirectoryExists(tmpDst) then
  begin
    try
      TDirectory.Delete(tmpDst, true);
    except
    end;
  end;

  ForceDirectories(tmpDst);

  files := TDirectory.GetFiles(src, '*.*', TSearchOption.soAllDirectories);
  for item in files do
  begin
    relPath := ExtractRelativePath(src, item);
    dstFile := tmpDst + relPath;
    ForceDirectories(ExtractFileDir(dstFile));
    if not CopyFile(PChar(item), PChar(dstFile), false) then
      exit;
  end;

  torExePath := tmpDst + 'tor.exe';
  if FileExists(torExePath) then
  begin
    torExeSize := 0;
    if FindFirst(torExePath, faAnyFile, searchRec) = 0 then
    begin
      torExeSize := searchRec.Size;
      FindClose(searchRec);
    end;

    if torExeSize < 1024 then
    begin
      try
        TDirectory.Delete(tmpDst, true);
      except
      end;
      Application.MessageBox('O execut'#225'vel do Tor embutido est'#225' corrompido ou incompleto.', messageCaption, MB_ICONERROR);
      exit;
    end;
  end
  else
  begin
    try
      TDirectory.Delete(tmpDst, true);
    except
    end;
    exit;
  end;

  if DirectoryExists(dst) then
  begin
    try
      TDirectory.Delete(dst, true);
    except
      exit;
    end;
  end;

  try
    TDirectory.Move(ExcludeTrailingPathDelimiter(tmpDst), ExcludeTrailingPathDelimiter(dst));
    result := true;
  except
    result := false;
  end;
end;

function TfrmMain.RequestManualDiscordDir(list: TStringList): boolean;
var
  selectedFile, selectedDir, parentDir, subfolder, s: string;
  subfolders: TArray<string>;
begin
  result := false;
  if Application.MessageBox('A pasta de instala'#231#227'o do Discord n'#227'o foi detectada automaticamente.'#13#10#13#10'Deseja localizar a pasta ou execut'#225'vel do Discord manualmente?',
    messageCaption, MB_ICONQUESTION or MB_YESNO) <> IDYES then
    exit;

  if OpenDialogDiscord.Execute then
  begin
    selectedFile := OpenDialogDiscord.FileName;
    selectedDir := IncludeTrailingPathDelimiter(ExtractFileDir(selectedFile));

    if DirHasDiscordExecutable(selectedDir) then
    begin
      list.Add(selectedDir);
      exit(true);
    end;

    parentDir := IncludeTrailingPathDelimiter(ExtractFilePath(ExcludeTrailingPathDelimiter(selectedDir)));
    if TDirectory.Exists(parentDir) then
    begin
      subfolders := TDirectory.GetDirectories(parentDir, 'app-*', TSearchOption.soTopDirectoryOnly);
      for subfolder in subfolders do
      begin
        s := IncludeTrailingPathDelimiter(subfolder);
        if DirHasDiscordExecutable(s) then
          list.Add(s);
      end;
    end;

    if list.Count = 0 then
    begin
      if DirHasDiscordExecutable(selectedDir) then
        list.Add(selectedDir);
    end;

    result := list.Count > 0;
  end;
end;

function TfrmMain.SelectTargetDiscordDirs(list: TStringList): boolean;
var
  TaskDialog: TTaskDialog;
  btn: TTaskDialogBaseButtonItem;
  i: integer;
  dir, labelText, editionName, verName: string;
  match: TMatch;
begin
  result := false;
  if list.Count = 0 then
    exit;

  if list.Count = 1 then
    exit(true);

  TaskDialog := TTaskDialog.Create(nil);
  try
    TaskDialog.Caption := messageCaption;
    TaskDialog.Title := 'M'#250'ltiplas instala'#231#245'es do Discord detectadas';
    TaskDialog.Text := 'Selecione onde deseja aplicar a opera'#231#227'o:';
    TaskDialog.MainIcon := tdiInformation;
    TaskDialog.CommonButtons := [tcbCancel];

    btn := TaskDialog.Buttons.Add;
    btn.Caption := 'Instalar em todas as vers'#245'es encontradas';
    btn.ModalResult := 1000;

    for i := 0 to list.Count - 1 do
    begin
      dir := list[i];
      editionName := 'Discord';
      if Pos('canary', LowerCase(dir)) > 0 then
        editionName := 'Discord Canary'
      else if Pos('ptb', LowerCase(dir)) > 0 then
        editionName := 'Discord PTB';

      match := TRegEx.match(dir, 'app-([\d.]+)');
      if match.Success then
        verName := ' (v' + match.Groups[1].Value + ')'
      else
        verName := '';

      labelText := Format('%s%s', [editionName, verName]);

      btn := TaskDialog.Buttons.Add;
      btn.Caption := labelText;
      btn.ModalResult := 1001 + i;
    end;

    if TaskDialog.Execute then
    begin
      if TaskDialog.ModalResult = 1000 then
      begin
        result := true;
      end
      else if (TaskDialog.ModalResult >= 1001) and (TaskDialog.ModalResult < 1001 + list.Count) then
      begin
        dir := list[TaskDialog.ModalResult - 1001];
        list.Clear;
        list.Add(dir);
        result := true;
      end;
    end;
  finally
    TaskDialog.Free;
  end;
end;

procedure TfrmMain.UpdateTorVisibility;
var
  showManual: boolean;
begin
  showManual := not chkAutoInstallTor.Checked;
  lTorPath.Visible := showManual;
  editTorPath.Visible := showManual;
  btnBrowseTor.Visible := showManual;
end;

procedure TfrmMain.UpdateWarmupVisibility;
var
  isTempMode: boolean;
begin
  isTempMode := chkTempTorMode.Checked;
  editWarmupSeconds.Enabled := isTempMode;
  lWarmupSeconds.Enabled := isTempMode;
  chkNotifyOnDirectMode.Enabled := isTempMode;
end;

procedure TfrmMain.chkTempTorModeClick(Sender: TObject);
begin
  UpdateWarmupVisibility;
end;

procedure TfrmMain.chkAutoInstallTorClick(Sender: TObject);
begin
  UpdateTorVisibility;
end;

procedure TfrmMain.FormCreate(Sender: TObject);
var
  optPath: string;
  opt: TDroverOptions;
begin
  messageCaption := PChar(Application.Title);
  currentProcessDir := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));

  chkAutoInstallTor.Checked := true;
  chkTempTorMode.Checked := true;
  chkNotifyOnDirectMode.Checked := true;
  editWarmupSeconds.Text := '60';
  editTorPath.Text := '';

  optPath := FindMostSuitableOptionsPath;
  if optPath <> '' then
  begin
    opt := LoadOptions(optPath);
    if Trim(opt.torExecutable) <> '' then
    begin
      editTorPath.Text := opt.torExecutable;
      if Pos('drover-tor', LowerCase(opt.torExecutable)) = 0 then
        chkAutoInstallTor.Checked := false;
    end;
    chkTempTorMode.Checked := opt.tempTorMode;
    chkNotifyOnDirectMode.Checked := opt.notifyOnDirectMode;
    if opt.torWarmupSeconds > 0 then
      editWarmupSeconds.Text := IntToStr(opt.torWarmupSeconds);
  end;

  UpdateTorVisibility;
  UpdateWarmupVisibility;
end;

procedure TfrmMain.FormShow(Sender: TObject);
begin
  self.ActiveControl := btnInstall;
end;

procedure TfrmMain.btnBrowseTorClick(Sender: TObject);
begin
  if Trim(editTorPath.Text) <> '' then
  begin
    if DirectoryExists(ExtractFileDir(editTorPath.Text)) then
      OpenDialogTor.InitialDir := ExtractFileDir(editTorPath.Text);
    OpenDialogTor.FileName := ExtractFileName(editTorPath.Text);
  end;

  if OpenDialogTor.Execute then
    editTorPath.Text := OpenDialogTor.FileName;
end;

procedure TfrmMain.miAboutClick(Sender: TObject);
begin
  ShellExecute(0, 'open', 'https://github.com/bonqf/discord-drover-tor', nil, nil, SW_SHOWNORMAL);
end;

procedure TfrmMain.btnInstallClick(Sender: TObject);
var
  dirs, errors: TStringList;
  dir, dllPath, filename, srcPath, dstPath, s: string;
  TaskDialog: TTaskDialog;
  opt: TDroverOptions;
  baseOptions: TDroverOptions;
  extraFilenames: TArray<string>;
  torFinalPath, bundledTorPath, bundledTorDir, targetTorDir: string;
  warmupSeconds: integer;
begin
  dllPath := currentProcessDir + DLL_FILENAME;
  if not FileExists(dllPath) then
  begin
    Application.MessageBox(PChar(Format('The file ''%s'' is missing.', [DLL_FILENAME])), messageCaption, MB_ICONERROR);
    exit;
  end;

  // ✅ HANDLER: Validar warmup seconds se modo temporário está ativo
  if chkTempTorMode.Checked then
  begin
    warmupSeconds := StrToIntDef(Trim(editWarmupSeconds.Text), 0);
    if warmupSeconds <= 0 then
    begin
      Application.MessageBox('O tempo de aquecimento deve ser maior que 0 segundos.', messageCaption, MB_ICONERROR);
      exit;
    end;
  end;

  if chkAutoInstallTor.Checked then
  begin
    bundledTorPath := currentProcessDir + 'tor\tor.exe';
    if not FileExists(bundledTorPath) then
      bundledTorPath := IncludeTrailingPathDelimiter(ExtractFilePath(ExcludeTrailingPathDelimiter(currentProcessDir))) + 'tor.exe';

    if not FileExists(bundledTorPath) then
    begin
      Application.MessageBox('Tor n'#227'o encontrado no pacote do instalador (tor\tor.exe).', messageCaption, MB_ICONERROR);
      exit;
    end;
    bundledTorDir := ExtractFilePath(bundledTorPath);
  end
  else
  begin
    torFinalPath := Trim(editTorPath.Text);
    if not FileExists(torFinalPath) then
    begin
      Application.MessageBox('Selecione um tor.exe v'#225'lido.', messageCaption, MB_ICONERROR);
      exit;
    end;
  end;

  dirs := TStringList.Create;
  errors := TStringList.Create;
  try
    // ✅ Carregar .ini base (template do desenvolvedor) como ponto de partida
    baseOptions := LoadOptions(currentProcessDir + OPTIONS_FILENAME);

    FindDiscordDirs(dirs);
    if (dirs.Count = 0) and not RequestManualDiscordDir(dirs) then
    begin
      Application.MessageBox('A pasta do Discord n'#227'o foi selecionada.', messageCaption, MB_ICONERROR);
      exit;
    end;

    if not SelectTargetDiscordDirs(dirs) then
      exit;

    if not EnsureProcessesClosed(dirs) then
      exit;

    extraFilenames := GetExtraFilenames(currentProcessDir, false);

    for dir in dirs do
    begin
      if chkAutoInstallTor.Checked then
      begin
        targetTorDir := dir + 'drover-tor';
        if not SafeCopyTorBundle(bundledTorDir, targetTorDir) then
        begin
          errors.Add(targetTorDir + ' (cópia segura do Tor falhou)');
          // ⚠️ NÃO usa continue! Continua para salvar o .ini
        end
        else
        begin
          torFinalPath := IncludeTrailingPathDelimiter(targetTorDir) + 'tor.exe';
        end;
      end;

      // ✅ SEMPRE salvar .ini, mesmo se Tor não foi copiado
      // Partir do template (baseOptions) e aplicar overrides do usuário/instalador
      opt := baseOptions;
      opt.torExecutable := torFinalPath;
      opt.autoStartTor := chkAutoInstallTor.Checked;
      opt.tempTorMode := chkTempTorMode.Checked;  // Usuário escolhe modo
      opt.torWarmupSeconds := StrToIntDef(Trim(editWarmupSeconds.Text), baseOptions.torWarmupSeconds);
      opt.notifyOnDirectMode := chkNotifyOnDirectMode.Checked;

      // ✅ Salvar .ini junto com o tor.exe:
      //   - Auto-install: <dir>\drover-tor\
      //   - Manual: junto do tor.exe escolhido pelo usuário
      if chkAutoInstallTor.Checked then
        s := dir + 'drover-tor\' + OPTIONS_FILENAME
      else
        s := ExtractFilePath(torFinalPath) + OPTIONS_FILENAME;

      if not SaveOptions(s, opt) then
      begin
        errors.Add(Format('Falha ao salvar %s', [s]));
      end
      else
      begin
        // ✅ LOG: Confirmar que foi salvo com sucesso
        // (Usuário pode verificar depois)
      end;

      s := dir + DLL_FILENAME;
      if not SameText(dllPath, s) and not CopyFile(PChar(dllPath), PChar(s), false) then
        errors.Add(s);

      for filename in extraFilenames do
      begin
        srcPath := currentProcessDir + filename;
        dstPath := dir + filename;
        if FileExists(srcPath) and not SameText(srcPath, dstPath) and not CopyFile(PChar(srcPath), PChar(dstPath), false)
        then
          errors.Add(dstPath);
      end;
    end;

    opt := baseOptions;
    opt.torExecutable := torFinalPath;
    opt.autoStartTor := chkAutoInstallTor.Checked;
    opt.tempTorMode := chkTempTorMode.Checked;
    opt.torWarmupSeconds := StrToIntDef(Trim(editWarmupSeconds.Text), baseOptions.torWarmupSeconds);
    opt.notifyOnDirectMode := chkNotifyOnDirectMode.Checked;
    s := currentProcessDir + OPTIONS_FILENAME;
    SaveOptions(s, opt);

    if errors.Count > 0 then
    begin
      TaskDialog := TTaskDialog.Create(nil);
      try
        TaskDialog.Caption := messageCaption;
        TaskDialog.Title := 'Installation error';
        TaskDialog.Text := 'Some files could not be written.';
        TaskDialog.ExpandedText := Trim(errors.Text);
        TaskDialog.CommonButtons := [tcbClose];
        TaskDialog.Flags := [tfExpandFooterArea];
        TaskDialog.MainIcon := tdiError;
        TaskDialog.Execute;
      finally
        TaskDialog.Free;
      end;
    end
    else
    begin
      Application.MessageBox('Installation complete!', messageCaption, MB_ICONINFORMATION);
    end;
  finally
    dirs.Free;
    errors.Free;
  end;
end;

procedure TfrmMain.btnUninstallClick(Sender: TObject);
var
  dirs, errors: TStringList;
  dir, filename, s, torDir: string;
  TaskDialog: TTaskDialog;
  extraFilenames: TArray<string>;
begin
  dirs := TStringList.Create;
  errors := TStringList.Create;
  try
    FindDiscordDirs(dirs);
    if (dirs.Count = 0) and not RequestManualDiscordDir(dirs) then
    begin
      Application.MessageBox('A pasta do Discord n'#227'o foi selecionada.', messageCaption, MB_ICONERROR);
      exit;
    end;

    if not SelectTargetDiscordDirs(dirs) then
      exit;

    if not EnsureProcessesClosed(dirs) then
      exit;

    extraFilenames := GetExtraFilenames(currentProcessDir, true);

    for dir in dirs do
    begin
      s := dir + DLL_FILENAME;
      if FileExists(s) and not DeleteFile(s) then
        errors.Add(s);

      s := dir + OPTIONS_FILENAME;
      if FileExists(s) and not DeleteFile(s) then
        errors.Add(s);

      for filename in extraFilenames do
      begin
        s := dir + filename;
        if FileExists(s) and not DeleteFile(s) then
          errors.Add(s);
      end;

      torDir := dir + 'drover-tor';
      if DirectoryExists(torDir) then
      begin
        try
          TDirectory.Delete(torDir, true);
        except
          errors.Add(torDir);
        end;
      end;
    end;

    if errors.Count > 0 then
    begin
      TaskDialog := TTaskDialog.Create(nil);
      try
        TaskDialog.Caption := messageCaption;
        TaskDialog.Title := 'Uninstall error';
        TaskDialog.Text := 'Some files could not be deleted.';
        TaskDialog.ExpandedText := Trim(errors.Text);
        TaskDialog.CommonButtons := [tcbClose];
        TaskDialog.Flags := [tfExpandFooterArea];
        TaskDialog.MainIcon := tdiError;
        TaskDialog.Execute;
      finally
        TaskDialog.Free;
      end;
    end
    else
    begin
      Application.MessageBox('Uninstall complete!', messageCaption, MB_ICONINFORMATION);
    end;
  finally
    dirs.Free;
    errors.Free;
  end;
end;

function TfrmMain.FindMostSuitableOptionsPath: string;
var
  dirs: TStringList;
  s, dir: string;
begin
  dirs := TStringList.Create;
  try
    FindDiscordDirs(dirs);
    dir := GetNewestDiscordDir(dirs);
  finally
    dirs.Free;
  end;

  if dir <> '' then
  begin
    s := dir + OPTIONS_FILENAME;
    if FileExists(s) then
      exit(s);
  end;

  s := currentProcessDir + OPTIONS_FILENAME;
  if FileExists(s) then
    exit(s);

  result := '';
end;

procedure TfrmMain.FindDiscordBaseDirs(list: TStringList);
var
  reg: TRegistry;
  match: TMatch;
  s, app: string;
const
  APPS: array [0 .. 2] of string = ('Discord', 'DiscordCanary', 'DiscordPTB');
begin
  list.Clear;
  list.Sorted := true;
  list.Duplicates := dupIgnore;
  list.CaseSensitive := false;

  reg := TRegistry.Create(KEY_QUERY_VALUE);
  try
    reg.RootKey := HKEY_CURRENT_USER;

    for app in APPS do
    begin
      if reg.OpenKeyReadOnly('Software\Microsoft\Windows\CurrentVersion\Uninstall\' + app) then
      begin
        if reg.ValueExists('InstallLocation') then
        begin
          s := reg.ReadString('InstallLocation');
          if s <> '' then
          begin
            s := IncludeTrailingPathDelimiter(s);
            if DirectoryExists(s) then
              list.Add(s);
          end;
        end;
        reg.CloseKey;
      end;
    end;

    if reg.OpenKeyReadOnly('Software\Classes\Discord\shell\open\command') then
    begin
      if reg.ValueExists('') then
      begin
        s := reg.ReadString('');
        if s <> '' then
        begin
          match := TRegEx.match(s, '\A"(.+\\)app-');
          if match.Success then
          begin
            s := match.Groups[1].Value;
            if DirectoryExists(s) then
              list.Add(s);
          end;
        end;
      end;
      reg.CloseKey;
    end;
  finally
    reg.Free;
  end;
end;

procedure TfrmMain.FindDiscordDirs(list: TStringList);
var
  baseDirs: TStringList;
  subfolders: TArray<string>;
  s, subfolder, baseDir: string;
begin
  baseDirs := TStringList.Create;
  try
    FindDiscordBaseDirs(baseDirs);
    for baseDir in baseDirs do
    begin
      if TDirectory.Exists(baseDir) then
      begin
        subfolders := TDirectory.GetDirectories(baseDir, 'app-*', TSearchOption.soTopDirectoryOnly);
        for subfolder in subfolders do
        begin
          s := IncludeTrailingPathDelimiter(subfolder);
          if DirHasDiscordExecutable(s) then
            list.Add(s);
        end;
      end;
    end;
  finally
    baseDirs.Free;
  end;
end;

function TfrmMain.GetNewestDiscordDir(list: TStringList): string;
var
  i, partsLen: integer;
  dir: string;
  match: TMatch;
  maxVer, curVer: TVersion;
  parts: TArray<string>;
begin
  if list.Count = 0 then
    exit('');

  result := list[0];
  maxVer := Default(TVersion);

  for dir in list do
  begin
    match := TRegEx.match(dir, 'app-([\d.]+)');
    if not match.Success then
      continue;
    parts := match.Groups[1].Value.Split(['.']);
    partsLen := Length(parts);
    for i := 0 to High(curVer) do
    begin
      if i < partsLen then
        curVer[i] := StrToIntDef(parts[i], 0)
      else
        curVer[i] := 0;
    end;

    for i := 0 to High(curVer) do
    begin
      if curVer[i] <> maxVer[i] then
      begin
        if curVer[i] > maxVer[i] then
        begin
          maxVer := curVer;
          result := dir;
        end;
        break;
      end;
    end;
  end;
end;

end.