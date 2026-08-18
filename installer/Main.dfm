object frmMain: TfrmMain
  Left = 0
  Top = 0
  BorderIcons = [biSystemMenu, biMinimize]
  BorderStyle = bsSingle
  Caption = 'Discord Drover'
  ClientHeight = 260
  ClientWidth = 260
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Menu = MainMenu
  Position = poScreenCenter
  OnCreate = FormCreate
  OnShow = FormShow
  TextHeight = 15
  object lTorPath: TLabel
    Left = 10
    Top = 104
    Width = 109
    Height = 15
    Caption = 'Caminho do Tor.exe:'
    Visible = False
  end
  object lWarmupSeconds: TLabel
    Left = 125
    Top = 33
    Width = 144
    Height = 15
    Caption = 'Segundos de aquecimento:'
    Enabled = False
  end
  object chkTempTorMode: TCheckBox
    Left = 10
    Top = 10
    Width = 240
    Height = 18
    Caption = 'Usar Tor apenas na inicializa'#231#227'o (modo tempor'#225'rio)'
    Checked = True
    State = cbChecked
    TabOrder = 0
    OnClick = chkTempTorModeClick
  end
  object editWarmupSeconds: TEdit
    Left = 10
    Top = 31
    Width = 105
    Height = 23
    Enabled = False
    NumbersOnly = True
    TabOrder = 1
    Text = '60'
  end
  object chkNotifyOnDirectMode: TCheckBox
    Left = 10
    Top = 55
    Width = 240
    Height = 18
    Caption = 'Notificar quando a conex'#227'o direta for estabelecida'
    Checked = True
    Enabled = False
    State = cbChecked
    TabOrder = 2
  end
  object chkAutoInstallTor: TCheckBox
    Left = 10
    Top = 80
    Width = 240
    Height = 18
    Caption = 'Instalar Tor automaticamente'
    Checked = True
    State = cbChecked
    TabOrder = 7
    OnClick = chkAutoInstallTorClick
  end
  object editTorPath: TEdit
    Left = 10
    Top = 124
    Width = 180
    Height = 23
    TabOrder = 3
    Visible = False
  end
  object btnBrowseTor: TButton
    Left = 195
    Top = 124
    Width = 55
    Height = 20
    Caption = 'Procurar...'
    TabOrder = 4
    Visible = False
    OnClick = btnBrowseTorClick
  end
  object btnInstall: TButton
    Left = 10
    Top = 220
    Width = 115
    Height = 25
    Caption = 'Install'
    TabOrder = 5
    OnClick = btnInstallClick
  end
  object btnUninstall: TButton
    Left = 135
    Top = 220
    Width = 115
    Height = 25
    Caption = 'Uninstall'
    TabOrder = 6
    OnClick = btnUninstallClick
  end
  object MainMenu: TMainMenu
    Left = 416
    Top = 156
    object miAbout: TMenuItem
      Caption = 'View on GitHub'
      OnClick = miAboutClick
    end
  end
  object OpenDialogTor: TOpenDialog
    DefaultExt = 'exe'
    Filter = 'Execut'#225'vel Tor (tor.exe)|tor.exe|Todos os arquivos (*.*)|*.*'
    Title = 'Selecione o execut'#225'vel do Tor'
    Left = 416
    Top = 80
  end
  object OpenDialogDiscord: TOpenDialog
    DefaultExt = 'exe'
    Filter = 
      'Execut'#225'vel do Discord (Discord*.exe)|Discord*.exe|Todos os arqui' +
      'vos (*.*)|*.*'
    Title = 'Selecione o execut'#225'vel do Discord ou a pasta app-*'
    Left = 416
    Top = 220
  end
end
