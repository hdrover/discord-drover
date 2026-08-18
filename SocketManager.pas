unit SocketManager;

interface

uses
  System.SysUtils,
  Winapi.Windows,
  WinSock,
  WinSock2,
  SyncObjs,
  System.Generics.Collections;

type
  TDroverMode = (dmTor, dmDirect);

  TSocketManagerItem = record
    sock: TSocket;
    isTcp: boolean;
    isUdp: boolean;
    hasSent: boolean;
    fakeHttpProxyFlag: boolean;
    createdAt: int64;
    mode: TDroverMode;
  end;

  TSocketManager = class
  private
    items: array of TSocketManagerItem;
    criticalSection: TCriticalSection;

    function FindIndexBySock(sock: TSocket): integer;
    procedure DeleteByIndex(index: integer);
    procedure CollectGarbage;
  public
    procedure Add(sock: TSocket; sockType, sockProtocol: integer; initialMode: TDroverMode);
    function IsFirstSend(sock: TSocket; var item: TSocketManagerItem): boolean;
    procedure SetFakeHttpProxyFlag(sock: TSocket);
    function ResetFakeHttpProxyFlag(sock: TSocket): boolean;
    procedure SetMode(sock: TSocket; mode: TDroverMode);
    function GetItem(sock: TSocket; var item: TSocketManagerItem): boolean;
    function CountActiveTorSockets: integer;
    function GetAllTorSockets: TArray<TSocket>;
    procedure Remove(sock: TSocket);
    procedure RemoveBySock(sock: TSocket);

    constructor Create;
    destructor Destroy; override;
  end;

implementation

constructor TSocketManager.Create;
begin
  criticalSection := TCriticalSection.Create;
end;

destructor TSocketManager.Destroy;
begin
  criticalSection.Free;
end;

function TSocketManager.FindIndexBySock(sock: TSocket): integer;
var
  i: integer;
begin
  for i := 0 to High(items) do
  begin
    if items[i].sock = sock then
      exit(i);
  end;
  result := -1;
end;

procedure TSocketManager.DeleteByIndex(index: integer);
var
  lastIndex: integer;
begin
  lastIndex := High(items);
  if index < lastIndex then
    items[index] := items[lastIndex];
  SetLength(items, lastIndex);
end;

procedure TSocketManager.Remove(sock: TSocket);
var
  i: integer;
begin
  criticalSection.Enter;
  try
    i := FindIndexBySock(sock);
    if i >= 0 then
      DeleteByIndex(i);
  finally
    criticalSection.Leave;
  end;
end;

procedure TSocketManager.CollectGarbage;
var
  i: integer;
  tick: int64;
begin
  tick := GetTickCount64 - 30000;
  for i := High(items) downto 0 do
  begin
    if items[i].createdAt < tick then
    begin
      self.DeleteByIndex(i);
    end;
  end;
end;

procedure TSocketManager.Add(sock: TSocket; sockType, sockProtocol: integer; initialMode: TDroverMode);
var
  item: TSocketManagerItem;
  i: integer;
begin
  item.sock := sock;
  item.isTcp := (sockType = SOCK_STREAM) and ((sockProtocol = IPPROTO_TCP) or (sockProtocol = 0));
  item.isUdp := (sockType = SOCK_DGRAM) and ((sockProtocol = IPPROTO_UDP) or (sockProtocol = 0));
  item.hasSent := false;
  item.fakeHttpProxyFlag := false;
  item.createdAt := GetTickCount64;
  item.mode := initialMode;   // em vez de dmTor fixo

  criticalSection.Enter;
  try
    CollectGarbage;

    i := FindIndexBySock(sock);
    if i = -1 then
    begin
      i := Length(items);
      SetLength(items, i + 1);
    end;

    items[i] := item;
  finally
    criticalSection.Leave;
  end;
end;

function TSocketManager.IsFirstSend(sock: TSocket; var item: TSocketManagerItem): boolean;
var
  i: integer;
begin
  criticalSection.Enter;
  try
    i := FindIndexBySock(sock);
    if (i = -1) or items[i].hasSent then
      exit(false);

    items[i].hasSent := true;
    item := items[i];
    result := true;
  finally
    criticalSection.Leave;
  end;
end;

procedure TSocketManager.SetFakeHttpProxyFlag(sock: TSocket);
var
  i: integer;
begin
  criticalSection.Enter;
  try
    i := FindIndexBySock(sock);
    if i >= 0 then
      items[i].fakeHttpProxyFlag := true;
  finally
    criticalSection.Leave;
  end;
end;

function TSocketManager.ResetFakeHttpProxyFlag(sock: TSocket): boolean;
var
  i: integer;
begin
  criticalSection.Enter;
  try
    i := FindIndexBySock(sock);
    if (i = -1) or (not items[i].fakeHttpProxyFlag) then
      exit(false);

    items[i].fakeHttpProxyFlag := false;
    result := true;
  finally
    criticalSection.Leave;
  end;
end;

procedure TSocketManager.SetMode(sock: TSocket; mode: TDroverMode);
var
  i: integer;
begin
  criticalSection.Enter;
  try
    i := FindIndexBySock(sock);
    if i >= 0 then
      items[i].mode := mode;
  finally
    criticalSection.Leave;
  end;
end;

function TSocketManager.GetItem(sock: TSocket; var item: TSocketManagerItem): boolean;
var
  i: integer;
begin
  criticalSection.Enter;
  try
    i := FindIndexBySock(sock);
    if i >= 0 then
    begin
      item := items[i];
      result := true;
    end
    else
      result := false;
  finally
    criticalSection.Leave;
  end;
end;

function TSocketManager.CountActiveTorSockets: integer;
var
  i: integer;
begin
  criticalSection.Enter;
  try
    result := 0;
    for i := 0 to High(items) do
      if items[i].mode = dmTor then
        Inc(result);
  finally
    criticalSection.Leave;
  end;
end;

function TSocketManager.GetAllTorSockets: TArray<TSocket>;
var
  i: integer;
  list: TList<TSocket>;
begin
  list := TList<TSocket>.Create;
  try
    criticalSection.Enter;
    try
      for i := 0 to High(items) do
        if items[i].mode = dmTor then
          list.Add(items[i].sock);
    finally
      criticalSection.Leave;
    end;
    result := list.ToArray;
  finally
    list.Free;
  end;
end;

procedure TSocketManager.RemoveBySock(sock: TSocket);
begin
  Remove(sock);
end;

end.
