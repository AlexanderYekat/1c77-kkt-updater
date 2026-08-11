object frmMain: TfrmMain
  Left = 0
  Top = 0
  Caption = '1C77 KKT Updater'
  ClientHeight = 650
  ClientWidth = 980
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  TextHeight = 15
  object pnlPaths: TPanel
    Left = 8
    Top = 8
    Width = 960
    Height = 152
    Anchors = [akLeft, akTop, akRight]
    BevelOuter = bvNone
    TabOrder = 0
    object lblPaths: TLabel
      Left = 0
      Top = 0
      Width = 400
      Height = 15
      AutoSize = True
      Caption = 'Module paths'
    end
    object lblZlobin: TLabel
      Left = 0
      Top = 28
      Width = 70
      Height = 15
      Caption = 'Zlobin'
    end
    object edtZlobin: TEdit
      Left = 80
      Top = 25
      Width = 770
      Height = 23
      Anchors = [akLeft, akTop, akRight]
      TabOrder = 0
    end
    object btnBrowseZlobin: TButton
      Left = 860
      Top = 24
      Width = 90
      Height = 25
      Anchors = [akTop, akRight]
      Caption = '...'
      TabOrder = 1
      OnClick = btnBrowseZlobinClick
    end
    object lblStrelets: TLabel
      Left = 0
      Top = 57
      Width = 70
      Height = 15
      Caption = 'Strelets'
    end
    object edtStrelets: TEdit
      Left = 80
      Top = 54
      Width = 770
      Height = 23
      Anchors = [akLeft, akTop, akRight]
      TabOrder = 2
    end
    object btnBrowseStrelets: TButton
      Left = 860
      Top = 53
      Width = 90
      Height = 25
      Anchors = [akTop, akRight]
      Caption = '...'
      TabOrder = 3
      OnClick = btnBrowseStreletsClick
    end
    object lblSurgut: TLabel
      Left = 0
      Top = 86
      Width = 70
      Height = 15
      Caption = 'Surgut'
    end
    object edtSurgut: TEdit
      Left = 80
      Top = 83
      Width = 770
      Height = 23
      Anchors = [akLeft, akTop, akRight]
      TabOrder = 4
    end
    object btnBrowseSurgut: TButton
      Left = 860
      Top = 82
      Width = 90
      Height = 25
      Anchors = [akTop, akRight]
      Caption = '...'
      TabOrder = 5
      OnClick = btnBrowseSurgutClick
    end
    object btnDetectRegistry: TButton
      Left = 80
      Top = 118
      Width = 180
      Height = 25
      Caption = 'Detect registry'
      TabOrder = 6
      OnClick = btnDetectRegistryClick
    end
    object btnSavePaths: TButton
      Left = 272
      Top = 118
      Width = 140
      Height = 25
      Caption = 'Save paths'
      TabOrder = 7
      OnClick = btnSavePathsClick
    end
  end
  object pnlServices: TPanel
    Left = 8
    Top = 164
    Width = 960
    Height = 100
    Anchors = [akLeft, akTop, akRight]
    BevelOuter = bvNone
    TabOrder = 1
    object lblServices: TLabel
      Left = 0
      Top = 0
      Width = 400
      Height = 15
      AutoSize = True
      Caption = 'Services'
    end
    object lblAtolSvc: TLabel
      Left = 0
      Top = 28
      Width = 70
      Height = 15
      Caption = 'ATOL'
    end
    object edtAtolExe: TEdit
      Left = 80
      Top = 25
      Width = 560
      Height = 23
      Anchors = [akLeft, akTop, akRight]
      TabOrder = 0
    end
    object btnBrowseAtolExe: TButton
      Left = 646
      Top = 24
      Width = 70
      Height = 25
      Anchors = [akTop, akRight]
      Caption = '...'
      TabOrder = 1
      OnClick = btnBrowseAtolExeClick
    end
    object edtAtolBaseUrl: TEdit
      Left = 724
      Top = 25
      Width = 226
      Height = 23
      Anchors = [akTop, akRight]
      TabOrder = 2
    end
    object lblShtrihSvc: TLabel
      Left = 0
      Top = 60
      Width = 70
      Height = 15
      Caption = 'Shtrih'
    end
    object edtShtrihExe: TEdit
      Left = 80
      Top = 57
      Width = 560
      Height = 23
      Anchors = [akLeft, akTop, akRight]
      TabOrder = 3
    end
    object btnBrowseShtrihExe: TButton
      Left = 646
      Top = 56
      Width = 70
      Height = 25
      Anchors = [akTop, akRight]
      Caption = '...'
      TabOrder = 4
      OnClick = btnBrowseShtrihExeClick
    end
    object edtShtrihBaseUrl: TEdit
      Left = 724
      Top = 57
      Width = 226
      Height = 23
      Anchors = [akTop, akRight]
      TabOrder = 5
    end
  end
  object grdUpdates: TStringGrid
    Left = 8
    Top = 272
    Width = 960
    Height = 140
    Anchors = [akLeft, akTop, akRight]
    ColCount = 4
    DefaultColWidth = 160
    DefaultRowHeight = 22
    FixedCols = 0
    Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goRowSelect, goThumbTracking]
    TabOrder = 2
  end
  object btnCheck: TButton
    Left = 8
    Top = 418
    Width = 150
    Height = 28
    Caption = 'Check'
    TabOrder = 3
    OnClick = btnCheckClick
  end
  object btnUpdateSelected: TButton
    Left = 166
    Top = 418
    Width = 140
    Height = 28
    Caption = 'Update selected'
    TabOrder = 4
    OnClick = btnUpdateSelectedClick
  end
  object btnUpdateAll: TButton
    Left = 314
    Top = 418
    Width = 120
    Height = 28
    Caption = 'Update all'
    TabOrder = 5
    OnClick = btnUpdateAllClick
  end
  object btnForceDowngrade: TButton
    Left = 442
    Top = 418
    Width = 150
    Height = 28
    Caption = 'Force downgrade'
    TabOrder = 6
    OnClick = btnForceDowngradeClick
  end
  object btnSnapshotWorking: TButton
    Left = 600
    Top = 418
    Width = 120
    Height = 28
    Caption = 'Snapshot'
    TabOrder = 7
    OnClick = btnSnapshotWorkingClick
  end
  object btnRestoreWorking: TButton
    Left = 728
    Top = 418
    Width = 120
    Height = 28
    Caption = 'Restore snapshot'
    TabOrder = 8
    OnClick = btnRestoreWorkingClick
  end
  object btnOpenSnapshots: TButton
    Left = 856
    Top = 418
    Width = 110
    Height = 28
    Anchors = [akTop, akRight]
    Caption = 'Open snapshots'
    TabOrder = 9
    OnClick = btnOpenSnapshotsClick
  end
  object lblSnapshotHint: TLabel
    Left = 8
    Top = 452
    Width = 960
    Height = 15
    Anchors = [akLeft, akTop, akRight]
    Caption = 'Snapshot hint'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clGrayText
    Font.Height = -11
    Font.Name = 'Segoe UI'
    Font.Style = []
    ParentFont = False
  end
  object memLog: TMemo
    Left = 8
    Top = 474
    Width = 960
    Height = 168
    Anchors = [akLeft, akTop, akRight, akBottom]
    ReadOnly = True
    ScrollBars = ssVertical
    TabOrder = 10
  end
  object dlgOpen: TOpenDialog
    Left = 900
    Top = 418
  end
end
