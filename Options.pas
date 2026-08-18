unit Options;

interface

uses
  System.SysUtils,
  System.IniFiles,
  System.RegularExpressions;

const
  DLL_FILENAME = 'version.dll';
  OPTIONS_FILENAME = 'drover.ini';
  PACKET_FILENAME = 'drover-packet.bin';

type
  TDroverOptions = record
    proxy: string;
    torExecutable: string;
    autoStartTor: boolean;
    tempTorMode: boolean;
    torWarmupSeconds: integer;
    notifyOnDirectMode: boolean;
  end;

  TProxyValue = record
    isSpecified: boolean;
    prot: string;
    login: string;
    password: string;
    host: string;
    port: integer;
    isHttp: boolean;
    isSocks5: boolean;
    isAuth: boolean;

    procedure ParseFromString(url: string);
    function FormatToHttpEnv: string;
    function FormatToChromeProxy: string;
  end;

function CreateDefaultOptions: TDroverOptions; forward;
function LoadOptions(filename: string): TDroverOptions;
function SaveOptions(filename: string; opt: TDroverOptions): boolean;
function GetExtraFilenames(const dir: string; forUninstall: boolean): TArray<string>;

implementation

procedure TProxyValue.ParseFromString(url: string);
var
  match: TMatch;
begin
  isSpecified := false;
  prot := '';
  login := '';
  password := '';
  host := '';
  port := 0;
  isHttp := false;
  isSocks5 := false;
  isAuth := false;

  match := TRegEx.match(Trim(url), '\A(?:([a-z\d]+)://)?(?:(.+):(.+)@)?(.+):(\d+)\z', [roIgnoreCase]);
  if not match.Success then
    exit;

  isSpecified := true;

  prot := LowerCase(Trim(match.Groups[1].Value));
  if (prot = '') or (prot = 'https') then
    prot := 'http';

  login := Trim(match.Groups[2].Value);
  password := Trim(match.Groups[3].Value);

  host := Trim(match.Groups[4].Value);
  port := StrToIntDef(match.Groups[5].Value, 0);

  isHttp := (prot = 'http');
  isSocks5 := (prot = 'socks5');
  isAuth := (login <> '') and (password <> '');
end;

function TProxyValue.FormatToHttpEnv: string;
begin
  if not isSpecified then
    exit('');

  result := 'http://';
  if isAuth then
    result := result + login + ':' + password + '@';
  result := result + host + ':' + IntToStr(port);
end;

function TProxyValue.FormatToChromeProxy: string;
begin
  if isSpecified then
    result := Format('%s://%s:%d', [prot, host, port])
  else
    result := '';
end;

function LoadOptions(filename: string): TDroverOptions;
var
  f: TIniFile;
begin
  // ✅ Sempre começar com valores padrão corretos
  result := CreateDefaultOptions;

  try
    if not FileExists(filename) then
      exit;  // Retorna com defaults corretos

    f := TIniFile.Create(filename);
    try
      with f do
      begin
        result.proxy := ReadString('drover', 'proxy', result.proxy);
        result.torExecutable := ReadString('drover', 'tor', result.torExecutable);
        result.autoStartTor := ReadBool('drover', 'autostart_tor', result.autoStartTor);
        result.tempTorMode := ReadBool('drover', 'temp_tor_mode', result.tempTorMode);
        result.torWarmupSeconds := ReadInteger('drover', 'tor_warmup_seconds', result.torWarmupSeconds);
        result.notifyOnDirectMode := ReadBool('drover', 'notify_on_direct_mode', result.notifyOnDirectMode);
      end;
    finally
      f.Free;
    end;
  except
    // Se houver erro lendo o arquivo, retorna com defaults
  end;
end;

function GetExtraFilenames(const dir: string; forUninstall: boolean): TArray<string>;
begin
  result := [PACKET_FILENAME];
end;

function CreateDefaultOptions: TDroverOptions;
begin
  // Handler de valores padrão: Tor permanente, sem desconectar
  result.proxy := 'socks5://127.0.0.1:9050';
  result.torExecutable := '';  // Será encontrado em drover-tor\tor.exe
  result.autoStartTor := true;  // ✅ Sempre inicia Tor
  result.tempTorMode := false;  // ✅ Tor PERMANENTE (não desconecta)
  result.torWarmupSeconds := 20;
  result.notifyOnDirectMode := false;
end;

function SaveOptions(filename: string; opt: TDroverOptions): boolean;
var
  f: TIniFile;
  dir: string;
begin
  result := false;
  try
    // ✅ Garantir que o diretório existe
    dir := ExtractFileDir(filename);
    if (dir <> '') and not DirectoryExists(dir) then
    begin
      try
        ForceDirectories(dir);
      except
        exit(false);
      end;
    end;

    // ✅ Usar TIniFile que é mais robusto que TextFile
    f := TIniFile.Create(filename);
    try
      with f do
      begin
        WriteString('drover', 'proxy', opt.proxy);
        
        if Trim(opt.torExecutable) <> '' then
          WriteString('drover', 'tor', opt.torExecutable);
        
        WriteBool('drover', 'autostart_tor', opt.autoStartTor);
        WriteBool('drover', 'temp_tor_mode', opt.tempTorMode);  // ✅ SEMPRE salvar
        WriteInteger('drover', 'tor_warmup_seconds', opt.torWarmupSeconds);
        WriteBool('drover', 'notify_on_direct_mode', opt.notifyOnDirectMode);
      end;
      result := true;
    finally
      f.Free;
    end;
  except
    result := false;
  end;
end;

end.
