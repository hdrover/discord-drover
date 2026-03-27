library drover;

uses
  System.SysUtils,
  Winapi.Windows,
  DDetours,
  PsAPI,
  TlHelp32,
  WinSock,
  WinSock2,
  IniFiles,
  System.RegularExpressions,
  System.NetEncoding,
  SocketManager,
  Options,
  System.IOUtils,
  Classes,
  DiscordFolders;

var
  RealGetFileVersionInfoA: pointer;
  RealGetFileVersionInfoByHandle: pointer;
  RealGetFileVersionInfoExA: pointer;
  RealGetFileVersionInfoExW: pointer;
  RealGetFileVersionInfoSizeA: pointer;
  RealGetFileVersionInfoSizeExA: pointer;
  RealGetFileVersionInfoSizeExW: pointer;
  RealGetFileVersionInfoSizeW: pointer;
  RealGetFileVersionInfoW: pointer;
  RealVerFindFileA: pointer;
  RealVerFindFileW: pointer;
  RealVerInstallFileA: pointer;
  RealVerInstallFileW: pointer;
  RealVerLanguageNameA: pointer;
  RealVerLanguageNameW: pointer;
  RealVerQueryValueA: pointer;
  RealVerQueryValueW: pointer;

  RealGetEnvironmentVariableW: function(lpName: LPCWSTR; lpBuffer: LPWSTR; nSize: DWORD): DWORD; stdcall;
  RealCreateProcessW: function(lpApplicationName: LPCWSTR; lpCommandLine: LPWSTR;
    lpProcessAttributes, lpThreadAttributes: PSecurityAttributes; bInheritHandles: bool; dwCreationFlags: DWORD;
    lpEnvironment: pointer; lpCurrentDirectory: LPCWSTR; const lpStartupInfo: TStartupInfoW;
    var lpProcessInformation: TProcessInformation): bool; stdcall;
  RealGetCommandLineW: function: LPWSTR; stdcall;

  RealSocket: function(af, type_, protocol: integer): TSocket; stdcall;
  RealWSASocket: function(af, type_, protocol: integer; lpProtocolInfo: LPWSAPROTOCOL_INFO; g: GROUP; dwFlags: DWORD)
    : TSocket; stdcall;
  RealWSASend: function(s: TSocket; lpBuffers: LPWSABUF; dwBufferCount: DWORD; lpNumberOfBytesSent: PDWORD;
    dwFlags: DWORD; lpOverlapped: LPWSAOVERLAPPED; lpCompletionRoutine: LPWSAOVERLAPPED_COMPLETION_ROUTINE)
    : integer; stdcall;
  RealWSASendTo: function(s: TSocket; lpBuffers: LPWSABUF; dwBufferCount: DWORD; lpNumberOfBytesSent: LPDWORD;
    dwFlags: DWORD; const lpTo: TSockAddr; iTolen: integer; lpOverlapped: LPWSAOVERLAPPED;
    lpCompletionRoutine: LPWSAOVERLAPPED_COMPLETION_ROUTINE): integer; stdcall;
  RealSend: function(s: TSocket; const buf; len, flags: integer): integer; stdcall;
  RealRecv: function(s: TSocket; var buf; len, flags: integer): integer; stdcall;

  currentProcessDir: string;
  sockManager: TSocketManager;
  droverOptions: TDroverOptions;
  proxyValue: TProxyValue;
  initComplete: boolean;
  threadId: DWORD;
  hInitThread: THandle;
  commandLineCache: string;

procedure MyGetFileVersionInfoA;
asm
  JMP [RealGetFileVersionInfoA]
end;

procedure MyGetFileVersionInfoByHandle;
asm
  JMP [RealGetFileVersionInfoByHandle]
end;

procedure MyGetFileVersionInfoExA;
asm
  JMP [RealGetFileVersionInfoExA]
end;

procedure MyGetFileVersionInfoExW;
asm
  JMP [RealGetFileVersionInfoExW]
end;

procedure MyGetFileVersionInfoSizeA;
asm
  JMP [RealGetFileVersionInfoSizeA]
end;

procedure MyGetFileVersionInfoSizeExA;
asm
  JMP [RealGetFileVersionInfoSizeExA]
end;

procedure MyGetFileVersionInfoSizeExW;
asm
  JMP [RealGetFileVersionInfoSizeExW]
end;

procedure MyGetFileVersionInfoSizeW;
asm
  JMP [RealGetFileVersionInfoSizeW]
end;

procedure MyGetFileVersionInfoW;
asm
  JMP [RealGetFileVersionInfoW]
end;

procedure MyVerFindFileA;
asm
  JMP [RealVerFindFileA]
end;

procedure MyVerFindFileW;
asm
  JMP [RealVerFindFileW]
end;

procedure MyVerInstallFileA;
asm
  JMP [RealVerInstallFileA]
end;

procedure MyVerInstallFileW;
asm
  JMP [RealVerInstallFileW]
end;

procedure MyVerLanguageNameA;
asm
  JMP [RealVerLanguageNameA]
end;

procedure MyVerLanguageNameW;
asm
  JMP [RealVerLanguageNameW]
end;

procedure MyVerQueryValueA;
asm
  JMP [RealVerQueryValueA]
end;

procedure MyVerQueryValueW;
asm
  JMP [RealVerQueryValueW]
end;

function MyGetEnvironmentVariableW(lpName: LPCWSTR; lpBuffer: LPWSTR; nSize: DWORD): DWORD; stdcall;
var
  s: string;
  newValue: string;
  requiredSize: DWORD;
begin
  if proxyValue.isSpecified then
  begin
    s := lpName;
    if (Pos('http_proxy', s) > 0) or (Pos('HTTP_PROXY', s) > 0) or (Pos('https_proxy', s) > 0) or
      (Pos('HTTPS_PROXY', s) > 0) then
    begin
      newValue := proxyValue.FormatToHttpEnv;
      requiredSize := DWORD(Length(newValue)) + 1;
      if (lpBuffer = nil) or (nSize < requiredSize) then
        exit(requiredSize);
      StringToWideChar(newValue, lpBuffer, nSize);
      result := Length(newValue);
      exit;
    end;
  end;

  result := RealGetEnvironmentVariableW(lpName, lpBuffer, nSize);
end;

procedure FindDiscordDirs(list: TStringList);
var
  subdirs: TArray<string>;
  s, subdir, baseDir: string;
begin
  baseDir := IncludeTrailingPathDelimiter(ExtractFilePath(ExcludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)))));
  if TDirectory.Exists(baseDir) then
  begin
    subdirs := TDirectory.GetDirectories(baseDir, 'app-*', TSearchOption.soTopDirectoryOnly);
    for subdir in subdirs do
    begin
      s := IncludeTrailingPathDelimiter(subdir);
      if DirHasDiscordExecutable(s) then
      begin
        list.Add(s);
      end;
    end;
  end;
end;

procedure CopyFilesToAllDiscordDirs;
var
  dirs: TStringList;
  dir: string;
  srcOptionsPath, srcDllPath, dstOptionsPath, dstDllPath: string;
begin
  srcOptionsPath := currentProcessDir + OPTIONS_FILENAME;
  srcDllPath := currentProcessDir + DLL_FILENAME;

  if not FileExists(srcOptionsPath) or not FileExists(srcDllPath) then
    exit;

  dirs := TStringList.Create;
  try
    FindDiscordDirs(dirs);

    for dir in dirs do
    begin
      dstOptionsPath := dir + OPTIONS_FILENAME;
      dstDllPath := dir + DLL_FILENAME;

      if DirHasDiscordExecutable(dir) and not FileExists(dstOptionsPath) and not FileExists(dstDllPath) then
      begin
        CopyFile(PChar(srcOptionsPath), PChar(dstOptionsPath), true);
        CopyFile(PChar(srcDllPath), PChar(dstDllPath), true);
      end;
    end;
  finally
    dirs.Free;
  end;
end;

procedure CopyFilesOnCreateProcessIfNeeded(lpApplicationName: LPCWSTR);
var
  appName: string;
begin
  if lpApplicationName = nil then
    exit;

  appName := ExtractFileName(lpApplicationName);

  if IsDiscordExecutable(appName) or SameText(appName, 'reg.exe') then
    CopyFilesToAllDiscordDirs;
end;

function MyCreateProcessW(lpApplicationName: LPCWSTR; lpCommandLine: LPWSTR;
  lpProcessAttributes, lpThreadAttributes: PSecurityAttributes; bInheritHandles: bool; dwCreationFlags: DWORD;
  lpEnvironment: pointer; lpCurrentDirectory: LPCWSTR; const lpStartupInfo: TStartupInfoW;
  var lpProcessInformation: TProcessInformation): bool; stdcall;
begin
  CopyFilesOnCreateProcessIfNeeded(lpApplicationName);

  result := RealCreateProcessW(lpApplicationName, lpCommandLine, lpProcessAttributes, lpThreadAttributes,
    bInheritHandles, dwCreationFlags, lpEnvironment, lpCurrentDirectory, lpStartupInfo, lpProcessInformation);
end;

function MyGetCommandLineW: LPWSTR; stdcall;
begin
  commandLineCache := RealGetCommandLineW;
  if proxyValue.isSpecified then
  begin
    if IsDiscordExecutable(ExtractFileName(ParamStr(0))) then
      commandLineCache := commandLineCache + ' --proxy-server=' + proxyValue.FormatToChromeProxy;
  end;
  result := PChar(commandLineCache);
end;

function MySocket(af, type_, protocol: integer): TSocket; stdcall;
begin
  result := RealSocket(af, type_, protocol);
  if initComplete then
    sockManager.Add(result, type_, protocol);
end;

function MyWSASocket(af, type_, protocol: integer; lpProtocolInfo: LPWSAPROTOCOL_INFO; g: GROUP; dwFlags: DWORD)
  : TSocket; stdcall;
begin
  result := RealWSASocket(af, type_, protocol, lpProtocolInfo, g, dwFlags);
  if initComplete then
    sockManager.Add(result, type_, protocol);
end;

function AddHttpProxyAuthorizationHeader(socketManagerItem: TSocketManagerItem; lpBuffers: LPWSABUF;
  dwBufferCount: DWORD; lpNumberOfBytesSent: PDWORD; dwFlags: DWORD; lpOverlapped: LPWSAOVERLAPPED;
  lpCompletionRoutine: LPWSAOVERLAPPED_COMPLETION_ROUTINE): boolean;
var
  pck, injectedData, filler: RawByteString;
  uaStartPos, uaEndPos, uaLen, fillerLen: integer;
begin
  result := false;

  if (not proxyValue.isSpecified) or (not proxyValue.isHttp) or (not proxyValue.isAuth) or (not socketManagerItem.isTcp)
  then
    exit;

  if (dwBufferCount <> 1) or (lpBuffers.len < 1) then
    exit;

  SetLength(pck, lpBuffers.len);
  Move(lpBuffers.buf^, pck[1], lpBuffers.len);

  if Pos(RawByteString(#13#10 + 'Proxy-Authorization: '), pck) > 0 then
    exit;

  uaStartPos := Pos(RawByteString('User-Agent:'), pck);
  if uaStartPos < 1 then
    exit;

  uaEndPos := Pos(RawByteString(#13#10), pck, uaStartPos);
  if uaEndPos < 1 then
    exit;

  uaLen := uaEndPos - uaStartPos;

  injectedData := 'Proxy-Authorization: Basic ' +
    RawByteString(TNetEncoding.Base64.EncodeBytesToString(BytesOf(RawByteString(proxyValue.login + ':' +
    proxyValue.password))));

  fillerLen := uaLen - Length(injectedData);
  if fillerLen < 6 then
    exit;

  filler := #13#10 + 'X: ' + RawByteString(StringOfChar('X', fillerLen - 5));
  injectedData := injectedData + filler;
  if Length(injectedData) <> uaLen then
    exit;

  Move(injectedData[1], pck[uaStartPos], uaLen);
  Move(pck[1], lpBuffers.buf^, lpBuffers.len);

  result := true;
end;

function MyWSASend(sock: TSocket; lpBuffers: LPWSABUF; dwBufferCount: DWORD; lpNumberOfBytesSent: PDWORD;
  dwFlags: DWORD; lpOverlapped: LPWSAOVERLAPPED; lpCompletionRoutine: LPWSAOVERLAPPED_COMPLETION_ROUTINE)
  : integer; stdcall;
var
  sockManagerItem: TSocketManagerItem;
begin
  if initComplete and sockManager.IsFirstSend(sock, sockManagerItem) then
  begin
    AddHttpProxyAuthorizationHeader(sockManagerItem, lpBuffers, dwBufferCount, lpNumberOfBytesSent, dwFlags,
      lpOverlapped, lpCompletionRoutine);
  end;

  result := RealWSASend(sock, lpBuffers, dwBufferCount, lpNumberOfBytesSent, dwFlags, lpOverlapped,
    lpCompletionRoutine);
end;

function MyWSASendTo(sock: TSocket; lpBuffers: LPWSABUF; dwBufferCount: DWORD; lpNumberOfBytesSent: LPDWORD;
  dwFlags: DWORD; const lpTo: TSockAddr; iTolen: integer; lpOverlapped: LPWSAOVERLAPPED;
  lpCompletionRoutine: LPWSAOVERLAPPED_COMPLETION_ROUTINE): integer; stdcall;
var
  payload: byte;
  sockManagerItem: TSocketManagerItem;
begin
  if initComplete and sockManager.IsFirstSend(sock, sockManagerItem) then
  begin
    if sockManagerItem.isUdp and (lpBuffers.len = 74) then
    begin
      payload := 0;
      sendto(sock, pointer(@payload)^, 1, 0, @lpTo, iTolen);
      payload := 1;
      sendto(sock, pointer(@payload)^, 1, 0, @lpTo, iTolen);
      Sleep(50);
    end;
  end;

  result := RealWSASendTo(sock, lpBuffers, dwBufferCount, lpNumberOfBytesSent, dwFlags, lpTo, iTolen, lpOverlapped,
    lpCompletionRoutine);
end;

function ConvertHttpToSocks5(socketManagerItem: TSocketManagerItem; const buf; len, flags: integer): boolean;
var
  s, targetHost: RawByteString;
  targetPort: word;
  fdSet: TFDSet;
  tv: TTimeVal;
  i: integer;
  match: TMatch;
  sock: TSocket;
begin
  result := false;

  if (not proxyValue.isSpecified) or (not proxyValue.isSocks5) or (not socketManagerItem.isTcp) then
    exit;

  i := 8;
  if len < i then
    exit;
  SetLength(s, i);
  Move(buf, s[1], i);
  if s <> 'CONNECT ' then
    exit;

  SetLength(s, len);
  Move(buf, s[1], len);
  match := TRegEx.match(string(s), '\ACONNECT ([a-z\d.-]+):(\d+)', [roIgnoreCase]);
  if not match.Success then
    exit;
  targetHost := RawByteString(match.Groups[1].Value);
  targetPort := StrToIntDef(match.Groups[2].Value, 0);

  sock := socketManagerItem.sock;

  s := #$05#$01#$00;
  i := Length(s);
  if RealSend(sock, s[1], i, flags) <> i then
    exit;

  FD_ZERO(fdSet);
  _FD_SET(sock, fdSet);
  tv.tv_sec := 10;
  tv.tv_usec := 0;

  if select(0, @fdSet, nil, nil, @tv) < 1 then
    exit;
  if not FD_ISSET(sock, fdSet) then
    exit;

  i := 2;
  SetLength(s, i);
  if RealRecv(sock, s[1], i, 0) <> i then
    exit;

  if s <> #$05#$00 then
    exit;

  s := #$05#$01#$00#$03 + RawByteString(AnsiChar(Length(targetHost))) + targetHost +
    RawByteString(AnsiChar(Hi(targetPort))) + RawByteString(AnsiChar(Lo(targetPort)));
  i := Length(s);
  if RealSend(sock, s[1], i, flags) <> i then
    exit;

  sockManager.SetFakeHttpProxyFlag(sock);

  result := true;
end;

function MySend(sock: TSocket; const buf; len, flags: integer): integer; stdcall;
var
  sockManagerItem: TSocketManagerItem;
begin
  if initComplete and sockManager.IsFirstSend(sock, sockManagerItem) then
  begin
    if ConvertHttpToSocks5(sockManagerItem, buf, len, flags) then
      exit(len);
  end;

  result := RealSend(sock, buf, len, flags);
end;

function MyRecv(sock: TSocket; var buf; len, flags: integer): integer; stdcall;
var
  s: RawByteString;
  i: integer;
begin
  result := RealRecv(sock, buf, len, flags);

  if initComplete and (result > 0) and sockManager.ResetFakeHttpProxyFlag(sock) then
  begin
    if result >= 10 then
    begin
      SetLength(s, result);
      Move(buf, s[1], result);
      if Copy(s, 1, 3) = #$05#$00#$00 then
      begin
        s := 'HTTP/1.1 200 Connection Established' + #13#10 + #13#10;
        i := Length(s);
        if i <= len then
        begin
          Move(s[1], buf, i);
          exit(i);
        end;
      end;
    end;
  end;
end;

function GetSystemFolder: string;
var
  s: string;
begin
  SetLength(s, MAX_PATH);
  GetSystemDirectory(PChar(s), MAX_PATH);
  result := IncludeTrailingPathDelimiter(PChar(s));
end;

procedure LoadOriginalVersionDll;
var
  hOriginal: THandle;
begin
  hOriginal := LoadLibrary(PChar(GetSystemFolder + 'version.dll'));
  if hOriginal = 0 then
    raise Exception.Create('Error.');

  RealGetFileVersionInfoA := GetProcAddress(hOriginal, 'GetFileVersionInfoA');
  RealGetFileVersionInfoByHandle := GetProcAddress(hOriginal, 'GetFileVersionInfoByHandle');
  RealGetFileVersionInfoExA := GetProcAddress(hOriginal, 'GetFileVersionInfoExA');
  RealGetFileVersionInfoExW := GetProcAddress(hOriginal, 'GetFileVersionInfoExW');
  RealGetFileVersionInfoSizeA := GetProcAddress(hOriginal, 'GetFileVersionInfoSizeA');
  RealGetFileVersionInfoSizeExA := GetProcAddress(hOriginal, 'GetFileVersionInfoSizeExA');
  RealGetFileVersionInfoSizeExW := GetProcAddress(hOriginal, 'GetFileVersionInfoSizeExW');
  RealGetFileVersionInfoSizeW := GetProcAddress(hOriginal, 'GetFileVersionInfoSizeW');
  RealGetFileVersionInfoW := GetProcAddress(hOriginal, 'GetFileVersionInfoW');
  RealVerFindFileA := GetProcAddress(hOriginal, 'VerFindFileA');
  RealVerFindFileW := GetProcAddress(hOriginal, 'VerFindFileW');
  RealVerInstallFileA := GetProcAddress(hOriginal, 'VerInstallFileA');
  RealVerInstallFileW := GetProcAddress(hOriginal, 'VerInstallFileW');
  RealVerLanguageNameA := GetProcAddress(hOriginal, 'VerLanguageNameA');
  RealVerLanguageNameW := GetProcAddress(hOriginal, 'VerLanguageNameW');
  RealVerQueryValueA := GetProcAddress(hOriginal, 'VerQueryValueA');
  RealVerQueryValueW := GetProcAddress(hOriginal, 'VerQueryValueW');
end;

function IsNekoBoxExists: bool;
var
  hSnapshot: THandle;
  pe32: TProcessEntry32;
  processName: string;
begin
  result := false;
  hSnapshot := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if hSnapshot = INVALID_HANDLE_VALUE then
    exit;
  try
    pe32.dwSize := SizeOf(TProcessEntry32);

    if Process32First(hSnapshot, pe32) then
    begin
      repeat
        processName := LowerCase(StrPas(pe32.szExeFile));
        if (Pos('nekobox', processName) > 0) or (Pos('nekoray', processName) > 0) then
        begin
          result := true;
          exit;
        end;

      until not Process32Next(hSnapshot, pe32);
    end;
  finally
    CloseHandle(hSnapshot);
  end;
end;

function DeferredInitThread(param: pointer): DWORD; stdcall;
begin
  result := 0;
  try
    sockManager := TSocketManager.Create;

    droverOptions := LoadOptions(currentProcessDir + OPTIONS_FILENAME);

    if droverOptions.useNekoboxProxy and IsNekoBoxExists then
      proxyValue.ParseFromString(droverOptions.nekoboxProxy)
    else
      proxyValue.ParseFromString(droverOptions.proxy);

    RealGetEnvironmentVariableW := InterceptCreate(@GetEnvironmentVariableW, @MyGetEnvironmentVariableW, nil);
    RealCreateProcessW := InterceptCreate(@CreateProcessW, @MyCreateProcessW, nil);
    RealGetCommandLineW := InterceptCreate(@GetCommandLineW, @MyGetCommandLineW, nil);

    RealSocket := InterceptCreate(@socket, @MySocket, nil);
    RealWSASocket := InterceptCreate(@WSASocket, @MyWSASocket, nil);
    RealWSASend := InterceptCreate(@WSASend, @MyWSASend, nil);
    RealWSASendTo := InterceptCreate(@WSASendTo, @MyWSASendTo, nil);
    RealSend := InterceptCreate(@send, @MySend, nil);
    RealRecv := InterceptCreate(@recv, @MyRecv, nil);

    MemoryBarrier;
    initComplete := true;
  except
    on E: Exception do
    begin
      try
        TFile.WriteAllText(currentProcessDir + 'drover-error.log',
          DateTimeToStr(Now) + ': ' + E.ClassName + ': ' + E.Message);
      except
      end;
    end;
  end;
end;

exports
  MyGetFileVersionInfoA index 1 name 'GetFileVersionInfoA',
  MyGetFileVersionInfoByHandle index 2 name 'GetFileVersionInfoByHandle',
  MyGetFileVersionInfoExA index 3 name 'GetFileVersionInfoExA',
  MyGetFileVersionInfoExW index 4 name 'GetFileVersionInfoExW',
  MyGetFileVersionInfoSizeA index 5 name 'GetFileVersionInfoSizeA',
  MyGetFileVersionInfoSizeExA index 6 name 'GetFileVersionInfoSizeExA',
  MyGetFileVersionInfoSizeExW index 7 name 'GetFileVersionInfoSizeExW',
  MyGetFileVersionInfoSizeW index 8 name 'GetFileVersionInfoSizeW',
  MyGetFileVersionInfoW index 9 name 'GetFileVersionInfoW',
  MyVerFindFileA index 10 name 'VerFindFileA',
  MyVerFindFileW index 11 name 'VerFindFileW',
  MyVerInstallFileA index 12 name 'VerInstallFileA',
  MyVerInstallFileW index 13 name 'VerInstallFileW',
  MyVerLanguageNameA index 14 name 'VerLanguageNameA',
  MyVerLanguageNameW index 15 name 'VerLanguageNameW',
  MyVerQueryValueA index 16 name 'VerQueryValueA',
  MyVerQueryValueW index 17 name 'VerQueryValueW';

begin
  initComplete := false;
  currentProcessDir := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));

  LoadOriginalVersionDll;

  DisableThreadLibraryCalls(HInstance);
  hInitThread := CreateThread(nil, 0, @DeferredInitThread, nil, 0, threadId);
  if hInitThread <> 0 then
    CloseHandle(hInitThread);
end.
