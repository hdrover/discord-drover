object frmMain: TfrmMain
  Left = 0
  Top = 0
  Margins.Left = 6
  Margins.Top = 6
  Margins.Right = 6
  Margins.Bottom = 6
  BorderIcons = [biSystemMenu, biMinimize]
  BorderStyle = bsSingle
  Caption = 'Discord Drover'
  ClientHeight = 520
  ClientWidth = 520
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -24
  Font.Name = 'Segoe UI'
  Font.Style = []
  Menu = MainMenu
  Position = poScreenCenter
  OnCreate = FormCreate
  OnShow = FormShow
  PixelsPerInch = 192
  TextHeight = 32
  object lHost: TLabel
    Left = 20
    Top = 93
    Width = 121
    Height = 32
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    Caption = 'Host name:'
  end
  object lPort: TLabel
    Left = 20
    Top = 163
    Width = 138
    Height = 32
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    Caption = 'Port number:'
  end
  object lLogin: TLabel
    Left = 20
    Top = 303
    Width = 64
    Height = 32
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    Caption = 'Login:'
  end
  object lPassword: TLabel
    Left = 20
    Top = 373
    Width = 102
    Height = 32
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    Caption = 'Password:'
  end
  object pType: TPanel
    Left = 10
    Top = 18
    Width = 500
    Height = 60
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    BevelOuter = bvNone
    TabOrder = 0
    object rbHttp: TRadioButton
      Left = 10
      Top = 10
      Width = 113
      Height = 40
      Margins.Left = 6
      Margins.Top = 6
      Margins.Right = 6
      Margins.Bottom = 6
      Caption = 'HTTP'
      TabOrder = 0
      OnClick = rbHttpClick
    end
    object rbSocks: TRadioButton
      Left = 140
      Top = 10
      Width = 149
      Height = 40
      Margins.Left = 6
      Margins.Top = 6
      Margins.Right = 6
      Margins.Bottom = 6
      Caption = 'SOCKS5'
      TabOrder = 1
      OnClick = rbSocksClick
    end
    object rbDirect: TRadioButton
      Left = 299
      Top = 10
      Width = 226
      Height = 40
      Margins.Left = 6
      Margins.Top = 6
      Margins.Right = 6
      Margins.Bottom = 6
      Caption = 'Direct'
      TabOrder = 2
      OnClick = rbDirectClick
    end
  end
  object btnInstall: TButton
    Left = 20
    Top = 450
    Width = 230
    Height = 50
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    Caption = 'Install'
    TabOrder = 6
    OnClick = btnInstallClick
  end
  object btnUninstall: TButton
    Left = 270
    Top = 450
    Width = 230
    Height = 50
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    Caption = 'Uninstall'
    TabOrder = 7
    OnClick = btnUninstallClick
  end
  object eHost: TEdit
    Left = 180
    Top = 90
    Width = 320
    Height = 40
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    TabOrder = 1
  end
  object ePort: TEdit
    Left = 180
    Top = 160
    Width = 140
    Height = 40
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    NumbersOnly = True
    TabOrder = 2
  end
  object cbAuth: TCheckBox
    Left = 20
    Top = 230
    Width = 283
    Height = 40
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    Caption = 'Authentication'
    TabOrder = 3
    OnClick = cbAuthClick
  end
  object eLogin: TEdit
    Left = 180
    Top = 300
    Width = 320
    Height = 40
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    TabOrder = 4
  end
  object ePassword: TEdit
    Left = 180
    Top = 370
    Width = 320
    Height = 40
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    TabOrder = 5
  end
  object MainMenu: TMainMenu
    Left = 416
    Top = 156
    object miAbout: TMenuItem
      Caption = 'View on GitHub'
      OnClick = miAboutClick
    end
  end
  object TrayIcon: TTrayIcon
    PopupMenu = TrayMenu
    Visible = True
    OnDblClick = TrayIconDblClick
    Left = 432
    Top = 212
  end
  object TrayMenu: TPopupMenu
    Left = 432
    Top = 256
    object miRestore: TMenuItem
      Caption = 'Restore'
      OnClick = miRestoreClick
    end
    object miHide: TMenuItem
      Caption = 'Hide'
      OnClick = miHideClick
    end
    object miExit: TMenuItem
      Caption = 'Exit'
      OnClick = miExitClick
    end
  end
end
