unit main;

{$mode objfpc}{$H+}

{$define ASM_DBMP}

interface

uses
  LazLogger, Classes, SysUtils, windows, FileUtil, Forms, Controls, Graphics, Dialogs, ExtCtrls, typinfo,
  StdCtrls, ComCtrls, Spin, Menus, Math, types, strutils, kmodes, MTProcs, extern,
  IntfGraphics, FPimage, FPWritePNG, zstream, Process;

type
  TEncoderStep = (esNone = -1, esLoad = 0, esDither, esMakeUnique, esGlobalTiling, esFrameTiling, esReindex, esSmooth, esSave);

const
  // tweakable constants

  cBitsPerComp = 8;
  cRandomKModesCount = 7;
  cFTPaletteTol = 0.05;

{$if true}
  cRedMul = 2126;
  cGreenMul = 7152;
  cBlueMul = 722;
{$else}
  cRedMul = 299;
  cGreenMul = 587;
  cBlueMul = 114;
{$endif}
  cRGBw = 13; // in 1 / 32th

  // don't change these

  cLumaDiv = cRedMul + cGreenMul + cBlueMul;
  cSmoothingPrevFrame = 1;
  cVecInvWidth = 16;
  cRGBBitsPerComp = 8;
  cRGBColors = 1 shl (cRGBBitsPerComp * 3);
  cTileWidth = 8;
  cColorCpns = 3;
  cTileDCTSize = cColorCpns * sqr(cTileWidth);
  cPhi = (1 + sqrt(5)) / 2;
  cInvPhi = 1 / cPhi;

  cDitheringListLen = 256;
  cDitheringMap : array[0..8*8 - 1] of Byte = (
     0, 48, 12, 60,  3, 51, 15, 63,
    32, 16, 44, 28, 35, 19, 47, 31,
     8, 56,  4, 52, 11, 59,  7, 55,
    40, 24, 36, 20, 43, 27, 39, 23,
     2, 50, 14, 62,  1, 49, 13, 61,
    34, 18, 46, 30, 33, 17, 45, 29,
    10, 58,  6, 54,  9, 57,  5, 53,
    42, 26, 38, 22, 41, 25, 37, 21
  );
  cDitheringLen = length(cDitheringMap);

  cEncoderStepLen: array[TEncoderStep] of Integer = (0, 2, 3, 1, 5, 2, 2, 2, 1);

  cQ = sqrt(16);
  cDCTQuantization: array[0..cColorCpns-1{YUV}, 0..7, 0..7] of TFloat = (
    (
      // Luma
      (cQ / sqrt(16), cQ / sqrt( 11), cQ / sqrt( 10), cQ / sqrt( 16), cQ / sqrt( 24), cQ / sqrt( 40), cQ / sqrt( 51), cQ / sqrt( 61)),
      (cQ / sqrt(12), cQ / sqrt( 12), cQ / sqrt( 14), cQ / sqrt( 19), cQ / sqrt( 26), cQ / sqrt( 58), cQ / sqrt( 60), cQ / sqrt( 55)),
      (cQ / sqrt(14), cQ / sqrt( 13), cQ / sqrt( 16), cQ / sqrt( 24), cQ / sqrt( 40), cQ / sqrt( 57), cQ / sqrt( 69), cQ / sqrt( 56)),
      (cQ / sqrt(14), cQ / sqrt( 17), cQ / sqrt( 22), cQ / sqrt( 29), cQ / sqrt( 51), cQ / sqrt( 87), cQ / sqrt( 80), cQ / sqrt( 62)),
      (cQ / sqrt(18), cQ / sqrt( 22), cQ / sqrt( 37), cQ / sqrt( 56), cQ / sqrt( 68), cQ / sqrt(109), cQ / sqrt(103), cQ / sqrt( 77)),
      (cQ / sqrt(24), cQ / sqrt( 35), cQ / sqrt( 55), cQ / sqrt( 64), cQ / sqrt( 81), cQ / sqrt(104), cQ / sqrt(113), cQ / sqrt( 92)),
      (cQ / sqrt(49), cQ / sqrt( 64), cQ / sqrt( 78), cQ / sqrt( 87), cQ / sqrt(103), cQ / sqrt(121), cQ / sqrt(120), cQ / sqrt(101)),
      (cQ / sqrt(72), cQ / sqrt( 92), cQ / sqrt( 95), cQ / sqrt( 98), cQ / sqrt(112), cQ / sqrt(100), cQ / sqrt(103), cQ / sqrt( 99))
    ),
    (
      // U, weighted by luma importance
      (cQ / sqrt(17), cQ / sqrt( 18), cQ / sqrt( 24), cQ / sqrt( 47), cQ / sqrt( 99), cQ / sqrt( 99), cQ / sqrt( 99), cQ / sqrt( 99)),
      (cQ / sqrt(18), cQ / sqrt( 21), cQ / sqrt( 26), cQ / sqrt( 66), cQ / sqrt( 99), cQ / sqrt( 99), cQ / sqrt( 99), cQ / sqrt(112)),
      (cQ / sqrt(24), cQ / sqrt( 26), cQ / sqrt( 56), cQ / sqrt( 99), cQ / sqrt( 99), cQ / sqrt( 99), cQ / sqrt(112), cQ / sqrt(128)),
      (cQ / sqrt(47), cQ / sqrt( 66), cQ / sqrt( 99), cQ / sqrt( 99), cQ / sqrt( 99), cQ / sqrt(112), cQ / sqrt(128), cQ / sqrt(144)),
      (cQ / sqrt(99), cQ / sqrt( 99), cQ / sqrt( 99), cQ / sqrt( 99), cQ / sqrt(112), cQ / sqrt(128), cQ / sqrt(144), cQ / sqrt(160)),
      (cQ / sqrt(99), cQ / sqrt( 99), cQ / sqrt( 99), cQ / sqrt(112), cQ / sqrt(128), cQ / sqrt(144), cQ / sqrt(160), cQ / sqrt(176)),
      (cQ / sqrt(99), cQ / sqrt( 99), cQ / sqrt(112), cQ / sqrt(128), cQ / sqrt(144), cQ / sqrt(160), cQ / sqrt(176), cQ / sqrt(192)),
      (cQ / sqrt(99), cQ / sqrt(112), cQ / sqrt(128), cQ / sqrt(144), cQ / sqrt(160), cQ / sqrt(176), cQ / sqrt(192), cQ / sqrt(208))
    ),
    (
      // V, weighted by luma importance
      (cQ / sqrt(17), cQ / sqrt( 18), cQ / sqrt( 24), cQ / sqrt( 47), cQ / sqrt( 99), cQ / sqrt( 99), cQ / sqrt( 99), cQ / sqrt( 99)),
      (cQ / sqrt(18), cQ / sqrt( 21), cQ / sqrt( 26), cQ / sqrt( 66), cQ / sqrt( 99), cQ / sqrt( 99), cQ / sqrt( 99), cQ / sqrt(112)),
      (cQ / sqrt(24), cQ / sqrt( 26), cQ / sqrt( 56), cQ / sqrt( 99), cQ / sqrt( 99), cQ / sqrt( 99), cQ / sqrt(112), cQ / sqrt(128)),
      (cQ / sqrt(47), cQ / sqrt( 66), cQ / sqrt( 99), cQ / sqrt( 99), cQ / sqrt( 99), cQ / sqrt(112), cQ / sqrt(128), cQ / sqrt(144)),
      (cQ / sqrt(99), cQ / sqrt( 99), cQ / sqrt( 99), cQ / sqrt( 99), cQ / sqrt(112), cQ / sqrt(128), cQ / sqrt(144), cQ / sqrt(160)),
      (cQ / sqrt(99), cQ / sqrt( 99), cQ / sqrt( 99), cQ / sqrt(112), cQ / sqrt(128), cQ / sqrt(144), cQ / sqrt(160), cQ / sqrt(176)),
      (cQ / sqrt(99), cQ / sqrt( 99), cQ / sqrt(112), cQ / sqrt(128), cQ / sqrt(144), cQ / sqrt(160), cQ / sqrt(176), cQ / sqrt(192)),
      (cQ / sqrt(99), cQ / sqrt(112), cQ / sqrt(128), cQ / sqrt(144), cQ / sqrt(160), cQ / sqrt(176), cQ / sqrt(192), cQ / sqrt(208))
    )
  );

type
  // GliGli's TileMotion header structs and commands

  TGTMHeader = packed record
    FourCC: array[0..3] of AnsiChar; // ASCII "GTMv"
    RIFFSize: Cardinal;
    WholeHeaderSize: Cardinal; // including TGTMKeyFrameInfo and all
    EncoderVersion: Cardinal;
    FramePixelWidth: Cardinal;
    FramePixelHeight: Cardinal;
    KFCount: Cardinal;
    FrameCount: Cardinal;
    AverageBytesPerSec: Cardinal;
    KFMaxBytesPerSec: Cardinal;
  end;

  TGTMKeyFrameInfo = packed record
    FourCC: array[0..3] of AnsiChar; // ASCII "GTMk"
    RIFFSize: Cardinal;
    KFIndex: Cardinal;
    FrameIndex: Cardinal;
    RawSize: Cardinal;
    CompressedSize: Cardinal;
    TimeCodeMillisecond: Cardinal;
  end;

  TGTMCommand = ( // commandBits -> palette index (8 bits); V mirror (1 bit); H mirror (1 bit)
    gtSkipBlock = 0, // commandBits -> skip count - 1 (10 bits)
    gtShortTileIdx = 1, // data -> tile index (16 bits)
    gtLongTileIdx = 2, // data -> tile index (32 bits)
    gtLoadPalette = 3, // data -> palette index (8 bits); palette format (8 bits) (00: RGBA32); RGBA bytes (32bits)
    // new commands here
    gtFrameEnd = 28, // commandBits bit 0 -> keyframe end
    gtTileSet = 29, // data -> start tile (32 bits); end tile (32 bits); { indexes per tile (64 bytes) } * count; commandBits -> indexes count per palette
    gtSetDimensions = 30, // data -> height in tiles (16 bits); width in tiles (16 bits); frame length in nanoseconds (32 bits); tile count (32 bits);
    gtExtendedCommand = 31, // data -> custom commands, proprietary extensions, ...; commandBits -> extended command index (10 bits)

    gtReservedAreaBegin = 32, // reserving the MSB for future use
    gtReservedAreaEnd = 63
  );

  TFTQuality = (ftFast, ftMedium, ftSlow);

  TSpinlock = LongInt;
  PSpinLock = ^TSpinlock;

  PIntegerDynArray = ^TIntegerDynArray;
  PBoolean = ^Boolean;
  PPBoolean = ^PBoolean;

  TFloatFloatFunction = function(x: TFloat; Data: Pointer): TFloat of object;

  PTile = ^TTile;
  PPTile = ^PTile;

  TRGBPixels = array[0..(cTileWidth - 1),0..(cTileWidth - 1)] of Integer;
  TPalPixels = array[0..(cTileWidth - 1),0..(cTileWidth - 1)] of Byte;
  PRGBPixels = ^TRGBPixels;
  PPalPixels = ^TPalPixels;

  TTile = record // /!\ update CopyTile each time this structure is changed /!\
    RGBPixels: TRGBPixels;
    PalPixels: TPalPixels;

    PaletteIndexes: TIntegerDynArray;
    PaletteRGB: TIntegerDynArray;

    Active, HMirror, VMirror: Boolean;
    UseCount, TmpIndex, MergeIndex, OriginalReloadedIndex, DitheringPalIndex: Integer;
  end;

  PTileMapItem = ^TTileMapItem;

  TTileMapItem = record
    GlobalTileIndex, TmpIndex: Integer;
    PalIdx: Integer;
    HMirror, VMirror, Smoothed: Boolean;
  end;

  TTileMapItems = array of TTileMapItem;

  TTilingDataset = record
    Dataset: TANNFloatDynArray2;
    TRToTileIdx: TIntegerDynArray;
    TRToPalIdx: TByteDynArray;
    TRToAttrs: TByteDynArray;
    KDT: PANNkdtree;
    DistErrCml: TFloatDynArray;
    DistErrCnt: TIntegerDynArray;
  end;

  PTilingDataset = ^TTilingDataset;

  TCountIndexArray = packed record
    Count, Index, Luma: Integer;
    Hue, Sat, Val, Dummy: Byte;
  end;

  PCountIndexArray = ^TCountIndexArray;

  TMixingPlan = record
    // static
    LumaPal: array of Integer;
    Y2Palette: array of array[0..3] of Integer;
    Y2MixedColors: Integer;
    // dynamic
    CacheLock: TSpinlock;
    ListCache: TList;
    CountCache: TIntegerDynArray;
  end;

  TKeyFrame = class;

  { TFrame }

  TFrame = class
    PKeyFrame: TKeyFrame;
    Index: Integer;

    TileMap: array of array of TTileMapItem;
    SmoothedTileMap: array of array of TTileMapItem;

    Tiles: array of TTile;
    FSPixels: TByteDynArray;
  end;

  { TKeyFrame }

  TKeyFrame = class
    StartFrame, EndFrame, FrameCount: Integer;
    FramesLeft: Integer;
    TileDS: PTilingDataset;
    CS: TRTLCriticalSection;
    MixingPlans: array of TMixingPlan;
    PaletteIndexes: TIntegerDynArray2;
    PaletteRGB: TIntegerDynArray2;
    PaletteCentroids: TFloatDynArray2;

    PaletteUseCount: array of record
      UseCount: Integer;
      Palette: TIntegerDynArray;
      PalIdx: Integer;
    end;

    constructor Create(APaletteCount, AStartFrame, AEndFrame: Integer);
    destructor Destroy; override;
  end;

  { TMainForm }

  TMainForm = class(TForm)
    btnGTS: TButton;
    btnInput: TButton;
    btnGTM: TButton;
    btnRunAll: TButton;
    cbxFTQ: TComboBox;
    cbxScaling: TComboBox;
    cbxEndStep: TComboBox;
    cbxPalCount: TComboBox;
    cbxStartStep: TComboBox;
    cbxYilMix: TComboBox;
    cbxPalSize: TComboBox;
    cbxDLBPC: TComboBox;
    chkFTGamma: TCheckBox;
    chkUseWL: TCheckBox;
    chkGamma: TCheckBox;
    chkLowMem: TCheckBox;
    chkDitheringGamma: TCheckBox;
    chkReduced: TCheckBox;
    chkMirrored: TCheckBox;
    chkDithered: TCheckBox;
    chkPlay: TCheckBox;
    chkReload: TCheckBox;
    chkUseDL3: TCheckBox;
    chkUseTK: TCheckBox;
    edInput: TEdit;
    edOutput: TEdit;
    edReload: TEdit;
    From: TLabel;
    imgDest: TImage;
    imgPalette: TImage;
    imgSource: TImage;
    imgTiles: TImage;
    Label1: TLabel;
    Label10: TLabel;
    Label11: TLabel;
    Label12: TLabel;
    Label13: TLabel;
    Label14: TLabel;
    Label15: TLabel;
    Label16: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    Label6: TLabel;
    Label7: TLabel;
    Label9: TLabel;
    lblPct: TLabel;
    odFFInput: TOpenDialog;
    pbProgress: TProgressBar;
    pcPages: TPageControl;
    pnLbl: TPanel;
    sbTiles: TScrollBox;
    sdGTM: TSaveDialog;
    sdGTS: TSaveDialog;
    seQbTiles: TFloatSpinEdit;
    seVisGamma: TFloatSpinEdit;
    seFrameCount: TSpinEdit;
    seMaxTiles: TSpinEdit;
    sePage: TSpinEdit;
    sePalVAR: TFloatSpinEdit;
    seStartFrame: TSpinEdit;
    seTempoSmoo: TFloatSpinEdit;
    seEncGamma: TFloatSpinEdit;
    tsTilesPal: TTabSheet;
    To1: TLabel;
    tsSettings: TTabSheet;
    tsInput: TTabSheet;
    tsOutput: TTabSheet;
    Label5: TLabel;
    Label8: TLabel;
    lblCorrel: TLabel;
    MenuItem2: TMenuItem;
    MenuItem3: TMenuItem;
    MenuItem4: TMenuItem;
    MenuItem5: TMenuItem;
    MenuItem6: TMenuItem;
    MenuItem7: TMenuItem;
    miLoad: TMenuItem;
    MenuItem1: TMenuItem;
    pmProcesses: TPopupMenu;
    PopupMenu1: TPopupMenu;
    sedPalIdx: TSpinEdit;
    IdleTimer: TIdleTimer;
    tbFrame: TTrackBar;

    procedure btnGTMClick(Sender: TObject);
    procedure btnGTSClick(Sender: TObject);
    procedure btnInputClick(Sender: TObject);
    procedure btnLoadClick(Sender: TObject);
    procedure btnDitherClick(Sender: TObject);
    procedure btnDoMakeUniqueClick(Sender: TObject);
    procedure btnDoGlobalTilingClick(Sender: TObject);
    procedure btnDoFrameTilingClick(Sender: TObject);
    procedure btnReindexClick(Sender: TObject);
    procedure btnSmoothClick(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);

    procedure btnRunAllClick(Sender: TObject);
    procedure btnDebugClick(Sender: TObject);
    procedure cbxYilMixChange(Sender: TObject);
    procedure chkLowMemChange(Sender: TObject);
    procedure chkUseTKChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure IdleTimerTimer(Sender: TObject);
    procedure imgPaletteClick(Sender: TObject);
    procedure imgPaletteDblClick(Sender: TObject);
    procedure seEncGammaChange(Sender: TObject);
    procedure seMaxTilesEditingDone(Sender: TObject);
    procedure seQbTilesEditingDone(Sender: TObject);
    procedure tbFrameChange(Sender: TObject);
  private
    FKeyFrames: array of TKeyFrame;
    FFrames: array of TFrame;
    FColorMap: array[0..cRGBColors - 1, 0..5] of Byte;
    FColorMapLuma: array[0..cRGBColors - 1] of Integer;
    FTiles: array of PTile;
    FUseThomasKnoll: Boolean;
    FY2MixedColors: Integer;
    FLowMem: Boolean;
    FInputPath: String;
    FFramesPerSecond: Double;

    FProgressStep: TEncoderStep;
    FProgressPosition, FOldProgressPosition, FProgressStartTime, FProgressPrevTime: Integer;

    FTileMapWidth: Integer;
    FTileMapHeight: Integer;
    FTileMapSize: Integer;
    FScreenWidth: Integer;
    FScreenHeight: Integer;

    FPaletteCount: Integer;
    FTilePaletteSize: Integer;

    FCS: TRTLCriticalSection;
    FLock: TSpinlock;

    FGlobalDS: TTilingDataset;

    function PearsonCorrelation(const x: TFloatDynArray; const y: TFloatDynArray): TFloat;
    function ComputeCorrelationBGR(const a: TIntegerDynArray; const b: TIntegerDynArray): TFloat;
    function ComputeDistanceRGB(const a: TIntegerDynArray; const b: TIntegerDynArray): TFloat;
    function ComputeInterFrameCorrelation(a, b: TFrame): TFloat;

    procedure LoadFrame(var AFrame: TFrame; ABitmap: TBitmap);
    procedure ClearAll;
    procedure ProgressRedraw(CurFrameIdx: Integer = -1; ProgressStep: TEncoderStep = esNone);
    procedure Render(AFrameIndex: Integer; playing, dithered, mirrored, reduced, gamma: Boolean; palIdx: Integer;
      ATilePage: Integer);
    procedure ReframeUI(AWidth, AHeight: Integer);

    procedure DitherFloydSteinberg(const AScreen: TByteDynArray);

    function HSVToRGB(h, s, v: Byte): Integer;
    procedure RGBToHSV(col: Integer; out h, s, v: Byte); overload;
    procedure RGBToHSV(col: Integer; out h, s, v: TFloat); overload;
    procedure RGBToYUV(col: Integer; GammaCor: Integer; out y, u, v: TFloat);
    procedure RGBToYUV(r, g, b: Byte; GammaCor: Integer; out y, u, v: TFloat);
    procedure RGBToLAB(r, g, b: TFloat; GammaCor: Integer; out ol, oa, ob: TFloat);
    procedure RGBToLAB(ir, ig, ib: Integer; GammaCor: Integer; out ol, oa, ob: TFloat);
    function LABToRGB(ll, aa, bb: TFloat): Integer;
    function YUVToRGB(y, u, v: TFloat): Integer;

    procedure WaveletGS(Data: PFloat; Output: PFloat; dx, dy, depth: cardinal);
    procedure DeWaveletGS(wl: PFloat; pic: PFloat; dx, dy, depth: longint);
    procedure ComputeTilePsyVisFeatures(const ATile: TTile; FromPal, UseWavelets, UseLAB, QWeighting, HMirror,
      VMirror: Boolean; GammaCor: Integer; const pal: TIntegerDynArray; var DCT: TFloatDynArray); inline;

    // Dithering algorithms ported from http://bisqwit.iki.fi/story/howto/dither/jy/

    function ColorCompare(r1, g1, b1, r2, g2, b2: Int64): Int64;
    procedure PreparePlan(var Plan: TMixingPlan; MixedColors: Integer; const pal: array of Integer);
    procedure TerminatePlan(var Plan: TMixingPlan);
    function DeviseBestMixingPlanYliluoma(var Plan: TMixingPlan; col: Integer; List: TByteDynArray): Integer;
    procedure DeviseBestMixingPlanThomasKnoll(var Plan: TMixingPlan; col: Integer; var List: TByteDynArray);
    procedure DitherTileFloydSteinberg(ATile: TTile; out RGBPixels: TRGBPixels);

    procedure LoadTiles;
    function GetGlobalTileCount: Integer;
    function GetFrameTileCount(AFrame: TFrame): Integer;
    procedure CopyTile(const Src: TTile; var Dest: TTile);

    procedure PrepareDitherTiles(AKeyFrame: TKeyFrame; ADitheringGamma: Integer; AUseWavelets: Boolean);
    procedure QuantizePalette(AKeyFrame: TKeyFrame; APalIdx: Integer; UseDLv3: Boolean; PalVAR: TFloat; DLv3BPC: Integer);
    procedure FinishQuantizePalette(AKeyFrame: TKeyFrame);
    procedure DitherTile(var ATile: TTile; var Plan: TMixingPlan);
    procedure FinishDitherTiles(AFrame: TFrame; ADitheringGamma: Integer; AUseWavelets: Boolean);

    function GetTileZoneSum(const ATile: TTile; x, y, w, h: Integer): Integer;
    function GetTilePalZoneThres(const ATile: TTile; ZoneCount: Integer; Zones: PByte): Integer;
    procedure MakeTilesUnique(FirstTileIndex, TileCount: Integer);
    procedure MergeTiles(const TileIndexes: array of Integer; TileCount: Integer; BestIdx: Integer; NewTile: PPalPixels; NewTileRGB: PRGBPixels);
    procedure InitMergeTiles;
    procedure FinishMergeTiles;
    function WriteTileDatasetLine(const ATile: TTile; DataLine: TByteDynArray; out PalSigni: Integer): Integer;
    procedure DoKModes(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
    procedure DoGlobalTiling(OutFN: String; DesiredNbTiles, RestartCount: Integer);

    procedure ReloadPreviousTiling(AFN: String);

    procedure HMirrorPalTile(var ATile: TTile);
    procedure VMirrorPalTile(var ATile: TTile);
    procedure PrepareGlobalFT;
    procedure FinishGlobalFT;
    procedure PrepareFrameTiling(AKF: TKeyFrame; AFTGamma: Integer; APalTol: TFloat; AUseWavelets: Boolean; AFTQuality: TFTQuality);
    procedure FinishFrameTiling(AKF: TKeyFrame);
    procedure DoFrameTiling(AFrame: TFrame; AFTGamma: Integer; APalVAR: TFloat; AUseWavelets: Boolean; AFTQuality: TFTQuality);
    procedure PrepareTileMirrors(var ATile: TTile);

    function GetTileUseCount(ATileIndex: Integer): Integer;
    procedure ReindexTiles;
    procedure DoTemporalSmoothing(AFrame, APrevFrame: TFrame; Y: Integer; Strength: TFloat);

    procedure SaveStream(AStream: TStream);

    function DoExternalFFMpeg(AFN: String; var AVidPath: String; AStartFrame, AFrameCount: Integer; AScale: Double; out
      AFPS: Double): String;
  public
    { public declarations }
  end;

  { T8BitPortableNetworkGraphic }

  T8BitPortableNetworkGraphic = class(TPortableNetworkGraphic)
    procedure InitializeWriter(AImage: TLazIntfImage; AWriter: TFPCustomImageWriter); override;
  end;

  { TFastPortableNetworkGraphic }

  TFastPortableNetworkGraphic = class(TPortableNetworkGraphic)
    procedure InitializeWriter(AImage: TLazIntfImage; AWriter: TFPCustomImageWriter); override;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

procedure SpinEnter(Lock: PSpinLock); assembler;
label spin_lock;
asm
spin_lock:
     mov     eax, 1          // Set the EAX register to 1.

     xchg    eax, [Lock]     // Atomically swap the EAX register with the lock variable.
                             // This will always store 1 to the lock, leaving the previous value in the EAX register.

     test    eax, eax        // Test EAX with itself. Among other things, this will set the processor's Zero Flag if EAX is 0.
                             // If EAX is 0, then the lock was unlocked and we just locked it.
                             // Otherwise, EAX is 1 and we didn't acquire the lock.

     jnz     spin_lock       // Jump back to the MOV instruction if the Zero Flag is not set;
                             // the lock was previously locked, and so we need to spin until it becomes unlocked.
end;

procedure SpinLeave(Lock: PSpinLock); assembler;
asm
    xor     eax, eax        // Set the EAX register to 0.

    xchg    eax, [Lock]     // Atomically swap the EAX register with the lock variable.
end;

function HasParam(p: String): Boolean;
var i: Integer;
begin
  Result := False;
  for i := 1 to ParamCount do
    if SameText(p, ParamStr(i)) then
      Exit(True);
end;

function ParamStart(p: String): Integer;
var i: Integer;
begin
  Result := -1;
  for i := 1 to ParamCount do
    if AnsiStartsStr(p, ParamStr(i)) then
      Exit(i);
end;

function ParamValue(p: String; def: Double): Double;
var
  idx: Integer;
begin
  idx := ParamStart(p);
  if idx < 0 then
    Exit(def);
  Result := StrToFloatDef(system.copy(ParamStr(idx), Length(p) + 1), def);
end;

procedure Exchange(var a, b: Integer);
var
  tmp: Integer;
begin
  tmp := b;
  b := a;
  a := tmp;
end;

function iDiv0(x,y:Integer):Integer;inline;
begin
  Result:=0;
  if y <> 0 then
    Result:=x div y;
end;

function SwapRB(c: Integer): Integer; inline;
begin
  Result := ((c and $ff) shl 16) or ((c shr 16) and $ff) or (c and $ff00);
end;

function ToRGB(r, g, b: Byte): Integer; inline;
begin
  Result := (b shl 16) or (g shl 8) or r;
end;

procedure FromRGB(col: Integer; out r, g, b: Integer); inline; overload;
begin
  r := col and $ff;
  g := (col shr 8) and $ff;
  b := (col shr 16) and $ff;
end;

procedure FromRGB(col: Integer; out r, g, b: Byte); inline; overload;
begin
  r := col and $ff;
  g := (col shr 8) and $ff;
  b := (col shr 16) and $ff;
end;

var
  gGamma: array[0..1] of TFloat = (2.0, 0.6);
  gGammaCorLut: array[-1..High(gGamma), 0..High(Byte)] of TFloat;
  gVecInv: array[0..256 * 4 - 1] of Cardinal;
  gDCTLut:array[0..sqr(sqr(cTileWidth)) - 1] of TFloat;
  gPalettePattern : TFloatDynArray2;

procedure InitLuts(ATilePaletteSize, APaletteCount: Integer);
const
  cCurvature = 2.0;
var
  g, i, j, v, u, y, x: Int64;
  f, fp: TFloat;
begin
  // gamma

  for g := -1 to High(gGamma) do
    for i := 0 to High(Byte) do
      if g >= 0 then
        gGammaCorLut[g, i] := power(i / 255.0, gGamma[g])
      else
        gGammaCorLut[g, i] := i / 255.0;

  // inverse

  for i := 0 to High(gVecInv) do
    gVecInv[i] := iDiv0(1 shl cVecInvWidth, i shr 2);

  // DCT

  i := 0;
  for v := 0 to (cTileWidth - 1) do
    for u := 0 to (cTileWidth - 1) do
      for y := 0 to (cTileWidth - 1) do
        for x := 0 to (cTileWidth - 1) do
        begin
          gDCTLut[i] := cos((x + 0.5) * u * PI / 16.0) * cos((y + 0.5) * v * PI / 16.0);
          Inc(i);
        end;

  // palette pattern

  SetLength(gPalettePattern, APaletteCount, ATilePaletteSize);

  f := 0;
  for i := 0 to ATilePaletteSize - 1 do
  begin
    fp := f;
    f := power(i + 2, cCurvature);

    for j := 0 to APaletteCount - 1 do
      gPalettePattern[j, i] := ((j + 1) / APaletteCount) * max(APaletteCount, f - fp) + fp;
  end;

  for j := 0 to APaletteCount - 1 do
    for i := 0 to ATilePaletteSize - 1 do
      gPalettePattern[j, i] /= gPalettePattern[APaletteCount - 1, ATilePaletteSize - 1];
end;

function GammaCorrect(lut: Integer; x: Byte): TFloat; inline;
begin
  Result := gGammaCorLut[lut, x];
end;

function lerp(x, y, alpha: TFloat): TFloat; inline;
begin
  Result := x + (y - x) * alpha;
end;

function revlerp(x, y, alpha: TFloat): TFloat; inline;
begin
  Result := (alpha - x) / (y - x);
end;

function CompareEuclideanDCTPtr(pa, pb: PFloat): TFloat;
var
  i: Integer;
begin
  Result := 0;
  for i := cTileDCTSize div 8 - 1 downto 0 do
  begin
    Result += sqr(pa^ - pb^); Inc(pa); Inc(pb);
    Result += sqr(pa^ - pb^); Inc(pa); Inc(pb);
    Result += sqr(pa^ - pb^); Inc(pa); Inc(pb);
    Result += sqr(pa^ - pb^); Inc(pa); Inc(pb);
    Result += sqr(pa^ - pb^); Inc(pa); Inc(pb);
    Result += sqr(pa^ - pb^); Inc(pa); Inc(pb);
    Result += sqr(pa^ - pb^); Inc(pa); Inc(pb);
    Result += sqr(pa^ - pb^); Inc(pa); Inc(pb);
  end;
end;

function CompareEuclideanDCT(const a, b: TFloatDynArray): TFloat; inline;
begin
  Result := CompareEuclideanDCTPtr(@a[0], @b[0]);
end;

function CompareEuclidean(const a, b: TFloatDynArray): TFloat; inline;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(a) do
    Result += sqr(a[i] - b[i]);
  Result := sqrt(Result);
end;

function CompareEuclideanANN(const a, b: TANNFloatDynArray): TANNFloat; inline;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(a) do
    Result += sqr(a[i] - b[i]);
  Result := sqrt(Result);
end;

const
  CvtPre =  (1 shl cBitsPerComp) - 1;
  CvtPost = 256 div CvtPre;

function Posterize(v: Integer): Byte; inline;
begin
  Result := min(255, (((v * CvtPre) div 255) * CvtPost));
end;

function Decimate(col: Integer): Integer; inline;
var
  r, g, b: Byte;
begin
  FromRGB(col, r, g, b);
  r := r shr (8 - cBitsPerComp);
  g := g shr (8 - cBitsPerComp);
  b := b shr (8 - cBitsPerComp);
  Result := r or (g shl cBitsPerComp) or (b shl (cBitsPerComp * 2));
end;

function EqualQualityTileCount(tileCount: TFloat): Integer;
begin
  Result := round(sqrt(tileCount) * log2(1 + tileCount));
end;

{ TKeyFrame }

constructor TKeyFrame.Create(APaletteCount, AStartFrame, AEndFrame: Integer);
begin
  StartFrame := AStartFrame;
  EndFrame := AEndFrame;
  FrameCount := AEndFrame - AStartFrame + 1;
  FramesLeft := -1;
  InitializeCriticalSection(CS);
  SetLength(MixingPlans, APaletteCount);
  SetLength(PaletteIndexes, APaletteCount);
  SetLength(PaletteRGB, APaletteCount);
end;

destructor TKeyFrame.Destroy;
begin
  inherited Destroy;
  DeleteCriticalSection(CS);
end;

{ T8BitPortableNetworkGraphic }

procedure T8BitPortableNetworkGraphic.InitializeWriter(AImage: TLazIntfImage; AWriter: TFPCustomImageWriter);
var
  W: TFPWriterPNG absolute AWriter;
begin
  inherited InitializeWriter(AImage, AWriter);
  W.Indexed := True;
  W.UseAlpha := False;
  W.CompressionLevel := clfastest;
end;

{ TFastPortableNetworkGraphic }

procedure TFastPortableNetworkGraphic.InitializeWriter(AImage: TLazIntfImage; AWriter: TFPCustomImageWriter);
var
  W: TFPWriterPNG absolute AWriter;
begin
  inherited InitializeWriter(AImage, AWriter);
  W.CompressionLevel := clfastest;
end;

function TMainForm.ComputeCorrelationBGR(const a: TIntegerDynArray; const b: TIntegerDynArray): TFloat;
var
  i: Integer;
  ya, yb: TDoubleDynArray;
  fr, fg, fb: TFloat;
begin
  SetLength(ya, Length(a) * 3);
  SetLength(yb, Length(a) * 3);

  for i := 0 to High(a) do
  begin
    fr := (a[i] shr 16) and $ff; fg := (a[i] shr 8) and $ff; fb := a[i] and $ff;
    ya[i] := fr * cRedMul; ya[i + Length(a)] := fg * cGreenMul; ya[i + Length(a) * 2] := fb * cBlueMul;

    fr := (b[i] shr 16) and $ff; fg := (b[i] shr 8) and $ff; fb := b[i] and $ff;
    yb[i] := fr * cRedMul; yb[i + Length(a)] := fg * cGreenMul; yb[i + Length(a) * 2] := fb * cBlueMul;
  end;

  Result := PearsonCorrelation(ya, yb);
end;

function TMainForm.ComputeDistanceRGB(const a: TIntegerDynArray; const b: TIntegerDynArray): TFloat;
var
  i: Integer;
  ya, yb: TDoubleDynArray;
  fr, fg, fb: TFloat;
begin
  SetLength(ya, Length(a) * 3);
  SetLength(yb, Length(a) * 3);

  for i := 0 to High(a) do
  begin
    fr := a[i] and $ff; fg := (a[i] shr 8) and $ff; fb := (a[i] shr 16) and $ff;
    ya[i] := fr * cRedMul; ya[i + Length(a)] := fg * cGreenMul; ya[i + Length(a) * 2] := fb * cBlueMul;

    fr := b[i] and $ff; fg := (b[i] shr 8) and $ff; fb := (b[i] shr 16) and $ff;
    yb[i] := fr * cRedMul; yb[i + Length(a)] := fg * cGreenMul; yb[i + Length(a) * 2] := fb * cBlueMul;
  end;

  Result := CompareEuclidean(ya, yb) / (Length(a) * cLumaDiv * 256.0);
end;

function TMainForm.ComputeInterFrameCorrelation(a, b: TFrame): TFloat;
var
  sz, i: Integer;
  ya, yb: TDoubleDynArray;
begin
  Assert(Length(a.FSPixels) = Length(b.FSPixels));
  sz := Length(a.FSPixels) div 3;
  SetLength(ya, sz * 3);
  SetLength(yb, sz * 3);

  for i := 0 to sz - 1 do
  begin
    ya[i + sz * 0] := a.FSPixels[i * 3 + 0];
    ya[i + sz * 1] := a.FSPixels[i * 3 + 1];
    ya[i + sz * 2] := a.FSPixels[i * 3 + 2];

    yb[i + sz * 0] := b.FSPixels[i * 3 + 0];
    yb[i + sz * 1] := b.FSPixels[i * 3 + 1];
    yb[i + sz * 2] := b.FSPixels[i * 3 + 2];
  end;

  Result := PearsonCorrelation(ya, yb);
end;

{ TMainForm }

procedure TMainForm.btnDoGlobalTilingClick(Sender: TObject);
begin
  if Length(FFrames) = 0 then
    Exit;

  ProgressRedraw(-1, esGlobalTiling);

  if chkReload.Checked then
  begin
    if not FileExists(edReload.Text) then
      raise EFileNotFoundException.Create('File not found: ' + edReload.Text);
    ReloadPreviousTiling(edReload.Text);
  end
  else
  begin
    DoGlobalTiling(edReload.Text, seMaxTiles.Value, cRandomKModesCount);
  end;

  tbFrameChange(nil);
end;

procedure TMainForm.btnDitherClick(Sender: TObject);
var
  Gamma: Integer;
  UseWavelets: Boolean;
  UseDL3: Boolean;
  DLBPC: Integer;
  PalVAR: TFloat;
  i: Integer;

  procedure DoPrepare(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
  begin
    PrepareDitherTiles(FKeyFrames[AIndex], Gamma, UseWavelets);
  end;

  procedure DoQuantize(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
  begin
    QuantizePalette(FKeyFrames[AIndex div FPaletteCount], AIndex mod FPaletteCount, UseDL3, PalVAR, DLBPC);
  end;

  procedure DoFinish(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
  begin
    FinishDitherTiles(FFrames[AIndex], Gamma, UseWavelets);
  end;

begin
  if Length(FFrames) = 0 then
    Exit;

  Gamma := IfThen(chkDitheringGamma.Checked, 0, -1);
  UseWavelets := chkUseWL.Checked;
  UseDL3 := chkUseDL3.Checked;
  DLBPC := StrToInt(cbxDLBPC.Text);
  PalVAR := sePalVAR.Value / 100;

  ProgressRedraw(-1, esDither);
  ProcThreadPool.DoParallelLocalProc(@DoPrepare, 0, High(FKeyFrames));
  WriteLn;
  ProgressRedraw(1);

  for i := 0 to High(FKeyFrames) do
  begin
    SetLength(FKeyFrames[i].PaletteUseCount, FPaletteCount);
  end;
  ProcThreadPool.DoParallelLocalProc(@DoQuantize, 0, Length(FKeyFrames) * FPaletteCount - 1);
  WriteLn;
  for i := 0 to High(FKeyFrames) do
  begin
    FinishQuantizePalette(FKeyFrames[i]);
    SetLength(FKeyFrames[i].PaletteUseCount, 0);
  end;
  ProgressRedraw(2);

  ProcThreadPool.DoParallelLocalProc(@DoFinish, 0, High(FFrames));
  ProgressRedraw(3);

  tbFrameChange(nil);
end;

procedure TMainForm.btnDoMakeUniqueClick(Sender: TObject);
var
  TilesAtATime: Integer;

  procedure DoMakeUnique(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
  begin
    MakeTilesUnique(AIndex * TilesAtATime, Min(Length(FTiles) - AIndex * TilesAtATime, TilesAtATime));
  end;

begin
  TilesAtATime := FTileMapSize * 25;

  if Length(FFrames) = 0 then
    Exit;

  ProgressRedraw(-1, esMakeUnique);

  ProcThreadPool.DoParallelLocalProc(@DoMakeUnique, 0, High(FTiles) div TilesAtATime);

  ProgressRedraw(1);

  tbFrameChange(nil);
end;

function CompareFrames(Item1,Item2,UserParameter:Pointer):Integer;
begin
  Result := CompareValue(PInteger(Item2)^, PInteger(Item1)^);
end;

procedure TMainForm.btnDoFrameTilingClick(Sender: TObject);
var
  Gamma: Integer;
  UseWavelets: Boolean;
  FTQuality: TFTQuality;

  procedure DoFrm(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
  begin
    DoFrameTiling(FFrames[AIndex], Gamma, cFTPaletteTol, UseWavelets, FTQuality);
  end;

var
  i: Integer;
begin
  if Length(FKeyFrames) = 0 then
    Exit;

  Gamma := IfThen(chkFTGamma.Checked, 0, -1);
  UseWavelets := chkUseWL.Checked;
  FTQuality := TFTQuality(cbxFTQ.ItemIndex);

  for i := 0 to High(FKeyFrames) do
    FKeyFrames[i].FramesLeft := -1;

  ProgressRedraw(-1, esFrameTiling);
  PrepareGlobalFT;
  ProgressRedraw(1);
  ProcThreadPool.DoParallelLocalProc(@DoFrm, 0, High(FFrames));
  FinishGlobalFT;
  ProgressRedraw(2);

  tbFrameChange(nil);
end;

procedure TMainForm.chkUseTKChange(Sender: TObject);
begin
  FUseThomasKnoll := chkUseTK.Checked;
end;

procedure TMainForm.btnLoadClick(Sender: TObject);
const
  CShotTransMaxTilesPerKF = 24 * 1920 * 1080 div sqr(cTileWidth);
  CShotTransGracePeriod = 24;
  CShotTransSAvgFrames = 6;
  CShotTransSoftThres = 0.9;
  CShotTransHardThres = 0.5;

  procedure DoLoadFrame(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
  var
    bmp: TPicture;
  begin
    bmp := TPicture.Create;
    try
      EnterCriticalSection(FCS);
      bmp.Bitmap.PixelFormat:=pf32bit;
      bmp.LoadFromFile(Format(FInputPath, [AIndex + PtrUInt(AData)]));
      LeaveCriticalSection(FCS);

      LoadFrame(FFrames[AIndex], bmp.Bitmap);

      FFrames[AIndex].Index := AIndex;
    finally
      bmp.Free;
    end;
  end;

var
  i, j, Cnt, LastKFIdx: Integer;
  v, av, ratio: TFloat;
  fn: String;
  kfIdx, frc, StartFrame: Integer;
  isKf: Boolean;
  sfr, efr: Integer;
  bmp: TPicture;
  wasAutoQ: Boolean;
begin
  FTilePaletteSize := StrToInt(cbxPalSize.Text);
  FPaletteCount := StrToInt(cbxPalCount.Text);
  wasAutoQ := seMaxTiles.Value = round(seQbTiles.Value * EqualQualityTileCount(Length(FFrames) * FTileMapSize));

  ProgressRedraw;

  ClearAll;

  ProgressRedraw(-1, esLoad);

  // init Gamma LUTs

  InitLuts(FTilePaletteSize, FPaletteCount);

  // load video

  StartFrame := seStartFrame.Value;
  frc := seFrameCount.Value;

  if FileExists(edInput.Text) then
  begin
    DoExternalFFMpeg(edInput.Text, FInputPath, StartFrame, frc, StrToFloat(cbxScaling.Text), FFramesPerSecond);
    StartFrame := 1;
  end
  else
  begin
    FInputPath := edInput.Text;
    FFramesPerSecond := 24.0;
  end;

  if frc <= 0 then
  begin
    if Pos('%', FInputPath) > 0 then
    begin
      i := 0;
      repeat
        fn := Format(FInputPath, [i + StartFrame]);
        Inc(i);
      until not FileExists(fn);

      frc := i - 1;
    end
    else
    begin
      frc := 1;
    end;

    seFrameCount.Value := frc;
    seFrameCount.Repaint;
  end;

  SetLength(FFrames, frc);
  tbFrame.Max := High(FFrames);

  for i := 0 to High(FFrames) do
  begin
    fn := Format(FInputPath, [i + StartFrame]);
    if not FileExists(fn) then
    begin
      SetLength(FFrames, 0);
      tbFrame.Max := 0;
      raise EFileNotFoundException.Create('File not found: ' + fn);
    end;
  end;

  bmp := TPicture.Create;
  try
    bmp.Bitmap.PixelFormat:=pf32bit;
    bmp.LoadFromFile(Format(FInputPath, [StartFrame]));
    ReframeUI(bmp.Width div cTileWidth, bmp.Height div cTileWidth);
  finally
    bmp.Free;
  end;

  ProcThreadPool.DoParallelLocalProc(@DoLoadFrame, 0, High(FFrames), Pointer(StartFrame));

  // find keyframes

  kfIdx := 0;
  SetLength(FKeyFrames, Length(FFrames));
  FKeyFrames[0] := TKeyFrame.Create(FPaletteCount, 0, 0);
  FFrames[0].PKeyFrame := FKeyFrames[0];

  av := -1.0;
  LastKFIdx := 0;
  for i := 1 to High(FFrames) do
  begin
    Cnt := 0;
    v := ComputeInterFrameCorrelation(FFrames[i - 1], FFrames[i]);
    if av = -1.0 then
    begin
      av := v
    end
    else
    begin
      av := av * (1.0 - 1.0 / CShotTransSAvgFrames) + v * (1.0 / CShotTransSAvgFrames);
      Inc(Cnt);
    end;

    ratio := max(0.01, v) / max(0.01, av);
    isKf := (ratio < CShotTransHardThres) or
      (ratio < CShotTransSoftThres) and ((i - LastKFIdx + 1) > CShotTransGracePeriod) or
      ((i - LastKFIdx + 1) * FTileMapSize > CShotTransMaxTilesPerKF);
    if isKf then
    begin
      Inc(kfIdx);
      FKeyFrames[kfIdx] := TKeyFrame.Create(FPaletteCount, 0, 0);

      av := -1.0;
      LastKFIdx := i;

      WriteLn('KF: ', kfIdx, #9'Frame: -> ', i, #9'Ratio: ', FloatToStr(ratio));
    end;

    FFrames[i].PKeyFrame := FKeyFrames[kfIdx];
  end;

  SetLength(FKeyFrames, kfIdx + 1);

  for j := 0 to High(FKeyFrames) do
  begin
    sfr := High(Integer);
    efr := Low(Integer);

    for i := 0 to High(FFrames) do
      if FFrames[i].PKeyFrame = FKeyFrames[j] then
      begin
        sfr := Min(sfr, i);
        efr := Max(efr, i);
      end;

    FKeyFrames[j].StartFrame := sfr;
    FKeyFrames[j].EndFrame := efr;
    FKeyFrames[j].FrameCount := efr - sfr + 1;
  end;

  ProgressRedraw(1);

  LoadTiles;

  ProgressRedraw(2);

  if wasAutoQ or (seMaxTiles.Value <= 0) then
    seQbTilesEditingDone(nil);
  tbFrameChange(nil);
end;

procedure TMainForm.btnInputClick(Sender: TObject);
begin
  odFFInput.InitialDir := ExtractFileDir(edInput.Text);
  if odFFInput.Execute then
  begin
    if (edOutput.Text = '') or (edOutput.Text = ChangeFileExt(edInput.Text, '.gtm')) then
    begin
      edOutput.Text := ChangeFileExt(odFFInput.FileName, '.gtm');
      sdGTM.FileName := edOutput.Text;
    end;
    if (edReload.Text = '') or (edReload.Text = ChangeFileExt(edInput.Text, '.gts')) then
    begin
      edReload.Text := ChangeFileExt(odFFInput.FileName, '.gts');
      sdGTS.FileName := edReload.Text;
    end;
    edInput.Text := odFFInput.FileName;
  end;
end;

procedure TMainForm.btnGTMClick(Sender: TObject);
begin
  if sdGTM.Execute then
    edOutput.Text := sdGTM.FileName;
end;

procedure TMainForm.btnGTSClick(Sender: TObject);
begin
  if sdGTS.Execute then
    edReload.Text := sdGTS.FileName;
end;

procedure TMainForm.btnReindexClick(Sender: TObject);
var
  i, sx, sy, tidx: Integer;
begin
  if Length(FFrames) = 0 then
    Exit;

  ProgressRedraw(-1, esReindex);

  for i := 0 to High(FTiles) do
  begin
    FTiles[i]^.UseCount := 0;
    FTiles[i]^.Active := False;
  end;

  for i := 0 to High(FFrames) do
    for sy := 0 to FTileMapHeight - 1 do
      for sx := 0 to FTileMapWidth - 1 do
      begin
        tidx := FFrames[i].TileMap[sy, sx].GlobalTileIndex;
        Inc(FTiles[tidx]^.UseCount);
        FTiles[tidx]^.Active := True;
      end;

  ProgressRedraw(1);

  ReindexTiles;

  ProgressRedraw(2);

  tbFrameChange(nil);
end;

procedure TMainForm.btnRunAllClick(Sender: TObject);
var
  firstStep: TEncoderStep;
  lastStep: TEncoderStep;

  function OkStep(Step: TEncoderStep): Boolean;
  begin
    Result := (Step >= firstStep) and (Step <= lastStep);
  end;

begin
  firstStep := TEncoderStep(cbxStartStep.ItemIndex);
  lastStep := TEncoderStep(cbxEndStep.ItemIndex);

  if OkStep(esLoad) then
    btnLoadClick(nil);

  if OkStep(esDither) then
    btnDitherClick(nil);

  if OkStep(esMakeUnique) then
    btnDoMakeUniqueClick(nil);

  if OkStep(esGlobalTiling) then
    btnDoGlobalTilingClick(nil);

  if OkStep(esFrameTiling) then
    btnDoFrameTilingClick(nil);

  if OkStep(esReindex) then
    btnReindexClick(nil);

  if OkStep(esSmooth) then
    btnSmoothClick(nil);

  if OkStep(esSave) then
    btnSaveClick(nil);

  ProgressRedraw;
  tbFrameChange(nil);
end;

procedure TMainForm.btnDebugClick(Sender: TObject);
var
  i, j: Integer;
  seed: Cardinal;
  pal: array[0..15] of Integer;
  list: TByteDynArray;
  plan: TMixingPlan;

  hh,ss,ll: Byte;

  dlpal: TDLUserPal;
begin
  seed := 42;
  for i := 0 to 15 do
    pal[i] := RandInt(1 shl 24, seed);
  PreparePlan(plan, 4, pal);

  SetLength(list, cDitheringListLen);
  DeviseBestMixingPlanYliluoma(plan, $ffffff, list);
  DeviseBestMixingPlanYliluoma(plan, $ff8000, list);
  DeviseBestMixingPlanYliluoma(plan, $808080, list);
  DeviseBestMixingPlanYliluoma(plan, $000000, list);


  for i := 0 to 255 do
    for j := 0 to 255 do
    begin
      hh := 0; ss := 0; ll := 0;
      RGBToHSV(HSVToRGB(i,j,255), hh, ss, ll);
      imgDest.Canvas.Pixels[i,j] := SwapRB(HSVToRGB(hh,ss,ll));
    end;

  imgDest.Picture.Bitmap.BeginUpdate;
  imgDest.Picture.Bitmap.ScanLine[0];
  dl3quant(PByte(imgDest.Picture.Bitmap.ScanLine[0]), imgDest.Picture.Bitmap.Width, cBitsPerComp - 2, imgDest.Picture.Bitmap.Height, 64, @dlpal);
  imgDest.Picture.Bitmap.EndUpdate;

  for i := 0 to 255 do
    writeln(dlpal[0][i], #9, dlpal[1][i], #9, dlpal[2][i]);

  TerminatePlan(plan);
end;

procedure TMainForm.btnSaveClick(Sender: TObject);
var
  fs: TFileStream;
begin
  if Length(FFrames) = 0 then
    Exit;

  ProgressRedraw(-1, esSave);

  fs := TFileStream.Create(edOutput.Text, fmCreate or fmShareDenyWrite);
  try
    SaveStream(fs);
  finally
    fs.Free;
  end;

  ProgressRedraw(1);

  tbFrameChange(nil);
end;

procedure TMainForm.btnSmoothClick(Sender: TObject);
var
  smoo: TFloat;

  procedure DoSmoothing(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
  var
    i: Integer;
  begin
    for i := cSmoothingPrevFrame to High(FFrames) do
      DoTemporalSmoothing(FFrames[i], FFrames[i - cSmoothingPrevFrame], AIndex, smoo);
  end;

var
  frm, j, i: Integer;
begin
  if Length(FFrames) = 0 then
    Exit;

  smoo := seTempoSmoo.Value / 1000.0;

  ProgressRedraw(-1, esSmooth);

  for frm := 0 to high(FFrames) do
    for j := 0 to (FTileMapHeight - 1) do
      for i := 0 to (FTileMapWidth - 1) do
        FFrames[frm].SmoothedTileMap[j, i] := FFrames[frm].TileMap[j, i];
  ProgressRedraw(1);

  ProcThreadPool.DoParallelLocalProc(@DoSmoothing, 0, FTileMapHeight - 1);
  ProgressRedraw(2);

  tbFrameChange(nil);
end;

procedure TMainForm.cbxYilMixChange(Sender: TObject);
begin
  FY2MixedColors := StrToIntDef(cbxYilMix.Text, 16);
end;

procedure TMainForm.chkLowMemChange(Sender: TObject);
begin
  FLowMem := chkLowMem.Checked;
end;

procedure TMainForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  k: Word;
begin
  k := Key;
  if k in [VK_F2, VK_F3, VK_F4, VK_F5, VK_F6, VK_F7, VK_F8, VK_F9, VK_F10, VK_F11, VK_F12, VK_ESCAPE] then
    Key := 0; // KLUDGE: workaround event called twice
  case k of
    VK_F2: btnLoadClick(nil);
    VK_F3: btnDitherClick(nil);
    VK_F4: btnDoMakeUniqueClick(nil);
    VK_F5: btnDoGlobalTilingClick(nil);
    VK_F6: btnDoFrameTilingClick(nil);
    VK_F7: btnReindexClick(nil);
    VK_F8: btnSmoothClick(nil);
    VK_F9: btnSaveClick(nil);
    VK_F10: btnRunAllClick(nil);
    VK_F11: chkPlay.Checked := not chkPlay.Checked;
    VK_F12: btnDebugClick(nil);
    VK_ESCAPE: TerminateProcess(GetCurrentProcess, 1);
  end;
end;

procedure TMainForm.IdleTimerTimer(Sender: TObject);
begin
  if chkPlay.Checked then
  begin
    if tbFrame.Position >= tbFrame.Max then
    begin
      tbFrame.Position := 0;
      Exit;
    end;

    tbFrame.Position := tbFrame.Position + 1;
  end;
end;

procedure TMainForm.imgPaletteClick(Sender: TObject);
var
  P: TPoint;
begin
  P := imgPalette.ScreenToClient(Mouse.CursorPos);
  sedPalIdx.Value := iDiv0(P.y * FPaletteCount, imgPalette.Height);
end;

procedure TMainForm.imgPaletteDblClick(Sender: TObject);
begin
  sedPalIdx.Value := -1;
end;

procedure TMainForm.seQbTilesEditingDone(Sender: TObject);
var
  RawTileCount: Integer;
begin
  if Length(FFrames) * FTileMapSize = 0 then Exit;
  RawTileCount := Length(FFrames) * FTileMapSize;
  seMaxTiles.Value := min(round(seQbTiles.Value * EqualQualityTileCount(RawTileCount)), RawTileCount);
end;

procedure TMainForm.seEncGammaChange(Sender: TObject);
begin
  gGamma[0] := seEncGamma.Value;
  gGamma[1] := seVisGamma.Value;
  InitLuts(FTilePaletteSize, FPaletteCount);
  tbFrameChange(nil);
end;

procedure TMainForm.seMaxTilesEditingDone(Sender: TObject);
var
  RawTileCount: Integer;
begin
  if Length(FFrames) * FTileMapSize = 0 then Exit;
  RawTileCount := Length(FFrames) * FTileMapSize;
  seMaxTiles.Value := EnsureRange(seMaxTiles.Value, 1, RawTileCount);
end;

procedure TMainForm.tbFrameChange(Sender: TObject);
begin
  IdleTimer.Interval := round(1000 / FFramesPerSecond);
  Screen.Cursor := crDefault;
  Render(tbFrame.Position, chkPlay.Checked, chkDithered.Checked, chkMirrored.Checked, chkReduced.Checked,  chkGamma.Checked, sedPalIdx.Value, sePage.Value);
end;

function TMainForm.PearsonCorrelation(const x: TFloatDynArray; const y: TFloatDynArray): TFloat;
var
  mx, my, num, den, denx, deny: TFloat;
  i: Integer;
begin
  Assert(Length(x) = Length(y));

  mx := mean(x);
  my := mean(y);

  num := 0.0;
  denx := 0.0;
  deny := 0.0;
  for i := 0 to High(x) do
  begin
    num += (x[i] - mx) * (y[i] - my);
    denx += sqr(x[i] - mx);
    deny += sqr(y[i] - my);
  end;

  denx := sqrt(denx);
  deny := sqrt(deny);
  den := denx * deny;

  Result := 0.0;
  if den <> 0.0 then
    Result := num / den;
end;

procedure TMainForm.PreparePlan(var Plan: TMixingPlan; MixedColors: Integer; const pal: array of Integer);
var
  i, col, r, g, b: Integer;
begin
  FillChar(Plan, SizeOf(Plan), 0);

  Plan.Y2MixedColors := MixedColors;
  SetLength(Plan.LumaPal, Length(pal));
  SetLength(Plan.Y2Palette, Length(pal));

  if not FLowMem then
  begin
    SpinLeave(@Plan.CacheLock);
    SetLength(Plan.CountCache, 1 shl 24);
    FillDWord(Plan.CountCache[0], 1 shl 24, $ffffffff);
    Plan.ListCache := TList.Create;
  end;

  for i := 0 to High(pal) do
  begin
    col := pal[i];
    r := col and $ff;
    g := (col shr 8) and $ff;
    b := (col shr 16) and $ff;

    Plan.LumaPal[i] := r*cRedMul + g*cGreenMul + b*cBlueMul;

    Plan.Y2Palette[i][0] := r;
    Plan.Y2Palette[i][1] := g;
    Plan.Y2Palette[i][2] := b;
    Plan.Y2Palette[i][3] := Plan.LumaPal[i] div cLumaDiv;
  end
end;

procedure TMainForm.TerminatePlan(var Plan: TMixingPlan);
var
  i: Integer;
begin
  if not FLowMem then
  begin
    for i := 0 to Plan.ListCache.Count - 1 do
      Freemem(Plan.ListCache[i]);
    Plan.ListCache.Free;
    SetLength(Plan.CountCache, 0);
  end;

  SetLength(Plan.LumaPal, 0);
  SetLength(Plan.Y2Palette, 0);
end;

function PlanCompareLuma(Item1,Item2,UserParameter:Pointer):Integer;
var
  pi1, pi2: PInteger;
begin
  pi1 := PInteger(UserParameter);
  pi2 := PInteger(UserParameter);

  Inc(pi1, PByte(Item1)^);
  Inc(pi2, PByte(Item2)^);

  Result := CompareValue(pi1^, pi2^);
end;

function TMainForm.ColorCompare(r1, g1, b1, r2, g2, b2: Int64): Int64;
var
  luma1, luma2, lumadiff, diffR, diffG, diffB: Int64;
begin
  luma1 := r1 * cRedMul + g1 * cGreenMul + b1 * cBlueMul;
  luma2 := r2 * cRedMul + g2 * cGreenMul + b2 * cBlueMul;
  lumadiff := (luma1 - luma2) div cLumaDiv;
  diffR := r1 - r2;
  diffG := g1 - g2;
  diffB := b1 - b2;
  Result := (diffR * diffR) * cRGBw;
  Result += (diffG * diffG) * cRGBw;
  Result += (diffB * diffB) * cRGBw;
  Result += (lumadiff * lumadiff) shl 5;
end;

function TMainForm.DeviseBestMixingPlanYliluoma(var Plan: TMixingPlan; col: Integer; List: TByteDynArray): Integer;
label
  pal_loop, inner_loop, worst;
var
  r, g, b: Integer;
  t, index, max_test_count, plan_count, y2pal_len: Integer;
  chosen_amount, chosen, least_penalty, penalty: Int64;
  so_far, sum, add: array[0..3] of Integer;
  VecInv: PCardinal;
  y2pal: PInteger;
  cachePos: Integer;
  pb: PByte;
begin
  if not FLowMem then
  begin
    SpinEnter(@Plan.CacheLock);
    cachePos := Plan.CountCache[col];
    if cachePos >= 0 then
    begin
      Result := PByte(Plan.ListCache[cachePos])[0];
      Move(PByte(Plan.ListCache[cachePos])[1], List[0], Result);
      SpinLeave(@Plan.CacheLock);
      Exit;
    end;
    SpinLeave(@Plan.CacheLock);
  end;

  FromRGB(col, r, g, b);

{$if defined(ASM_DBMP) and defined(CPUX86_64)}
  asm
    sub rsp, 16 * 6
    movdqu oword ptr [rsp + $00], xmm1
    movdqu oword ptr [rsp + $10], xmm2
    movdqu oword ptr [rsp + $20], xmm3
    movdqu oword ptr [rsp + $30], xmm4
    movdqu oword ptr [rsp + $40], xmm5
    movdqu oword ptr [rsp + $50], xmm6

    push rax
    push rbx
    push rcx
    push rdx

    mov eax, r
    mov ebx, g
    mov ecx, b

    pinsrd xmm4, eax, 0
    pinsrd xmm4, ebx, 1
    pinsrd xmm4, ecx, 2

    imul eax, cRedMul
    imul ebx, cGreenMul
    imul ecx, cBlueMul

    add eax, ebx
    add eax, ecx
    mov ecx, cLumaDiv
    xor edx, edx
    div ecx

    pinsrd xmm4, eax, 3

    mov rax, 1 or (1 shl 32)
    pinsrq xmm5, rax, 0
    pinsrq xmm5, rax, 1

    mov rax, cRGBw or (cRGBw shl 32)
    pinsrq xmm6, rax, 0
    mov rax, cRGBw or (32 shl 32)
    pinsrq xmm6, rax, 1

    pop rdx
    pop rcx
    pop rbx
    pop rax
  end;
{$endif}

  VecInv := @gVecInv[0];
  plan_count := 0;
  so_far[0] := 0; so_far[1] := 0; so_far[2] := 0; so_far[3] := 0;

  while plan_count < Plan.Y2MixedColors do
  begin
    max_test_count := IfThen(plan_count = 0, 1, plan_count);

{$if defined(ASM_DBMP) and defined(CPUX86_64)}
    y2pal_len := Length(Plan.Y2Palette);
    y2pal := @Plan.Y2Palette[0][0];

    asm
      push rax
      push rbx
      push rcx
      push rdx
      push rsi
      push rdi
      push r8
      push r9
      push r10

      xor r9, r9
      xor r10, r10
      inc r10

      mov rbx, (1 shl 63) - 1

      mov rdi, y2pal
      mov r8d, dword ptr [y2pal_len]
      shl r8d, 4
      add r8, rdi

      pal_loop:

        movdqu xmm1, oword ptr [so_far]
        movdqu xmm2, oword ptr [rdi]

        mov ecx, plan_count
        inc rcx
        mov edx, max_test_count
        shl rcx, 4
        shl rdx, 4
        add rcx, VecInv
        add rdx, rcx

        inner_loop:
          paddd xmm1, xmm2
          paddd xmm2, xmm5

          movdqu xmm3, oword ptr [rcx]

          pmulld xmm3, xmm1
          psrld xmm3, cVecInvWidth

          psubd xmm3, xmm4
          pmulld xmm3, xmm3
          pmulld xmm3, xmm6

          phaddd xmm3, xmm3
          phaddd xmm3, xmm3
          pextrd eax, xmm3, 0

          cmp rax, rbx
          jae worst

            mov rbx, rax
            mov r9, rdi
            mov r10, rcx

          worst:

        add rcx, 16
        cmp rcx, rdx
        jne inner_loop

      add rdi, 16
      cmp rdi, r8
      jne pal_loop

      sub r9, y2pal
      shr r9, 4
      mov chosen, r9

      sub r10, VecInv
      shr r10, 4
      sub r10d, plan_count
      mov chosen_amount, r10

      pop r10
      pop r9
      pop r8
      pop rdi
      pop rsi
      pop rdx
      pop rcx
      pop rbx
      pop rax
    end ['rax', 'rbx', 'rcx', 'rdx', 'rsi', 'rdi', 'r8', 'r9', 'r10'];
{$else}
    chosen_amount := 1;
    chosen := 0;

    least_penalty := High(Int64);

    for index := 0 to High(Plan.Y2Palette) do
    begin
      sum[0] := so_far[0]; sum[1] := so_far[1]; sum[2] := so_far[2]; sum[3] := so_far[3];
      add[0] := Plan.Y2Palette[index][0]; add[1] := Plan.Y2Palette[index][1]; add[2] := Plan.Y2Palette[index][2]; add[3] := Plan.Y2Palette[index][3];

      for t := plan_count + 1 to plan_count + max_test_count do
      begin
        sum[0] += add[0];
        sum[1] += add[1];
        sum[2] += add[2];

        Inc(add[0]);
        Inc(add[1]);
        Inc(add[2]);

        penalty := ColorCompare(r, g, b, sum[0] div t, sum[1] div t, sum[2] div t);

        if penalty < least_penalty then
        begin
          least_penalty := penalty;
          chosen := index;
          chosen_amount := t - plan_count;
        end;
      end;
    end;
{$endif}

    chosen_amount := Min(chosen_amount, Length(List) - plan_count);
    FillByte(List[plan_count], chosen_amount, chosen);
    Inc(plan_count, chosen_amount);

    so_far[0] += Plan.Y2Palette[chosen][0] * chosen_amount;
    so_far[1] += Plan.Y2Palette[chosen][1] * chosen_amount;
    so_far[2] += Plan.Y2Palette[chosen][2] * chosen_amount;
    so_far[3] += Plan.Y2Palette[chosen][3] * chosen_amount;
  end;

  QuickSort(List[0], 0, plan_count - 1, SizeOf(Byte), @PlanCompareLuma, @Plan.LumaPal[0]);

  Result := plan_count;

{$if defined(ASM_DBMP) and defined(CPUX86_64)}
  asm
    movdqu xmm1, oword ptr [rsp + $00]
    movdqu xmm2, oword ptr [rsp + $10]
    movdqu xmm3, oword ptr [rsp + $20]
    movdqu xmm4, oword ptr [rsp + $30]
    movdqu xmm5, oword ptr [rsp + $40]
    movdqu xmm6, oword ptr [rsp + $50]
    add rsp, 16 * 6
  end;
{$endif}

  if not FLowMem then
  begin
    SpinEnter(@Plan.CacheLock);
    if Plan.CountCache[col] < 0 then
    begin
      cachePos := Plan.ListCache.Count;
      pb := GetMem(Result + 1);
      pb[0] := Result;
      Move(List[0], pb[1], Result);
      Plan.ListCache.Add(pb);
      Plan.CountCache[col] := cachePos;
    end;
    SpinLeave(@Plan.CacheLock);
  end;
end;

procedure TMainForm.DeviseBestMixingPlanThomasKnoll(var Plan: TMixingPlan; col: Integer; var List: TByteDynArray);
var
  index, chosen, c: Integer;
  src : array[0..2] of Byte;
  s, t, e: array[0..2] of Int64;
  least_penalty, penalty: Int64;
begin
  FromRGB(col, src[0], src[1], src[2]);

  s[0] := src[0];
  s[1] := src[1];
  s[2] := src[2];

  e[0] := 0;
  e[1] := 0;
  e[2] := 0;

  for c := 0 to cDitheringLen - 1 do
  begin
    t[0] := s[0] + (e[0] * 9) div 100;
    t[1] := s[1] + (e[1] * 9) div 100;
    t[2] := s[2] + (e[2] * 9) div 100;

    least_penalty := High(Int64);
    chosen := c and (length(Plan.Y2Palette) - 1);
    for index := 0 to length(Plan.Y2Palette) - 1 do
    begin
      penalty := ColorCompare(t[0], t[1], t[2], Plan.Y2Palette[index][0], Plan.Y2Palette[index][1], Plan.Y2Palette[index][2]);
      if penalty < least_penalty then
      begin
        least_penalty := penalty;
        chosen := index;
      end;
    end;

    List[c] := chosen;

    e[0] += s[0];
    e[1] += s[1];
    e[2] += s[2];

    e[0] -= Plan.Y2Palette[chosen][0];
    e[1] -= Plan.Y2Palette[chosen][1];
    e[2] -= Plan.Y2Palette[chosen][2];
  end;

  QuickSort(List[0], 0, cDitheringLen - 1, SizeOf(Byte), @PlanCompareLuma, @Plan.LumaPal[0]);
end;

procedure TMainForm.DitherTileFloydSteinberg(ATile: TTile; out RGBPixels: TRGBPixels);
var
  x, y, c, yp, xm, xp: Integer;
  OldPixel, NewPixel, QuantError: Integer;
  Pixels: array[-1..cTileWidth, -1..cTileWidth, 0..2{RGB}] of Integer;
begin
  for y := 0 to (cTileWidth - 1) do
  begin
    for x := 0 to (cTileWidth - 1) do
      FromRGB(ATile.RGBPixels[y, x], Pixels[y, x, 0], Pixels[y, x, 1], Pixels[y, x, 2]);

    Pixels[y, -1, 0] := Pixels[y, 0, 0];
    Pixels[y, -1, 1] := Pixels[y, 0, 1];
    Pixels[y, -1, 2] := Pixels[y, 0, 2];
    Pixels[y, 8, 0] := Pixels[y, 7, 0];
    Pixels[y, 8, 1] := Pixels[y, 7, 1];
    Pixels[y, 8, 2] := Pixels[y, 7, 2];
  end;

  for x := -1 to cTileWidth do
  begin
    Pixels[-1, x, 0] := Pixels[0, x, 0];
    Pixels[-1, x, 1] := Pixels[0, x, 1];
    Pixels[-1, x, 2] := Pixels[0, x, 2];
    Pixels[8, x, 0] := Pixels[7, x, 0];
    Pixels[8, x, 1] := Pixels[7, x, 1];
    Pixels[8, x, 2] := Pixels[7, x, 2];
  end;

  for y := 0 to (cTileWidth - 1) do
    for x := 0 to (cTileWidth - 1) do
      for c := 0 to 2 do
      begin
        OldPixel := Pixels[y, x, c];
        NewPixel := Posterize(OldPixel);
        QuantError := OldPixel - NewPixel;

        yp := y + 1;
        xp := x + 1;
        xm := x - 1;

        Pixels[y,  x,  c] := NewPixel;

        Pixels[y,  xp, c] += (QuantError * 7) shr 4;
        Pixels[yp, xm, c] += (QuantError * 3) shr 4;
        Pixels[yp, x,  c] += (QuantError * 5) shr 4;
        Pixels[yp, xp, c] += (QuantError * 1) shr 4;
      end;

  for y := 0 to (cTileWidth - 1) do
    for x := 0 to (cTileWidth - 1) do
      RGBPixels[y, x] := ToRGB(min(255, Pixels[y, x, 0]), min(255, Pixels[y, x, 1]), min(255, Pixels[y, x, 2]));
end;

procedure TMainForm.ReframeUI(AWidth, AHeight: Integer);
begin
  FTileMapWidth := min(AWidth, 1920 div cTileWidth);
  FTileMapHeight := min(AHeight, 1080 div cTileWidth);

  FTileMapSize := FTileMapWidth * FTileMapHeight;
  FScreenWidth := FTileMapWidth * cTileWidth;
  FScreenHeight := FTileMapHeight * cTileWidth;

  imgSource.Picture.Bitmap.Width:=FScreenWidth;
  imgSource.Picture.Bitmap.Height:=FScreenHeight;
  imgSource.Picture.Bitmap.PixelFormat:=pf32bit;

  imgDest.Picture.Bitmap.Width:=FScreenWidth;
  imgDest.Picture.Bitmap.Height:=FScreenHeight;
  imgDest.Picture.Bitmap.PixelFormat:=pf32bit;

  imgTiles.Picture.Bitmap.Width:=FScreenWidth;
  imgTiles.Picture.Bitmap.Height:=FScreenHeight;
  imgTiles.Picture.Bitmap.PixelFormat:=pf32bit;

  imgPalette.Picture.Bitmap.Width := FTilePaletteSize;
  imgPalette.Picture.Bitmap.Height := FPaletteCount;
  imgPalette.Picture.Bitmap.PixelFormat:=pf32bit;

  imgTiles.Width := FScreenWidth shl IfThen(FScreenHeight <= 256, 2, 1);
  imgTiles.Height := FScreenHeight shl IfThen(FScreenHeight <= 256, 2, 1);
  imgSource.Width := FScreenWidth shl IfThen(FScreenHeight <= 256, 1, 0);
  imgSource.Height := FScreenHeight shl IfThen(FScreenHeight <= 256, 1, 0);
  imgDest.Width := FScreenWidth shl IfThen(FScreenHeight <= 256, 1, 0);
  imgDest.Height := FScreenHeight shl IfThen(FScreenHeight <= 256, 1, 0);

  sedPalIdx.MaxValue := FPaletteCount - 1;
end;

procedure TMainForm.DitherFloydSteinberg(const AScreen: TByteDynArray);
var
  x, y, c, yp, xm, xp: Integer;
  OldPixel, NewPixel, QuantError: Integer;
  ppx: PByte;
begin
  ppx := @AScreen[0];
  for y := 0 to FScreenHeight - 1 do
    for x := 0 to FScreenWidth - 1 do
    begin
      yp := IfThen(y < FScreenHeight - 1, FScreenWidth * 3, 0);
      xp := IfThen(x < FScreenWidth - 1, 3, 0);
      xm := IfThen(x > 0, -3, 0);

      for c := 0 to 2 do
      begin
        OldPixel := ppx^;
        NewPixel := Posterize(OldPixel);
        QuantError := OldPixel - NewPixel;

        ppx^ := NewPixel;

        ppx[xp] := EnsureRange(ppx[xp] + (QuantError * 7) shr 4, 0, 255);
        ppx[yp + xm] := EnsureRange(ppx[yp + xm] + (QuantError * 3) shr 4, 0, 255);
        ppx[yp] := EnsureRange(ppx[yp] + (QuantError * 5) shr 4, 0, 255);
        ppx[yp + xp] := EnsureRange(ppx[yp + xp] + (QuantError * 1) shr 4, 0, 255);

        Inc(ppx);
      end;
    end;
end;

procedure TMainForm.DitherTile(var ATile: TTile; var Plan: TMixingPlan);
var
  col, x, y: Integer;
  count, map_value: Integer;
  list: TByteDynArray;
  cachePos: Integer;
  pb: PByte;
begin
  if FUseThomasKnoll then
  begin
    SetLength(list, cDitheringLen);

    if FLowMem then
    begin
     for y := 0 to (cTileWidth - 1) do
       for x := 0 to (cTileWidth - 1) do
       begin
         map_value := cDitheringMap[(y * cTileWidth) + x];
         DeviseBestMixingPlanThomasKnoll(Plan, ATile.RGBPixels[y, x], list);
         ATile.PalPixels[y, x] := list[map_value];
       end;
    end
    else
    begin
      for y := 0 to (cTileWidth - 1) do
        for x := 0 to (cTileWidth - 1) do
        begin
          col := ATile.RGBPixels[y, x];
          map_value := cDitheringMap[(y shl 3) + x];
          SpinEnter(@Plan.CacheLock);
          cachePos := Plan.CountCache[col];
          if cachePos >= 0 then
          begin
            ATile.PalPixels[y, x] := PByte(Plan.ListCache[cachePos])[map_value];
            SpinLeave(@Plan.CacheLock);
          end
          else
          begin
            SpinLeave(@Plan.CacheLock);

            DeviseBestMixingPlanThomasKnoll(Plan, ATile.RGBPixels[y, x], list);
            ATile.PalPixels[y, x] := list[map_value];

            SpinEnter(@Plan.CacheLock);
            if Plan.CountCache[col] < 0 then
            begin
              cachePos := Plan.ListCache.Count;
              pb := GetMem(cDitheringLen);
              Move(List[0], pb^, cDitheringLen);
              Plan.ListCache.Add(pb);
              Plan.CountCache[col] := cachePos;
            end;
            SpinLeave(@Plan.CacheLock);
          end;
        end;
    end;
  end
  else
  begin
    SetLength(list, cDitheringListLen);

    for y := 0 to (cTileWidth - 1) do
      for x := 0 to (cTileWidth - 1) do
      begin
        map_value := cDitheringMap[(y shl 3) + x];
        count := DeviseBestMixingPlanYliluoma(Plan, ATile.RGBPixels[y,x], list);
        map_value := (map_value * count) shr 6;
        ATile.PalPixels[y, x] := list[map_value];
      end;
  end;
end;

function CompareCMUCntHLS(Item1,Item2:Pointer):Integer;
begin
  Result := PCountIndexArray(Item2)^.Count - PCountIndexArray(Item1)^.Count;
  if Result = 0 then
    Result := CompareValue(PCountIndexArray(Item1)^.Hue, PCountIndexArray(Item2)^.Hue);
  if Result = 0 then
    Result := CompareValue(PCountIndexArray(Item1)^.Val, PCountIndexArray(Item2)^.Val);
  if Result = 0 then
    Result := CompareValue(PCountIndexArray(Item1)^.Sat, PCountIndexArray(Item2)^.Sat);
end;

function CompareCMULHS(Item1,Item2:Pointer):Integer;
begin
  Result := CompareValue(PCountIndexArray(Item1)^.Luma, PCountIndexArray(Item2)^.Luma);
  if Result = 0 then
    Result := CompareValue(PCountIndexArray(Item1)^.Val, PCountIndexArray(Item2)^.Val);
  if Result = 0 then
    Result := CompareValue(PCountIndexArray(Item1)^.Sat, PCountIndexArray(Item2)^.Sat);
  if Result = 0 then
    Result := CompareValue(PCountIndexArray(Item1)^.Hue, PCountIndexArray(Item2)^.Hue);
end;

function ComparePaletteUseCount(Item1,Item2,UserParameter:Pointer):Integer;
begin
  Result := CompareValue(PInteger(Item2)^, PInteger(Item1)^);
end;

procedure TMainForm.PrepareDitherTiles(AKeyFrame: TKeyFrame; ADitheringGamma: Integer; AUseWavelets: Boolean);
var
  sx, sy, i: Integer;
  GTile: PTile;

  Dataset: TFloatDynArray2;
  Clusters: TIntegerDynArray;
  di: Integer;

  Yakmo: PYakmo;
begin
  Assert(FPaletteCount <= Length(gPalettePattern));

  SetLength(Dataset, AKeyFrame.FrameCount * FTileMapSize, cTileDCTSize);
  SetLength(Clusters, Length(Dataset));
  SetLength(AKeyFrame.PaletteCentroids, FPaletteCount, cTileDCTSize);

  di := 0;
  for i := AKeyFrame.StartFrame to AKeyFrame.EndFrame do
    for sy := 0 to FTileMapHeight - 1 do
      for sx := 0 to FTileMapWidth - 1 do
      begin
        GTile := FTiles[FFrames[i].TileMap[sy, sx].GlobalTileIndex];
        ComputeTilePsyVisFeatures(GTile^, False, AUseWavelets, True, False, False, False, ADitheringGamma, nil, Dataset[di]);
        Inc(di);
      end;
  assert(di = Length(Dataset));

  if (di > 1) and (FPaletteCount > 1) then
  begin
   Yakmo := yakmo_create(FPaletteCount, 1, MaxInt, 1, 0, 0, 0);
   yakmo_load_train_data(Yakmo, di, cTileDCTSize, @Dataset[0]);
   SetLength(Dataset, 0); // free up some memmory
   Write('.');
   yakmo_train_on_data(Yakmo, @Clusters[0]);
   yakmo_get_centroids(Yakmo, @AKeyFrame.PaletteCentroids[0]);
   yakmo_destroy(Yakmo);
  end
  else
  begin
    FillDWord(Clusters[0], Length(Clusters), 0);
  end;

  di := 0;
  for i := AKeyFrame.StartFrame to AKeyFrame.EndFrame do
    for sy := 0 to FTileMapHeight - 1 do
      for sx := 0 to FTileMapWidth - 1 do
      begin
        GTile := FTiles[FFrames[i].TileMap[sy, sx].GlobalTileIndex];
        GTile^.DitheringPalIndex := Clusters[di];
        Inc(di);
      end;
  assert(di = Length(Clusters));

  Write('.');
end;

procedure TMainForm.QuantizePalette(AKeyFrame: TKeyFrame; APalIdx: Integer; UseDLv3: Boolean; PalVAR: TFloat; DLv3BPC: Integer);
var
  col, i: Integer;
  CMUsage, CMPal: TFPList;
  CMItem: PCountIndexArray;

  dlCnt: Integer;
  dlInput: PByte;

  procedure DoDennisLeeV3(PalIdx: Integer);
  var
    i, j, sy, sx, dx, dy, ty, k, tileCnt, tileFx, tileFy, best: Integer;
    dlPal: TDLUserPal;
    GTile: PTile;
  begin
    FillChar(dlInput^, dlCnt * 3, 0);

    // find width and height of a rectangular area to arrange tiles

    tileCnt := 0;
    for i := AKeyFrame.StartFrame to AKeyFrame.EndFrame do
      for sy := 0 to FTileMapHeight - 1 do
        for sx := 0 to FTileMapWidth - 1 do
        begin
          GTile := FTiles[FFrames[i].TileMap[sy, sx].GlobalTileIndex];
          if GTile^.Active and (GTile^.DitheringPalIndex = PalIdx) then
            Inc(tileCnt);
        end;

    best := MaxInt;
    tileFx := 0;
    tileFy := 0;
    j := 0;
    k := 0;
    for i := 1 to tileCnt do
    begin
      DivMod(tileCnt, i, j, k);
      if (k = 0) and (abs(i - j) < best) then
      begin
        best := abs(i - j);
        tileFx := i;
        tileFy := j;
      end;
    end;

    // copy tile date into area

    dx := 0;
    dy := 0;
    for i := AKeyFrame.StartFrame to AKeyFrame.EndFrame do
    begin
      for sy := 0 to FTileMapHeight - 1 do
        for sx := 0 to FTileMapWidth - 1 do
        begin
          GTile := FTiles[FFrames[i].TileMap[sy, sx].GlobalTileIndex];

          if GTile^.Active and (GTile^.DitheringPalIndex = PalIdx) then
          begin
            j := ((dy * cTileWidth) * tileFx * cTileWidth + (dx * cTileWidth)) * 3;
            k := ((sy * cTileWidth) * FScreenWidth + (sx * cTileWidth)) * 3;
            for ty := 0 to cTileWidth - 1 do
            begin
              Move(FFrames[i].FSPixels[k], dlInput[j], cTileWidth * 3);
              Inc(j, tileFx * cTileWidth * 3);
              Inc(k, FScreenWidth * 3);
            end;

            Inc(dx);
            if dx >= tileFx then
            begin
              dx := 0;
              Inc(dy);
            end;

            Inc(AKeyFrame.PaletteUseCount[PalIdx].UseCount);
          end;
        end;
    end;

    // call Dennis Lee v3 method

    dl3quant(dlInput, tileFx * cTileWidth, tileFy * cTileWidth, FTilePaletteSize, DLv3BPC, @dlPal);

    // retrieve palette data

    CMUsage.Count := FTilePaletteSize;
    for i := 0 to FTilePaletteSize - 1 do
    begin
      col := ToRGB(dlPal[0][i], dlPal[1][i], dlPal[2][i]);

      New(CMItem);
      CMItem^.Index := col;
      CMItem^.Count := 1;
      CMItem^.Hue := FColorMap[col, 3]; CMItem^.Sat := FColorMap[col, 4]; CMItem^.Val := FColorMap[col, 5];
      CMItem^.Luma := FColorMapLuma[col];
      CMUsage[i] := CMItem;
    end;

    CMPal.Clear;
    CMPal.Assign(CMUsage);
  end;

  procedure DoValueAtRiskBased(PalIdx: Integer);
  var
    col, i, bestI, LastUsed, CmlPct, AtCmlPct, acc, r, g, b, rr, gg, bb, sy, sx, ty, tx: Integer;
    GTile: PTile;
    CMItem: PCountIndexArray;
    TrueColorUsage: TCardinalDynArray;
    diff, best, PrevBest: Int64;
    ciI, ciJ: PCountIndexArray;
  begin
    SetLength(TrueColorUsage, cRGBColors);
    FillDWord(TrueColorUsage[0], Length(TrueColorUsage), 0);

    // get color usage stats

    for i := AKeyFrame.StartFrame to AKeyFrame.EndFrame do
    begin
      for sy := 0 to FTileMapHeight - 1 do
        for sx := 0 to FTileMapWidth - 1 do
        begin
          GTile := FTiles[FFrames[i].TileMap[sy, sx].GlobalTileIndex];

          if GTile^.Active and (GTile^.DitheringPalIndex = PalIdx) then
          begin
{$if cBitsPerComp = 8}
            for ty := 0 to cTileWidth - 1 do
              for tx := 0 to cTileWidth - 1 do
              begin
                col := GTile^.RGBPixels[ty, tx];
                Inc(TrueColorUsage[col]);
              end;
{$else}
            DitherTileFloydSteinberg(GTile^, FSPixels);
            for ty := 0 to cTileWidth - 1 do
              for tx := 0 to cTileWidth - 1 do
              begin
                col := FSPixels[ty, tx];
                Inc(TrueColorUsage[col]);
              end;
{$endif}

            Inc(AKeyFrame.PaletteUseCount[PalIdx].UseCount);
          end;
        end;
    end;

    CMUsage.Count := Length(TrueColorUsage);
    for i := 0 to High(TrueColorUsage) do
    begin
      New(CMItem);
      CMItem^.Count := TrueColorUsage[i];
      CMItem^.Index := i;
      CMItem^.Hue := FColorMap[i, 3]; CMItem^.Sat := FColorMap[i, 4]; CMItem^.Val := FColorMap[i, 5];
      CMItem^.Luma := FColorMapLuma[CMItem^.Index];
      CMUsage[i] := CMItem;
    end;

    // sort colors by use count

    CMUsage.Sort(@CompareCMUCntHLS);

    LastUsed := -1;
    for i := CMUsage.Count - 1 downto 0 do    //TODO: rev algo
      if PCountIndexArray(CMUsage[i])^.Count <> 0 then
      begin
        LastUsed := i;
        Break;
      end;

    CmlPct := 0;
    acc := AKeyFrame.FrameCount * FTileMapSize * sqr(cTileWidth);
    acc := round(acc * PalVAR);
    for i := 0 to CMUsage.Count - 1 do
    begin
      acc -= PCountIndexArray(CMUsage[i])^.Count;
      if acc <= 0 then
      begin
        CmlPct := i;
        Break;
      end;
    end;
    AtCmlPct := PCountIndexArray(CMUsage[CmlPct])^.Count;

    WriteLn('Frame: ', AKeyFrame.StartFrame, #9'LastUsed: ', LastUsed, #9'CmlPct: ', CmlPct, #9'AtCmlPct: ', AtCmlPct);

    CmlPct := max(CmlPct, min(LastUsed + 1, FTilePaletteSize * FPaletteCount)); // ensure enough colors

    // prune colors that are too close to each other

    for i := LastUsed + 1 to CMUsage.Count - 1 do
      Dispose(PCountIndexArray(CMUsage[i]));
    CMUsage.Count := LastUsed + 1;

    best := High(Int64);
    repeat
      bestI := -1;
      PrevBest := best;
      best := High(Int64);

      ciJ := PCountIndexArray(CMUsage[0]);
      rr := FColorMap[ciJ^.Index, 0]; gg := FColorMap[ciJ^.Index, 1]; bb := FColorMap[ciJ^.Index, 2];
      for i := 1 to CMUsage.Count - 1 do
      begin
        ciI := PCountIndexArray(CMUsage[i]);
        r := FColorMap[ciI^.Index, 0]; g := FColorMap[ciI^.Index, 1]; b := FColorMap[ciI^.Index, 2];
        diff := ColorCompare(r, g, b, rr, gg, bb);
        if diff < best then
        begin
          best := diff;
          bestI := i;
        end;
        rr := r; gg := g; bb := b;
        ciJ := ciI;
      end;

      if bestI > 0 then
      begin
        ciI := PCountIndexArray(CMUsage[bestI]);
        ciJ := PCountIndexArray(CMUsage[bestI - 1]);

        acc := ciI^.Count + ciJ^.Count;
        ciI^.Hue := (ciI^.Hue * ciI^.Count + ciJ^.Hue * ciJ^.Count) div acc;
        ciI^.Sat := (ciI^.Sat * ciI^.Count + ciJ^.Sat * ciJ^.Count) div acc;
        ciI^.Val := (ciI^.Val * ciI^.Count + ciJ^.Val * ciJ^.Count) div acc;
        ciI^.Luma := (ciI^.Luma * ciI^.Count + ciJ^.Luma * ciJ^.Count) div acc;
        ciI^.Count := acc;

        ciI^.Index := HSVToRGB(ciI^.Hue, ciI^.Sat, ciI^.Val);

        Dispose(PCountIndexArray(CMUsage[bestI - 1]));
        CMUsage.Delete(bestI - 1);
      end;

    until (CMUsage.Count <= CmlPct) or (best = PrevBest);


    CMPal.Clear;
    for i := 0 to FTilePaletteSize - 1 do
      CMPal.Add(CMUsage[round(gPalettePattern[PalIdx, i] * (CMUsage.Count - 1))]);
  end;

begin
  Assert(FPaletteCount <= Length(gPalettePattern));

  AKeyFrame.PaletteUseCount[APalIdx].UseCount := 0;

  dlCnt := AKeyFrame.FrameCount * FScreenWidth * FScreenHeight;
  dlInput := GetMem(dlCnt * 3);
  CMUsage := TFPList.Create;
  CMPal := TFPList.Create;
  try
    if UseDLv3 then
      DoDennisLeeV3(APalIdx)
    else
      DoValueAtRiskBased(APalIdx);

    // split most used colors into tile palettes

    CMPal.Sort(@CompareCMULHS);

    SetLength(AKeyFrame.PaletteIndexes[APalIdx], FTilePaletteSize);
    for i := 0 to FTilePaletteSize - 1 do
      AKeyFrame.PaletteIndexes[APalIdx, i] := PCountIndexArray(CMPal[i])^.Index;

    for i := 0 to CMUsage.Count - 1 do
      Dispose(PCountIndexArray(CMUsage[i]));

    CMUsage.Clear;
    CMPal.Clear;

  finally
    CMPal.Free;
    CMUsage.Free;
    Freemem(dlInput);
  end;

  if APalIdx mod (FPaletteCount div 2) = 0 then
    Write('.');
end;

procedure TMainForm.FinishQuantizePalette(AKeyFrame: TKeyFrame);
var
  i, j, di, sy, sx, PalIdx: Integer;
  PalIdxLUT: TIntegerDynArray;
  TmpCentroids: TFloatDynArray2;
  GTile: PTile;
begin
  SetLength(PalIdxLUT, FPaletteCount);

  // sort entire palettes by use count
  for PalIdx := 0 to FPaletteCount - 1 do
  begin
    AKeyFrame.PaletteUseCount[PalIdx].Palette := AKeyFrame.PaletteIndexes[PalIdx];
    AKeyFrame.PaletteUseCount[PalIdx].PalIdx := PalIdx;
  end;
  QuickSort(AKeyFrame.PaletteUseCount[0], 0, FPaletteCount - 1, SizeOf(AKeyFrame.PaletteUseCount[0]), @ComparePaletteUseCount, AKeyFrame);
  for PalIdx := 0 to FPaletteCount - 1 do
  begin
    AKeyFrame.PaletteIndexes[PalIdx] := AKeyFrame.PaletteUseCount[PalIdx].Palette;
    PalIdxLUT[AKeyFrame.PaletteUseCount[PalIdx].PalIdx] := PalIdx;
  end;

  for PalIdx := 0 to FPaletteCount - 1 do
  begin
    SetLength(AKeyFrame.PaletteRGB[PalIdx], FTilePaletteSize);
    for i := 0 to FTilePaletteSize - 1 do
    begin
      j := AKeyFrame.PaletteIndexes[PalIdx, i];
      AKeyFrame.PaletteRGB[PalIdx, i] := ToRGB(FColorMap[j, 0], FColorMap[j, 1], FColorMap[j, 2]);
    end;
  end;

  di := 0;
  for i := AKeyFrame.StartFrame to AKeyFrame.EndFrame do
    for sy := 0 to FTileMapHeight - 1 do
      for sx := 0 to FTileMapWidth - 1 do
      begin
        GTile := FTiles[FFrames[i].TileMap[sy, sx].GlobalTileIndex];
        GTile^.DitheringPalIndex := PalIdxLUT[GTile^.DitheringPalIndex];
        Inc(di);
      end;

  TmpCentroids := Copy(AKeyFrame.PaletteCentroids);
  for PalIdx := 0 to FPaletteCount - 1 do
    AKeyFrame.PaletteCentroids[PalIdxLUT[PalIdx]] := TmpCentroids[PalIdx];
end;

procedure TMainForm.FinishDitherTiles(AFrame: TFrame; ADitheringGamma: Integer; AUseWavelets: Boolean);
var
  i, PalIdx: Integer;
  cnt, mx, sx, sy: Integer;
  OrigTile: PTile;
begin
  EnterCriticalSection(AFrame.PKeyFrame.CS);
  if AFrame.PKeyFrame.FramesLeft < 0 then
  begin
    for i := 0 to FPaletteCount - 1 do
      PreparePlan(AFrame.PKeyFrame.MixingPlans[i], FY2MixedColors, AFrame.PKeyFrame.PaletteRGB[i]);
    AFrame.PKeyFrame.FramesLeft := AFrame.PKeyFrame.FrameCount;
  end;
  LeaveCriticalSection(AFrame.PKeyFrame.CS);

  for sy := 0 to FTileMapHeight - 1 do
    for sx := 0 to FTileMapWidth - 1 do
    begin
      OrigTile := FTiles[AFrame.TileMap[sy, sx].GlobalTileIndex];

      if OrigTile^.Active then
      begin
        // choose best palette from the keyframe by comparing DCT of the tile colored with either palette

        PalIdx := OrigTile^.DitheringPalIndex;
        DitherTile(OrigTile^, AFrame.PKeyFrame.MixingPlans[PalIdx]);

        // now that the palette is chosen, keep only one version of the tile

        AFrame.TileMap[sy, sx].PalIdx := PalIdx;

        AFrame.Tiles[sx + sy * FTileMapWidth].PaletteRGB := system.Copy(AFrame.PKeyFrame.PaletteRGB[PalIdx]);
        AFrame.Tiles[sx + sy * FTileMapWidth].PaletteIndexes := system.Copy(AFrame.PKeyFrame.PaletteIndexes[PalIdx]);

        Move(OrigTile^.PalPixels[0, 0], AFrame.Tiles[sx + sy * FTileMapWidth].PalPixels[0, 0], SizeOf(TPalPixels));

        PrepareTileMirrors(OrigTile^);
      end;
    end;

  // free up frame memory
  SetLength(AFrame.FSPixels, 0);

  EnterCriticalSection(AFrame.PKeyFrame.CS);
  Dec(AFrame.PKeyFrame.FramesLeft);
  if AFrame.PKeyFrame.FramesLeft <= 0 then
  begin
    mx := 0;
    cnt := 0;
    for i := 0 to FPaletteCount - 1 do
    begin
      if not FLowMem then
      begin
        mx := Max(AFrame.PKeyFrame.MixingPlans[i].ListCache.Count, mx);
        cnt += AFrame.PKeyFrame.MixingPlans[i].ListCache.Count;
      end;
      TerminatePlan(AFrame.PKeyFrame.MixingPlans[i]);
    end;

    WriteLn('Frame: ', AFrame.PKeyFrame.StartFrame, #9'CacheCnt: ', cnt, #9'CacheMax: ', mx);
  end;
  LeaveCriticalSection(AFrame.PKeyFrame.CS);
end;

function CompareTilePalPixels(Item1, Item2:Pointer):Integer;
var
  t1, t2: PTile;
begin
  t1 := PTile(Item1);
  t2 := PTile(Item2);
  Result := CompareDWord(t1^.PalPixels[0, 0], t2^.PalPixels[0, 0], sqr(cTileWidth) div SizeOf(DWORD));
end;

procedure TMainForm.MakeTilesUnique(FirstTileIndex, TileCount: Integer);
var
  i, pos, firstSameIdx: Integer;
  sortList: TFPList;
  sameIdx: array of Integer;

  procedure DoOneMerge;
  var
    j: Integer;
  begin
    if i - firstSameIdx >= 2 then
    begin
      for j := firstSameIdx to i - 1 do
        sameIdx[j - firstSameIdx] := PTile(sortList[j])^.TmpIndex;
      MergeTiles(sameIdx, i - firstSameIdx, sameIdx[0], nil, nil);
    end;
    firstSameIdx := i;
  end;

begin
  InitMergeTiles;

  sortList := TFPList.Create;
  try

    // sort global tiles by palette indexes (L to R, T to B)

    SetLength(sameIdx, TileCount);

    sortList.Count := TileCount;
    pos := 0;
    for i := 0 to TileCount - 1 do
      if FTiles[i + FirstTileIndex]^.Active then
      begin
        sortList[pos] := FTiles[i + FirstTileIndex];
        PTile(sortList[pos])^.TmpIndex := i + FirstTileIndex;
        Inc(pos);
      end;
    sortList.Count := pos;

    sortList.Sort(@CompareTilePalPixels);

    // merge exactly similar tiles (so, consecutive after prev code)

    firstSameIdx := 0;
    for i := 1 to sortList.Count - 1 do
      if CompareDWord(PTile(sortList[i - 1])^.PalPixels[0, 0], PTile(sortList[i])^.PalPixels[0, 0], sqr(cTileWidth) div SizeOf(DWORD)) <> 0 then
        DoOneMerge;

    i := sortList.Count - 1;
    DoOneMerge;

  finally
    sortList.Free;
  end;

  FinishMergeTiles;
end;

procedure TMainForm.LoadTiles;
var
  i,j,x,y: Integer;
  tileCnt: Integer;
begin
  // free memory from a prev run
  for i := 0 to High(FTiles) do
    Dispose(FTiles[i]);

  tileCnt := Length(FFrames) * FTileMapSize;

  SetLength(FTiles, tileCnt);

  // allocate tiles
  for i := 0 to High(FTiles) do
  begin
    FTiles[i] := New(PTile);
    FillChar(FTiles[i]^, SizeOf(TTile), 0);
  end;

  // copy frame tiles to global tiles, point tilemap on proper global tiles
  for i := 0 to High(FFrames) do
  begin
    tileCnt := i * FTileMapSize;
    for j := 0 to FTileMapSize - 1 do
      CopyTile(FFrames[i].Tiles[j], FTiles[tileCnt + j]^);
    for y := 0 to (FTileMapHeight - 1) do
      for x := 0 to (FTileMapWidth - 1) do
        Inc(FFrames[i].TileMap[y, x].GlobalTileIndex, tileCnt);
  end;
end;

procedure TMainForm.RGBToYUV(col: Integer; GammaCor: Integer; out y, u, v: TFloat); inline;
var
  yy, uu, vv: TFloat;
  r, g, b: Byte;
begin
  FromRGB(col, r, g, b);
  RGBToYUV(r, g, b, GammaCor, yy, uu, vv);
  y := yy; u := uu; v := vv; // for safe "out" param
end;

procedure TMainForm.RGBToYUV(r, g, b: Byte; GammaCor: Integer; out y, u, v: TFloat);
var
  fr, fg, fb: TFloat;
  yy, uu, vv: TFloat;
begin
  if GammaCor >= 0 then
  begin
    fr := GammaCorrect(GammaCor, r);
    fg := GammaCorrect(GammaCor, g);
    fb := GammaCorrect(GammaCor, b);
  end
  else
  begin
    fr := r / 255.0;
    fg := g / 255.0;
    fb := b / 255.0;
  end;

  yy := (cRedMul * fr + cGreenMul * fg + cBlueMul * fb) / cLumaDiv;
  uu := (fb - yy) * (0.5 / (1.0 - cBlueMul / cLumaDiv));
  vv := (fr - yy) * (0.5 / (1.0 - cRedMul / cLumaDiv));

  y := yy; u := uu; v := vv; // for safe "out" param
end;

function TMainForm.YUVToRGB(y, u, v: TFloat): Integer;
var
  r, g, b: TFloat;
begin
{$if cRedMul = 299}
  r := y + v * 1.13983;
  g := y - u * 0.39465 - v * 0.58060;
  b := y + u * 2.03211;
{$elseif cRedMul = 2126}
  r := y + v * 1.28033;
  g := y - u * 0.21482 - v * 0.38059;
  b := y + u * 2.12798;
{$else}
  {$error YUVToRGB not implemented!}
{$endif}

  Result := ToRGB(EnsureRange(Round(r * 255), 0, 255), EnsureRange(Round(g * 255), 0, 255), EnsureRange(Round(b * 255), 0, 255));
end;

procedure TMainForm.RGBToHSV(col: Integer; out h, s, v: TFloat);
var
  bh, bs, bv: Byte;
begin
  bh := 0; bs := 0; bv := 0;
  RGBToHSV(col, bh, bs, bv);
  h := bh / 255.0;
  s := bs / 255.0;
  v := bv / 255.0;
end;

procedure TMainForm.RGBToLAB(ir, ig, ib: Integer; GammaCor: Integer; out ol, oa, ob: TFloat); inline;
var
  r, g, b, x, y, z: TFloat;
begin
  r := GammaCorrect(GammaCor, ir);
  g := GammaCorrect(GammaCor, ig);
  b := GammaCorrect(GammaCor, ib);

  if r > 0.04045 then r := power((r + 0.055) / 1.055, 2.4) else r := r / 12.92;
  if g > 0.04045 then g := power((g + 0.055) / 1.055, 2.4) else g := g / 12.92;
  if b > 0.04045 then b := power((b + 0.055) / 1.055, 2.4) else b := b / 12.92;

  // CIE XYZ color space from the Wright–Guild data
  x := (r * 0.49000 + g * 0.31000 + b * 0.20000) / 0.17697;
  y := (r * 0.17697 + g * 0.81240 + b * 0.01063) / 0.17697;
  z := (r * 0.00000 + g * 0.01000 + b * 0.99000) / 0.17697;

{$if true}
  // Illuminant D50
  x /= 96.6797 / 100;
  y /= 100.000 / 100;
  z /= 82.5188 / 100;
{$else}
  // Illuminant D65
  x /= 95.0470 / 100;
  y /= 100.000 / 100;
  z /= 108.883 / 100;
{$endif}

  if x > 0.008856 then x := power(x, 1/3) else x := (7.787 * x) + 16/116;
  if y > 0.008856 then y := power(y, 1/3) else y := (7.787 * y) + 16/116;
  if z > 0.008856 then z := power(z, 1/3) else z := (7.787 * z) + 16/116;

  ol := (116 * y) - 16;
  oa := 500 * (x - y);
  ob := 200 * (y - z);
end;

procedure TMainForm.RGBToLAB(r, g, b: TFloat; GammaCor: Integer; out ol, oa, ob: TFloat); inline;
var
  ll, aa, bb: TFloat;
begin
  RGBToLAB(Integer(round(r * 255.0)), round(g * 255.0), round(b * 255.0), GammaCor, ll, aa, bb);
  ol := ll;
  oa := aa;
  ob := bb;
end;

function TMainForm.LABToRGB(ll, aa, bb: TFloat): Integer;
var
  x, y, z, r, g, b: TFloat;
begin
  y := (ll + 16) / 116;
  x := aa / 500 + y;
  z := y - bb / 200;

  if IntPower(y, 3) > 0.008856 then
    y := IntPower(y, 3)
  else
    y := (y - 16 / 116) / 7.787;
  if IntPower(x, 3) > 0.008856 then
    x := IntPower(x, 3)
  else
    x := (x - 16 / 116) / 7.787;
  if IntPower(z, 3) > 0.008856 then
    z := IntPower(z, 3)
  else
    z := (z - 16 / 116) / 7.787;

  x := 96.6797 / 100 * x;
  y := 100.000 / 100 * y;
  z := 182.5188 / 100 * z;

  r := x * 0.41847 + y * (-0.15866) + z * (-0.082835);
  g := x * (-0.091169) + y * 0.25243 + z * 0.015708;
  b := x * 0.00092090 + y * (-0.0025498) + z * 0.17860;

  if r > 0.04045 then
    r := 1.055 * Power(r, 1 / 2.4) - 0.055
  else
    r := 12.92 * r;
  if g > 0.04045 then
    g := 1.055 * Power(g, 1 / 2.4) - 0.055
  else
    g := 12.92 * g;
  if b > 0.04045 then
    b := 1.055 * Power(b, 1 / 2.4) - 0.055
  else
    b := 12.92 * b;

  Result := ToRGB(EnsureRange(Round(r * 255), 0, 255), EnsureRange(Round(g * 255), 0, 255), EnsureRange(Round(b * 255), 0, 255));
end;

// from https://lists.freepascal.org/pipermail/fpc-announce/2006-September/000508.html
procedure TMainForm.WaveletGS(Data : PFloat; Output : PFloat; dx, dy, depth : cardinal);
var
  x, y: longint;
  offset: cardinal;
  factor: TFloat;
  tempX: array[0 .. sqr(cTileWidth) - 1] of TFloat;
  tempY: array[0 .. sqr(cTileWidth) - 1] of TFloat;
begin
  FillChar(tempX[0], SizeOf(tempX), 0);
  FillChar(tempY[0], SizeOf(tempY), 0);

  factor:=(1.0 / sqrt(2.0)); //Normalized Haar

  for y:=0 to dy - 1 do //Transform Rows
  begin
    offset := y * cTileWidth;
    for x := 0 to (dx div 2) - 1 do
    begin
      tempX[x + offset]             := (Data[x * 2 + offset] + Data[(x * 2 + 1) + offset]) * factor; //LOW-PASS
      tempX[(x + dx div 2) +offset] := (Data[x * 2 + offset] - Data[(x * 2 + 1) + offset]) * factor; //HIGH-PASS
    end;
  end;

  for x := 0 to dx - 1 do //Transform Columns
    for y := 0 to (dy div 2) - 1 do
    begin
      tempY[x +y * cTileWidth]              := (tempX[x +y * 2 * cTileWidth] + tempX[x +(y * 2 + 1) * cTileWidth]) * factor; //LOW-PASS
      tempY[x +(y + dy div 2) * cTileWidth] := (tempX[x +y * 2 * cTileWidth] - tempX[x +(y * 2 + 1) * cTileWidth]) * factor; //HIGH-PASS
    end;

  for y := 0 to dy - 1 do
    Move(tempY[y * cTileWidth], Output[y * cTileWidth], dx * sizeof(TFloat)); //Copy to Wavelet

  if depth>0 then
    waveletgs(Output, Output, dx div 2, dy div 2, depth - 1); //Repeat for SubDivisionDepth
end;

procedure TMainForm.DeWaveletGS(wl: PFloat; pic: PFloat; dx, dy, depth: longint);
 Var x,y : longint;
     tempX: array[0 .. sqr(cTileWidth) - 1] of TFloat;
     tempY: array[0 .. sqr(cTileWidth) - 1] of TFloat;
     offset,offsetm1,offsetp1 : longint;
     factor : TFloat;
     dyoff,yhalf,yhalfoff,yhalfoff2,yhalfoff3 : longint;
BEGIN
  FillChar(tempX[0], SizeOf(tempX), 0);
  FillChar(tempY[0], SizeOf(tempY), 0);

  if depth>0 then dewaveletgs(wl,wl,dx div 2,dy div 2,depth-1); //Repeat for SubDivisionDepth

  factor:=(1.0/sqrt(2.0)); //Normalized Haar

  ////

  yhalf:=(dy div 2)-1;
  dyoff:=(dy div 2)*cTileWidth;
  yhalfoff:=yhalf*cTileWidth;
  yhalfoff2:=(yhalf+(dy div 2))*cTileWidth;
  yhalfoff3:=yhalfoff*2 +cTileWidth;

  if (yhalf>0) then begin //The first and last pixel has to be done "normal"
   for x:=0 to dx-1 do begin
    tempy[x]     := (wl[x] + wl[x+dyoff])*factor; //LOW-PASS
    tempy[x+cTileWidth]:= (wl[x] - wl[x+dyoff])*factor; //HIGH-PASS

    tempy[x +yhalfoff*2]:= (wl[x +yhalfoff] + wl[x +yhalfoff2])*factor; //LOW-PASS
    tempy[x +yhalfoff3] := (wl[x +yhalfoff] - wl[x +yhalfoff2])*factor; //HIGH-PASS
   end;
  end else begin
   for x:=0 to dx-1 do begin
    tempy[x]     := (wl[x] + wl[x+dyoff])*factor; //LOW-PASS
    tempy[x+cTileWidth]:= (wl[x] - wl[x+dyoff])*factor; //HIGH-PASS
   end;
  end;

  //

  dyoff:=(dy div 2)*cTileWidth;
  yhalf:=(dy div 2)-2;

  if (yhalf>=1) then begin                  //More then 2 pixels in the row?
   //
   if (dy>=4) then begin                    //DY must be greater then 4 to make the faked algo look good.. else it must be done "normal"
   //
    for x:=0 to dx-1 do begin               //Inverse Transform Colums (fake: if (high-pass coefficient=0.0) and (surrounding high-pass coefficients=0.0) then interpolate between surrounding low-pass coefficients)
     offsetm1:=0;
     offset:=cTileWidth;
     offsetp1:=cTileWidth*2;

     for y:=1 to yhalf do begin
      if (wl[x +offset+dyoff]<>0.0) then begin //!UPDATED
       tempy[x +offset*2]       := (wl[x +offset] + wl[x +offset+dyoff])*factor; //LOW-PASS
       tempy[x +offset*2 +cTileWidth] := (wl[x +offset] - wl[x +offset+dyoff])*factor; //HIGH-PASS
      end else begin //!UPDATED
       if (wl[x +offsetm1 +dyoff]=0.0) and (wl[x +offsetp1]<>wl[x +offset]) and ((y=yhalf) or (wl[x +offsetp1]<>wl[x +offsetp1 +cTileWidth])) then tempy[x +offset*2]:=(wl[x +offset]*0.8 + wl[x +offsetm1]*0.2)*factor //LOW-PASS
        else tempy[x +offset*2]:=wl[x +offset]*factor;
       if (wl[x +offsetp1 +dyoff]=0.0) and (wl[x +offsetm1]<>wl[x +offset]) and ((y=1) or (wl[x +offsetm1]<>wl[x +offsetm1 -cTileWidth])) then tempy[x +offset*2 +cTileWidth]:=(wl[x +offset]*0.8 + wl[x +offsetp1]*0.2)*factor //HIGH-PASS
        else tempy[x +offset*2 +cTileWidth]:=wl[x +offset]*factor;
      end;

      inc(offsetm1,cTileWidth);
      inc(offset,cTileWidth);
      inc(offsetp1,cTileWidth);
     end;

    end;
   //
   end else //DY<4
   //
    for x:=0 to dx-1 do begin
     offset:=cTileWidth;
     for y:=1 to yhalf do begin
      tempy[x +offset*2]      := (wl[x +offset] + wl[x +offset +dyoff])*factor; //LOW-PASS
      tempy[x +offset*2+cTileWidth] := (wl[x +offset] - wl[x +offset +dyoff])*factor; //HIGH-PASS

      inc(offset,cTileWidth);
     end;
    end;
   //
  end;

  ////

  offset:=0;
  yhalf:=(dx div 2)-1;
  yhalfoff:=(yhalf+dx div 2);
  yhalfoff2:=yhalf*2+1;

  if (yhalf>0) then begin
   for y:=0 to dy-1 do begin //The first and last pixel has to be done "normal"
    tempx[offset]   :=(tempy[offset] + tempy[yhalf+1 +offset])*factor; //LOW-PASS
    tempx[offset+1] :=(tempy[offset] - tempy[yhalf+1 +offset])*factor; //HIGH-PASS

    tempx[yhalf*2 +offset]   :=(tempy[yhalf +offset] + tempy[yhalfoff +offset])*factor; //LOW-PASS
    tempx[yhalfoff2 +offset] :=(tempy[yhalf +offset] - tempy[yhalfoff +offset])*factor; //HIGH-PASS

    inc(offset,cTileWidth);
   end;
  end else begin
   for y:=0 to dy-1 do begin //The first and last pixel has to be done "normal"
    tempx[offset]   :=(tempy[offset] + tempy[yhalf+1 +offset])*factor; //LOW-PASS
    tempx[offset+1] :=(tempy[offset] - tempy[yhalf+1 +offset])*factor; //HIGH-PASS

    inc(offset,cTileWidth);
   end;
  end;

  //

  dyoff:=(dx div 2);
  yhalf:=(dx div 2)-2;

  if (yhalf>=1) then begin

   if (dx>=4) then begin

    offset:=0;
    for y:=0 to dy-1 do begin               //Inverse Transform Rows (fake: if (high-pass coefficient=0.0) and (surrounding high-pass coefficients=0.0) then interpolate between surrounding low-pass coefficients)
     for x:=1 to yhalf do
      if (tempy[x +dyoff +offset]<>0.0) then begin //!UPDATED
       tempx[x*2 +offset]   :=(tempy[x +offset] + tempy[x +dyoff +offset])*factor; //LOW-PASS
       tempx[x*2+1 +offset] :=(tempy[x +offset] - tempy[x +dyoff +offset])*factor; //HIGH-PASS
      end else begin //!UPDATED
       if (tempy[x-1+dyoff +offset]=0.0) and (tempy[x+1 +offset]<>tempy[x +offset]) and ((x=yhalf) or (tempy[x+1 +offset]<>tempy[x+2 +offset])) then tempx[x*2 +offset]:=(tempy[x +offset]*0.8 + tempy[x-1 +offset]*0.2)*factor //LOW-PASS
        else tempx[x*2 +offset]:=tempy[x +offset]*factor;
       if (tempy[x+1+dyoff +offset]=0.0) and (tempy[x-1 +offset]<>tempy[x +offset]) and ((x=1) or (tempy[x-1 +offset]<>tempy[x-2 +offset])) then tempx[x*2+1 +offset]:=(tempy[x +offset]*0.8 + tempy[x+1 +offset]*0.2)*factor //HIGH-PASS
        else tempx[x*2+1 +offset]:=tempy[x +offset]*factor;
      end;
     inc(offset,cTileWidth);
    end;

   end else begin //DX<4

    offset:=0;
    for y:=0 to dy-1 do begin               //Inverse Transform Rows (fake: if (high-pass coefficient=0.0) and (surrounding high-pass coefficients=0.0) then interpolate between surrounding low-pass coefficients)
     for x:=1 to yhalf do begin
      tempx[x*2 +offset]   := (tempy[x +offset] + tempy[x +dyoff +offset])*factor; //LOW-PASS
      tempx[x*2+1 +offset] := (tempy[x +offset] - tempy[x +dyoff +offset])*factor; //HIGH-PASS
     end;
     inc(offset,cTileWidth);
    end;

   end;

  end;

  ////

  for y:=0 to dy-1 do
   move(tempx[y*cTileWidth],pic[y*cTileWidth],dx*sizeof(TFloat)); //Copy to Pic
END;

procedure TMainForm.ComputeTilePsyVisFeatures(const ATile: TTile; FromPal, UseWavelets, UseLAB, QWeighting, HMirror, VMirror: Boolean;
  GammaCor: Integer; const pal: TIntegerDynArray; var DCT: TFloatDynArray);
const
  cUVRatio: array[0..cTileWidth-1,0..cTileWidth-1] of TFloat = (
    (0.5, sqrt(0.5), sqrt(0.5), sqrt(0.5), sqrt(0.5), sqrt(0.5), sqrt(0.5), sqrt(0.5)),
    (sqrt(0.5), 1, 1, 1, 1, 1, 1, 1),
    (sqrt(0.5), 1, 1, 1, 1, 1, 1, 1),
    (sqrt(0.5), 1, 1, 1, 1, 1, 1, 1),
    (sqrt(0.5), 1, 1, 1, 1, 1, 1, 1),
    (sqrt(0.5), 1, 1, 1, 1, 1, 1, 1),
    (sqrt(0.5), 1, 1, 1, 1, 1, 1, 1),
    (sqrt(0.5), 1, 1, 1, 1, 1, 1, 1)
  );
var
  u, v, x, y, xx, yy, cpn: Integer;
  z: TFloat;
  CpnPixels: array[0..cColorCpns-1, 0..cTileWidth-1,0..cTileWidth-1] of TFloat;
  pRatio, pDCT, pCpn, pLut: PFloat;

  procedure ToCpn(col, x, y: Integer); inline;
  var
    r, g, b: Byte;
    yy, uu, vv: TFloat;
  begin
    FromRGB(col, r, g, b);

    if UseLAB then
      RGBToLAB(r, g, b, GammaCor, yy, uu, vv)
    else
      RGBToYUV(r, g, b, GammaCor, yy, uu, vv);

    CpnPixels[0, y, x] := yy;
    CpnPixels[1, y, x] := uu;
    CpnPixels[2, y, x] := vv;
  end;

begin
  Assert(Length(DCT) >= cTileDCTSize, 'DCT too small!');

  if FromPal then
  begin
    for y := 0 to (cTileWidth - 1) do
      for x := 0 to (cTileWidth - 1) do
      begin
        xx := x;
        yy := y;
        if HMirror then xx := cTileWidth - 1 - x;
        if VMirror then yy := cTileWidth - 1 - y;

        ToCpn(pal[ATile.PalPixels[yy,xx]], x, y);
      end;
  end
  else
  begin
    for y := 0 to (cTileWidth - 1) do
      for x := 0 to (cTileWidth - 1) do
      begin
        xx := x;
        yy := y;
        if HMirror then xx := cTileWidth - 1 - x;
        if VMirror then yy := cTileWidth - 1 - y;

        ToCpn(ATile.RGBPixels[yy,xx], x, y);
      end;
  end;

  pDCT := @DCT[0];
  if UseWavelets then
  begin
    for cpn := 0 to cColorCpns - 1 do
    begin
      pCpn := @CpnPixels[cpn, 0, 0];
      WaveletGS(pCpn, pDCT, cTileWidth, cTileWidth, 2);
      Inc(pDCT, sqr(cTileWidth));
    end;
  end
  else
  begin
    for cpn := 0 to cColorCpns - 1 do
    begin
      pRatio := @cUVRatio[0, 0];
      pLut := @gDCTLut[0];

      for v := 0 to (cTileWidth - 1) do
        for u := 0 to (cTileWidth - 1) do
        begin
  		    z := 0.0;
          pCpn := @CpnPixels[cpn, 0, 0];

          // unroll y by cTileWidth

          // unroll x by cTileWidth
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);

          // unroll x by cTileWidth
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);

          // unroll x by cTileWidth
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);

          // unroll x by cTileWidth
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);

          // unroll x by cTileWidth
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);

          // unroll x by cTileWidth
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);

          // unroll x by cTileWidth
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);

          // unroll x by cTileWidth
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
          z += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);

          if QWeighting then
             z *= cDCTQuantization[cpn, v, u];

          pDCT^ := z * pRatio^;
          Inc(pDCT);
          Inc(pRatio);
        end;
    end;
  end;
end;

procedure TMainForm.VMirrorPalTile(var ATile: TTile);
var
  j, i: Integer;
  v: Integer;
begin
  // hardcode vertical mirror into the tile

  for j := 0 to cTileWidth div 2 - 1  do
    for i := 0 to cTileWidth - 1 do
    begin
      v := ATile.PalPixels[j, i];
      ATile.PalPixels[j, i] := ATile.PalPixels[cTileWidth - 1 - j, i];
      ATile.PalPixels[cTileWidth - 1 - j, i] := v;
    end;
end;

procedure TMainForm.HMirrorPalTile(var ATile: TTile);
var
  i, j: Integer;
  v: Integer;
begin
  // hardcode horizontal mirror into the tile

  for j := 0 to cTileWidth - 1 do
    for i := 0 to cTileWidth div 2 - 1  do
    begin
      v := ATile.PalPixels[j, i];
      ATile.PalPixels[j, i] := ATile.PalPixels[j, cTileWidth - 1 - i];
      ATile.PalPixels[j, cTileWidth - 1 - i] := v;
    end;
end;

procedure TMainForm.LoadFrame(var AFrame: TFrame; ABitmap: TBitmap);
var
  i, j, col, ti, tx, ty: Integer;
  pcol: PInteger;
  pfs: PByte;
  TilesRGBPixels: array of TRGBPixels;
begin
  AFrame := TFrame.Create;

  SetLength(TilesRGBPixels, FTileMapSize);
  SetLength(AFrame.Tiles, FTileMapSize);
  SetLength(AFrame.TileMap, FTileMapHeight, FTileMapWidth);
  SetLength(AFrame.SmoothedTileMap, FTileMapHeight, FTileMapWidth);
  SetLength(AFrame.FSPixels, FScreenHeight * FScreenWidth * 3);

  for j := 0 to (FTileMapHeight - 1) do
    for i := 0 to (FTileMapWidth - 1) do
    begin
      AFrame.TileMap[j, i].GlobalTileIndex := FTileMapWidth * j + i;
      AFrame.TileMap[j, i].HMirror := False;
      AFrame.TileMap[j, i].VMirror := False;
      AFrame.TileMap[j, i].PalIdx := -1;
      AFrame.TileMap[j, i].Smoothed := False;
      AFrame.TileMap[j, i].TmpIndex := -1;
      AFrame.SmoothedTileMap[j, i] := AFrame.TileMap[j, i];
    end;

  Assert(ABitmap.Width >= FScreenWidth, 'Wrong video width!');
  Assert(ABitmap.Height >= FScreenHeight, 'Wrong video height!');

  ABitmap.BeginUpdate;
  try
    pfs := @AFrame.FSPixels[0];
    for j := 0 to (FScreenHeight - 1) do
    begin
      pcol := ABitmap.ScanLine[j];
      for i := 0 to (FScreenWidth - 1) do
        begin
          col := pcol^;
          Inc(pcol);

          ti := FTileMapWidth * (j div cTileWidth) + (i div cTileWidth);
          tx := i and (cTileWidth - 1);
          ty := j and (cTileWidth - 1);

          col := SwapRB(col);

          TilesRGBPixels[ti][ty, tx] := col;

          FromRGB(col, pfs[0], pfs[1], pfs[2]);
          Inc(pfs, 3);
        end;
    end;

    DitherFloydSteinberg(AFrame.FSPixels);

    for i := 0 to (FTileMapSize - 1) do
    begin
      Move(TilesRGBPixels[i], AFrame.Tiles[i].RGBPixels, SizeOf(TRGBPixels));

      for ty := 0 to (cTileWidth - 1) do
        for tx := 0 to (cTileWidth - 1) do
          AFrame.Tiles[i].PalPixels[ty, tx] := 0;

      AFrame.Tiles[i].Active := True;
      AFrame.Tiles[i].UseCount := 1;
      AFrame.Tiles[i].TmpIndex := -1;
      AFrame.Tiles[i].MergeIndex := -1;
      AFrame.Tiles[i].OriginalReloadedIndex := -1;
      AFrame.Tiles[i].DitheringPalIndex := -1;
    end;

  finally
    ABitmap.EndUpdate;
  end;
end;

procedure TMainForm.ClearAll;
var
  i: Integer;
begin
  for i := 0 to High(FFrames) do
    FFrames[i].Free;
  SetLength(FFrames, 0);

  for i := 0 to High(FKeyFrames) do
    FKeyFrames[i].Free;
  SetLength(FKeyFrames, 0);

  for i := 0 to High(FTiles) do
    Dispose(FTiles[i]);
  SetLength(FTiles, 0);
end;

procedure TMainForm.Render(AFrameIndex: Integer; playing, dithered, mirrored, reduced, gamma: Boolean; palIdx: Integer;
  ATilePage: Integer);

  procedure DrawTile(bitmap: TBitmap; sx, sy: Integer; tilePtr: PTile; pal: TIntegerDynArray; hmir, vmir: Boolean);
  var
    r, g, b, tx, ty, txm, tym: Integer;
    psl: PInteger;
  begin
    for ty := 0 to cTileWidth - 1 do
    begin
      psl := bitmap.ScanLine[ty + sy * cTileWidth];
      Inc(psl, sx * cTileWidth);

      tym := ty;
      if (vmir and mirrored) xor tilePtr^.VMirror then tym := cTileWidth - 1 - tym;

      for tx := 0 to cTileWidth - 1 do
      begin
        txm := tx;
        if (hmir and mirrored) xor tilePtr^.HMirror then txm := cTileWidth - 1 - txm;

        r := 255; g := 0; b := 255;
        if dithered and Assigned(pal) then
          FromRGB(pal[tilePtr^.PalPixels[tym, txm]], r, g, b)
        else
          FromRGB(tilePtr^.RGBPixels[tym, txm], r, g, b);

        if gamma then
        begin
          r := round(GammaCorrect(1, r) * 255.0);
          g := round(GammaCorrect(1, g) * 255.0);
          b := round(GammaCorrect(1, b) * 255.0);
        end;

        psl^ := SwapRB(ToRGB(r, g, b));
        Inc(psl);
      end;
    end;
  end;

var
  i, j, sx, sy, ti: Integer;
  p: PInteger;
  tilePtr: PTile;
  TMItem: TTileMapItem;
  Frame: TFrame;
  pal: TIntegerDynArray;
  oriCorr, chgCorr: TIntegerDynArray;
begin
  if Length(FFrames) <= 0 then
    Exit;

  mirrored := mirrored and reduced;

  AFrameIndex := EnsureRange(AFrameIndex, 0, high(FFrames));

  Frame := FFrames[AFrameIndex];

  if not Assigned(Frame) or not Assigned(Frame.PKeyFrame) then
    Exit;

  try
    if not playing then
    begin
      pnLbl.Caption := 'Global: ' + IntToStr(GetGlobalTileCount) + ' / Frame #' + IntToStr(AFrameIndex) + IfThen(Frame.PKeyFrame.StartFrame = AFrameIndex, ' [KF]', '     ') + ' : ' + IntToStr(GetFrameTileCount(Frame));

      imgTiles.Picture.Bitmap.BeginUpdate;
      try
        imgTiles.Picture.Bitmap.Canvas.Brush.Color := clAqua;
        imgTiles.Picture.Bitmap.Canvas.Brush.Style := bsSolid;
        imgTiles.Picture.Bitmap.Canvas.Clear;

        for sy := 0 to FTileMapHeight - 1 do
          for sx := 0 to FTileMapWidth - 1 do
          begin
            ti := FTileMapWidth * sy + sx + FTileMapSize * ATilePage;

            if InRange(ti, 0, High(FTiles)) then
            begin
              tilePtr := FTiles[ti];
              pal := Frame.PKeyFrame.PaletteRGB[Max(0, palIdx)];

              DrawTile(imgTiles.Picture.Bitmap, sx, sy, tilePtr, pal, False, False);
            end;
          end;
      finally
        imgTiles.Picture.Bitmap.EndUpdate;
      end;
    end;

    imgSource.Picture.Bitmap.BeginUpdate;
    try
      for sy := 0 to FTileMapHeight - 1 do
        for sx := 0 to FTileMapWidth - 1 do
        begin
          tilePtr :=  @Frame.Tiles[sy * FTileMapWidth + sx];
          DrawTile(imgSource.Picture.Bitmap, sx, sy, tilePtr, nil, False, False);
        end;
    finally
      imgSource.Picture.Bitmap.EndUpdate;
    end;

    imgDest.Picture.Bitmap.BeginUpdate;
    try
      imgDest.Picture.Bitmap.Canvas.Brush.Color := clFuchsia;
      imgDest.Picture.Bitmap.Canvas.Brush.Style := bsDiagCross;
      imgDest.Picture.Bitmap.Canvas.Clear;

      for sy := 0 to FTileMapHeight - 1 do
        for sx := 0 to FTileMapWidth - 1 do
        begin
          TMItem := Frame.TileMap[sy, sx];
          if Frame.SmoothedTileMap[sy, sx].Smoothed then
            TMItem := Frame.SmoothedTileMap[sy, sx];

          ti := TMItem.GlobalTileIndex;

          if InRange(ti, 0, High(FTiles)) then
          begin
            tilePtr :=  @Frame.Tiles[sy * FTileMapWidth + sx];
            pal := tilePtr^.PaletteRGB;

            if reduced then
            begin
              tilePtr := FTiles[ti];
              if palIdx < 0 then
              begin
                if not InRange(TMItem.PalIdx, 0, High(Frame.PKeyFrame.PaletteRGB)) then
                  Continue;
                pal := Frame.PKeyFrame.PaletteRGB[TMItem.PalIdx]
              end
              else
              begin
                if palIdx <> TMItem.PalIdx then
                  Continue;
                pal := Frame.PKeyFrame.PaletteRGB[palIdx];
              end
            end;

            DrawTile(imgDest.Picture.Bitmap, sx, sy, tilePtr, pal, TMItem.HMirror, TMItem.VMirror);
          end;
        end;
    finally
      imgDest.Picture.Bitmap.EndUpdate;
    end;

    imgPalette.Picture.Bitmap.BeginUpdate;
    try
      for j := 0 to imgPalette.Picture.Bitmap.Height - 1 do
      begin
        p := imgPalette.Picture.Bitmap.ScanLine[j];
        for i := 0 to imgPalette.Picture.Bitmap.Width - 1 do
        begin
          if Assigned(Frame.PKeyFrame.PaletteRGB[j]) then
            p^ := SwapRB(Frame.PKeyFrame.PaletteRGB[j, i])
          else
            p^ := clFuchsia;

          Inc(p);
        end;
      end;
    finally
      imgPalette.Picture.Bitmap.EndUpdate;
    end;

    if not playing then
    begin
      SetLength(oriCorr, FScreenHeight * FScreenWidth * 2);
      SetLength(chgCorr, FScreenHeight * FScreenWidth * 2);

      for j := 0 to FScreenHeight - 1 do
      begin
        Move(PInteger(imgSource.Picture.Bitmap.ScanLine[j])^, oriCorr[j * FScreenWidth], FScreenWidth * SizeOf(Integer));
        Move(PInteger(imgDest.Picture.Bitmap.ScanLine[j])^, chgCorr[j * FScreenWidth], FScreenWidth * SizeOf(Integer));
      end;

      for j := 0 to FScreenHeight - 1 do
        for i := 0 to FScreenWidth - 1 do
        begin
          oriCorr[FScreenWidth * FScreenHeight + i * FScreenHeight + j] := oriCorr[j * FScreenWidth + i];
          chgCorr[FScreenWidth * FScreenHeight + i * FScreenHeight + j] := chgCorr[j * FScreenWidth + i];
        end;

      lblCorrel.Caption := FormatFloat('0.0000000', ComputeCorrelationBGR(oriCorr, chgCorr));
    end;
  finally
    Repaint;
  end;
end;

// from https://www.delphipraxis.net/157099-fast-integer-rgb-hsl.html
procedure TMainForm.RGBToHSV(col: Integer; out h, s, v: Byte);
var
  rr, gg, bb: Integer;

  function RGBMaxValue: Integer;
  begin
    Result := rr;
    if (Result < gg) then Result := gg;
    if (Result < bb) then Result := bb;
  end;

  function RGBMinValue : Integer;
  begin
    Result := rr;
    if (Result > gg) then Result := gg;
    if (Result > bb) then Result := bb;
  end;

var
  Delta, mx, mn, hh, ss, ll: Integer;
begin
  FromRGB(col, rr, gg, bb);

  mx := RGBMaxValue;
  mn := RGBMinValue;

  hh := 0;
  ss := 0;
  ll := mx;
  if ll <> mn then
  begin
    Delta := ll - mn;
    ss := MulDiv(Delta, 255, ll);

    if (rr = ll) then
      hh := MulDiv(42, gg - bb, Delta)
    else if (gg = ll) then
      hh := MulDiv(42, bb - rr, Delta) + 84
    else if (bb = ll) then
      hh := MulDiv(42, rr - gg, Delta) + 168;

    hh := hh mod 252;
  end;

  h := hh and $ff;
  s := ss and $ff;
  v := ll and $ff;
end;

function TMainForm.HSVToRGB(h, s, v: Byte): Integer;
const
  MaxHue: Integer = 252;
  MaxSat: Integer = 255;
  MaxLum: Integer = 255;
  Divisor: Integer = 42;
var
 f, LS, p, q, r: integer;
begin
 if (s = 0) then
   Result := ToRGB(v, v, v)
 else
  begin
   h := h mod MaxHue;
   s := EnsureRange(s, 0, MaxSat);
   v := EnsureRange(v, 0, MaxLum);

   f := h mod Divisor;
   h := h div Divisor;
   LS := v*s;
   p := v - LS div MaxLum;
   q := v - (LS*f) div (255 * Divisor);
   r := v - (LS*(Divisor - f)) div (255 * Divisor);
   case h of
    0: Result := ToRGB(v, r, p);
    1: Result := ToRGB(q, v, p);
    2: Result := ToRGB(p, v, r);
    3: Result := ToRGB(p, q, v);
    4: Result := ToRGB(r, p, v);
    5: Result := ToRGB(v, p, q);
   else
    Result := ToRGB(0, 0, 0);
   end;
  end;
end;

procedure TMainForm.ProgressRedraw(CurFrameIdx: Integer; ProgressStep: TEncoderStep);
const
  cProgressMul = 100;
var
  esLen: Integer;
  t: Integer;
begin
  pbProgress.Max := (Ord(High(TEncoderStep)) + 1) * cProgressMul;

  if CurFrameIdx >= 0 then
  begin
    esLen := Max(0, cEncoderStepLen[FProgressStep]) + Max(0, -cEncoderStepLen[FProgressStep]) * Length(FKeyFrames);
    FProgressPosition := iDiv0(CurFrameIdx * cProgressMul, esLen);
  end;

  if ProgressStep <> esNone then
  begin
    FProgressPosition := 0;
    FOldProgressPosition := 0;
    FProgressStep := ProgressStep;
    pbProgress.Position := Ord(FProgressStep) * cProgressMul;
    Screen.Cursor := crHourGlass;
    FProgressPrevTime := GetTickCount;
  end;

  if (CurFrameIdx < 0) and (ProgressStep = esNone) then
  begin
    FProgressPosition := 0;
    FOldProgressPosition := 0;
    FProgressStep := esNone;
    FProgressPosition := 0;
    FProgressPrevTime := GetTickCount;
    FProgressStartTime := FProgressPrevTime;
  end;

  pbProgress.Position := pbProgress.Position + (FProgressPosition - FOldProgressPosition);
  pbProgress.Invalidate;
  lblPct.Caption := IntToStr(pbProgress.Position * 100 div pbProgress.Max) + '%';
  lblPct.Invalidate;
  Repaint;

  t := GetTickCount;
  if CurFrameIdx >= 0 then
  begin
    WriteLn('Step: ', Copy(GetEnumName(TypeInfo(TEncoderStep), Ord(FProgressStep)), 3), ' / ', FProgressPosition,
      #9'Time: ', FormatFloat('0.000', (t - FProgressPrevTime) / 1000), #9'All: ', FormatFloat('0.000', (t - FProgressStartTime) / 1000));
  end;
  FProgressPrevTime := t;

  FOldProgressPosition := FProgressPosition;
end;

function TMainForm.GetGlobalTileCount: Integer;
var i: Integer;
begin
  Result := 0;
  for i := 0 to High(FTiles) do
    if FTiles[i]^.Active then
      Inc(Result);
end;

function TMainForm.GetFrameTileCount(AFrame: TFrame): Integer;
var
  Used: TIntegerDynArray;
  i, j: Integer;
begin
  Result := 0;

  if Length(FTiles) = 0 then
    Exit;

  SetLength(Used, Length(FTiles));
  FillDWord(Used[0], Length(FTiles), 0);

  for j := 0 to FTileMapHeight - 1 do
    for i := 0 to FTileMapWidth - 1 do
      Used[AFrame.TileMap[j, i].GlobalTileIndex] := 1;

  for i := 0 to High(Used) do
    Inc(Result, Used[i]);
end;

procedure TMainForm.CopyTile(const Src: TTile; var Dest: TTile);
begin
  Dest.Active := Src.Active;
  Dest.TmpIndex := Src.TmpIndex;
  Dest.MergeIndex := Src.MergeIndex;
  Dest.UseCount := Src.UseCount;
  Dest.OriginalReloadedIndex := Src.OriginalReloadedIndex;
  Dest.DitheringPalIndex := Src.DitheringPalIndex;

  SetLength(Dest.PaletteIndexes, Length(Src.PaletteIndexes));
  SetLength(Dest.PaletteRGB, Length(Src.PaletteRGB));

  if Assigned(Dest.PaletteIndexes) then
    move(Src.PaletteIndexes[0], Dest.PaletteIndexes[0], Length(Src.PaletteIndexes) * SizeOf(Integer));
  if Assigned(Dest.PaletteRGB) then
    move(Src.PaletteRGB[0], Dest.PaletteRGB[0], Length(Src.PaletteRGB) * SizeOf(Integer));

  Move(Src.PalPixels[0, 0], Dest.PalPixels[0, 0], SizeOf(TPalPixels));
  Move(Src.RGBPixels[0, 0], Dest.RGBPixels[0, 0], SizeOf(TRGBPixels));
end;

procedure TMainForm.MergeTiles(const TileIndexes: array of Integer; TileCount: Integer; BestIdx: Integer;
  NewTile: PPalPixels; NewTileRGB: PRGBPixels);
var
  j, k: Integer;
begin
  if TileCount <= 0 then
    Exit;

  if Assigned(NewTile) then
    Move(NewTile^[0, 0], FTiles[BestIdx]^.PalPixels[0, 0], sizeof(TPalPixels));

  if Assigned(NewTileRGB) then
    Move(NewTileRGB^[0, 0], FTiles[BestIdx]^.RGBPixels[0, 0], sizeof(TRGBPixels));

  for k := 0 to TileCount - 1 do
  begin
    j := TileIndexes[k];

    if j = BestIdx then
      Continue;

    Inc(FTiles[BestIdx]^.UseCount, FTiles[j]^.UseCount);

    FTiles[j]^.Active := False;
    FTiles[j]^.MergeIndex := BestIdx;

    FillChar(FTiles[j]^.PalPixels, SizeOf(FTiles[j]^.PalPixels), 0);
  end;
end;

procedure TMainForm.InitMergeTiles;
var
  i: Integer;
begin
  for i := 0 to High(FTiles) do
    FTiles[i]^.MergeIndex := -1;
end;

procedure TMainForm.FinishMergeTiles;
var
  i, j, k, idx: Integer;
begin
  for k := 0 to High(FFrames) do
    for j := 0 to (FTileMapHeight - 1) do
      for i := 0 to (FTileMapWidth - 1) do
      begin
        idx := FTiles[FFrames[k].TileMap[j, i].GlobalTileIndex]^.MergeIndex;
        if idx >= 0 then
          FFrames[k].TileMap[j, i].GlobalTileIndex := idx;
      end;
end;

procedure TMainForm.PrepareGlobalFT;
var
  di, i: Integer;
  T: PTile;

  procedure DoOne(TileIdx: Integer; HMirror, VMirror: Boolean);
  var
    j: Integer;
    PB: PByte;
  begin
    PB := @T^.PalPixels[0, 0];
    for j := 0 to sqr(cTileWidth) - 1 do
    begin
      FGlobalDS.Dataset[di, j] := PB^;
      Inc(PB);
    end;
    FGlobalDS.TRToTileIdx[di] := TileIdx;
    FGlobalDS.TRToAttrs[di] := Ord(HMirror) or (Ord(VMirror) shl 1);
    Inc(di);
  end;

begin
  SetLength(FGlobalDS.Dataset, GetGlobalTileCount * 4, sqr(cTileWidth));
  SetLength(FGlobalDS.TRToTileIdx, Length(FGlobalDS.Dataset));
  SetLength(FGlobalDS.TRToAttrs, Length(FGlobalDS.Dataset));

  di := 0;
  for i := 0 to High(FTiles) do
  begin
    T := FTiles[i];
    if T^.Active then
    begin
      DoOne(i, False, False);
      HMirrorPalTile(T^);
      DoOne(i, True, False);
      VMirrorPalTile(T^);
      DoOne(i, True, True);
      HMirrorPalTile(T^);
      DoOne(i, False, True);
      VMirrorPalTile(T^);
    end;
  end;

  FGlobalDS.KDT := ann_kdtree_create(PPANNFloat(FGlobalDS.Dataset), Length(FGlobalDS.Dataset), sqr(cTileWidth), 1, ANN_KD_STD);
end;

procedure TMainForm.FinishGlobalFT;
begin
  ann_kdtree_destroy(FGlobalDS.KDT);
  FGlobalDS.KDT := nil;
  SetLength(FGlobalDS.Dataset, 0);
  SetLength(FGlobalDS.TRToPalIdx, 0);
  SetLength(FGlobalDS.TRToTileIdx, 0);
end;

procedure TMainForm.PrepareFrameTiling(AKF: TKeyFrame; AFTGamma: Integer; APalTol: TFloat; AUseWavelets: Boolean;
  AFTQuality: TFTQuality);
var
  KNNSize, i, j: Integer;
  palIdx: Integer;
  DS: PTilingDataset;
  used: array of array of array[-1..3] of Boolean;
  usedCount: TIntegerDynArray;
  Corrs: TFloatDynArray2;
  HighestCorr: TFloat;

  procedure UseOne(Item: PTileMapItem);
  const
    cBucketSize = 8;
  var
    i, idx: Integer;
    palIdx: Integer;
    idxs: array[0 .. cBucketSize - 1] of Integer;
    errs: array[0 .. cBucketSize - 1] of TANNFloat;
    Line: array[0 .. sqr(cTileWidth) - 1] of TANNFloat;
    PB: PByte;
    last: TFloat;
  begin
    SpinEnter(@FLock);
    if used[Item^.PalIdx, Item^.GlobalTileIndex, -1] then
    begin
      SpinLeave(@FLock);
      Exit;
    end;
    used[Item^.PalIdx, Item^.GlobalTileIndex, -1] := True;
    SpinLeave(@FLock);

    PB := @FTiles[Item^.GlobalTileIndex]^.PalPixels[0, 0];
    for i := 0 to sqr(cTileWidth) - 1 do
    begin
      Line[i] := PB^;
      Inc(PB);
    end;

    ann_kdtree_search_multi(FGlobalDS.KDT, @idxs[0], @errs[0], cBucketSize, @Line[0], 0.0);

    last := Infinity;
    for i := 0 to cBucketSize - 1 do
    begin
      if errs[i] = last then
        Continue;
      last := errs[i];

      idx := idxs[i];

      case AFTQuality of
        ftFast:
          used[Item^.PalIdx, FGlobalDS.TRToTileIdx[idx], FGlobalDS.TRToAttrs[idx]] := True;
        ftMedium:
          for palIdx := 0 to FPaletteCount - 1 do
            if Corrs[palIdx, Item^.PalIdx] < APalTol * HighestCorr then
              used[palIdx, FGlobalDS.TRToTileIdx[idx], FGlobalDS.TRToAttrs[idx]] := True;
        ftSlow:
          for palIdx := 0 to FPaletteCount - 1 do
            used[palIdx, FGlobalDS.TRToTileIdx[idx], FGlobalDS.TRToAttrs[idx]] := True;
      end;
    end;
  end;

  function BuildPaletteCorrTriangle: TFloatDynArray2;
  var
    i, j : Integer;
  begin
    SetLength(Result, FPaletteCount, FPaletteCount);
    for j := 0 to FPaletteCount - 1 do
      for i := 0 to FPaletteCount - 1 do
      begin
        Result[j, i] := CompareEuclideanDCT(AKF.PaletteCentroids[j], AKF.PaletteCentroids[i]);
        if not IsNan(Result[j, i]) then
          HighestCorr := Max(HighestCorr, Result[j, i]);
      end;
  end;

  procedure DoBuild(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
  var
    frm: TFrame;
    idx, sy, sx: Integer;
  begin
    if not InRange(AIndex, 0, AKF.FrameCount * FTileMapHeight - 1) then
      Exit;

    DivMod(AIndex, FTileMapHeight, idx, sy);
    frm := FFrames[AKF.StartFrame + idx];
    for sx := 0 to FTileMapWidth - 1 do
      UseOne(@frm.TileMap[sy, sx]);
  end;

  procedure DoPsyV(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
  var
    di, dend, i, j: Integer;
    vmir, hmir: Boolean;
    T: PTile;
    DCT: TFloatDynArray;
  begin
    if not InRange(AIndex, 0, FPaletteCount - 1) then
      Exit;

    SetLength(DCT, cTileDCTSize);

    SpinEnter(@FLock);
    di := 0;
    for i := 0 to AIndex - 1 do
      Inc(di, usedCount[i]);
    dend := di + usedCount[AIndex];
    SpinLeave(@FLock);

    for i := 0 to High(FTiles) do
      for vmir := False to True do
        for hmir := False to True do
          if used[AIndex, i, (Ord(vmir) shl 1) or Ord(hmir)] then
          begin
            T := FTiles[i];
            DS^.TRToTileIdx[di] := i;
            DS^.TRToPalIdx[di] := AIndex;
            DS^.TRToAttrs[di] := Ord(hmir) or (Ord(vmir) shl 1);

            ComputeTilePsyVisFeatures(T^, True, AUseWavelets, False, False, hmir xor T^.HMirror, vmir xor T^.VMirror, AFTGamma, AKF.PaletteRGB[AIndex], DCT);
            for j := 0 to cTileDCTSize - 1 do
              DS^.Dataset[di, j] := DCT[j];
            Inc(di);
          end;

    Assert(di = dend);
  end;

begin
  DS := New(PTilingDataset);
  FillChar(DS^, SizeOf(TTilingDataset), 0);
  AKF.TileDS := DS;

  HighestCorr := 0.0;
  Corrs := nil;
  if AFTQuality = ftMedium then
    Corrs := BuildPaletteCorrTriangle;

  SetLength(usedCount, FPaletteCount);
  SetLength(used, FPaletteCount, Length(FTiles));
  for palIdx := 0 to FPaletteCount - 1 do
    FillByte(used[palIdx, 0], Length(FTiles) * SizeOf(used[0, 0]), 0);

  // Build an indicator table of used tiles

  ProcThreadPool.DoParallelLocalProc(@DoBuild, 0, AKF.FrameCount * FTileMapHeight - 1);

  // Compute psycho visual model for all used tiles (in all palettes / mirrors)

  KNNSize := 0;
  for palIdx := 0 to FPaletteCount - 1 do
  begin
    usedCount[palIdx] := 0;
    for i := 0 to High(FTiles) do
      for j := 0 to 3 do
        Inc(usedCount[palIdx], Ord(used[palIdx, i, j]));
    KNNSize += usedCount[palIdx];
  end;

  SetLength(DS^.TRToTileIdx, KNNSize);
  SetLength(DS^.TRToPalIdx, KNNSize);
  SetLength(DS^.TRToAttrs, KNNSize);
  SetLength(DS^.Dataset, KNNSize, cTileDCTSize);

  ProcThreadPool.DoParallelLocalProc(@DoPsyV, 0, FPaletteCount - 1, @used[0]);

  // Build KNN

  DS^.KDT := ann_kdtree_create(@DS^.Dataset[0], Length(DS^.Dataset), cTileDCTSize, 1, ANN_KD_STD);

  SetLength(DS^.DistErrCml, FPaletteCount);
  SetLength(DS^.DistErrCnt, FPaletteCount);

  WriteLn('Frame: ', AKF.StartFrame, #9'KNNSize: ', KNNSize);
end;

procedure TMainForm.FinishFrameTiling(AKF: TKeyFrame);
var
  i: Integer;
  resDist: TFloat;
begin
  resDist := 0.0;
  for i := 0 to FPaletteCount - 1 do
    if AKF.TileDS^.DistErrCnt[i] <> 0 then
    begin
      //WriteLn(AKF.StartFrame, #9, i, #9, FloatToStr(AKF.TileDS^.DistErrCml[i] / AKF.TileDS^.DistErrCnt[i]));
      resDist += AKF.TileDS^.DistErrCml[i];
    end;
  WriteLn('Frame: ', AKF.StartFrame, #9'ResidualErr: ', FloatToStr(resDist));

  ann_kdtree_destroy(AKF.TileDS^.KDT);
  AKF.TileDS^.KDT := nil;
  SetLength(AKF.TileDS^.Dataset, 0);
  SetLength(AKF.TileDS^.TRToPalIdx, 0);
  SetLength(AKF.TileDS^.TRToTileIdx, 0);
  Dispose(AKF.TileDS);
  AKF.TileDS := nil;
end;

procedure TMainForm.DoFrameTiling(AFrame: TFrame; AFTGamma: Integer; APalVAR: TFloat; AUseWavelets: Boolean;
  AFTQuality: TFTQuality);
var
  sy, sx: Integer;
  DS: PTilingDataset;
  tmiO: PTileMapItem;

  i, bestIdx: Integer;
  DCT: TFloatDynArray;
  ANNDCT: TANNFloatDynArray;
  bestErr: TANNFloat;

begin
  EnterCriticalSection(AFrame.PKeyFrame.CS);
  if AFrame.PKeyFrame.FramesLeft < 0 then
  begin
    PrepareFrameTiling(AFrame.PKeyFrame, AFTGamma, APalVAR, AUseWavelets, AFTQuality);
    AFrame.PKeyFrame.FramesLeft := AFrame.PKeyFrame.FrameCount;
  end;
  LeaveCriticalSection(AFrame.PKeyFrame.CS);

  DS := AFrame.PKeyFrame.TileDS;

  // map frame tilemap items to reduced tiles and mirrors and choose best corresponding palette

  SetLength(DCT, cTileDCTSize);
  SetLength(ANNDCT, cTileDCTSize);

  for sy := 0 to FTileMapHeight - 1 do
    for sx := 0 to FTileMapWidth - 1 do
    begin
      ComputeTilePsyVisFeatures(AFrame.Tiles[sy * FTileMapWidth + sx], False, AUseWavelets, False, False, False, False, AFTGamma, AFrame.Tiles[sy * FTileMapWidth + sx].PaletteRGB, DCT);
      for i := 0 to cTileDCTSize - 1 do
        ANNDCT[i] := DCT[i];

      bestIdx := ann_kdtree_search(DS^.KDT, @ANNDCT[0], 0.0, @bestErr);

      tmiO := @FFrames[AFrame.Index].TileMap[sy, sx];

      tmiO^.GlobalTileIndex := DS^.TRToTileIdx[bestIdx];
      tmiO^.PalIdx :=  DS^.TRToPalIdx[bestIdx];
      tmiO^.HMirror := (DS^.TRToAttrs[bestIdx] and 1) <> 0;
      tmiO^.VMirror := (DS^.TRToAttrs[bestIdx] and 2) <> 0;

      DS^.DistErrCml[tmiO^.PalIdx] += bestErr;
      Inc(DS^.DistErrCnt[tmiO^.PalIdx]);
    end;

  WriteLn('Frame: ', AFrame.Index, #9'FramesLeft: ', AFrame.PKeyFrame.FramesLeft);

  EnterCriticalSection(AFrame.PKeyFrame.CS);
  Dec(AFrame.PKeyFrame.FramesLeft);
  if AFrame.PKeyFrame.FramesLeft <= 0 then
    FinishFrameTiling(AFrame.PKeyFrame);
  LeaveCriticalSection(AFrame.PKeyFrame.CS);
end;

procedure TMainForm.PrepareTileMirrors(var ATile: TTile);
var
  bestV, v: Integer;
  hf, vf: Boolean;
begin
  bestV := -1;
  for vf := False to True do
    for hf := False to True do
    begin
      v := GetTileZoneSum(ATile, IfThen(hf, cTileWidth div 2), IfThen(vf, cTileWidth div 2), cTileWidth div 2, cTileWidth div 2);
      if v > bestV then
      begin
        ATile.HMirror := hf;
        ATile.VMirror := vf;
        bestV := v;
      end;
    end;

  if ATile.HMirror then HMirrorPalTile(ATile);
  if ATile.VMirror then VMirrorPalTile(ATile);
end;

procedure TMainForm.DoTemporalSmoothing(AFrame, APrevFrame: TFrame; Y: Integer; Strength: TFloat);
const
  cSqrtFactor = 1 / (sqr(cTileWidth) * 3);
var
  sx: Integer;
  cmp: TFloat;
  TMI, PrevTMI: PTileMapItem;
  Tile_, PrevTile: TTile;
  TileDCT, PrevTileDCT: TFloatDynArray;
begin
  if AFrame.PKeyFrame <> APrevFrame.PKeyFrame then
    Exit;

  SetLength(PrevTileDCT, cTileDCTSize);
  SetLength(TileDCT, cTileDCTSize);

  for sx := 0 to FTileMapWidth - 1 do
  begin
    TMI := @AFrame.SmoothedTileMap[Y, sx];
    PrevTMI := @APrevFrame.SmoothedTileMap[Y, sx];

    // compare DCT of current tile with tile from prev frame tilemap

    PrevTile := FTiles[PrevTMI^.GlobalTileIndex]^;
    Tile_ := FTiles[TMI^.GlobalTileIndex]^;

    ComputeTilePsyVisFeatures(PrevTile, True, False, False, True, PrevTMI^.HMirror, PrevTMI^.VMirror, -1, APrevFrame.PKeyFrame.PaletteRGB[PrevTMI^.PalIdx], PrevTileDCT);
    ComputeTilePsyVisFeatures(Tile_, True, False, False, True, TMI^.HMirror, TMI^.VMirror, -1, AFrame.PKeyFrame.PaletteRGB[TMI^.PalIdx], TileDCT);

    cmp := CompareEuclideanDCT(TileDCT, PrevTileDCT);
    cmp := sqrt(cmp * cSqrtFactor);

    // if difference is low enough, mark the tile as smoothed for tilemap compression use

    if Abs(cmp) <= Strength then
    begin
      if TMI^.GlobalTileIndex >= PrevTMI^.GlobalTileIndex then // lower tile index means the tile is used more often
        TMI^ := PrevTMI^
      else
        PrevTMI^ := TMI^;

      TMI^.Smoothed := True;
    end
    else
    begin
      TMI^.Smoothed := False;
    end;
  end;
end;

function TMainForm.GetTileUseCount(ATileIndex: Integer): Integer;
var
  i, sx, sy: Integer;
begin
  Result := 0;
  for i := 0 to High(FFrames) do
    for sy := 0 to FTileMapHeight - 1 do
      for sx := 0 to FTileMapWidth - 1 do
        Inc(Result, Ord(FFrames[i].TileMap[sy, sx].GlobalTileIndex = ATileIndex));
end;

function TMainForm.GetTileZoneSum(const ATile: TTile; x, y, w, h: Integer): Integer;
var
  i, j: Integer;
begin
  Result := 0;
  for j := y to y + h - 1 do
    for i := x to x + w - 1 do
      Result += ATile.PalPixels[j, i];
end;

function TMainForm.GetTilePalZoneThres(const ATile: TTile; ZoneCount: Integer; Zones: PByte): Integer;
var
  i, x, y: Integer;
  b: Byte;
  signi: Boolean;
  acc: array[0..sqr(cTileWidth)-1] of Byte;
begin
  FillByte(acc[0], Length(acc), 0);
  for y := 0 to cTileWidth - 1 do
    for x := 0 to cTileWidth - 1 do
    begin
      b := ATile.PalPixels[y, x];
      Inc(acc[b * ZoneCount div FTilePaletteSize]);
    end;

  Result := sqr(cTileWidth);
  for i := 0 to ZoneCount - 1 do
  begin
    Result := Min(Result, sqr(cTileWidth) - acc[i]);
    signi := acc[i] > (FTilePaletteSize div ZoneCount);
    Zones^ := Ord(signi);
    Inc(Zones);
  end;
end;

function TMainForm.WriteTileDatasetLine(const ATile: TTile; DataLine: TByteDynArray; out PalSigni: Integer): Integer;
var
  x, y: Integer;
begin
  Result := 0;
  for y := 0 to cTileWidth - 1 do
    for x := 0 to cTileWidth - 1 do
    begin
      DataLine[Result] := ATile.PalPixels[y, x];
      Inc(Result);
    end;

  PalSigni := GetTilePalZoneThres(ATile, sqr(cTileWidth) div 4, @DataLine[Result]);
  Inc(Result, sqr(cTileWidth) div 4);

  Assert(Result = cKModesFeatureCount);
end;

type
  TKModesBin = record
    Dataset: TByteDynArray3;
    TileIndices: TIntegerDynArray2;
    StartingPoint: TIntegerDynArray;
    ClusterCount: TFloatDynArray;
  end;

  PKModesBin = ^TKModesBin;

procedure TMainForm.DoKModes(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
var
  KModes: TKModes;
  LocCentroids: TByteDynArray2;
  LocClusters: TIntegerDynArray;
  i, j, di, DSLen: Integer;
  ActualNbTiles: Integer;
  ToMergeIdxs: TIntegerDynArray;
  ToMerge: TByteDynArray2;
  KMBin: PKModesBin;
  dis: UInt64;
begin
  if not InRange(AIndex, 0, FPaletteCount - 1) then
    Exit;

  KMBin := PKModesBin(AData);

  DSLen := Length(KMBin^.Dataset[AIndex]);

  if DSLen <= KMBin^.ClusterCount[AIndex] then
    Exit;

  KModes := TKModes.Create(4, 0, False);
  try
    ActualNbTiles := KModes.ComputeKModes(KMBin^.Dataset[AIndex], round(KMBin^.ClusterCount[AIndex]), -KMBin^.StartingPoint[AIndex], FTilePaletteSize, LocClusters, LocCentroids);
    Assert(Length(LocCentroids) = ActualNbTiles);
    Assert(MaxIntValue(LocClusters) = ActualNbTiles - 1);
  finally
    KModes.Free;
  end;

  SetLength(ToMerge, DSLen);
  SetLength(ToMergeIdxs, DSLen);

  // build a list of this centroid tiles

  for j := 0 to round(KMBin^.ClusterCount[AIndex]) - 1 do
  begin
    di := 0;
    for i := 0 to High(KMBin^.TileIndices[AIndex]) do
    begin
      if LocClusters[i] = j then
      begin
        ToMerge[di] := KMBin^.Dataset[AIndex, i];
        ToMergeIdxs[di] := KMBin^.TileIndices[AIndex, i];
        Inc(di);
      end;
    end;

    // choose a tile from the centroids

    if di >= 2 then
    begin
      i := GetMinMatchingDissim(ToMerge, LocCentroids[j], di, dis);
      SpinEnter(@FLock);
      MergeTiles(ToMergeIdxs, di, ToMergeIdxs[i], nil, nil);
      SpinLeave(@FLock);
    end;
  end;
end;

procedure TMainForm.DoGlobalTiling(OutFN: String; DesiredNbTiles, RestartCount: Integer);
var
  fs: TFileStream;
  acc, i, j, disCnt, signi, ActiveTileCnt: Integer;
  dis: TIntegerDynArray;
  best: TIntegerDynArray;
  share: TFloat;
  Line: TByteDynArray;
  KMBin: TKModesBin;
begin
  SetLength(KMBin.TileIndices, FPaletteCount);
  SetLength(KMBin.StartingPoint, FPaletteCount);
  SetLength(KMBin.ClusterCount, FPaletteCount);
  SetLength(dis, FPaletteCount);
  SetLength(best, FPaletteCount);

  // prepare KModes dataset, one line per tile, 64 palette indexes per line plus 16 additional features
  // also choose KModes starting point

  SetLength(KMBin.Dataset, FPaletteCount, Length(FTiles) shr 4, cKModesFeatureCount);
  SetLength(Line, cKModesFeatureCount);

  for i := 0 to FPaletteCount - 1 do
    SetLength(KMBin.TileIndices[i], Length(FTiles));

  FillDWord(dis[0], FPaletteCount, 0);
  FillDWord(KMBin.StartingPoint[0], FPaletteCount, DWORD(-RestartCount));
  FillDWord(best[0], FPaletteCount, DWORD(MaxInt));
  ActiveTileCnt := GetGlobalTileCount;

  // bin tiles by PalSigni (highest number of pixels the same color from the tile)

  for i := 0 to High(FTiles) do
  begin
    if not FTiles[i]^.Active then
      Continue;

    WriteTileDatasetLine(FTiles[i]^, Line, j);

    signi :=FTiles[i]^.DitheringPalIndex;
    if dis[signi] >= Length(KMBin.Dataset[signi]) then
      SetLength(KMBin.Dataset[signi], ActiveTileCnt, cKModesFeatureCount);
    Move(Line[0], KMBin.Dataset[signi, dis[signi], 0], cKModesFeatureCount);
    KMBin.TileIndices[signi, dis[signi]] := i;

    acc := 0;
    for j := 0 to cKModesFeatureCount - 1 do
      acc += KMBin.Dataset[signi, dis[signi], j];
    if acc <= best[signi] then
    begin
      KMBin.StartingPoint[signi] := dis[signi];
      best[signi] := acc;
    end;

    Inc(dis[signi]);
  end;

  for i := 0 to FPaletteCount - 1 do
  begin
    SetLength(KMBin.Dataset[i], dis[i]);
    SetLength(KMBin.TileIndices[i], dis[i]);
  end;

  // share DesiredNbTiles among bins, proportional to amount of tiles

  FillQWord(KMBin.ClusterCount[0], FPaletteCount, 0);
  disCnt := 0;
  for i := 0 to FPaletteCount - 1 do
    disCnt += EqualQualityTileCount(dis[i]);
  share := DesiredNbTiles / disCnt;

  for i := 0 to FPaletteCount - 1 do
    KMBin.ClusterCount[i] := ceil(EqualQualityTileCount(dis[i]) * share);

  //for i := 0 to FPaletteCount - 1 do
  //  WriteLn('EntropyBin # ', i, #9'RawTiles: ', dis[i], #9'FinalTiles: ', round(KMBin.ClusterCount[i]));

  InitMergeTiles;

  ProgressRedraw(1);

  // run the KModes algorithm, which will group similar tiles until it reaches a fixed amount of groups

  ProcThreadPool.DoParallel(@DoKModes, 0, FPaletteCount - 1, @KMBin);

  ProgressRedraw(2);

  FinishMergeTiles;

  // ensure inter block tile unicity

  MakeTilesUnique(0, Length(FTiles));

  ProgressRedraw(3);

  // put most probable tiles first

  ReindexTiles;

  ProgressRedraw(4);

  // save raw tiles

  fs := TFileStream.Create(OutFN, fmCreate or fmShareDenyWrite);
  try
    fs.WriteByte(FTilePaletteSize);
    for i := 0 to High(FTiles) do
      if FTiles[i]^.Active then
        fs.Write(FTiles[i]^.PalPixels[0, 0], sqr(cTileWidth));
  finally
    fs.Free;
  end;

  ProgressRedraw(5);
end;

procedure TMainForm.ReloadPreviousTiling(AFN: String);
var
  SigniDataset: TByteDynArray3;
  Dataset: TByteDynArray2;

  procedure DoFindBest(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
  var
    last, bin, signi, i, tidx: Integer;
    DataLine: TByteDynArray;
    dis: UInt64;
  begin
    SetLength(DataLine, cKModesFeatureCount);

    bin := Length(FTiles) div PtrUInt(AData);
    last := (AIndex + 1) * bin - 1;
    if AIndex >= PtrUInt(AData) - 1 then
      last := High(FTiles);

    for i := bin * AIndex to last do
    begin
      if FTiles[i]^.Active then
      begin
        WriteTileDatasetLine(FTiles[i]^, DataLine, signi);
        if Length(SigniDataset[signi]) > 0 then
        begin
          tidx := GetMinMatchingDissim(SigniDataset[signi], DataLine, Length(SigniDataset[signi]), dis);
          Move(SigniDataset[signi, tidx, 0], FTiles[i]^.PalPixels[0, 0], sqr(cTileWidth));
        end
        else
        begin
          tidx := GetMinMatchingDissim(Dataset, DataLine, Length(Dataset), dis);
          Move(Dataset[tidx, 0], FTiles[i]^.PalPixels[0, 0], sqr(cTileWidth));
        end;
      end;

      if i mod 10000 = 0 then
        WriteLn('Thread: ', GetCurrentThreadId, #9'TileIdx: ', i);
    end;
  end;

var
  signi, i, y, x: Integer;
  fs: TFileStream;
  T: TTile;
  cnt: PtrUInt;
  SigniIndices: TIntegerDynArray2;
  TilingPaletteSize: Integer;
begin
  fs := TFileStream.Create(AFN, fmOpenRead or fmShareDenyNone);
  try
    FillChar(T, SizeOf(T), 0);
    T.Active := True;

    SetLength(SigniIndices, High(Word) + 1, 0);
    SetLength(Dataset, fs.Size div sqr(cTileWidth), cKModesFeatureCount);

    TilingPaletteSize := sqr(cTileWidth);
    if fs.Size mod sqr(cTileWidth) <> 0 then
      TilingPaletteSize := fs.ReadByte;

    for i := 0 to High(Dataset) do
    begin
      fs.ReadBuffer(T.PalPixels[0, 0], SizeOf(TPalPixels));

      for y := 0 to cTileWidth - 1 do
        for x := 0 to cTileWidth - 1 do
          T.PalPixels[y, x] := (T.PalPixels[y, x] * FTilePaletteSize) div TilingPaletteSize;

      WriteTileDatasetLine(T, Dataset[i], signi);

      SetLength(SigniIndices[signi], Length(SigniIndices[signi]) + 1);
      SigniIndices[signi][High(SigniIndices[signi])] := i;
    end;

    SetLength(SigniDataset, High(Word) + 1, 0);
    for signi := 0 to High(Word) do
      if Length(SigniIndices[signi]) > 0 then
      begin
        SetLength(SigniDataset[signi], Length(SigniIndices[signi]));
        for i := 0 to High(SigniIndices[signi]) do
          SigniDataset[signi, i] := Dataset[SigniIndices[signi, i]];
      end;

    SetLength(SigniIndices, 0);

    ProgressRedraw(1);

    cnt := ProcThreadPool.MaxThreadCount * 10;
    ProcThreadPool.DoParallelLocalProc(@DoFindBest, 0, cnt - 1, Pointer(cnt));

    ProgressRedraw(4);

    MakeTilesUnique(0, Length(FTiles));

    ProgressRedraw(5);
  finally
    fs.Free;
  end;
end;

function CompareTileUseCountRev(Item1, Item2, UserParameter:Pointer):Integer;
var
  t1, t2: PTile;
begin
  t1 := PPTile(Item1)^;
  t2 := PPTile(Item2)^;
  Result := CompareValue(t2^.UseCount, t1^.UseCount);
  if Result = 0 then
    Result := CompareValue(t1^.TmpIndex, t2^.TmpIndex);
end;

procedure TMainForm.ReindexTiles;
var
  i, j, x, y, cnt: Integer;
  IdxMap: TIntegerDynArray;
begin
  cnt := 0;
  for i := 0 to High(FTiles) do
  begin
    FTiles[i]^.TmpIndex := i;
    if FTiles[i]^.Active then
      Inc(cnt);
  end;

  // pack the global tiles, removing inactive ones

  j := 0;
  for i := 0 to High(FTiles) do
    if not FTiles[i]^.Active then
    begin
      Dispose(FTiles[i])
    end
    else
    begin
      FTiles[j] := FTiles[i];
      Inc(j);
    end;

  SetLength(IdxMap, Length(FTiles));
  FillDWord(IdxMap[0], Length(FTiles), $ffffffff);

  // sort global tiles by use count descending (to make smoothing work better) then by tile index (to make tile indexes compression work better)

  SetLength(FTiles, cnt);
  QuickSort(FTiles[0], 0, High(FTiles), SizeOf(PTile), @CompareTileUseCountRev);

  // point tilemap items on new tiles indexes

  for i := 0 to High(FTiles) do
    IdxMap[FTiles[i]^.TmpIndex] := i;

  for i := 0 to High(FFrames) do
    for y := 0 to (FTileMapHeight - 1) do
      for x := 0 to (FTileMapWidth - 1) do
        FFrames[i].TileMap[y,x].GlobalTileIndex := IdxMap[FFrames[i].TileMap[y,x].GlobalTileIndex];
end;

procedure TMainForm.SaveStream(AStream: TStream);
const
  CGTMCommandsCount = Ord(High(TGTMCommand)) + 1;
  CGTMCommandsBits = round(ln(CGTMCommandsCount) / ln(2));
  CGTMAttributeBits = 16 - CGTMCommandsBits;
  CMinBlkSkipCount = 1;
  CMaxBlkSkipCount = 1 shl CGTMAttributeBits;

var
  ZStream: TMemoryStream;

  procedure DoDWord(v: Cardinal);
  begin
    ZStream.WriteDWord(v);
  end;

  procedure Do3Bytes(v: Cardinal);
  begin
    Assert(v < 1 shl 24);
    ZStream.WriteByte(v and $ff);
    v := v shr 8;
    ZStream.WriteByte(v and $ff);
    v := v shr 8;
    ZStream.WriteByte(v and $ff);
  end;

  procedure DoWord(v: Word);
  begin
    ZStream.WriteWord(v);
  end;

  procedure DoByte(v: Byte);
  begin
    ZStream.WriteByte(v);
  end;

  procedure DoCmd(Cmd: TGTMCommand; Data: Cardinal);
  begin
    assert(Data < (1 shl CGTMAttributeBits));
    assert(Ord(Cmd) < CGTMCommandsCount);

    DoWord((Data shl CGTMCommandsBits) or Ord(Cmd));
  end;

  procedure DoTMI(PalIdx: Integer; TileIdx: Integer; VMirror, HMirror: Boolean);
  begin
    Assert((PalIdx >= 0) and (PalIdx < FPaletteCount));

    if TileIdx < (1 shl 16) then
    begin
      DoCmd(gtShortTileIdx, (PalIdx shl 2) or (Ord(VMirror) shl 1) or Ord(HMirror));
      DoWord(TileIdx);
    end
    else
    begin
      DoCmd(gtLongTileIdx, (PalIdx shl 2) or (Ord(VMirror) shl 1) or Ord(HMirror));
      DoDWord(TileIdx);
    end;
  end;

  procedure WriteKFAttributes(KF: TKeyFrame);
  var
    i, j: Integer;
  begin
    for j := 0 to FPaletteCount - 1 do
    begin
      DoCmd(gtLoadPalette, 0);
      DoByte(j);
      DoByte(0);
      for i := 0 to FTilePaletteSize - 1 do
        DoDWord(KF.PaletteRGB[j, i] or $ff000000);
    end;
  end;

  procedure WriteTiles;
  var
    i, TileCnt: Integer;
  begin
    TileCnt := GetGlobalTileCount;

    DoCmd(gtSetDimensions, 0);
    DoWord(FTileMapWidth); // frame tilemap width
    DoWord(FTileMapHeight); // frame tilemap height
    DoDWord(round(1000*1000*1000 / FFramesPerSecond)); // frame length in nanoseconds
    DoDWord(TileCnt); // tile count

    DoCmd(gtTileSet, FTilePaletteSize);
    DoDWord(0); // start tile
    DoDWord(TileCnt - 1); // end tile

    for i := 0 to High(FTiles) do
      if FTiles[i]^.Active then
        ZStream.Write(FTiles[i]^.PalPixels[0, 0], sqr(cTileWidth));
  end;

var
  StartPos, StreamSize, LastKF, KFCount, KFSize, kf, fri, yx, yxs, cs, BlkSkipCount: Integer;
  IsKF: Boolean;
  frm: TFrame;
  tmi: PTileMapItem;
  Header: TGTMHeader;
  KFInfo: array of TGTMKeyFrameInfo;
begin
  StartPos := AStream.Size;

  FillChar(Header, SizeOf(Header), 0);
  Header.FourCC := 'GTMv';
  Header.RIFFSize := SizeOf(Header) - SizeOf(Header.FourCC) - SizeOf(Header.RIFFSize);
  Header.EncoderVersion := 1;
  Header.FramePixelWidth := FScreenWidth;
  Header.FramePixelHeight := FScreenHeight;
  Header.KFCount := Length(FKeyFrames);
  Header.FrameCount := Length(FFrames);
  Header.AverageBytesPerSec := 0;
  Header.KFMaxBytesPerSec := 0;
  AStream.WriteBuffer(Header, SizeOf(Header));

  SetLength(KFInfo, Length(FKeyFrames));
  for kf := 0 to High(FKeyFrames) do
  begin
    FillChar(KFInfo[kf], SizeOf(KFInfo[0]), 0);
    KFInfo[kf].FourCC := 'GTMk';
    KFInfo[kf].RIFFSize := SizeOf(KFInfo[0]) - SizeOf(KFInfo[0].FourCC) - SizeOf(KFInfo[0].RIFFSize);
    KFInfo[kf].KFIndex := kf;
    KFInfo[kf].FrameIndex := FKeyFrames[kf].StartFrame;
    KFInfo[kf].TimeCodeMillisecond := Round(1000.0 * FKeyFrames[kf].StartFrame / FFramesPerSecond);
    AStream.WriteBuffer(KFInfo[kf], SizeOf(KFInfo[0]));
  end;

  Header.WholeHeaderSize := AStream.Size - StartPos;

  StartPos := AStream.Size;

  ZStream := TMemoryStream.Create;
  try
    WriteTiles;

    LastKF := 0;
    for kf := 0 to High(FKeyFrames) do
    begin
      WriteKFAttributes(FKeyFrames[kf]);

      for fri := FKeyFrames[kf].StartFrame to FKeyFrames[kf].EndFrame do
      begin
        frm := FFrames[fri];

        cs := 0;
        BlkSkipCount := 0;
        for yx := 0 to FTileMapSize - 1 do
        begin
          if BlkSkipCount > 0 then
          begin
            // handle an ongoing block skip

            Dec(BlkSkipCount);
          end
          else
          begin
            // find a potential new skip

            BlkSkipCount := 0;
            for yxs := yx to FTileMapSize - 1 do
            begin
              if not frm.SmoothedTileMap[yxs div FTileMapWidth, yxs mod FTileMapWidth].Smoothed then
                Break;
              Inc(BlkSkipCount);
            end;
            BlkSkipCount := min(CMaxBlkSkipCount, BlkSkipCount);

            // filter using heuristics to avoid unbeneficial skips

            if BlkSkipCount >= CMinBlkSkipCount then
            begin
              //writeln('blk ', BlkSkipCount);

              DoCmd(gtSkipBlock, BlkSkipCount - 1);
              Inc(cs, BlkSkipCount);
              Dec(BlkSkipCount);
            end
            else
            begin
              // standard case: emit tilemap item

              BlkSkipCount := 0;

              tmi := @frm.SmoothedTileMap[yx div FTileMapWidth, yx mod FTileMapWidth];
              DoTMI(tmi^.PalIdx, tmi^.GlobalTileIndex, tmi^.VMirror xor FTiles[tmi^.GlobalTileIndex]^.VMirror, tmi^.HMirror xor FTiles[tmi^.GlobalTileIndex]^.HMirror);
              Inc(cs);
            end;
          end;
        end;
        Assert(cs = FTileMapSize, 'incomplete TM');
        Assert(BlkSkipCount = 0, 'pending skips');

        IsKF := (fri = FKeyFrames[kf].EndFrame);

        DoCmd(gtFrameEnd, Ord(IsKF));

        if IsKF then
        begin
          KFCount := FKeyFrames[kf].EndFrame - LastKF + 1;
          LastKF := FKeyFrames[kf].EndFrame + 1;

          AStream.Position := AStream.Size;
          KFSize := AStream.Position;
          LZCompress(ZStream, False, AStream);
          ZStream.Clear;

          KFSize := AStream.Size - KFSize;

          KFInfo[kf].RawSize := ZStream.Size;
          KFInfo[kf].CompressedSize := KFSize;
          if (kf > 0) or (Length(FKeyFrames) = 1) then
            Header.KFMaxBytesPerSec := max(Header.KFMaxBytesPerSec, round(KFSize * FFramesPerSecond / KFCount));
          Header.AverageBytesPerSec += KFSize;

          WriteLn('Frame: ', FKeyFrames[kf].StartFrame, #9'FCnt: ', KFCount, #9'Written: ', KFSize, #9'Bitrate: ', FormatFloat('0.00', KFSize / 1024.0 * 8.0 / KFCount) + ' kbpf  '#9'(' + FormatFloat('0.00', KFSize / 1024.0 * 8.0 / KFCount * FFramesPerSecond)+' kbps)');
        end;
      end;
    end;
  finally
    ZStream.Free;
  end;

  Header.AverageBytesPerSec := round(Header.AverageBytesPerSec * FFramesPerSecond / Length(FFrames));
  AStream.Position := 0;
  AStream.WriteBuffer(Header, SizeOf(Header));
  for kf := 0 to High(FKeyFrames) do
    AStream.WriteBuffer(KFInfo[kf], SizeOf(KFInfo[0]));
  AStream.Position := AStream.Size;

  StreamSize := AStream.Size - StartPos;

  WriteLn('Written: ', StreamSize, #9'Bitrate: ', FormatFloat('0.00', StreamSize / 1024.0 * 8.0 / Length(FFrames)) + ' kbpf  '#9'(' + FormatFloat('0.00', StreamSize / 1024.0 * 8.0 / Length(FFrames) * FFramesPerSecond)+' kbps)');
end;

function TMainForm.DoExternalFFMpeg(AFN: String; var AVidPath: String; AStartFrame, AFrameCount: Integer; AScale: Double; out AFPS: Double): String;
var
  i: Integer;
  Output, ErrOut, vfl, s: String;
  Process: TProcess;
begin
  Process := TProcess.Create(nil);

  Result := IncludeTrailingPathDelimiter(sysutils.GetTempDir) + 'tiler_png\';
  ForceDirectories(Result);

  DeleteDirectory(Result, True);

  AVidPath := Result + '%.4d.png';

  vfl := ' -vf select="between(n\,' + IntToStr(AStartFrame) + '\,' +
    IntToStr(IfThen(AFrameCount > 0, AStartFrame + AFrameCount - 1, MaxInt)) +
    '),setpts=PTS-STARTPTS,scale=in_range=auto:out_range=full",scale=iw*' + FloatToStr(AScale, InvariantFormatSettings) + ':ih*' + FloatToStr(AScale, InvariantFormatSettings) + ':flags=lanczos ';

  Process.CurrentDirectory := ExtractFilePath(ParamStr(0));
  Process.Executable := 'ffmpeg.exe';
  Process.Parameters.Add('-y -i "' + AFN + '" ' + vfl + ' -compression_level 0 -pix_fmt rgb24 "' + Result + '%04d.png' + '"');
  Process.ShowWindow := swoHIDE;
  Process.Priority := ppIdle;

  i := 0;
  internalRuncommand(Process, Output, ErrOut, i, True); // destroys Process
  WriteLn;

  s := ErrOut;
  s := Copy(s, 1, Pos(' fps', s) - 1);
  s := ReverseString(s);
  s := Copy(s, 1, Pos(' ', s) - 1);
  s := ReverseString(s);
  AFPS := StrToFloatDef(s, 24.0, InvariantFormatSettings);
end;

procedure TMainForm.FormCreate(Sender: TObject);
var
  col, i, sr: Integer;
  es: TEncoderStep;
begin
  FormatSettings.DecimalSeparator := '.';
  InitializeCriticalSection(FCS);
  SpinLeave(@FLock);

{$ifdef DEBUG}
  //ProcThreadPool.MaxThreadCount := 1;
{$else}
  SetPriorityClass(GetCurrentProcess(), IDLE_PRIORITY_CLASS);
{$endif}

  Constraints.MinHeight := Height;
  Constraints.MinWidth := Width;
  pcPages.ActivePage := tsSettings;
  ReframeUI(80, 45);
  FFramesPerSecond := 24.0;

  cbxYilMixChange(nil);
  chkUseTKChange(nil);
  chkLowMemChange(nil);

  for es := Succ(Low(TEncoderStep)) to High(TEncoderStep) do
  begin
    cbxStartStep.AddItem(Copy(GetEnumName(TypeInfo(TEncoderStep), Ord(es)), 3), TObject(PtrInt(Ord(es))));
    cbxEndStep.AddItem(Copy(GetEnumName(TypeInfo(TEncoderStep), Ord(es)), 3), TObject(PtrInt(Ord(es))));
  end;
  cbxStartStep.ItemIndex := Ord(Succ(Low(TEncoderStep)));
  cbxEndStep.ItemIndex := Ord(High(TEncoderStep));

  sr := (1 shl cRGBBitsPerComp) - 1;

  for i := 0 to cRGBColors - 1 do
  begin
    col :=
       ((((i shr (cRGBBitsPerComp * 0)) and sr) * 255 div sr) and $ff) or //R
      (((((i shr (cRGBBitsPerComp * 1)) and sr) * 255 div sr) and $ff) shl 8) or //G
      (((((i shr (cRGBBitsPerComp * 2)) and sr) * 255 div sr) and $ff) shl 16);  //B

    FromRGB(col, FColorMap[i, 0], FColorMap[i, 1], FColorMap[i, 2]);
    RGBToHSV(col, FColorMap[i, 3], FColorMap[i, 4], FColorMap[i, 5]);
    FColorMapLuma[i] := (FColorMap[i, 0] * cRedMul + FColorMap[i, 1] * cGreenMul + FColorMap[i, 2] * cBlueMul) div cLumaDiv;
  end;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  DeleteCriticalSection(FCS);

  ClearAll;
end;

end.

