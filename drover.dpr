library drover;

uses
  System.SysUtils,
  Winapi.Windows,
  DDetours,
  PsAPI,
  TlHelp32,
  WinSock,
  WinSock2,
  System.IniFiles,
  System.RegularExpressions,
  System.NetEncoding,
  SocketManager,
  Options,
  System.IOUtils,
  Classes,
  SyncObjs,
  DiscordFolders,
  DroverProxy;

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
  RealConnect: function(s: TSocket; const name: TSockAddr; namelen: integer): integer; stdcall;
  RealCloseSocket: function(s: TSocket): integer; stdcall;

  currentProcessDir: string;
  sockManager: TSocketManager;
  droverOptions: TDroverOptions;
  proxyValue: TProxyValue;
  commandLineCache: string;
  currentMode: TDroverMode;
  modeCS: TCriticalSection;
  torProcessInfo: TProcessInformation;
  torProcessStarted: boolean;
  localProxyActive: boolean;
  detectedTorPort: word;
  isMainDiscordProcess: boolean;

procedure ForceCutTorConnections; forward;
function GetCurrentMode: TDroverMode; forward;
function DetectTorSocksPort: word; forward;

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
    if SameText(s, 'http_proxy') or SameText(s, 'https_proxy') then
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
  dir, filename, srcPath: string;
  srcOptionsPath, srcDllPath, dstOptionsPath, dstDllPath: string;
  extraFilenames: TArray<string>;
begin
  srcOptionsPath := currentProcessDir + OPTIONS_FILENAME;
  srcDllPath := currentProcessDir + DLL_FILENAME;

  if not FileExists(srcOptionsPath) or not FileExists(srcDllPath) then
    exit;

  extraFilenames := GetExtraFilenames(currentProcessDir, false);

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

        for filename in extraFilenames do
        begin
          srcPath := currentProcessDir + filename;
          if FileExists(srcPath) then
            CopyFile(PChar(srcPath), PChar(dir + filename), true);
        end;
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

procedure BuildCommandLineCache;
var
  s: string;
begin
  if Assigned(RealGetCommandLineW) then
    s := RealGetCommandLineW
  else
    s := GetCommandLineW;
  if proxyValue.isSpecified then
  begin
    if IsDiscordExecutable(ExtractFileName(ParamStr(0))) then
      // ✅ Usa detectedTorPort — a porta REAL que o Tor abriu (9050 ou 9150),
      // descoberta por probe-connect. proxyValue.FormatToChromeProxy embutiria a
      // porta fixa do .ini (sempre 9050), que pode nao ser a porta real do Tor.
      s := s + ' --proxy-server=socks5://' + proxyValue.host + ':' + IntToStr(detectedTorPort);
  end;
  commandLineCache := s;
end;

function MyGetCommandLineW: LPWSTR; stdcall;
begin
  result := PChar(commandLineCache);
end;

function MySocket(af, type_, protocol: integer): TSocket; stdcall;
begin
  result := RealSocket(af, type_, protocol);
  if droverOptions.tempTorMode then
    sockManager.Add(result, type_, protocol, GetCurrentMode)
  else
    sockManager.Add(result, type_, protocol, dmTor); // comportamento antigo intacto se o toggle tá off
end;

function MyWSASocket(af, type_, protocol: integer; lpProtocolInfo: LPWSAPROTOCOL_INFO; g: GROUP; dwFlags: DWORD)
  : TSocket; stdcall;
begin
  result := RealWSASocket(af, type_, protocol, lpProtocolInfo, g, dwFlags);
  if droverOptions.tempTorMode then
    sockManager.Add(result, type_, protocol, GetCurrentMode)
  else
    sockManager.Add(result, type_, protocol, dmTor);
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

  if (lpBuffers = nil) or (dwBufferCount <> 1) or (lpBuffers.len < 1) then
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
  if sockManager.IsFirstSend(sock, sockManagerItem) then
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
  packetData: TBytes;
  packetPath: string;
begin
  if sockManager.IsFirstSend(sock, sockManagerItem) then
  begin
    if sockManagerItem.isUdp and (lpBuffers <> nil) and (dwBufferCount > 0) and (lpBuffers.len = 74) then
    begin
      packetPath := currentProcessDir + PACKET_FILENAME;
      if FileExists(packetPath) then
      begin
        try
          packetData := TFile.ReadAllBytes(packetPath);
          if Length(packetData) > 0 then
            sendto(sock, packetData[0], Length(packetData), 0, @lpTo, iTolen);
        except
        end;
      end;
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

function GetCurrentMode: TDroverMode;
begin
  if modeCS <> nil then
  begin
    modeCS.Enter;
    try
      result := currentMode;
    finally
      modeCS.Leave;
    end;
  end
  else
    result := dmTor;
end;

procedure SetCurrentMode(m: TDroverMode);
begin
  if modeCS <> nil then
  begin
    modeCS.Enter;
    try
      currentMode := m;
    finally
      modeCS.Leave;
    end;
  end
  else
    currentMode := m;
end;

type
  TModeSwitchThread = class(TThread)
  protected
    procedure Execute; override;
  end;

procedure TModeSwitchThread.Execute;
var
  warmup: integer;
  proxyPortW: word;
begin
  warmup := droverOptions.torWarmupSeconds;
  if warmup <= 0 then
    warmup := 20;

  Sleep(warmup * 1000);

  SetCurrentMode(dmDirect);

  // ✅ NOVA ORDEM:
  // 1. Mata o Tor PRIMEIRO (libera a porta 9050/9150).
  // 2. Sobe o listener SOCKS5 local nessa porta (com retry de bind).
  // 3. SÓ DEPOIS corta os sockets do Discord (ForceCutTorConnections).
  //    Assim, quando o Discord detecta a queda e reconecta, a porta já tá
  //    sendo atendida por nós — evita WSAECONNREFUSED que faria o Discord
  //    marcar o proxy como morto e ficar "carregando infinitamente".

  // ✅ Usa detectedTorPort (porta REAL do Tor, detectada por probe-connect em
  // 9050/9150). O listener Tem que subir na MESMA porta que o Discord esta
  // apontando (injetada em BuildCommandLineCache), senao Discord reconecta em
  // porta vazia e fica "carregando infinitamente".
  proxyPortW := detectedTorPort;

  if torProcessStarted then
  begin
    TerminateProcess(torProcessInfo.hProcess, 0);
    CloseHandle(torProcessInfo.hProcess);
    CloseHandle(torProcessInfo.hThread);
    torProcessStarted := false;
  end;

  // Sobe listener e dá um pequeno respiro pro bind/accept estabilizar
  StartLocalSocks5Proxy(proxyPortW);
  localProxyActive := true;
  Sleep(500);

  // Só agora derruba as conexões ativas do Discord — ele vai reconectar
  // ao nosso listener já ativo.
  ForceCutTorConnections;

  if droverOptions.notifyOnDirectMode then
    MessageBoxW(0, PWideChar('Modo temporário: Conexão mudou para direto.' + #13#10 +
                              'Tor foi encerrado com sucesso.'),
              PWideChar('Discord Drover'), MB_ICONINFORMATION or MB_OK or MB_SYSTEMMODAL);
end;

function MyConnect(s: TSocket; const name: TSockAddr; namelen: integer): integer; stdcall;
var
  addr: PSockAddrIn;
  targetPort: word;
  targetIsLocalProxy: boolean;
begin
  addr := PSockAddrIn(@name);
  targetPort := ntohs(addr.sin_port);
  targetIsLocalProxy := (addr.sin_addr.S_addr = inet_addr('127.0.0.1')) and
    ((targetPort = 9050) or (targetPort = 9150) or (proxyValue.isSpecified and (targetPort = proxyValue.port)));

  if targetIsLocalProxy then
    sockManager.SetMode(s, GetCurrentMode)
  else
    // Conexões não-proxy (raras com --proxy-server) seguem o modo atual,
    // pra consistência com MySocket/MyWSASocket.
    sockManager.SetMode(s, GetCurrentMode);

  result := RealConnect(s, name, namelen);
end;

function MyCloseSocket(s: TSocket): integer; stdcall;
begin
  sockManager.RemoveBySock(s);
  result := RealCloseSocket(s);
end;

procedure ForceCutTorConnections;
var
  socks: TArray<TSocket>;
  sock: TSocket;
begin
  socks := sockManager.GetAllTorSockets;
  for sock in socks do
  begin
    shutdown(sock, SD_BOTH);
    closesocket(sock);
    sockManager.RemoveBySock(sock);
  end;
end;

procedure RelaySockets(sock1, sock2: TSocket);
var
  fdSet: TFDSet;
  buf: array[0..8191] of byte;
  bytesRead, bytesSent: integer;
begin
  try
    while True do
    begin
      FD_ZERO(fdSet);
      _FD_SET(sock1, fdSet);
      _FD_SET(sock2, fdSet);

      if select(0, @fdSet, nil, nil, nil) <= 0 then
        break;

      if FD_ISSET(sock1, fdSet) then
      begin
        bytesRead := RealRecv(sock1, buf, SizeOf(buf), 0);
        if bytesRead <= 0 then
          break;
        bytesSent := RealSend(sock2, buf, bytesRead, 0);
        if bytesSent <= 0 then
          break;
      end;

      if FD_ISSET(sock2, fdSet) then
      begin
        bytesRead := RealRecv(sock2, buf, SizeOf(buf), 0);
        if bytesRead <= 0 then
          break;
        bytesSent := RealSend(sock1, buf, bytesRead, 0);
        if bytesSent <= 0 then
          break;
      end;
    end;
  finally
    closesocket(sock1);
    closesocket(sock2);
    sockManager.Remove(sock1);
  end;
end;

function HandleDirectSocks5(var item: TSocketManagerItem; const buf; len: integer): boolean;
var
  s, targetHost: RawByteString;
  targetPort: word;
  hostLen: integer;
  directSock, clientSock: TSocket;
  addr: sockaddr_in;
  sa: TSockAddr;
  reply: RawByteString;
  hostEnt: PHostEnt;
  ipAddr: in_addr;
begin
  result := false;
  if item.mode <> dmDirect then
    exit;

  SetLength(s, len);
  Move(buf, s[1], len);

  if (len = 3) and (s = #$05#$01#$00) then
  begin
    RealSend(item.sock, PAnsiChar(#$05#$00)^, 2, 0);
    exit(true);
  end;

  if (len > 5) and (s[1] = #$05) and (s[2] = #$01) and (s[4] = #$03) then
  begin
    hostLen := Ord(s[5]);
    if len < 5 + hostLen + 2 then
      exit(false);

    targetHost := Copy(s, 6, hostLen);
    targetPort := (Ord(s[6 + hostLen]) shl 8) or Ord(s[7 + hostLen]);

    directSock := socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if directSock = INVALID_SOCKET then
      exit(false);

    ZeroMemory(@addr, SizeOf(addr));
    addr.sin_family := AF_INET;
    addr.sin_port := htons(targetPort);
    addr.sin_addr.S_addr := inet_addr(PAnsiChar(targetHost));

    if addr.sin_addr.S_addr = INADDR_NONE then
    begin
      hostEnt := gethostbyname(PAnsiChar(targetHost));
      if hostEnt = nil then
      begin
        closesocket(directSock);
        exit(false);
      end;
      ipAddr := PInAddr(hostEnt.h_addr_list^)^;
      addr.sin_addr := ipAddr;
    end;

    Move(addr, sa, SizeOf(addr));

    if RealConnect(directSock, sa, SizeOf(sa)) <> 0 then
    begin
      closesocket(directSock);
      exit(false);
    end;

    clientSock := item.sock;
    reply := #$05#$00#$00#$01#$00#$00#$00#$00#$00#$00;
    RealSend(clientSock, reply[1], Length(reply), 0);

    TThread.CreateAnonymousThread(procedure
    begin
      RelaySockets(clientSock, directSock);
    end).Start;

    result := true;
  end;
end;

function MySend(sock: TSocket; const buf; len, flags: integer): integer; stdcall;
var
  sockManagerItem: TSocketManagerItem;
begin
  if sockManager.IsFirstSend(sock, sockManagerItem) then
  begin
    // Quando o proxy SOCKS5 local está ativo (modo temporário pós-virada),
    // o listener próprio já trata o SOCKS5. Não competir com ele.
    if not localProxyActive then
    begin
      if (sockManagerItem.mode = dmDirect) and HandleDirectSocks5(sockManagerItem, buf, len) then
        exit(len);

      if ConvertHttpToSocks5(sockManagerItem, buf, len, flags) then
        exit(len);
    end;
  end;

  result := RealSend(sock, buf, len, flags);
end;

function MyRecv(sock: TSocket; var buf; len, flags: integer): integer; stdcall;
var
  s: RawByteString;
  i: integer;
begin
  result := RealRecv(sock, buf, len, flags);

  if (result > 0) and sockManager.ResetFakeHttpProxyFlag(sock) then
  begin
    if result >= 10 then
    begin
      // Potential issue: real server data may mix with the SOCKS5 response
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

function ResolveTorExecutablePath: string;
var
  candidate: string;
begin
  candidate := currentProcessDir + 'drover-tor\tor.exe';
  if FileExists(candidate) then
    exit(candidate);

  candidate := currentProcessDir + 'tor\tor.exe';
  if FileExists(candidate) then
    exit(candidate);

  candidate := currentProcessDir + 'tor.exe';
  if FileExists(candidate) then
    exit(candidate);

  if (droverOptions.torExecutable <> '') and FileExists(droverOptions.torExecutable) then
    exit(droverOptions.torExecutable);

  result := '';
end;

function GetDllDirectory: string;
var
  dllPath: array[0..MAX_PATH] of Char;
begin
  // ✅ Obter caminho da DLL (não do processo chamador)
  if GetModuleFileName(HInstance, dllPath, Length(dllPath)) > 0 then
    result := IncludeTrailingPathDelimiter(ExtractFilePath(string(dllPath)))
  else
    // Fallback se GetModuleFileName falhar
    result := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
end;

function IsTorProcessAlreadyRunning: boolean;
var
  snapshot: THandle;
  pe: TProcessEntry32;
begin
  result := false;
  snapshot := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if snapshot = INVALID_HANDLE_VALUE then
    exit;

  try
    pe.dwSize := SizeOf(TProcessEntry32);
    if Process32First(snapshot, pe) then
    begin
      repeat
        if SameText(pe.szExeFile, 'tor.exe') then
          exit(true);
      until not Process32Next(snapshot, pe);
    end;
  finally
    CloseHandle(snapshot);
  end;
end;

// ✅ Detecta a porta SOCKS5 real que o tor.exe abriu.
// O Tor pode subir em 9050 ou 9150 (definido no próprio torrc do bunde), e nao
// somos nos quem escolhe. Em vez de ler proxyValue.port do .ini (que é fixo e
// pode estar errado), fazemos probe-connect em 127.0.0.1 nas duas portas candidatas
// ate uma aceitar — quem aceitar é a porta vencedora. Isso garante que:
//   - BuildCommandLineCache injeta --proxy-server=...:<portaReal> (Discord aponta
//     pra onde o Tor realmente tá escutando).
//   - TModeSwitchThread sobe o listener na MESMA porta, pra Discord reconectar
//     nele apos a virada.
function DetectTorSocksPort: word;
const
  CANDIDATES: array[0..1] of word = (9050, 9150);
  // Tor abre o listener SOCKS5 cedo no startup (antes de bootstrap completo),
  // normalmente em <2s. Probe em porta fechada retorna ECONNREFUSED instantaneo,
  // entao o custo por ciclo e so o Sleep. 50 x 100 ms = ~5s de teto esperando
  // o Tor bindar — caso comum detecta em <2s.
  MAX_ATTEMPTS = 50;
var
  attempt, i: integer;
  s: TSocket;
  sa: sockaddr_in;
  connected: boolean;
  fdSet: TFDSet;
  tv: TTimeVal;
  nonblock: u_long;
  err: integer;
begin
  result := 9050;  // fallback default se nada responder a tempo
  for attempt := 1 to MAX_ATTEMPTS do
  begin
    for i := Low(CANDIDATES) to High(CANDIDATES) do
    begin
      s := socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
      if s = INVALID_SOCKET then
        Continue;

      // connect nao-bloqueante p/ ter timeout curto sem travar a DLL
      nonblock := 1;
      ioctlsocket(s, FIONBIO, nonblock);

      ZeroMemory(@sa, SizeOf(sa));
      sa.sin_family := AF_INET;
      sa.sin_addr.S_addr := inet_addr('127.0.0.1');
      sa.sin_port := htons(CANDIDATES[i]);

      connect(s, TSockAddr(sa), SizeOf(sa));
      err := WSAGetLastError;

      connected := false;
      if err = 0 then
        connected := true
      else if err = WSAEWOULDBLOCK then
      begin
        FD_ZERO(fdSet);
        _FD_SET(s, fdSet);
        tv.tv_sec := 0;
        tv.tv_usec := 200000;  // 200 ms de timeout por probe
        if select(0, nil, @fdSet, nil, @tv) > 0 then
          connected := true;
      end;

      closesocket(s);

      if connected then
      begin
        result := CANDIDATES[i];
        OutputDebugStringW(PWideChar(Format('[Drover] DetectTorSocksPort: porta %d respondeu (tentativa %d)', [result, attempt])));
        exit;
      end;
    end;

    if attempt mod 10 = 0 then
      OutputDebugStringW(PWideChar(Format('[Drover] DetectTorSocksPort: ainda procurando (tentativa %d/%d)', [attempt, MAX_ATTEMPTS])));
    Sleep(100);
  end;

  OutputDebugStringW(PWideChar(Format('[Drover] DetectTorSocksPort: nenhuma porta respondeu, usando fallback %d', [result])));
end;

procedure StartTorIfConfigured;
var
  torPath: string;
  cmdLine: string;
  si: TStartupInfoW;
begin
  if not droverOptions.autoStartTor then
    exit;  // Configurado para não autostart

  if IsTorProcessAlreadyRunning then
    exit;  // Já está rodando

  torPath := ResolveTorExecutablePath;
  if (torPath = '') or not FileExists(torPath) then
    exit;  // tor.exe não encontrado

  ZeroMemory(@si, SizeOf(si));
  si.cb := SizeOf(si);
  si.dwFlags := STARTF_USESHOWWINDOW;
  si.wShowWindow := SW_HIDE;
  cmdLine := '"' + torPath + '"';

  // ✅ CORREÇÃO: Usar lpApplicationName (torPath) em vez de nil
  // Isso garante que Windows encontre o executável corretamente
  if CreateProcessW(PWideChar(torPath), PWideChar(cmdLine), nil, nil, False, 0, nil,
    PWideChar(ExtractFileDir(torPath)), si, torProcessInfo) then
  begin
    torProcessStarted := true;
    if not droverOptions.tempTorMode then
    begin
      if torProcessInfo.hThread <> 0 then
        CloseHandle(torProcessInfo.hThread);
      if torProcessInfo.hProcess <> 0 then
        CloseHandle(torProcessInfo.hProcess);
      torProcessStarted := false;
    end;
  end;
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
  // ✅ Obter o diretório da DLL corretamente usando GetModuleFileName
  // (ParamStr(0) em DLL não funciona corretamente)
  var
    dllPath: array[0..MAX_PATH] of Char;
  begin
    GetModuleFileName(HInstance, dllPath, SizeOf(dllPath));
    currentProcessDir := IncludeTrailingPathDelimiter(ExtractFilePath(string(dllPath)));
  end;

  // ✅ Sempre carregar a version.dll original do sistema para os exports
  // funcionarem (a DLL é uma shim de version.dll).
  LoadOriginalVersionDll;

  // ✅ NÃO se ativar dentro do instalador (drover.exe).
  // O instalador carrega funções de versão (GetFileVersionInfo...) para detectar
  // a versão do Discord, e o Windows resolve version.dll do diretório do exe —
  // que é esta DLL. Se não fizermos esse guard, a DLL inicializa dentro do
  // instalador: inicia o Tor em dobro, roda TModeSwitchThread e mostra o MessageBox
  // "Modo temporário" no processo errado.
  if SameText(ExtractFileName(ParamStr(0)), 'drover.exe') then
    exit;

  // ✅ Identifica se este processo e o browser process principal do Discord.
  // O Discord (Chromium/Electron) lança varios subprocessos: renderer, GPU,
  // utility, etc. Todos carregam version.dll e rodam esta initialization.
  // Se cada um rodar StartTorIfConfigured/TModeSwitchThread/MessageBox, teriamos
  // 5+ instalacoes rodando e N MessageBox ao final da conexão (o bug).
  // O browser process principal NAO tem --type= na linha de comando; os
  // subprocessos teem --type=renderer | --type=gpu-process | --type=utility ...
  if IsDiscordExecutable(ExtractFileName(ParamStr(0))) and
     (Pos('--type=', string(GetCommandLineW)) = 0) then
    isMainDiscordProcess := true
  else
    isMainDiscordProcess := false;

  sockManager := TSocketManager.Create;
  modeCS := TCriticalSection.Create;
  currentMode := dmTor;
  torProcessStarted := false;
  localProxyActive := false;
  detectedTorPort := 9050;  // default ate detectar a real

  // ✅ Carregar configurações do .ini:
  // 1. Tenta na mesma pasta do tor.exe (drover-tor\drover.ini)
  // 2. Fallback: pasta da DLL
  var torPath := ResolveTorExecutablePath;
  var optionsPath := '';
  if torPath <> '' then
    optionsPath := ExtractFilePath(torPath) + OPTIONS_FILENAME;
  if not FileExists(optionsPath) then
    optionsPath := currentProcessDir + OPTIONS_FILENAME;
  droverOptions := LoadOptions(optionsPath);

  // ✅ INICIA TOR INSTANTANEAMENTE - SINCRONICAMENTE (apenas processo principal;
  // subprocessos nao iniciam Tor em dobro nem detectam porta).
  if isMainDiscordProcess then
    StartTorIfConfigured;

  proxyValue.ParseFromString(droverOptions.proxy);

  // ✅ Detecta a porta SOCKS5 REAL que o Tor abriu (9050 ou 9150, probe-connect).
  // So o main process deteta — ele e quem iniciou o Tor. Subprocessos herdam
  // detectedTorPort default 9050 e injetam --proxy-server via BuildCommandLineCache
  // abaixo (a linha de comando deles ja vem com --proxy-server herdado do main,
  // entao o cache e identico e harmless).
  if isMainDiscordProcess and torProcessStarted then
    detectedTorPort := DetectTorSocksPort;

  // ✅ BuildCommandLineCache precisa rodar DEPOIS de proxyValue.ParseFromString,
  // senão o proxyValue ainda está vazio e o --proxy-server=socks5://... nunca é
  // injetado na linha de comando — o Discord conecta direto (sem Tor).
  BuildCommandLineCache;

  RealGetEnvironmentVariableW := InterceptCreate(@GetEnvironmentVariableW, @MyGetEnvironmentVariableW, nil);
  RealCreateProcessW := InterceptCreate(@CreateProcessW, @MyCreateProcessW, nil);
  RealGetCommandLineW := InterceptCreate(@GetCommandLineW, @MyGetCommandLineW, nil);

  RealSocket := InterceptCreate(@socket, @MySocket, nil);
  RealWSASocket := InterceptCreate(@WSASocket, @MyWSASocket, nil);
  RealWSASend := InterceptCreate(@WSASend, @MyWSASend, nil);
  RealWSASendTo := InterceptCreate(@WSASendTo, @MyWSASendTo, nil);
  RealSend := InterceptCreate(@send, @MySend, nil);
  RealRecv := InterceptCreate(@recv, @MyRecv, nil);

  // ✅ Apenas ativar thread de mudança de modo se tempTorMode estiver ativo E
  // este for o processo principal (subprocessos nao rodam TModeSwitchThread:
  // senao N deles matam o Tor, sobem N listeners na mesma porta e mostram N
  // MessageBox ao finalizar a conexão).
  if droverOptions.tempTorMode and isMainDiscordProcess then
  begin
    RealConnect := InterceptCreate(@connect, @MyConnect, nil);
    RealCloseSocket := InterceptCreate(@closesocket, @MyCloseSocket, nil);
    TModeSwitchThread.Create(false);
  end;

end.
