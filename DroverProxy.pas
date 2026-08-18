unit DroverProxy;

{
  Listener SOCKS5 local do drover.

  Quando tempTorMode esta ativo:
    - Antes da virada: o tor.exe atende na 9050 (Tor roteando).
    - Na virada: TModeSwitchThread mata o Tor e chama StartLocalSocks5Proxy,
      que sobe um listener proprio em 127.0.0.1:proxyPort.
      A partir dai, todo socket que o Discord abre contra 127.0.0.1:proxyPort
      e atendido aqui e repassado DIRETO pra internet (sem Tor).

  Isso resolve o "fica sem internet apos a virada": o Discord continua
  apontando pra 127.0.0.1:9050 (nao muda config), mas quem atende agora e
  nos, encaminhando direto.
}

interface

uses
  Winapi.Windows,
  WinSock,
  WinSock2;

procedure StartLocalSocks5Proxy(port: word);
procedure StopLocalSocks5Proxy;

implementation

uses
  System.SysUtils,
  System.Classes,
  SyncObjs;

var
  proxyStopEvent: THandle = 0;
  proxyThread: TThread = nil;

function Relay(a, b: TSocket): integer;
var
  fdSet: TFDSet;
  buf: array[0..8191] of byte;
  r, w: integer;
begin
  result := 0;
  while True do
  begin
    FD_ZERO(fdSet);
    _FD_SET(a, fdSet);
    _FD_SET(b, fdSet);
    if select(0, @fdSet, nil, nil, nil) <= 0 then
      break;
    if FD_ISSET(a, fdSet) then
    begin
      r := recv(a, buf, SizeOf(buf), 0);
      if r <= 0 then
        break;
      w := send(b, buf, r, 0);
      if w <= 0 then
        break;
    end;
    if FD_ISSET(b, fdSet) then
    begin
      r := recv(b, buf, SizeOf(buf), 0);
      if r <= 0 then
        break;
      w := send(a, buf, r, 0);
      if w <= 0 then
        break;
    end;
  end;
  closesocket(a);
  closesocket(b);
end;

procedure HandleSocks5Client(client: TSocket);
var
  ver, nmethods: byte;
  methods: array[0..255] of byte;
  ver2, cmd, rsv, atyp: byte;
  bnd: sockaddr_in;
  directSock: TSocket;
  reply: array[0..9] of byte;
  addr_sin: sockaddr_in;
  dstHost: AnsiString;
  dstPort: word;
  hostLen: byte;
  ip: u_long;
  sa: sockaddr_in;
begin
  OutputDebugStringW(PWideChar(Format('[DroverProxy] HandleSocks5Client sock=%d', [client])));
  // 1) Saudacao: VER NMETHODS METHODS...
  if recv(client, ver, 1, 0) <> 1 then
  begin
    closesocket(client);
    exit;
  end;
  if ver <> 5 then
  begin
    closesocket(client);
    exit;
  end;
  if recv(client, nmethods, 1, 0) <> 1 then
  begin
    closesocket(client);
    exit;
  end;
  if nmethods = 0 then
  begin
    closesocket(client);
    exit;
  end;
  if recv(client, methods[0], nmethods, 0) <> nmethods then
  begin
    closesocket(client);
    exit;
  end;
  // Responde: sem autenticacao
  if send(client, PAnsiChar(#$05#$00)^, 2, 0) <> 2 then
  begin
    closesocket(client);
    exit;
  end;

  // 2) Pedido: VER CMD RSV ATYP ...
  if recv(client, ver2, 1, 0) <> 1 then
  begin
    closesocket(client);
    exit;
  end;
  if recv(client, cmd, 1, 0) <> 1 then
  begin
    closesocket(client);
    exit;
  end;
  if recv(client, rsv, 1, 0) <> 1 then
  begin
    closesocket(client);
    exit;
  end;
  if recv(client, atyp, 1, 0) <> 1 then
  begin
    closesocket(client);
    exit;
  end;

  // So suportamos CONNECT (cmd=1)
  if cmd <> 1 then
  begin
    // Command not supported
    reply[0] := 5; reply[1] := 7; reply[2] := 0; reply[3] := 1;
    FillChar(reply[4], 6, 0);
    send(client, reply[0], 10, 0);
    closesocket(client);
    exit;
  end;

  ZeroMemory(@sa, SizeOf(sa));
  sa.sin_family := AF_INET;

  case atyp of
    1: // IPv4
    begin
      if recv(client, sa.sin_addr, 4, 0) <> 4 then
      begin
        closesocket(client);
        exit;
      end;
    end;
    3: // Domain
    begin
      if recv(client, hostLen, 1, 0) <> 1 then
      begin
        closesocket(client);
        exit;
      end;
      SetLength(dstHost, hostLen);
      if recv(client, dstHost[1], hostLen, 0) <> hostLen then
      begin
        closesocket(client);
        exit;
      end;
      ip := inet_addr(PAnsiChar(dstHost));
      if ip = u_long(INADDR_NONE) then
      begin
        var hostEntry := gethostbyname(PAnsiChar(dstHost));
        if hostEntry = nil then
        begin
          // Host unreachable
          reply[0] := 5; reply[1] := 4; reply[2] := 0; reply[3] := 1;
          FillChar(reply[4], 6, 0);
          send(client, reply[0], 10, 0);
          closesocket(client);
          exit;
        end;
        sa.sin_addr := PInAddr(hostEntry.h_addr_list^)^;
      end
      else
        sa.sin_addr := PInAddr(@ip)^;
    end;
  else
    // Address type not supported
    reply[0] := 5; reply[1] := 8; reply[2] := 0; reply[3] := 1;
    FillChar(reply[4], 6, 0);
    send(client, reply[0], 10, 0);
    closesocket(client);
    exit;
  end;

  // Porta (2 bytes, big endian)
  if recv(client, sa.sin_port, 2, 0) <> 2 then
  begin
    closesocket(client);
    exit;
  end;

  // 3) Connect direto no alvo
  var dstIp := string(inet_ntoa(sa.sin_addr));
  var dstPortW := ntohs(sa.sin_port);
  OutputDebugStringW(PWideChar(Format('[DroverProxy] CONNECT solicitado -> %s:%d', [dstIp, dstPortW])));
  directSock := socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if directSock = INVALID_SOCKET then
  begin
    reply[0] := 5; reply[1] := 1; reply[2] := 0; reply[3] := 1;
    FillChar(reply[4], 6, 0);
    send(client, reply[0], 10, 0);
    closesocket(client);
    exit;
  end;

  if connect(directSock, TSockAddr(sa), SizeOf(sa)) <> 0 then
  begin
    closesocket(directSock);
    reply[0] := 5; reply[1] := 5; reply[2] := 0; reply[3] := 1;
    FillChar(reply[4], 6, 0);
    send(client, reply[0], 10, 0);
    closesocket(client);
    exit;
  end;

  // 4) Sucesso
  reply[0] := 5; reply[1] := 0; reply[2] := 0; reply[3] := 1;
  FillChar(reply[4], 6, 0);  // BND.ADDR=0.0.0.0 BND.PORT=0
  if send(client, reply[0], 10, 0) <> 10 then
  begin
    closesocket(directSock);
    closesocket(client);
    exit;
  end;

  // 5) Relay bidirecional (bloqueante nesta thread)
  Relay(client, directSock);
end;

type
  TProxyThread = class(TThread)
  private
    FPort: word;
  protected
    procedure Execute; override;
  end;

procedure TProxyThread.Execute;
var
  listenSock, client: TSocket;
  sa: sockaddr_in;
  fdSet: TFDSet;
  tv: TTimeVal;
  opt: integer;
  attempt: integer;
  bound: boolean;
begin
  OutputDebugStringW(PWideChar(Format('[DroverProxy] thread iniciada, porta=%d', [FPort])));

  listenSock := socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if listenSock = INVALID_SOCKET then
  begin
    OutputDebugStringW('[DroverProxy] socket() falhou');
    exit;
  end;

  // Reutilizar porta (caso o SO ainda nao liberou apos o Tor morrer)
  opt := 1;
  setsockopt(listenSock, SOL_SOCKET, SO_REUSEADDR, PAnsiChar(@opt), SizeOf(opt));

  ZeroMemory(@sa, SizeOf(sa));
  sa.sin_family := AF_INET;
  sa.sin_addr.S_addr := inet_addr('127.0.0.1');
  sa.sin_port := htons(FPort);

  // ✅ Retry de bind com backoff: o Tor acabou de morrer, a porta pode ainda
  // estar em TIME_WAIT ou o SO nao liberou o handle. Sem retry, o bind falha
  // silenciosamente e o Discord fica "carregando infinitamente" (ninguem escuta).
  bound := false;
  for attempt := 1 to 20 do
  begin
    if bind(listenSock, TSockAddr(sa), SizeOf(sa)) = 0 then
    begin
      bound := true;
      break;
    end;
    OutputDebugStringW(PWideChar(Format('[DroverProxy] bind tentativa %d falhou (err=%d), tentando em 250ms...', [attempt, WSAGetLastError])));
    Sleep(250);
  end;

  if not bound then
  begin
    OutputDebugStringW(PWideChar(Format('[DroverProxy] bind falhou definitivamente apos %d tentativas', [attempt])));
    closesocket(listenSock);
    exit;
  end;

  OutputDebugStringW('[DroverProxy] bind OK');

  if listen(listenSock, 16) = SOCKET_ERROR then
  begin
    OutputDebugStringW(PWideChar(Format('[DroverProxy] listen falhou (err=%d)', [WSAGetLastError])));
    closesocket(listenSock);
    exit;
  end;

  OutputDebugStringW('[DroverProxy] listen OK, aguardando conexoes');

  while not Terminated do
  begin
    FD_ZERO(fdSet);
    _FD_SET(listenSock, fdSet);
    tv.tv_sec := 1;
    tv.tv_usec := 0;

    if select(0, @fdSet, nil, nil, @tv) <= 0 then
    begin
      // Verifica stop a cada segundo
      if (proxyStopEvent <> 0) and (WaitForSingleObject(proxyStopEvent, 0) = WAIT_OBJECT_0) then
        break;
      Continue;
    end;

    if not FD_ISSET(listenSock, fdSet) then
      Continue;

    client := accept(listenSock, nil, nil);
    if client = INVALID_SOCKET then
      Continue;

    OutputDebugStringW('[DroverProxy] cliente connectado, despachando thread');

    // Atende cada cliente numa thread propria (bloqueante)
    TThread.CreateAnonymousThread(
      procedure
      begin
        HandleSocks5Client(client);
      end).Start;
  end;

  closesocket(listenSock);
end;

procedure StartLocalSocks5Proxy(port: word);
begin
  if proxyThread <> nil then
    exit;  // ja rodando
  if proxyStopEvent = 0 then
    proxyStopEvent := CreateEvent(nil, True, False, nil);
  ResetEvent(proxyStopEvent);
  proxyThread := TProxyThread.Create(True);
  TProxyThread(proxyThread).FPort := port;
  TProxyThread(proxyThread).FreeOnTerminate := False;
  TProxyThread(proxyThread).Start;
end;

procedure StopLocalSocks5Proxy;
begin
  if proxyStopEvent <> 0 then
    SetEvent(proxyStopEvent);
  if proxyThread <> nil then
  begin
    proxyThread.Terminate;
    proxyThread.WaitFor;
    FreeAndNil(proxyThread);
  end;
end;

end.
