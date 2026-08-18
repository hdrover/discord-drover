unit Main;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls, System.Win.Registry, System.RegularExpressions,
  System.IOUtils, Options, TlHelp32, Vcl.Menus, ShellApi, DiscordFolders;

type
  TVersion = array [0 .. 3] of integer;

  TfrmMain = class(TForm)
    pType: TPanel;
    rbHttp: TRadioButton;
    rbSocks: TRadioButton;
    btnInstall: TButton;
    btnUninstall: TButton;
    eHost: TEdit;
    ePort: TEdit;
    lHost: TLabel;
    lPort: TLabel;
    MainMenu: TMainMenu;
    miAbout: TMenuItem;
    cbAuth: TCheckBox;
    eLogin: TEdit;
    ePassword: TEdit;
    lLogin: TLabel;
    lPassword: TLabel;
    rbDirect: TRadioButton;
    TrayIcon: TTrayIcon;
    TrayMenu: TPopupMenu;
    miRestore: TMenuItem;
    miHide: TMenuItem;
    miExit: TMenuItem;
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure btnInstallClick(Sender: TObject);
    procedure btnUninstallClick(Sender: TObject);
    procedure miAboutClick(Sender: TObject);
    procedure miRestoreClick(Sender: TObject);
    procedure miHideClick(Sender: TObject);
    procedure miExitClick(Sender: TObject);
    procedure TrayIconDblClick(Sender: TObject);
    procedure cbAuthClick(Sender: TObject);
    procedure rbDirectClick(Sender: TObject);
    procedure rbHttpClick(Sender: TObject);
    procedure rbSocksClick(Sender: TObject);
  private
    currentProcessDir: string;
    messageCaption: PChar;
    FExitRequested: Boolean;

    procedure SetWindowVisible(const AVisible: Boolean);
    function FindMostSuitableOptionsPath: string;
    procedure FindDiscordBaseDirs(list: TStringList);
    procedure FindDiscordDirs(list: TStringList);
    function GetNewestDiscordDir(list: TStringList): string;
    function IsDiscordRunning: boolean;
    function ShowDiscordRunningMessage: boolean;
    procedure ProcessProxyTypeRadioButtonValue;
    procedure ProcessAuthCheckBoxValue;
    function ValidateAndPrepareProxySettings(var url: string): boolean;
  public
    { Public declarations }
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.dfm}

procedure TfrmMain.FormCreate(Sender: TObject);
var
  optPath: string;
  opt: TDroverOptions;
  proxyValue: TProxyValue;
begin
  messageCaption := PChar(Application.Title);
  currentProcessDir := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));

  optPath := FindMostSuitableOptionsPath;

  if optPath <> '' then
  begin
    opt := LoadOptions(optPath);
  end
  else
  begin
    opt := Default (TDroverOptions);
    opt.proxy := '';
  end;

  proxyValue.ParseFromString(opt.proxy);

  rbHttp.Checked := proxyValue.isHttp;
  rbSocks.Checked := proxyValue.isSocks5;
  rbDirect.Checked := not proxyValue.isSpecified;

  eHost.Text := proxyValue.host;
  if proxyValue.port > 0 then
    ePort.Text := IntToStr(proxyValue.port)
  else
    ePort.Text := '';

  cbAuth.Checked := proxyValue.isAuth;
  eLogin.Text := proxyValue.login;
  ePassword.Text := proxyValue.password;

  ProcessProxyTypeRadioButtonValue;
end;

procedure TfrmMain.FormShow(Sender: TObject);
begin
  self.ActiveControl := btnInstall;
  TrayIcon.Visible := True;
end;

procedure TfrmMain.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  if FExitRequested then
  begin
    Action := caFree;
    exit;
  end;

  Action := caHide;
  SetWindowVisible(False);
end;

procedure TfrmMain.SetWindowVisible(const AVisible: Boolean);
begin
  if AVisible then
  begin
    Show;
    WindowState := wsNormal;
    TrayIcon.Visible := True;
  end
  else
  begin
    Hide;
    TrayIcon.Visible := True;
  end;
end;

procedure TfrmMain.miAboutClick(Sender: TObject);
begin
  ShellExecute(0, 'open', 'https://github.com/hdrover/discord-drover', nil, nil, SW_SHOWNORMAL);
end;

procedure TfrmMain.miRestoreClick(Sender: TObject);
begin
  SetWindowVisible(True);
  Application.BringToFront;
end;

procedure TfrmMain.miHideClick(Sender: TObject);
begin
  SetWindowVisible(False);
end;

procedure TfrmMain.miExitClick(Sender: TObject);
begin
  FExitRequested := True;
  Application.Terminate;
end;

procedure TfrmMain.TrayIconDblClick(Sender: TObject);
begin
  if Visible then
    SetWindowVisible(False)
  else
    SetWindowVisible(True);
end;

procedure TfrmMain.btnInstallClick(Sender: TObject);
var
  dirs, errors: TStringList;
  dir, dllPath, filename, srcPath, dstPath, s: string;
  TaskDialog: TTaskDialog;
  opt: TDroverOptions;
  extraFilenames: TArray<string>;
begin
  dllPath := currentProcessDir + DLL_FILENAME;
  if not FileExists(dllPath) then
  begin
    Application.MessageBox(PChar(Format('The file ''%s'' is missing.', [DLL_FILENAME])), messageCaption, MB_ICONERROR);
    exit;
  end;

  if not ValidateAndPrepareProxySettings(opt.proxy) then
    exit;

  if ShowDiscordRunningMessage then
    exit;

  dirs := TStringList.Create;
  errors := TStringList.Create;
  try
    FindDiscordDirs(dirs);
    if dirs.Count = 0 then
    begin
      Application.MessageBox('The Discord folder was not found.', messageCaption, MB_ICONERROR);
      exit;
    end;

    s := currentProcessDir + OPTIONS_FILENAME;
    if not SaveOptions(s, opt) then
      errors.Add(s);

    extraFilenames := GetExtraFilenames(currentProcessDir, false);

    for dir in dirs do
    begin
      s := dir + OPTIONS_FILENAME;
      if not SaveOptions(s, opt) then
        errors.Add(s);

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
  dir, filename, s: string;
  TaskDialog: TTaskDialog;
begin
  if ShowDiscordRunningMessage then
    exit;

  dirs := TStringList.Create;
  errors := TStringList.Create;
  try
    FindDiscordDirs(dirs);
    for dir in dirs do
      for filename in [OPTIONS_FILENAME, DLL_FILENAME] + GetExtraFilenames(dir, true) do
      begin
        s := dir + filename;
        if FileExists(s) and (not DeleteFile(s)) then
          errors.Add(s);
      end;

    if errors.Count > 0 then
    begin
      TaskDialog := TTaskDialog.Create(nil);
      try
        TaskDialog.Caption := messageCaption;
        TaskDialog.Title := 'Uninstallation error';
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
      Application.MessageBox('Uninstallation complete. All files have been successfully removed.', messageCaption,
        MB_ICONINFORMATION);
    end;
  finally
    dirs.Free;
    errors.Free;
  end;
end;

procedure TfrmMain.rbHttpClick(Sender: TObject);
begin
  ProcessProxyTypeRadioButtonValue;
end;

procedure TfrmMain.rbSocksClick(Sender: TObject);
begin
  ProcessProxyTypeRadioButtonValue;
end;

procedure TfrmMain.rbDirectClick(Sender: TObject);
begin
  ProcessProxyTypeRadioButtonValue;
end;

procedure TfrmMain.cbAuthClick(Sender: TObject);
begin
  ProcessAuthCheckBoxValue;
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
          begin
            list.Add(s);
          end;
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
  maxVer := Default (TVersion);

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

function TfrmMain.IsDiscordRunning: boolean;
var
  snapshot: THandle;
  processEntry: TProcessEntry32;
begin
  result := false;
  snapshot := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if snapshot = INVALID_HANDLE_VALUE then
    exit;

  try
    processEntry.dwSize := SizeOf(processEntry);
    if Process32First(snapshot, processEntry) then
    begin
      repeat
        if IsDiscordExecutable(ExtractFileName(processEntry.szExeFile)) then
        begin
          result := true;
          break;
        end;
      until not Process32Next(snapshot, processEntry);
    end;
  finally
    CloseHandle(snapshot);
  end;
end;

function TfrmMain.ShowDiscordRunningMessage: boolean;
begin
  if IsDiscordRunning then
  begin
    result := true;
    Application.MessageBox('Please exit Discord before proceeding.', messageCaption, MB_ICONERROR);
  end
  else
  begin
    result := false;
  end;
end;

procedure TfrmMain.ProcessProxyTypeRadioButtonValue;
var
  b: boolean;
begin
  b := not rbDirect.Checked;
  eHost.Enabled := b;
  lHost.Enabled := b;
  ePort.Enabled := b;
  lPort.Enabled := b;
  cbAuth.Enabled := b;

  ProcessAuthCheckBoxValue;
end;

procedure TfrmMain.ProcessAuthCheckBoxValue;
var
  b: boolean;
begin
  b := cbAuth.Checked and cbAuth.Enabled;
  eLogin.Enabled := b;
  lLogin.Enabled := b;
  ePassword.Enabled := b;
  lPassword.Enabled := b;
end;

function TfrmMain.ValidateAndPrepareProxySettings(var url: string): boolean;
const
  PROTO_SOCKS5 = 'socks5';
var
  s: string;
  isAuth: boolean;
  proto, host, login, password: string;
  port: integer;
begin
  url := '';

  if rbDirect.Checked then
    exit(true);

  result := false;

  proto := '';
  if rbHttp.Checked then
    proto := 'http';
  if rbSocks.Checked then
    proto := PROTO_SOCKS5;

  host := Trim(eHost.Text);
  port := StrToIntDef(Trim(ePort.Text), 0);
  isAuth := cbAuth.Checked;
  login := Trim(eLogin.Text);
  password := Trim(ePassword.Text);

  if proto = '' then
  begin
    Application.MessageBox('Protocol is not specified.', messageCaption, MB_ICONERROR);
    exit;
  end;
  if host = '' then
  begin
    Application.MessageBox('Invalid host specified.', messageCaption, MB_ICONERROR);
    exit;
  end;
  if (port < 1) or (port > 65535) then
  begin
    Application.MessageBox('Invalid port specified.', messageCaption, MB_ICONERROR);
    exit;
  end;

  if isAuth then
  begin
    if proto = PROTO_SOCKS5 then
    begin
      Application.MessageBox
        ('Authentication for SOCKS5 is not supported in the current version. Please use an unprotected proxy or switch to HTTP if authentication is required.',
        messageCaption, MB_ICONERROR);
      exit;
    end;
    if (login = '') or (password = '') then
    begin
      Application.MessageBox('Fill in Login and Password or uncheck Authentication.', messageCaption, MB_ICONERROR);
      exit;
    end;
  end;

  s := proto + '://';
  if isAuth then
    s := s + login + ':' + password + '@';
  s := s + host + ':' + IntToStr(port);

  url := s;

  result := true;
end;

end.
