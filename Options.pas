unit Options;

interface

uses
  System.SysUtils,
  System.IniFiles,
  System.RegularExpressions;

const
  DLL_FILENAME = 'version.dll';
  OPTIONS_FILENAME = 'drover.ini';

type
  TDroverOptions = record
    proxy: string;
    useNekoboxProxy: boolean;
    nekoboxProxy: string;
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

function LoadOptions(filename: string): TDroverOptions;
function SaveOptions(filename: string; opt: TDroverOptions): boolean;

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
  result := Default (TDroverOptions);

  try
    f := TIniFile.Create(filename);
    try
      with f do
      begin
        result.proxy := ReadString('drover', 'proxy', '');
        result.useNekoboxProxy := ReadBool('drover', 'use-nekobox-proxy', false);
        result.nekoboxProxy := ReadString('drover', 'nekobox-proxy', '127.0.0.1:2080');
      end;
    finally
      f.Free;
    end;
  except
  end;
end;

function SaveOptions(filename: string; opt: TDroverOptions): boolean;
var
  f: TextFile;
begin
  try
    AssignFile(f, filename);
    try
      Rewrite(f);
      WriteLn(f, '[drover]');
      WriteLn(f, Trim('proxy = ' + opt.proxy));
    finally
      CloseFile(f);
    end;
    result := true;
  except
    result := false;
  end;
end;

end.
