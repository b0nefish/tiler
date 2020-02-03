unit main;

{$mode objfpc}{$H+}

{$define ASM_DBMP}

interface

uses
  LazLogger, Classes, SysUtils, windows, FileUtil, Forms, Controls, Graphics, Dialogs, ExtCtrls,
  StdCtrls, ComCtrls, Spin, Menus, Math, types, Process, strutils, kmodes, MTProcs, correlation, extern, typinfo;

type
  TEncoderStep = (esNone = -1, esLoad = 0, esDither, esMakeUnique, esGlobalTiling, esFrameTiling, esReindex, esSmooth, esSave);

const
  cPhi = (1 + sqrt(5)) / 2;
  cInvPhi = 1 / cPhi;

  // Tweakable params
  cRandomKModesCount = 7;
  cKeyframeFixedColors = 4;
  cGamma: array[0..1] of TFloat = (2.0, 0.9);
  cInvertSpritePalette = False;
  cGammaCorrectSmoothing = -1;
  cKFFromPal = False;
  cKFGamma = 0;
  cKFQWeighting = False;

  cRedMultiplier = 299;
  cGreenMultiplier = 587;
  cBlueMultiplier = 114;
  cLumaMultiplier = cRedMultiplier + cGreenMultiplier + cBlueMultiplier;
  cRGBw = 13; // in 1 / 32th

  // SMS consts
  cVecInvWidth = 16;
  cBitsPerComp = 2;
  cTotalColors = 1 shl (cBitsPerComp * 3);
  cTileWidth = 8;
  cPaletteCount = 2;
  cTilePaletteSize = 16;
  cTileMapWidth = 32;
  cTileMapHeight = 24;
  cTileMapSize = cTileMapWidth * cTileMapHeight;
  cScreenWidth = cTileMapWidth * cTileWidth;
  cScreenHeight = cTileMapHeight * cTileWidth;
  cBankSize = 16384;
  cTileSize = cTileWidth * cTileWidth div 2;
  cTilesPerBank = cBankSize div cTileSize;
  cZ80Clock = 3546893;
  cLineCount = 313;
  cRefreshRate = 50;
  cCyclesPerLine = cZ80Clock / (cLineCount * cRefreshRate);
  cCyclesPerDisplayPhase : array[Boolean{VBlank?}] of Integer = (
    Round(cScreenHeight * cCyclesPerLine),
    Round((cLineCount - cScreenHeight) * cCyclesPerLine)
  );

  // Video player consts
  cMaxTilesPerFrame = 207;
  cSmoothingPrevFrame = 2;
  cTileIndexesTileOffset = cTilesPerBank + 1;
  cTileIndexesMaxDiff = 223;
  cTileIndexesRepeatStart = 224;
  cTileIndexesMaxRepeat = 30;
  cTileIndexesDirectValue = 223;
  cTileIndexesTerminator = 254;
  cTileIndexesVBlankSwitch = 255;
  cTileMapIndicesOffset : array[0..1] of Integer = (49, 256 + 49);
  cTileMapCacheBits = 5;
  cTileMapCacheSize = 1 shl cTileMapCacheBits;
  cTileMapMaxRepeat : array[Boolean{Raw?}] of Integer = (6, 4);
  cTileMapMaxSkip = 31;
  cTileMapCommandCache : array[1..6{Rpt}] of Byte = ($01, $40, $41, $80, $81, $c0);
  cTileMapCommandSkip = $00;
  cTileMapCommandRaw : array[1..4{Rpt}] of Byte = ($c1, $d1, $e1, $f1);
  cTileMapTerminator = $00; // skip 0
  cClocksPerSample = 344;
  cFrameSoundSize = cZ80Clock / cClocksPerSample / 2 / (cRefreshRate / 4);

  // number of Z80 cycles to execute a function
  cTileIndexesTimings : array[Boolean{VBlank?}, 0..4 {Direct/Std/RptFix/RptVar/VBlankSwitch}] of Integer = (
    (343 + 688, 289 + 17 + 688, 91 + 5, 213 + 12 + 688, 113 + 7),
    (347 + 344, 309 + 18 + 344, 91 + 5, 233 + 14 + 344, 113 + 7)
  );
  cLineJitterCompensation = 4;
  cTileIndexesInitialLine = 201; // algo starts in VBlank

  cColorCpns = 3;
  cTileDCTSize = cColorCpns * sqr(cTileWidth);

  cQ = 16.0;
  cDCTQuantization: array[0..cColorCpns-1{YUV}, 0..7, 0..7] of TFloat = (
    (
      // Luma
      (cQ / 10, cQ / 11, cQ / 12, cQ / 15, cQ /  21, cQ /  32, cQ /  50, cQ /  66),
      (cQ / 11, cQ / 12, cQ / 13, cQ / 18, cQ /  24, cQ /  46, cQ /  62, cQ /  73),
      (cQ / 12, cQ / 13, cQ / 16, cQ / 23, cQ /  38, cQ /  56, cQ /  73, cQ /  75),
      (cQ / 15, cQ / 18, cQ / 23, cQ / 29, cQ /  53, cQ /  75, cQ /  83, cQ /  80),
      (cQ / 21, cQ / 24, cQ / 38, cQ / 53, cQ /  68, cQ /  95, cQ / 103, cQ /  94),
      (cQ / 32, cQ / 46, cQ / 56, cQ / 75, cQ /  95, cQ / 104, cQ / 117, cQ /  96),
      (cQ / 50, cQ / 62, cQ / 73, cQ / 83, cQ / 103, cQ / 117, cQ / 120, cQ / 128),
      (cQ / 66, cQ / 73, cQ / 75, cQ / 80, cQ /  94, cQ /  96, cQ / 128, cQ / 144)
    ),
    (
      // U, weighted by luma importance
      (cQ / 17, cQ /  18, cQ /  24, cQ /  47, cQ /  99, cQ /  99, cQ /  99, cQ /  99),
      (cQ / 18, cQ /  21, cQ /  26, cQ /  66, cQ /  99, cQ /  99, cQ /  99, cQ / 112),
      (cQ / 24, cQ /  26, cQ /  56, cQ /  99, cQ /  99, cQ /  99, cQ / 112, cQ / 128),
      (cQ / 47, cQ /  66, cQ /  99, cQ /  99, cQ /  99, cQ / 112, cQ / 128, cQ / 144),
      (cQ / 99, cQ /  99, cQ /  99, cQ /  99, cQ / 112, cQ / 128, cQ / 144, cQ / 160),
      (cQ / 99, cQ /  99, cQ /  99, cQ / 112, cQ / 128, cQ / 144, cQ / 160, cQ / 176),
      (cQ / 99, cQ /  99, cQ / 112, cQ / 128, cQ / 144, cQ / 160, cQ / 176, cQ / 192),
      (cQ / 99, cQ / 112, cQ / 128, cQ / 144, cQ / 160, cQ / 176, cQ / 192, cQ / 208)
    ),
    (
      // V, weighted by luma importance
      (cQ / 17, cQ /  18, cQ /  24, cQ /  47, cQ /  99, cQ /  99, cQ /  99, cQ /  99),
      (cQ / 18, cQ /  21, cQ /  26, cQ /  66, cQ /  99, cQ /  99, cQ /  99, cQ / 112),
      (cQ / 24, cQ /  26, cQ /  56, cQ /  99, cQ /  99, cQ /  99, cQ / 112, cQ / 128),
      (cQ / 47, cQ /  66, cQ /  99, cQ /  99, cQ /  99, cQ / 112, cQ / 128, cQ / 144),
      (cQ / 99, cQ /  99, cQ /  99, cQ /  99, cQ / 112, cQ / 128, cQ / 144, cQ / 160),
      (cQ / 99, cQ /  99, cQ /  99, cQ / 112, cQ / 128, cQ / 144, cQ / 160, cQ / 176),
      (cQ / 99, cQ /  99, cQ / 112, cQ / 128, cQ / 144, cQ / 160, cQ / 176, cQ / 192),
      (cQ / 99, cQ / 112, cQ / 128, cQ / 144, cQ / 160, cQ / 176, cQ / 192, cQ / 208)
    )
  );

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

  cEncoderStepLen: array[TEncoderStep] of Integer = (0, 2, 3, 1, 5, 1, 3, 1, 2);

type
  TSpinlock = LongInt;
  PSpinLock = ^TSpinlock;

  TFloatFloatFunction = function(x: TFloat; Data: Pointer): TFloat of object;

  PTile = ^TTile;
  PPTile = ^PTile;

  TPalPixels = array[0..(cTileWidth - 1),0..(cTileWidth - 1)] of Byte;
  TRGBPixels = array[0..(cTileWidth - 1),0..(cTileWidth - 1)] of Integer;
  PPalPixels = ^TPalPixels;

  TTile = record
    RGBPixels: TRGBPixels;
    PalPixels: TPalPixels;

    PaletteIndexes: TIntegerDynArray;
    PaletteRGB: TIntegerDynArray;

    Active: Boolean;
    UseCount, TmpIndex, MergeIndex: Integer;
  end;

  PTileMapItem = ^TTileMapItem;

  TTileMapItem = record
    GlobalTileIndex, FrameTileIndex, TmpIndex: Integer;
    HMirror,VMirror,SpritePal,Smoothed: Boolean;
  end;

  TTileMapItems = array of TTileMapItem;

  PKeyFrame = ^TKeyFrame;

  TFrame = record
    Index: Integer;
    Tiles: array[0..(cTileMapSize - 1)] of TTile;
    TilesIndexes: array of Integer;
    TileMap: array[0..(cTileMapHeight - 1),0..(cTileMapWidth - 1)] of TTileMapItem;
    FSPixels: TByteDynArray;
    KeyFrame: PKeyFrame;
  end;

  PFrame = ^TFrame;

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

  TKeyFrame = record
    PaletteIndexes: array[Boolean{SpritePal?}] of TIntegerDynArray;
    PaletteRGB: array[Boolean{SpritePal?}] of TIntegerDynArray;
    StartFrame, EndFrame, FrameCount: Integer;
    MixingPlans: array[0 .. cPaletteCount - 1] of TMixingPlan;
    FramesLeft: Integer;
  end;

  PFrameTilingData = ^TFrameTilingData;

  TFrameTilingData = record
    OutputTMIs: array of TTileMapItem;
    KF: PKeyFrame;
    KFFrmIdx: Integer;
    Iteration, DesiredNbTiles: Integer;

    Dataset: TFloatDynArray2;
    FrameDataset: TFloatDynArray2;
    DsTMItem: array of TTileMapItem;
    TileBestDissim: TUInt64DynArray;
    TileUseCount: TIntegerDynArray;
    MaxDissim: UInt64;
  end;

  { TMainForm }

  TMainForm = class(TForm)
    btnRunAll: TButton;
    btnDebug: TButton;
    cbxYilMix: TComboBox;
    chkGamma: TCheckBox;
    chkReduced: TCheckBox;
    chkSprite: TCheckBox;
    chkMirrored: TCheckBox;
    chkDithered: TCheckBox;
    chkPlay: TCheckBox;
    chkUseTK: TCheckBox;
    chkExtFT: TCheckBox;
    edInput: TEdit;
    edOutputDir: TEdit;
    edWAV: TEdit;
    imgPalette: TImage;
    Label1: TLabel;
    Label10: TLabel;
    Label11: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    Label5: TLabel;
    lblCorrel: TLabel;
    lblPct: TLabel;
    Label6: TLabel;
    Label7: TLabel;
    Label9: TLabel;
    lblTileCount: TLabel;
    MenuItem2: TMenuItem;
    MenuItem3: TMenuItem;
    MenuItem4: TMenuItem;
    MenuItem5: TMenuItem;
    MenuItem6: TMenuItem;
    miLoad: TMenuItem;
    MenuItem1: TMenuItem;
    pmProcesses: TPopupMenu;
    PopupMenu1: TPopupMenu;
    pbProgress: TProgressBar;
    seAvgTPF: TSpinEdit;
    seMaxTiles: TSpinEdit;
    seTempoSmoo: TSpinEdit;
    seMaxTPF: TSpinEdit;
    sePage: TSpinEdit;
    IdleTimer: TIdleTimer;
    imgTiles: TImage;
    imgSource: TImage;
    imgDest: TImage;
    seFrameCount: TSpinEdit;
    tbFrame: TTrackBar;

    procedure chkExtFTChange(Sender: TObject);
    procedure chkUseTKChange(Sender: TObject);
    function testGR(x: TFloat; Data: Pointer): TFloat;

    procedure btnLoadClick(Sender: TObject);
    procedure btnDitherClick(Sender: TObject);
    procedure btnDoGlobalTilingClick(Sender: TObject);
    procedure btnDoKeyFrameTilingClick(Sender: TObject);
    procedure btnReindexClick(Sender: TObject);
    procedure btnSmoothClick(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);

    procedure btnRunAllClick(Sender: TObject);
    procedure btnDebugClick(Sender: TObject);
    procedure cbxYilMixChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure IdleTimerTimer(Sender: TObject);
    procedure seAvgTPFEditingDone(Sender: TObject);
    procedure seMaxTilesEditingDone(Sender: TObject);
    procedure tbFrameChange(Sender: TObject);
  private
    FKeyFrames: array of PKeyFrame;
    FFrames: array of TFrame;
    FColorMap: array[0..cTotalColors - 1] of Integer;
    FColorMapLuma: array[0..cTotalColors - 1] of Integer;
    FColorMapHue: array[0..cTotalColors - 1] of Integer;
    FColorMapImportance: array[0..cTotalColors - 1] of Integer;
    FTiles: array of PTile;

    FUseThomasKnoll: Boolean;
    FExtendedFrmTiling: Boolean;
    FY2MixedColors: Integer;
    FLowMem: Boolean;

    FProgressStep: TEncoderStep;
    FProgressPosition, FOldProgressPosition, FProgressStartTime, FProgressPrevTime: Integer;

    FCS: TRTLCriticalSection;

    function ComputeCorrelation(const a, b: TIntegerDynArray): TFloat;
    function ComputeInterFrameCorrelation(a, b: PFrame): TFloat;
    procedure DitherFloydSteinberg(var AScreen: TByteDynArray);
    procedure DoFinal(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
    procedure DoFindBest(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
    procedure DoPre(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);

    procedure LoadFrame(AFrame: PFrame; ABitmap: TBitmap);
    procedure ProgressRedraw(CurFrameIdx: Integer = -1; ProgressStep: TEncoderStep = esNone);
    procedure Render(AFrameIndex: Integer; dithered, mirrored, reduced, gamma: Boolean; spritePal: Integer; ATilePage: Integer);

    procedure RGBToYUV(col: Integer; GammaCor: Integer; out y, u, v: TFloat);

    procedure ComputeTileDCT(const ATile: TTile; FromPal, QWeighting, HMirror, VMirror: Boolean; GammaCor: Integer;
      const pal: TIntegerDynArray; var DCT: TFloatDynArray); inline;

    // Dithering algorithms ported from http://bisqwit.iki.fi/story/howto/dither/jy/

    function ColorCompare(r1, g1, b1, r2, g2, b2: Int64): Int64;
    function ColorCompareTK(r1, g1, b1, r2, g2, b2: Int64): Int64;
    procedure PreparePlan(var Plan: TMixingPlan; MixedColors: Integer; const pal: array of Integer);
    procedure TerminatePlan(var Plan: TMixingPlan);
    function DeviseBestMixingPlan(var Plan: TMixingPlan; col: Integer; const List: TByteDynArray): Integer;
    procedure DeviseBestMixingPlanThomasKnoll(var Plan: TMixingPlan; col: Integer; var List: TByteDynArray);
    procedure DitherTileFloydSteinberg(ATile: TTile; out RGBPixels: TRGBPixels);

    procedure LoadTiles;
    function GetGlobalTileCount: Integer;
    function GetFrameTileCount(AFrame: PFrame): Integer;
    procedure CopyTile(const Src: TTile; var Dest: TTile);

    procedure DitherTile(var ATile: TTile; var Plan: TMixingPlan);
    procedure PreDitherTiles(AFrame: PFrame);
    procedure FindBestKeyframePalette(AKeyFrame: PKeyFrame);
    procedure FinalDitherTiles(AFrame: PFrame);

    function GetTilePalZoneThres(const ATile: TTile; ZoneCount: Integer; Zones: PByte): Integer;

    procedure MergeTiles(const TileIndexes: array of Integer; TileCount: Integer; BestIdx: Integer; NewTile: PPalPixels);
    procedure InitMergeTiles;
    procedure FinishMergeTiles;

    function WriteTileDatasetLine(const ATile: TTile; DataLine: TByteDynArray; out PalSigni: Integer): Integer;
    procedure DoGlobalTiling(DesiredNbTiles, RestartCount: Integer);

    function GoldenRatioSearch(Func: TFloatFloatFunction; Mini, Maxi: TFloat; ObjectiveY: TFloat = 0.0; Epsilon: TFloat = 1e-12; Data: Pointer = nil): TFloat;
    procedure HMirrorPalTile(var ATile: TTile);
    procedure VMirrorPalTile(var ATile: TTile);
    function GetMaxTPF(AKF: PKeyFrame): Integer;
    function TestTMICount(PassX: TFloat; Data: Pointer): TFloat;
    procedure DoKeyFrameTiling(AFTD: PFrameTilingData);
    procedure DoFrameTiling(AKF: PKeyFrame; DesiredNbTiles: Integer);

    function GetTileUseCount(ATileIndex: Integer): Integer;
    procedure ReindexTiles;
    procedure IndexFrameTiles(AFrame: PFrame);
    procedure DoTemporalSmoothing(AFrame, APrevFrame: PFrame; Y: Integer; Strength: TFloat);

    function DoExternalPCMEnc(AFN: String; Volume: Integer): String;

    procedure SaveTileIndexes(ADataStream: TStream; AFrame: PFrame);
    procedure SaveTilemap(ADataStream: TStream; AFrame: PFrame; AFrameIdx: Integer; ASkipFirst: Boolean);

    procedure Save(ADataStream, ASoundStream: TStream);

    procedure ClearAll;
  public
    { public declarations }
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

var
  gGammaCorLut: array[-1..High(cGamma), 0..High(Byte)] of TFloat;
  gVecInv: array[0..256 * 4 - 1] of Cardinal;
  gDCTLut:array[0..sqr(sqr(cTileWidth)) - 1] of TFloat;
  gPalettePattern : array[0 .. cPaletteCount - 1, 0 .. cTilePaletteSize - 1] of TFloat;

procedure InitLuts;
const
  cCurvature = 2.0;
var
  g, i, j, v, u, y, x: Int64;
  f, fp: TFloat;
begin
  for g := -1 to High(cGamma) do
    for i := 0 to High(Byte) do
      if g >= 0 then
        gGammaCorLut[g, i] := power(i / 255.0, cGamma[g])
      else
        gGammaCorLut[g, i] := i / 255.0;

  for i := 0 to High(gVecInv) do
    gVecInv[i] := iDiv0(1 shl cVecInvWidth, i shr 2);

  i := 0;
  for v := 0 to (cTileWidth - 1) do
    for u := 0 to (cTileWidth - 1) do
      for y := 0 to (cTileWidth - 1) do
        for x := 0 to (cTileWidth - 1) do
        begin
          gDCTLut[i] := cos((x + 0.5) * u * PI / 16.0) * cos((y + 0.5) * v * PI / 16.0);
          Inc(i);
        end;

  f := 0;
  for i := 0 to cTilePaletteSize - 1 do
  begin
    fp := f;
    f := power(i + 2, cCurvature);

    for j := 0 to cPaletteCount - 1 do
      gPalettePattern[j, i] := ((j + 1) / cPaletteCount) * max(cPaletteCount, f - fp) + fp;
  end;

  for j := 0 to cPaletteCount - 1 do
    for i := 0 to cTilePaletteSize - 1 do
      gPalettePattern[j, i] /= gPalettePattern[cPaletteCount - 1, cTilePaletteSize - 1];
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

const
  CvtPre =  (1 shl cBitsPerComp) - 1;
  CvtPost = 256 div CvtPre;

function Posterize(v: Byte): Byte; inline;
begin
  Result := ((v * CvtPre) div 255) * CvtPost;
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

Const
  READ_BYTES = 65536; // not too small to avoid fragmentation when reading large files.

// helperfunction that does the bulk of the work.
// We need to also collect stderr output in order to avoid
// lock out if the stderr pipe is full.
function internalRuncommand(p:TProcess;var outputstring:string;
                            var stderrstring:string; var exitstatus:integer):integer;
var
    numbytes,bytesread,available : integer;
    outputlength, stderrlength : integer;
    stderrnumbytes,stderrbytesread : integer;
begin
  result:=-1;
  try
    try
    p.Options :=  [poUsePipes];
    bytesread:=0;
    outputlength:=0;
    stderrbytesread:=0;
    stderrlength:=0;
    p.Execute;
    while p.Running do
      begin
        // Only call ReadFromStream if Data from corresponding stream
        // is already available, otherwise, on  linux, the read call
        // is blocking, and thus it is not possible to be sure to handle
        // big data amounts bboth on output and stderr pipes. PM.
        available:=P.Output.NumBytesAvailable;
        if  available > 0 then
          begin
            if (BytesRead + available > outputlength) then
              begin
                outputlength:=BytesRead + READ_BYTES;
                Setlength(outputstring,outputlength);
              end;
            NumBytes := p.Output.Read(outputstring[1+bytesread], available);
            if NumBytes > 0 then
              Inc(BytesRead, NumBytes);
          end
        // The check for assigned(P.stderr) is mainly here so that
        // if we use poStderrToOutput in p.Options, we do not access invalid memory.
        else if assigned(P.stderr) and (P.StdErr.NumBytesAvailable > 0) then
          begin
            available:=P.StdErr.NumBytesAvailable;
            if (StderrBytesRead + available > stderrlength) then
              begin
                stderrlength:=StderrBytesRead + READ_BYTES;
                Setlength(stderrstring,stderrlength);
              end;
            StderrNumBytes := p.StdErr.Read(stderrstring[1+StderrBytesRead], available);
            if StderrNumBytes > 0 then
              Inc(StderrBytesRead, StderrNumBytes);
          end
        else
          Sleep(100);
      end;
    // Get left output after end of execution
    available:=P.Output.NumBytesAvailable;
    while available > 0 do
      begin
        if (BytesRead + available > outputlength) then
          begin
            outputlength:=BytesRead + READ_BYTES;
            Setlength(outputstring,outputlength);
          end;
        NumBytes := p.Output.Read(outputstring[1+bytesread], available);
        if NumBytes > 0 then
          Inc(BytesRead, NumBytes);
        available:=P.Output.NumBytesAvailable;
      end;
    setlength(outputstring,BytesRead);
    while assigned(P.stderr) and (P.Stderr.NumBytesAvailable > 0) do
      begin
        available:=P.Stderr.NumBytesAvailable;
        if (StderrBytesRead + available > stderrlength) then
          begin
            stderrlength:=StderrBytesRead + READ_BYTES;
            Setlength(stderrstring,stderrlength);
          end;
        StderrNumBytes := p.StdErr.Read(stderrstring[1+StderrBytesRead], available);
        if StderrNumBytes > 0 then
          Inc(StderrBytesRead, StderrNumBytes);
      end;
    setlength(stderrstring,StderrBytesRead);
    exitstatus:=p.exitstatus;
    result:=0; // we came to here, document that.
    except
      on e : Exception do
         begin
           result:=1;
           setlength(outputstring,BytesRead);
         end;
     end;
  finally
    p.free;
  end;
end;

function Compareeuclidean32Asm(a_rcx: PFloat; b_rdx: PFloat): TFloat; register; assembler; nostackframe;
asm
  movdqu xmm0, oword ptr [rcx + $00]
  movdqu xmm1, oword ptr [rcx + $10]
  movdqu xmm2, oword ptr [rcx + $20]
  movdqu xmm3, oword ptr [rcx + $30]
  movdqu xmm4, oword ptr [rcx + $40]
  movdqu xmm5, oword ptr [rcx + $50]
  movdqu xmm6, oword ptr [rcx + $60]
  movdqu xmm7, oword ptr [rcx + $70]

  subps xmm0, oword ptr [rdx + $00]
  subps xmm1, oword ptr [rdx + $10]
  subps xmm2, oword ptr [rdx + $20]
  subps xmm3, oword ptr [rdx + $30]
  subps xmm4, oword ptr [rdx + $40]
  subps xmm5, oword ptr [rdx + $50]
  subps xmm6, oword ptr [rdx + $60]
  subps xmm7, oword ptr [rdx + $70]

  mulps xmm0, xmm0
  mulps xmm1, xmm1
  mulps xmm2, xmm2
  mulps xmm3, xmm3
  mulps xmm4, xmm4
  mulps xmm5, xmm5
  mulps xmm6, xmm6
  mulps xmm7, xmm7

  addps xmm0, xmm1
  addps xmm2, xmm3
  addps xmm4, xmm5
  addps xmm6, xmm7

  addps xmm0, xmm2
  addps xmm4, xmm6

  addps xmm0, xmm4

  haddps xmm0, xmm0
  haddps xmm0, xmm0
end ['xmm0', 'xmm1', 'xmm2', 'xmm3', 'xmm4', 'xmm5', 'xmm6', 'xmm7'];

function CompareManhattan192Ptr(pa, pb: PFloat): TFloat;
var
  i: Integer;
begin
  Result := 0;
  for i := 192 div 8 - 1 downto 0 do
  begin
    Result += abs(pa^ - pb^); Inc(pa); Inc(pb);
    Result += abs(pa^ - pb^); Inc(pa); Inc(pb);
    Result += abs(pa^ - pb^); Inc(pa); Inc(pb);
    Result += abs(pa^ - pb^); Inc(pa); Inc(pb);
    Result += abs(pa^ - pb^); Inc(pa); Inc(pb);
    Result += abs(pa^ - pb^); Inc(pa); Inc(pb);
    Result += abs(pa^ - pb^); Inc(pa); Inc(pb);
    Result += abs(pa^ - pb^); Inc(pa); Inc(pb);
  end;
end;

function CompareEuclidean192Ptr(pa, pb: PFloat): TFloat;
var
  i: Integer;
begin
  Result := 0;
  for i := 192 div 8 - 1 downto 0 do
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

function CompareEuclidean192(const a, b: TFloatDynArray): TFloat; inline;
begin
//{$if SizeOf(TFloat) <> 4}
  Result := CompareEuclidean192Ptr(@a[0], @b[0]);
//{$else}
//  Result := Compareeuclidean32Asm(@a[0 ], @b[0 ]) +
//            Compareeuclidean32Asm(@a[32], @b[32]) +
//            Compareeuclidean32Asm(@a[64], @b[64]) +
//            Compareeuclidean32Asm(@a[96], @b[96]) +
//            Compareeuclidean32Asm(@a[128], @b[128]) +
//            Compareeuclidean32Asm(@a[160], @b[160]);
//{$endif}
end;

function CompareManhattan192(const a, b: TFloatDynArray): TFloat; inline;
begin
  Result := CompareManhattan192Ptr(@a[0], @b[0]);
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

function ColorCompare(r1, g1, b1, r2, g2, b2: Integer): Int64; inline;
begin
  Result := sqr(r1 - r2) + sqr(g1 - g2) + sqr(b1 - b2);
end;

function TMainForm.ComputeCorrelation(const a, b: TIntegerDynArray): TFloat;
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
    ya[i] := fr; ya[i + Length(a)] := fg; ya[i + Length(a) * 2] := fb;

    fr := (b[i] shr 16) and $ff; fg := (b[i] shr 8) and $ff; fb := b[i] and $ff;
    yb[i] := fr; yb[i + Length(a)] := fg; yb[i + Length(a) * 2] := fb;
  end;

  Result := PearsonCorrelation(ya, yb, Length(a) * 3);
end;

function TMainForm.ComputeInterFrameCorrelation(a, b: PFrame): TFloat;
var
  sz, i: Integer;
  ya, yb: TDoubleDynArray;
begin
  Assert(Length(a^.FSPixels) = Length(b^.FSPixels));
  sz := Length(a^.FSPixels) div 3;
  SetLength(ya, sz * 3);
  SetLength(yb, sz * 3);

  for i := 0 to sz - 1 do
  begin
    ya[i + sz * 0] := a^.FSPixels[i * 3 + 0];
    ya[i + sz * 1] := a^.FSPixels[i * 3 + 1];
    ya[i + sz * 2] := a^.FSPixels[i * 3 + 2];

    yb[i + sz * 0] := b^.FSPixels[i * 3 + 0];
    yb[i + sz * 1] := b^.FSPixels[i * 3 + 1];
    yb[i + sz * 2] := b^.FSPixels[i * 3 + 2];
  end;
  Result := PearsonCorrelation(ya, yb, Length(ya));
end;

{ TMainForm }

procedure TMainForm.btnDoGlobalTilingClick(Sender: TObject);
var
  dnt: Integer;
begin
  if Length(FFrames) = 0 then
    Exit;

  ProgressRedraw(-1, esGlobalTiling);

  dnt := seMaxTiles.Value;
  dnt -= Ord(odd(dnt));

  DoGlobalTiling(dnt, cRandomKModesCount);

  tbFrameChange(nil);
end;

procedure TMainForm.DoPre(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
begin
  PreDitherTiles(@FFrames[AIndex]);
end;

procedure TMainForm.DoFindBest(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
begin
  FindBestKeyframePalette(FKeyFrames[AIndex]);
end;

procedure TMainForm.DoFinal(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
begin
  FinalDitherTiles(@FFrames[AIndex]);
end;

procedure TMainForm.btnDitherClick(Sender: TObject);
begin
  if Length(FFrames) = 0 then
    Exit;

  ProgressRedraw(-1, esDither);
  ProcThreadPool.DoParallel(@DoPre, 0, High(FFrames));
  ProgressRedraw(1);
  ProcThreadPool.DoParallel(@DoFindBest, 0, High(FKeyFrames));
  ProgressRedraw(2);
  ProcThreadPool.DoParallel(@DoFinal, 0, High(FFrames));
  ProgressRedraw(3);

  tbFrameChange(nil);
end;

function CompareFrames(Item1,Item2,UserParameter:Pointer):Integer;
begin
  Result := CompareValue(PInteger(Item2)^, PInteger(Item1)^);
end;

procedure TMainForm.btnDoKeyFrameTilingClick(Sender: TObject);

  procedure DoFrm(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
  begin
    DoFrameTiling(FKeyFrames[AIndex], seMaxTPF.Value)
  end;

var
  i: Integer;
begin
  if Length(FKeyFrames) = 0 then
    Exit;

  ProgressRedraw(-1, esFrameTiling);
  ProcThreadPool.DoParallelLocalProc(@DoFrm, 0, High(FKeyFrames));
  ProgressRedraw(1);

  tbFrameChange(nil);
end;

function TMainForm.testGR(x: TFloat; Data: Pointer): TFloat;
begin
  Result := 12 + log10(x - 100) * 7;
end;

procedure TMainForm.chkUseTKChange(Sender: TObject);
begin
  FUseThomasKnoll := chkUseTK.Checked;
end;

procedure TMainForm.chkExtFTChange(Sender: TObject);
begin
  FExtendedFrmTiling := chkExtFT.Checked;
end;

procedure TMainForm.btnLoadClick(Sender: TObject);
const
  CShotTransGracePeriod = 12;
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
      bmp.LoadFromFile(Format(PChar(AData), [AIndex]));
      LeaveCriticalSection(FCS);

      LoadFrame(@FFrames[AIndex], bmp.Bitmap);

      FFrames[AIndex].Index := AIndex;
    finally
      bmp.Free;
    end;
  end;

var
  inPath: String;
  i, j, Cnt, LastKFIdx: Integer;
  v, av, ratio: TFloat;
  fn: String;
  kfIdx, frc: Integer;
  isKf: Boolean;
  kfSL: TStringList;
  sfr, efr: Integer;
begin
  ProgressRedraw;

  for i := 0 to High(FTiles) do
    Dispose(FTiles[i]);

  SetLength(FFrames, 0);

  for i := 0 to High(FKeyFrames) do
    Dispose(FKeyFrames[i]);

  SetLength(FKeyFrames, 0);
  SetLength(FTiles, 0);

  ProgressRedraw(-1, esLoad);

  inPath := edInput.Text;
  frc := seFrameCount.Value;

  if frc <= 0 then
  begin
    if Pos('%', inPath) > 0 then
    begin
      i := 0;
      repeat
        fn := Format(inPath, [i]);
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
    fn := Format(inPath, [i]);
    if not FileExists(fn) then
    begin
      SetLength(FFrames, 0);
      tbFrame.Max := 0;
      raise EFileNotFoundException.Create('File not found: ' + fn);
    end;
  end;

  ProcThreadPool.DoParallelLocalProc(@DoLoadFrame, 0, High(FFrames), PChar(inPath));

{$if false}
  kfSL := TStringList.Create;
  try
    fn := ChangeFileExt(Format(inPath, [0]), '.kf');
    if FileExists(fn) then
    begin
      kfSL.LoadFromFile(fn);
      kfSL.Insert(0, 'I'); // fix format shifted 1 frame in the past
    end;

    kfIdx := 0;
    for i := 0 to High(FFrames) do
    begin
      fn := ChangeFileExt(Format(inPath, [i]), '.kf');
      isKf := FileExists(fn) or (i = 0) or (i < kfSL.Count) and (Pos('I', kfSL[i]) <> 0);
      if isKf then
      begin
        WriteLn('KF: ', kfIdx, #9'Frame: ', i);
        Inc(kfIdx);
      end;
    end;

    SetLength(FKeyFrames, kfIdx);
    kfIdx := -1;
    for i := 0 to High(FFrames) do
    begin
      fn := ChangeFileExt(Format(inPath, [i]), '.kf');
      isKf := FileExists(fn) or (i = 0) or (i < kfSL.Count) and (Pos('I', kfSL[i]) <> 0);
      if isKf then
        Inc(kfIdx);
      FFrames[i].KeyFrame := FKeyFrames[kfIdx];
    end;
  finally
    kfSL.Free;
  end;
{$else}
  kfIdx := 0;
  SetLength(FKeyFrames, 1);
  New(FKeyFrames[0]);
  FFrames[0].KeyFrame := FKeyFrames[0];

  av := -1.0;
  LastKFIdx := 0;
  for i := 1 to High(FFrames) do
  begin
    Cnt := 0;
    v := ComputeInterFrameCorrelation(@FFrames[i - 1], @FFrames[i]);
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
    isKf := (ratio < CShotTransHardThres) or (ratio < CShotTransSoftThres) and ((i - LastKFIdx) >= CShotTransGracePeriod);
    if isKf then
    begin
      Inc(kfIdx);
      SetLength(FKeyFrames, kfIdx + 1);
      New(FKeyFrames[kfIdx]);
      av := -1.0;
      LastKFIdx := i;

      WriteLn('Frm: -> ', i, #9'KF: ', kfIdx, #9'Ratio: ', FloatToStr(ratio));
    end;

    FFrames[i].KeyFrame := FKeyFrames[kfIdx];
  end;
{$endif}

  for j := 0 to High(FKeyFrames) do
  begin
    sfr := High(Integer);
    efr := Low(Integer);

    for i := 0 to High(FFrames) do
      if FFrames[i].KeyFrame = FKeyFrames[j] then
      begin
        sfr := Min(sfr, i);
        efr := Max(efr, i);
      end;

    FKeyFrames[j]^.StartFrame := sfr;
    FKeyFrames[j]^.EndFrame := efr;
    FKeyFrames[j]^.FrameCount := efr - sfr + 1;
    FKeyFrames[j]^.FramesLeft := -1;
  end;

  ProgressRedraw(1);

  LoadTiles;

  ProgressRedraw(2);

  tbFrameChange(nil);
end;

procedure TMainForm.btnReindexClick(Sender: TObject);

  procedure DoPruneUnusedTiles(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
  begin
    if FTiles[AIndex]^.Active then
    begin
      FTiles[AIndex]^.UseCount := GetTileUseCount(AIndex);
      FTiles[AIndex]^.Active := FTiles[AIndex]^.UseCount <> 0;
    end
    else
    begin
      FTiles[AIndex]^.UseCount := 0;
    end;
  end;

  procedure DoIndexFrameTiles(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
  begin
    IndexFrameTiles(@FFrames[AIndex]);
  end;

begin
  if Length(FFrames) = 0 then
    Exit;

  ProgressRedraw(-1, esReindex);

  ProcThreadPool.DoParallelLocalProc(@DoPruneUnusedTiles, 0, High(FTiles));
  ProgressRedraw(1);
  ReindexTiles;
  ProgressRedraw(2);
  ProcThreadPool.DoParallelLocalProc(@DoIndexFrameTiles, 0, High(FFrames));
  ProgressRedraw(3);

  tbFrameChange(nil);
end;

procedure TMainForm.btnRunAllClick(Sender: TObject);
begin
  btnLoadClick(nil);
  btnDitherClick(nil);
  //btnDoMakeUniqueClick(nil); // useless and may alter tiles weighting
  btnDoGlobalTilingClick(nil);
  btnDoKeyFrameTilingClick(nil);
  btnReindexClick(nil);
  btnSmoothClick(nil);
  btnSaveClick(nil);

  ProgressRedraw;
  tbFrameChange(nil);
end;

procedure TMainForm.btnDebugClick(Sender: TObject);
begin
end;

procedure TMainForm.btnSaveClick(Sender: TObject);
var
  dataFS, soundFS: TFileStream;
begin
  if Length(FFrames) = 0 then
    Exit;

  ProgressRedraw(-1, esSave);

  dataFS := TFileStream.Create(IncludeTrailingPathDelimiter(edOutputDir.Text) + 'data.bin', fmCreate);
  soundFS := nil;
  if Trim(edWAV.Text) <> '' then
    soundFS := TFileStream.Create(DoExternalPCMEnc(edWAV.Text, 115), fmOpenRead or fmShareDenyWrite);

  ProgressRedraw(1);

  try
    Save(dataFS, soundFS);
  finally
    dataFS.Free;
    if Assigned(soundFS) then
      soundFS.Free;
  end;

  ProgressRedraw(2);

  tbFrameChange(nil);
end;

procedure TMainForm.btnSmoothClick(Sender: TObject);
  procedure DoSmoothing(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
  var i: Integer;
  begin
    for i := cSmoothingPrevFrame to High(FFrames) do
      DoTemporalSmoothing(@FFrames[i], @FFrames[i - cSmoothingPrevFrame], AIndex, seTempoSmoo.Value / 10.0);
  end;
begin
  if Length(FFrames) = 0 then
    Exit;

  ProgressRedraw(-1, esSmooth);

  ProcThreadPool.DoParallelLocalProc(@DoSmoothing, 0, cTileMapHeight - 1);

  ProgressRedraw(1);

  tbFrameChange(nil);
end;

procedure TMainForm.cbxYilMixChange(Sender: TObject);
begin
  FY2MixedColors := StrToIntDef(cbxYilMix.Text, 16);
end;

procedure TMainForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_F1: btnLoadClick(nil);
    VK_F2: btnDitherClick(nil);
    VK_F3: btnDoGlobalTilingClick(nil);
    VK_F4: btnDoKeyFrameTilingClick(nil);
    VK_F5: btnReindexClick(nil);
    VK_F6: btnSmoothClick(nil);
    VK_F7: btnSaveClick(nil);
    VK_F10: btnRunAllClick(nil);
    VK_F11: chkPlay.Checked := not chkPlay.Checked;
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

procedure TMainForm.seAvgTPFEditingDone(Sender: TObject);
begin
  if Length(FFrames) = 0 then Exit;
  seMaxTiles.Value := seAvgTPF.Value * Length(FFrames);
end;

procedure TMainForm.seMaxTilesEditingDone(Sender: TObject);
begin
  if Length(FFrames) = 0 then Exit;
  seAvgTPF.Value := seMaxTiles.Value div Length(FFrames);
end;

procedure TMainForm.tbFrameChange(Sender: TObject);
begin
  Screen.Cursor := crDefault;
  seAvgTPFEditingDone(nil);
  Render(tbFrame.Position, chkDithered.Checked, chkMirrored.Checked, chkReduced.Checked,  chkGamma.Checked, Ord(chkSprite.State), sePage.Value);
end;

function TMainForm.GoldenRatioSearch(Func: TFloatFloatFunction; Mini, Maxi: TFloat; ObjectiveY: TFloat;
  Epsilon: TFloat; Data: Pointer): TFloat;
var
  x, y: TFloat;
begin
  if SameValue(Mini, Maxi, Epsilon) then
  begin
    DebugLn('GoldenRatioSearch failed!');
    Result := NaN;
    Exit;
  end;

  if Mini < Maxi then
    x := lerp(Mini, Maxi, 1.0 - cInvPhi)
  else
    x := lerp(Mini, Maxi, cInvPhi);

  y := Func(x, Data);

  //EnterCriticalSection(FCS);
  //WriteLn('X: ', FormatFloat('0.000', x), #9'Y: ', FormatFloat('0.000', y), #9'Mini: ', FormatFloat('0.000', Mini), #9'Maxi: ', FormatFloat('0.000', Maxi));
  //LeaveCriticalSection(FCS);

  case CompareValue(y, ObjectiveY, Epsilon) of
    LessThanValue:
      Result := GoldenRatioSearch(Func, x, Maxi, ObjectiveY, Epsilon, Data);
    GreaterThanValue:
      Result := GoldenRatioSearch(Func, Mini, x, ObjectiveY, Epsilon, Data);
  else
      Result := x;
  end;
end;


function TMainForm.ColorCompare(r1, g1, b1, r2, g2, b2: Int64): Int64;
var
  luma1, luma2, lumadiff, diffR, diffG, diffB: Int64;
begin
  luma1 := r1 * cRedMultiplier + g1 * cGreenMultiplier + b1 * cBlueMultiplier;
  luma2 := r2 * cRedMultiplier + g2 * cGreenMultiplier + b2 * cBlueMultiplier;
  lumadiff := luma1 - luma2;
  diffR := r1 - r2;
  diffG := g1 - g2;
  diffB := b1 - b2;
  Result := diffR * diffR * cRedMultiplier * cRGBw div 32;
  Result += diffG * diffG * cGreenMultiplier * cRGBw div 32;
  Result += diffB * diffB * cBlueMultiplier * cRGBw div 32;
  Result += lumadiff * lumadiff;
end;

function TMainForm.DeviseBestMixingPlan(var Plan: TMixingPlan; col: Integer; const List: TByteDynArray): Integer;
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

    mov eax, r
    mov ebx, g
    mov ecx, b

    pinsrd xmm4, eax, 0
    pinsrd xmm4, ebx, 1
    pinsrd xmm4, ecx, 2

    imul eax, cRedMultiplier
    imul ebx, cGreenMultiplier
    imul ecx, cBlueMultiplier

    add eax, ebx
    add eax, ecx
    imul eax, (1 shl 22) / cLumaMultiplier
    shr eax, 22

    pinsrd xmm4, eax, 3

    mov rax, 1 or (1 shl 32)
    pinsrq xmm5, rax, 0
    pinsrq xmm5, rax, 1

    mov rax, (cRedMultiplier * cRGBw / 128) or ((cGreenMultiplier * cRGBw / 128) shl 32)
    pinsrq xmm6, rax, 0
    mov rax, (cBlueMultiplier * cRGBw / 128) or ((cLumaMultiplier * 32 / 128) shl 32)
    pinsrq xmm6, rax, 1

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

function TMainForm.ColorCompareTK(r1, g1, b1, r2, g2, b2: Int64): Int64;
var
  luma1, luma2, lumadiff, diffR, diffG, diffB: Int64;
begin
  luma1 := r1 * cRedMultiplier + g1 * cGreenMultiplier + b1 * cBlueMultiplier;
  luma2 := r2 * cRedMultiplier + g2 * cGreenMultiplier + b2 * cBlueMultiplier;
  lumadiff := (luma1 - luma2) div cLumaMultiplier;
  diffR := r1 - r2;
  diffG := g1 - g2;
  diffB := b1 - b2;
  Result := diffR * diffR * cRGBw div 32;
  Result += diffG * diffG * cRGBw div 32;
  Result += diffB * diffB * cRGBw div 32;
  Result += lumadiff * lumadiff;
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

    Plan.LumaPal[i] := r*cRedMultiplier + g*cGreenMultiplier + b*cBlueMultiplier;

    Plan.Y2Palette[i][0] := r;
    Plan.Y2Palette[i][1] := g;
    Plan.Y2Palette[i][2] := b;
    Plan.Y2Palette[i][3] := Plan.LumaPal[i] div cLumaMultiplier;
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

    //t[0] := EnsureRange(t[0], 0, 255);
    //t[1] := EnsureRange(t[1], 0, 255);
    //t[2] := EnsureRange(t[2], 0, 255);

    least_penalty := High(Int64);
    chosen := c and (length(Plan.Y2Palette) - 1);
    for index := 0 to length(Plan.Y2Palette) - 1 do
    begin
      penalty := ColorCompareTK(t[0], t[1], t[2], Plan.Y2Palette[index][0], Plan.Y2Palette[index][1], Plan.Y2Palette[index][2]);
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

procedure TMainForm.DitherFloydSteinberg(var AScreen: TByteDynArray);
var
  x, y, c, yp, xm, xp: Integer;
  OldPixel, NewPixel, QuantError: Integer;
  ppx: PByte;
begin
  ppx := @AScreen[0];
  for y := 0 to CScreenHeight - 1 do
    for x := 0 to CScreenWidth - 1 do
    begin
      yp := IfThen(y < CScreenHeight - 1, cScreenWidth * 3, 0);
      xp := IfThen(x < CScreenWidth - 1, 3, 0);
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
         map_value := cDitheringMap[(y shl 3) + x];
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
        count := DeviseBestMixingPlan(Plan, ATile.RGBPixels[y, x], list);
        map_value := (map_value * count) shr 6;
        ATile.PalPixels[y, x] := list[map_value];
      end;
  end;
end;

type
  TCountIndexArray = packed record
    Count, Index, Luma: Integer;
    Hue, Importance: Integer;
  end;

  PCountIndexArray = ^TCountIndexArray;


function CompareCMUCntImp(Item1,Item2,UserParameter:Pointer):Integer;
begin
  Result := CompareValue(PCountIndexArray(Item2)^.Count shr 3, PCountIndexArray(Item1)^.Count shr 3);
  if Result = 0 then
    Result := CompareValue(PCountIndexArray(Item2)^.Importance, PCountIndexArray(Item1)^.Importance);
end;

function CompareCMUHueLuma(Item1,Item2,UserParameter:Pointer):Integer;
begin
  Result := CompareValue(PCountIndexArray(Item1)^.Hue, PCountIndexArray(Item2)^.Hue);
  if Result = 0 then
    Result := CompareValue(PCountIndexArray(Item1)^.Luma, PCountIndexArray(Item2)^.Luma);
end;

function CompareCMULumaHueInv(Item1,Item2,UserParameter:Pointer):Integer;
begin
  Result := CompareValue(PCountIndexArray(Item2)^.Luma, PCountIndexArray(Item1)^.Luma);
  if Result = 0 then
    Result := CompareValue(PCountIndexArray(Item2)^.Hue, PCountIndexArray(Item1)^.Hue);
end;

procedure TMainForm.PreDitherTiles(AFrame: PFrame);
var
  sx, sy, i, tx, ty: Integer;
  CMUsage: array of TCountIndexArray;
  Tile_: PTile;
  FullPalTile: TTile;
  Plan, CMPlan: TMixingPlan;
begin
  PreparePlan(CMPlan, FY2MixedColors, FColorMap);

  SetLength(CMUsage, cTotalColors);

  for sy := 0 to cTileMapHeight - 1 do
    for sx := 0 to cTileMapWidth - 1 do
    begin
      Tile_ := FTiles[AFrame^.TileMap[sy, sx].GlobalTileIndex];

      if not Tile_^.Active then
        Exit;

      // dither using full RGB palette

      CopyTile(Tile_^, FullPalTile);

      DitherTile(FullPalTile, CMPlan);

      for i := 0 to High(CMUsage) do
      begin
        CMUsage[i].Count := 0;
        CMUsage[i].Index := i;
        CMUsage[i].Importance := FColorMapImportance[i];
        CMUsage[i].Luma := FColorMapLuma[i];
        CMUsage[i].Hue := FColorMapHue[i];
      end;

      // keep the 16 most used color

      for ty := 0 to (cTileWidth - 1) do
        for tx := 0 to (cTileWidth - 1) do
          Inc(CMUsage[FullPalTile.PalPixels[ty, tx]].Count);

      QuickSort(CMUsage[0], 0, High(CMUsage), SizeOf(CMUsage[0]), @CompareCMUCntImp);

      // sort those by importance and luma
      QuickSort(CMUsage[0], 0, cTilePaletteSize - 1, SizeOf(CMUsage[0]), @CompareCMULumaHueInv);

      SetLength(Tile_^.PaletteIndexes, cTilePaletteSize);
      SetLength(Tile_^.PaletteRGB, cTilePaletteSize);
      for i := 0 to cTilePaletteSize - 1 do
      begin
        Tile_^.PaletteIndexes[i] := CMUsage[cTilePaletteSize - 1 - i].Index;
        Tile_^.PaletteRGB[i] := FColorMap[Tile_^.PaletteIndexes[i]];
      end;

      // dither again using that 16 color palette
      PreparePlan(Plan, FY2MixedColors, Tile_^.PaletteRGB);

      DitherTile(Tile_^, Plan);

      TerminatePlan(Plan);
    end;

  TerminatePlan(CMPlan);
end;

procedure TMainForm.FindBestKeyframePalette(AKeyFrame: PKeyFrame);
const
  cPalettePattern : array[Boolean, 0 .. cTilePaletteSize - 1] of Integer = (
{$if true}
    (4, 5, 8, 9, 12,13,16,17,20,21,24,25,0, 1, 2, 3),
    (6, 7, 10,11,14,15,18,19,22,23,26,27,0, 1, 2, 3)
{$else}
    (4, 6, 8, 10,12,14,16,18,20,22,24,26,0, 1, 2, 3),
    (5, 7, 9, 11,13,15,17,19,21,23,25,27,0, 1, 2, 3)
{$endif}
  );
var
  sx, sy, tx, ty, i: Integer;
  GTile: PTile;
  CMUsage: array of TCountIndexArray;
  sfr, efr: Integer;
begin
  SetLength(CMUsage, cTotalColors);

  for i := 0 to High(CMUsage) do
  begin
    CMUsage[i].Count := 0;
    CMUsage[i].Index := i;
    CMUsage[i].Importance := FColorMapImportance[i];
    CMUsage[i].Luma := FColorMapLuma[i];
    CMUsage[i].Hue := FColorMapHue[i];
  end;

  // get color usage stats

  sfr := High(Integer);
  efr := Low(Integer);
  for i := 0 to High(FFrames) do
    if FFrames[i].KeyFrame = AKeyFrame then
    begin
      sfr := Min(sfr, i);
      efr := Max(efr, i);

      for sy := 0 to cTileMapHeight - 1 do
        for sx := 0 to cTileMapWidth - 1 do
        begin
          GTile := FTiles[FFrames[i].TileMap[sy, sx].GlobalTileIndex];

          for ty := 0 to cTileWidth - 1 do
            for tx := 0 to cTileWidth - 1 do
              Inc(CMUsage[GTile^.PaletteIndexes[GTile^.PalPixels[ty, tx]]].Count);
        end;
    end;

  AKeyFrame^.StartFrame := sfr;
  AKeyFrame^.EndFrame := efr;
  AKeyFrame^.FrameCount := efr - sfr + 1;

  // sort colors by use count

  QuickSort(CMUsage[0], 0, High(CMUsage), SizeOf(CMUsage[0]), @CompareCMUCntImp);

  // split most used colors into two 16 color palettes, with brightest and darkest colors repeated in both

  QuickSort(CMUsage[0], 0, cKeyframeFixedColors - 1, SizeOf(CMUsage[0]), @CompareCMULumaHueInv);
  QuickSort(CMUsage[0], cKeyframeFixedColors, cTilePaletteSize * 2 - 1, SizeOf(CMUsage[0]), @CompareCMUHueLuma);

  SetLength(AKeyFrame^.PaletteIndexes[False], cTilePaletteSize);
  SetLength(AKeyFrame^.PaletteIndexes[True], cTilePaletteSize);
  SetLength(AKeyFrame^.PaletteRGB[False], cTilePaletteSize);
  SetLength(AKeyFrame^.PaletteRGB[True], cTilePaletteSize);

  for i := 0 to cTilePaletteSize - 1 do
  begin
    AKeyFrame^.PaletteIndexes[False, i] := CMUsage[cPalettePattern[False, i]].Index;
    AKeyFrame^.PaletteIndexes[True, i] := CMUsage[cPalettePattern[True, i]].Index;
  end;

{$if cInvertSpritePalette}
  for i := 0 to (cTilePaletteSize - cKeyframeFixedColors) div 2 - 1 do
    Exchange(AKeyFrame^.PaletteIndexes[False, cTilePaletteSize - cKeyframeFixedColors - 1 - i], AKeyFrame^.PaletteIndexes[False, i]);

  for i := 0 to cKeyframeFixedColors div 2 - 1 do
    Exchange(AKeyFrame^.PaletteIndexes[False, cTilePaletteSize - 1 - i], AKeyFrame^.PaletteIndexes[False, cTilePaletteSize - cKeyframeFixedColors + i]);
{$endif}

  for i := 0 to cTilePaletteSize - 1 do
  begin
    AKeyFrame^.PaletteRGB[False, i] := FColorMap[AKeyFrame^.PaletteIndexes[False, i]];
    AKeyFrame^.PaletteRGB[True, i] := FColorMap[AKeyFrame^.PaletteIndexes[True, i]];
  end;
end;

procedure TMainForm.FinalDitherTiles(AFrame: PFrame);
var
  sx, sy: Integer;
  KF: PKeyFrame;
  SpritePal: Boolean;
  OrigTile: TTile;
  OrigTileDCT: TFloatDynArray;
  TileDCT: array[Boolean] of TFloatDynArray;
  cmp: array[Boolean] of TFloat;
  Tile_: array[Boolean] of TTile;
  Plan: array[Boolean] of TMixingPlan;
begin
  SetLength(OrigTileDCT, cTileDCTSize);
  SetLength(TileDCT[False], cTileDCTSize);
  SetLength(TileDCT[True], cTileDCTSize);

  KF := AFrame^.KeyFrame;
  PreparePlan(Plan[False], FY2MixedColors, KF^.PaletteRGB[False]);
  PreparePlan(Plan[True], FY2MixedColors, KF^.PaletteRGB[True]);

  for sy := 0 to cTileMapHeight - 1 do
    for sx := 0 to cTileMapWidth - 1 do
    begin
      if not FTiles[AFrame^.TileMap[sy, sx].GlobalTileIndex]^.Active then
        Continue;

      CopyTile(FTiles[AFrame^.TileMap[sy, sx].GlobalTileIndex]^, Tile_[False]);
      CopyTile(FTiles[AFrame^.TileMap[sy, sx].GlobalTileIndex]^, Tile_[True]);
      CopyTile(FTiles[AFrame^.TileMap[sy, sx].GlobalTileIndex]^, OrigTile);

      // choose best palette from the keyframe by comparing DCT of the tile colored with either palette

      ComputeTileDCT(OrigTile, False, True, False, False, 0, OrigTile.PaletteRGB, OrigTileDCT);

      for SpritePal := False to True do
      begin
        DitherTile(Tile_[SpritePal], Plan[SpritePal]);

        ComputeTileDCT(Tile_[SpritePal], True, True, False, False, 0, KF^.PaletteRGB[SpritePal], TileDCT[SpritePal]);
        cmp[SpritePal] := CompareEuclidean192(TileDCT[SpritePal], OrigTileDCT);
      end;

      SpritePal := cmp[True] < cmp[False];

      // now that the palette is chosen, keep only one version of the tile

      AFrame^.TileMap[sy, sx].SpritePal := SpritePal;

      Move(KF^.PaletteIndexes[SpritePal][0], Tile_[SpritePal].PaletteIndexes[0], cTilePaletteSize * SizeOf(Integer));
      Move(KF^.PaletteRGB[SpritePal][0], Tile_[SpritePal].PaletteRGB[0], cTilePaletteSize * SizeOf(Integer));

      CopyTile(Tile_[SpritePal], AFrame^.Tiles[sx + sy * cTileMapWidth]);

      SetLength(Tile_[SpritePal].PaletteIndexes, 0);
      SetLength(Tile_[SpritePal].PaletteRGB, 0);
      CopyTile(Tile_[SpritePal], FTiles[AFrame^.TileMap[sy, sx].GlobalTileIndex]^);
    end;

  TerminatePlan(Plan[False]);
  TerminatePlan(Plan[True]);
end;

procedure TMainForm.LoadTiles;
var
  i,j,x,y: Integer;
  tileCnt: Integer;
begin
  // free memory from a prev run
  for i := 0 to High(FTiles) do
    Dispose(FTiles[i]);

  tileCnt := Length(FFrames) * cTileMapSize;

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
    tileCnt := i * cTileMapSize;
    for j := 0 to cTileMapSize - 1 do
      CopyTile(FFrames[i].Tiles[j], FTiles[tileCnt+j]^);
    for y := 0 to (cTileMapHeight - 1) do
      for x := 0 to (cTileMapWidth - 1) do
        Inc(FFrames[i].TileMap[y,x].GlobalTileIndex, tileCnt);
  end;
end;

procedure TMainForm.RGBToYUV(col: Integer; GammaCor: Integer; out y, u, v: TFloat); inline;
var
  fr, fg, fb: TFloat;
  yy, uu, vv: TFloat;
  r, g, b: Integer;
begin
  FromRGB(col, r, g, b);

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

  yy := (cRedMultiplier * fr + cGreenMultiplier * fg + cBlueMultiplier * fb) / cLumaMultiplier;
  uu := (fb - yy) * (0.5 / (1.0 - cBlueMultiplier / cLumaMultiplier));
  vv := (fr - yy) * (0.5 / (1.0 - cRedMultiplier / cLumaMultiplier));

  y := yy; u := uu; v := vv; // for safe "out" param
end;

procedure TMainForm.ComputeTileDCT(const ATile: TTile; FromPal, QWeighting, HMirror, VMirror: Boolean;
  GammaCor: Integer; const pal: TIntegerDynArray; var DCT: TFloatDynArray);  inline;
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
    yy, uu, vv: TFloat;
  begin
    RGBToYUV(col, GammaCor, yy, uu, vv);

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
           z *= sqrt(cDCTQuantization[cpn, v, u]);

        pDCT^ := z * pRatio^;
        Inc(pDCT);
        Inc(pRatio);
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

procedure TMainForm.LoadFrame(AFrame: PFrame; ABitmap: TBitmap);
var
  i, j, col, ti, tx, ty: Integer;
  pcol: PInteger;
  pfs: PByte;
begin
  FillChar(AFrame^, SizeOf(TFrame), 0);

  for j := 0 to (cTileMapHeight - 1) do
    for i := 0 to (cTileMapWidth - 1) do
    begin
      AFrame^.TileMap[j, i].GlobalTileIndex := cTileMapWidth * j + i;
      AFrame^.TileMap[j, i].HMirror := False;
      AFrame^.TileMap[j, i].VMirror := False;
      AFrame^.TileMap[j, i].SpritePal := False;
      AFrame^.TileMap[j, i].Smoothed := False;
      AFrame^.TileMap[j, i].TmpIndex := -1;
    end;

  ABitmap.BeginUpdate;
  try
    SetLength(AFrame^.FSPixels, CScreenHeight * CScreenWidth * 3);

    pfs := @AFrame^.FSPixels[0];
    for j := 0 to (CScreenHeight - 1) do
    begin
      pcol := ABitmap.ScanLine[j];
      for i := 0 to (CScreenWidth - 1) do
        begin
          col := pcol^;
          Inc(pcol);

          ti := CTileMapWidth * (j shr 3) + (i shr 3);
          tx := i and (cTileWidth - 1);
          ty := j and (cTileWidth - 1);

          col := SwapRB(col);
          AFrame^.Tiles[ti].RGBPixels[ty, tx] := col;

          FromRGB(col, pfs[0], pfs[1], pfs[2]);
          Inc(pfs, 3);
        end;
    end;

    DitherFloydSteinberg(AFrame^.FSPixels);

    for i := 0 to (cTileMapSize - 1) do
    begin
      for ty := 0 to (cTileWidth - 1) do
        for tx := 0 to (cTileWidth - 1) do
          AFrame^.Tiles[i].PalPixels[ty, tx] := 0;

      AFrame^.Tiles[i].Active := True;
      AFrame^.Tiles[i].UseCount := 1;
      AFrame^.Tiles[i].TmpIndex := -1;
      AFrame^.Tiles[i].MergeIndex := -1;
    end;

  finally
    ABitmap.EndUpdate;
  end;
end;

procedure TMainForm.ClearAll;
var
  i: Integer;
begin
  for i := 0 to High(FTiles) do
  begin
    SetLength(FTiles[i]^.PaletteIndexes, 0);
    SetLength(FTiles[i]^.PaletteRGB, 0);
    Dispose(FTiles[i]);
  end;

  SetLength(FTiles, 0);

  for i := 0 to High(FFrames) do
  begin
    SetLength(FFrames[i].TilesIndexes, 0);
    SetLength(FFrames[i].FSPixels, 0);
  end;

  SetLength(FFrames, 0);

  for i := 0 to High(FKeyFrames) do
  begin
    Dispose(FKeyFrames[i]);
  end;

  SetLength(FKeyFrames, 0);
end;

procedure TMainForm.Render(AFrameIndex: Integer; dithered, mirrored, reduced, gamma: Boolean; spritePal: Integer;
  ATilePage: Integer);
var
  i, j, r, g, b, ti, tx, ty, col: Integer;
  pTiles, pDest, pDest2, p: PInteger;
  tilePtr: PTile;
  TMItem: TTileMapItem;
  Frame: PFrame;
  fn: String;
  pal: TIntegerDynArray;
  oriCorr, chgCorr: TIntegerDynArray;
begin
  if Length(FFrames) <= 0 then
    Exit;

  AFrameIndex := EnsureRange(AFrameIndex, 0, high(FFrames));
  ATilePage := EnsureRange(ATilePage, 0, high(FFrames));

  Frame := @FFrames[AFrameIndex];

  if not Assigned(Frame) or not Assigned(Frame^.KeyFrame) then
    Exit;

  lblTileCount.Caption := 'Global: ' + IntToStr(GetGlobalTileCount) + ' / Frame #' + IntToStr(AFrameIndex) + IfThen(Frame^.KeyFrame^.StartFrame = AFrameIndex, ' [KF]', '     ') + ' : ' + IntToStr(GetFrameTileCount(Frame));

  imgTiles.Picture.Bitmap.BeginUpdate;
  imgDest.Picture.Bitmap.BeginUpdate;
  try
    // tile pages

    for j := 0 to cScreenHeight * 2 - 1 do
    begin
      pTiles := imgTiles.Picture.Bitmap.ScanLine[j];

      for i := 0 to cScreenWidth - 1 do
      begin
        ti := 32 * (j shr 3) + (i shr 3) + cTileMapSize * ATilePage;

        tx := i and (cTileWidth - 1);
        ty := j and (cTileWidth - 1);

        if ti >= Length(FTiles) then
        begin
          r := 0;
          g := 255;
          b := 255;
        end
        else
        begin
          tilePtr := FTiles[ti];

          case spritePal of
            0, 2: pal := Frame^.KeyFrame^.PaletteRGB[False];
            1: pal := Frame^.KeyFrame^.PaletteRGB[True];
          end;

          if dithered and Assigned(pal) then
          begin
            col := pal[tilePtr^.PalPixels[ty, tx]];

            b := (col shr 16) and $ff; g := (col shr 8) and $ff; r := col and $ff;
          end
          else
          begin
            FromRGB(tilePtr^.RGBPixels[ty, tx], r, g, b);
          end;

          if not tilePtr^.Active then
          begin
            r := 255;
            g := 0;
            b := 255;
		     end;
        end;

        p := pTiles;
        Inc(p, i);
        p^ := SwapRB(ToRGB(r, g, b));
      end;
    end;

    // dest screen

    SetLength(oriCorr, cScreenHeight * cScreenWidth * 2);
    SetLength(chgCorr, cScreenHeight * cScreenWidth * 2);

    for j := 0 to cScreenHeight - 1 do
    begin
      pDest := imgDest.Picture.Bitmap.ScanLine[j shl 1];
      pDest2 := imgDest.Picture.Bitmap.ScanLine[(j shl 1) + 1];

      for i := 0 to cScreenWidth - 1 do
      begin
        tx := i and (cTileWidth - 1);
        ty := j and (cTileWidth - 1);

        TMItem := Frame^.TileMap[j shr 3, i shr 3];
        if TMItem.Smoothed then
        begin
          // emulate smoothing (use previous frame tilemap item)
          TMItem := FFrames[AFrameIndex - cSmoothingPrevFrame].TileMap[j shr 3, i shr 3];
          TMItem.GlobalTileIndex := Frame^.TilesIndexes[TMItem.FrameTileIndex];
        end;
        ti := TMItem.GlobalTileIndex;

        if ti < Length(FTiles) then
        begin
          tilePtr :=  @Frame^.Tiles[(j shr 3) * cTileMapWidth + (i shr 3)];
          pal := tilePtr^.PaletteRGB;
          oriCorr[j * cScreenWidth + i] := tilePtr^.RGBPixels[ty, tx];
          oriCorr[i * cScreenHeight + j + cScreenWidth * cScreenHeight] := oriCorr[j * cScreenWidth + i];

          if reduced then
          begin
            tilePtr := FTiles[ti];
            if mirrored and TMItem.HMirror then tx := cTileWidth - 1 - tx;
            if mirrored and TMItem.VMirror then ty := cTileWidth - 1 - ty;
            case spritePal of
              0: pal := Frame^.KeyFrame^.PaletteRGB[False];
              1: pal := Frame^.KeyFrame^.PaletteRGB[True];
              2: pal := Frame^.KeyFrame^.PaletteRGB[TMItem.SpritePal];
            end
          end;

          if dithered and Assigned(pal) then
          begin
            col := pal[tilePtr^.PalPixels[ty, tx]];
            b := (col shr 16) and $ff; g := (col shr 8) and $ff; r := col and $ff;
          end
          else
          begin
            FromRGB(tilePtr^.RGBPixels[ty, tx], r, g, b);
          end;

          if gamma then
          begin
            r := round(GammaCorrect(0, r) * 255.0);
            g := round(GammaCorrect(0, g) * 255.0);
            b := round(GammaCorrect(0, b) * 255.0);
          end;

          p := pDest;
          Inc(p, i);
          p^ := SwapRB(ToRGB(r, g, b));

          chgCorr[j * cScreenWidth + i] := ToRGB(r, g, b);
          chgCorr[i * cScreenHeight + j + cScreenWidth * cScreenHeight] := chgCorr[j * cScreenWidth + i];

          // 25% scanlines
          //r := r - r shr 2;
          //g := g - g shr 2;
          //b := b - b shr 2;

          p := pDest2;
          Inc(p, i);
          p^ := SwapRB(ToRGB(r, g, b));
        end;
      end;
    end;

    lblCorrel.Caption := FormatFloat('0.0000', ComputeCorrelation(oriCorr, chgCorr));
  finally
    imgTiles.Picture.Bitmap.EndUpdate;
    imgDest.Picture.Bitmap.EndUpdate;
  end;

  imgPalette.Picture.Bitmap.BeginUpdate;
  try
    for j := 0 to imgPalette.Height - 1 do
    begin
      p := imgPalette.Picture.Bitmap.ScanLine[j];
      for i := 0 to imgPalette.Width - 1 do
      begin
        if Assigned(Frame^.KeyFrame^.PaletteRGB[False]) and Assigned(Frame^.KeyFrame^.PaletteRGB[True]) then
          p^ := SwapRB(Frame^.KeyFrame^.PaletteRGB[j >= imgPalette.Height div 2, i * cTilePaletteSize div imgPalette.Width])
        else
          p^ := $00ff00ff;

        Inc(p);
      end;
    end;
  finally
    imgPalette.Picture.Bitmap.EndUpdate;
  end;

  fn := Format(edInput.Text, [AFrameIndex]);
  if FileExists(fn) then
    imgSource.Picture.LoadFromFile(fn);

  imgSource.Invalidate;
  imgDest.Invalidate;
  imgTiles.Invalidate;
  imgPalette.Invalidate;
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
    FProgressStartTime := FProgressPrevTime;
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
  Application.ProcessMessages;

  t := GetTickCount;
  if CurFrameIdx >= 0 then
  begin
    WriteLn('Step: ', GetEnumName(TypeInfo(TEncoderStep), Ord(FProgressStep)), ' / ', FProgressPosition,
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

function TMainForm.GetFrameTileCount(AFrame: PFrame): Integer;
var
  Used: array of Boolean;
  i, j: Integer;
begin
  Result := 0;

  if Length(FTiles) = 0 then
    Exit;

  SetLength(Used, Length(FTiles));
  FillChar(Used[0], Length(FTiles) * SizeOf(Boolean), 0);

  for j := 0 to cTileMapHeight - 1 do
    for i := 0 to cTileMapWidth - 1 do
      Used[AFrame^.TileMap[j, i].GlobalTileIndex] := True;

  for i := 0 to High(Used) do
    Inc(Result, ifthen(Used[i], 1));
end;

procedure TMainForm.CopyTile(const Src: TTile; var Dest: TTile);
var x,y: Integer;
begin
  Dest.Active := Src.Active;
  Dest.TmpIndex := Src.TmpIndex;
  Dest.MergeIndex := Src.MergeIndex;
  Dest.UseCount := Src.UseCount;

  SetLength(Dest.PaletteIndexes, Length(Src.PaletteIndexes));
  SetLength(Dest.PaletteRGB, Length(Src.PaletteRGB));

  if Assigned(Dest.PaletteIndexes) then
    move(Src.PaletteIndexes[0], Dest.PaletteIndexes[0], Length(Src.PaletteIndexes) * SizeOf(Integer));
  if Assigned(Dest.PaletteRGB) then
    move(Src.PaletteRGB[0], Dest.PaletteRGB[0], Length(Src.PaletteRGB) * SizeOf(Integer));

  for y := 0 to cTileWidth - 1 do
    for x := 0 to cTileWidth - 1 do
    begin
      Dest.RGBPixels[y, x] := Src.RGBPixels[y, x];
      Dest.PalPixels[y, x] := Src.PalPixels[y, x];
    end;
end;

procedure TMainForm.MergeTiles(const TileIndexes: array of Integer; TileCount: Integer; BestIdx: Integer;
  NewTile: PPalPixels);
var
  j, k: Integer;
begin
  if TileCount <= 0 then
    Exit;

  if Assigned(NewTile) then
    Move(NewTile^[0, 0], FTiles[BestIdx]^.PalPixels[0, 0], sizeof(TPalPixels));

  for k := 0 to TileCount - 1 do
  begin
    j := TileIndexes[k];

    if j = BestIdx then
      Continue;

    Inc(FTiles[BestIdx]^.UseCount, FTiles[j]^.UseCount);

    FTiles[j]^.Active := False;
    FTiles[j]^.MergeIndex := BestIdx;

    FillChar(FTiles[j]^.RGBPixels, SizeOf(FTiles[j]^.RGBPixels), 0);
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
    for j := 0 to (CTileMapHeight - 1) do
      for i := 0 to (CTileMapWidth - 1) do
      begin
        idx := FTiles[FFrames[k].TileMap[j, i].GlobalTileIndex]^.MergeIndex;
        if idx >= 0 then
          FFrames[k].TileMap[j, i].GlobalTileIndex := idx;
      end;
end;

function TMainForm.GetMaxTPF(AKF: PKeyFrame): Integer;
var
  frame: Integer;
begin
  Result := 0;
  for frame := AKF^.StartFrame to AKF^.EndFrame do
    Result := Max(Result, GetFrameTileCount(@FFrames[frame]));
end;

function TMainForm.TestTMICount(PassX: TFloat; Data: Pointer): TFloat;
var
  PassDissim, MaxTPF, TPF, i, di, tmi, TrIdx, FrmIdx: Integer;
  ReducedIdxToDS: TIntegerDynArray;
  tmiO: TTileMapItem;
  Used: TBooleanDynArray;
  FTD: PFrameTilingData;
  KDT: PANNkdtree;
  DCT: TDoubleDynArray;
  ReducedDS: TDoubleDynArray2;
begin
  PassDissim := floor(PassX);
  FTD := PFrameTilingData(Data);

  SetLength(Used, Length(FTiles));

  if PassDissim < FTD^.MaxDissim then
  begin
    SetLength(ReducedDS, Length(FTD^.Dataset));
    SetLength(ReducedIdxToDS, Length(FTD^.Dataset));

    di := 0;
    for i := 0 to High(FTD^.Dataset) do
      if FTD^.TileBestDissim[i shr 1] >= PassDissim then
      begin
        ReducedDS[di] := FTD^.Dataset[i];
        ReducedIdxToDS[di] := i;
        Inc(di);
      end;

    SetLength(ReducedDS, di);
    SetLength(ReducedIdxToDS, di);
  end
  else
  begin
    ReducedDS := FTD^.Dataset;
    SetLength(ReducedIdxToDS, Length(FTD^.Dataset));
    for i := 0 to High(FTD^.Dataset) do
      ReducedIdxToDS[i] := i;
  end;

  KDT := ann_kdtree_create(PPDouble(ReducedDS), Length(ReducedDS), cTileDCTSize, 1, ANN_KD_STD);

  SetLength(DCT, cTileDCTSize);

  MaxTPF := 0;
  for FrmIdx := 0 to FTD^.KF^.FrameCount - 1 do
    if (FrmIdx = FTD^.KFFrmIdx) or (FTD^.KFFrmIdx < 0) then
    begin
      FillChar(Used[0], Length(FTiles), 0);

      for tmi := 0 to cTileMapSize - 1 do
      begin
        for i := 0 to cTileDCTSize - 1 do
          DCT[i] := FTD^.FrameDataset[FrmIdx * cTileMapSize + tmi, i];

        TrIdx := ReducedIdxToDS[ann_kdtree_search(KDT, PDouble(DCT), 0.0)];

        Assert(TrIdx >= 0);

        tmiO.GlobalTileIndex := FTD^.DsTMItem[TrIdx].GlobalTileIndex;
        tmiO.HMirror := FTD^.DsTMItem[TrIdx].HMirror;
        tmiO.VMirror := FTD^.DsTMItem[TrIdx].VMirror;
        tmiO.SpritePal := FTD^.DsTMItem[TrIdx].SpritePal;

        FTD^.OutputTMIs[FrmIdx * cTileMapSize + tmi] := tmiO;
        Used[tmiO.GlobalTileIndex] := True;
      end;

      TPF := 0;
      for i := 0 to High(Used) do
        Inc(TPF, Ord(Used[i]));

      MaxTPF := max(MaxTPF, TPF);
    end;

  ann_kdtree_destroy(KDT);

  EnterCriticalSection(FCS);
  WriteLn('KF FrmIdx: ', FTD^.KF^.StartFrame + max(0, FTD^.KFFrmIdx), #9'Itr: ', FTD^.Iteration, #9'MaxTPF: ', MaxTPF, #9'TileCnt: ', Length(ReducedDS));
  LeaveCriticalSection(FCS);

  Inc(FTD^.Iteration);

  Result := MaxTPF;
end;

procedure TMainForm.DoKeyFrameTiling(AFTD: PFrameTilingData);
var
  TRSize, di, i, frame, sy, sx, signi: Integer;
  frm: PFrame;
  spal, vmir, hmir: Boolean;
  dis: UInt64;
  pdis: PUInt64;

  Line: TByteDynArray;
  Dataset: TByteDynArray2;
  TileIndices: TIntegerDynArray;
begin
  AFTD^.MaxDissim := 0;
  SetLength(AFTD^.TileBestDissim, Length(FTiles) * 4);
  FillQWord(AFTD^.TileBestDissim[0], Length(AFTD^.TileBestDissim), 0);

  SetLength(AFTD^.TileUseCount, Length(FTiles));
  FillDWord(AFTD^.TileUseCount[0], Length(FTiles), 0);

  SetLength(Line, cKModesFeatureCount);
  SetLength(Dataset, Length(FTiles), cKModesFeatureCount);
  SetLength(TileIndices, Length(FTiles));
  di := 0;
  for i := 0 to High(FTiles) do
  begin
    if not FTiles[i]^.Active then
      Continue;

    WriteTileDatasetLine(FTiles[i]^, Dataset[di], signi);
    TileIndices[di] := i;
    Inc(di);
  end;
  SetLength(Dataset, di);
  SetLength(TileIndices, di);

  for frame := 0 to AFTD^.KF^.FrameCount - 1 do
  begin
    frm := @FFrames[AFTD^.KF^.StartFrame + frame];
    for sy := 0 to cTileMapHeight - 1 do
      for sx := 0 to cTileMapWidth - 1 do
        for hmir := False to True do
        begin
          if hmir then HMirrorPalTile(FTiles[frm^.TileMap[sy, sx].GlobalTileIndex]^);

          for vmir := False to True do
          begin
            if vmir then VMirrorPalTile(FTiles[frm^.TileMap[sy, sx].GlobalTileIndex]^);
            WriteTileDatasetLine(FTiles[frm^.TileMap[sy, sx].GlobalTileIndex]^, Line, signi);
            if vmir then VMirrorPalTile(FTiles[frm^.TileMap[sy, sx].GlobalTileIndex]^);

            GetMinMatchingDissim(Dataset, Line, Length(Dataset), dis);

            pdis := @AFTD^.TileBestDissim[(frm^.TileMap[sy, sx].GlobalTileIndex shl 2) or (Ord(hmir) shl 1) or (Ord(vmir) shl 0)];

            pdis^ += dis;
            if pdis^ > AFTD^.MaxDissim then
              AFTD^.MaxDissim := pdis^;

            Inc(AFTD^.TileUseCount[frm^.TileMap[sy, sx].GlobalTileIndex]);
          end;

          if hmir then HMirrorPalTile(FTiles[frm^.TileMap[sy, sx].GlobalTileIndex]^);
        end;
  end;

  // make a list of all used tiles
  SetLength(AFTD^.FrameDataset, AFTD^.KF^.FrameCount * cTileMapSize, cTileDCTSize);

  di := 0;
  for frame := 0 to AFTD^.KF^.FrameCount - 1 do
  begin
    frm := @FFrames[AFTD^.KF^.StartFrame + frame];
    for sy := 0 to cTileMapHeight - 1 do
      for sx := 0 to cTileMapWidth - 1 do
      begin
{$if cKFFromPal}
        ComputeTileDCT(FTiles[frm^.TileMap[sy, sx].GlobalTileIndex]^, cKFFromPal, cKFQWeighting, False, False, cKFGamma, frm^.KeyFrame^.PaletteRGB[frm^.TileMap[sy, sx].SpritePal], AFTD^.FrameDataset[di]);
{$else}
        ComputeTileDCT(frm^.Tiles[sy * cTileMapWidth + sx], False, cKFQWeighting, False, False, cKFGamma, nil, AFTD^.FrameDataset[di]);
{$endif}
        Inc(di);
      end;
  end;

  Assert(di = AFTD^.KF^.FrameCount * cTileMapSize);

  TRSize := Length(FTiles) * 8;
  SetLength(AFTD^.DsTMItem, TRSize);
  SetLength(AFTD^.Dataset, TRSize, cTileDCTSize);

  di := 0;
  for i := 0 to High(FTiles) do
  begin
    if not FTiles[i]^.Active then
      Continue;

    for hmir := False to True do
      for vmir := False to True do
        for spal := False to True do
        begin
          ComputeTileDCT(FTiles[i]^, True, cKFQWeighting, hmir, vmir, cKFGamma, AFTD^.KF^.PaletteRGB[spal], AFTD^.Dataset[di]);

          AFTD^.DsTMItem[di].GlobalTileIndex := i;
          AFTD^.DsTMItem[di].VMirror := vmir;
          AFTD^.DsTMItem[di].HMirror := hmir;
          AFTD^.DsTMItem[di].SpritePal := spal;

          Inc(di);
        end;
  end;

  SetLength(AFTD^.DsTMItem, di);
  SetLength(AFTD^.Dataset, di);

  EnterCriticalSection(FCS);
  WriteLn('KF FrmIdx: ',AFTD^.KF^.StartFrame, #9'FullRepo: ', TRSize, #9'ActiveRepo: ', Length(AFTD^.Dataset), #9'MaxDissim: ', AFTD^.MaxDissim);
  LeaveCriticalSection(FCS);
end;

procedure TMainForm.DoFrameTiling(AKF: PKeyFrame; DesiredNbTiles: Integer);
const
  cNBTilesEpsilon = 1;
var
  FrmIdx, sy, sx, i: Integer;
  FTD: PFrameTilingData;
  tmiO, tmiI: PTileMapItem;
begin
  FTD := New(PFrameTilingData);
  try
    FTD^.KF := AKF;
    FTD^.KFFrmIdx := -1;
    FTD^.Iteration := 0;
    FTD^.DesiredNbTiles := DesiredNbTiles;
    SetLength(FTD^.OutputTMIs, AKF^.FrameCount * cTileMapSize);

    DoKeyFrameTiling(FTD);

    // search of PassTileCount that gives MaxTPF closest to DesiredNbTiles

    if FExtendedFrmTiling then
    begin
      for i := 0 to AKF^.FrameCount - 1 do
      begin
        FTD^.Iteration := 0;
        FTD^.KFFrmIdx := i;
        if TestTMICount(FTD^.MaxDissim, FTD) > DesiredNbTiles then // no GR in case ok before reducing
          GoldenRatioSearch(@TestTMICount, FTD^.MaxDissim, 0, DesiredNbTiles - cNBTilesEpsilon, cNBTilesEpsilon, FTD);
      end;
    end
    else
    begin
      if TestTMICount(FTD^.MaxDissim, FTD) > DesiredNbTiles then // no GR in case ok before reducing
        GoldenRatioSearch(@TestTMICount, FTD^.MaxDissim, 0, DesiredNbTiles - cNBTilesEpsilon, cNBTilesEpsilon, FTD);
    end;

    // update tilemap

    for FrmIdx := 0 to AKF^.FrameCount - 1 do
      for sy := 0 to cTileMapHeight - 1 do
        for sx := 0 to cTileMapWidth - 1 do
        begin
          tmiO := @FFrames[FrmIdx + AKF^.StartFrame].TileMap[sy, sx];
          tmiI := @FTD^.OutputTMIs[FrmIdx * cTileMapSize + sy * cTileMapWidth + sx];

          tmiO^.GlobalTileIndex := tmiI^.GlobalTileIndex;
          tmiO^.SpritePal := tmiI^.SpritePal;
          tmiO^.VMirror := tmiI^.VMirror;
          tmiO^.HMirror := tmiI^.HMirror;
        end;
  finally
    Dispose(FTD);
  end;
end;

procedure TMainForm.DoTemporalSmoothing(AFrame, APrevFrame: PFrame; Y: Integer; Strength: TFloat);
const
  cSqrtFactor = 1 / (sqr(cTileWidth) * 3);
var
  sx: Integer;
  cmp: TFloat;
  TMI, PrevTMI: PTileMapItem;
  Tile_, PrevTile: PTile;
  TileDCT, PrevTileDCT: TFloatDynArray;
begin
  if AFrame^.KeyFrame <> APrevFrame^.KeyFrame then
    Exit;

  SetLength(PrevTileDCT, cTileDCTSize);
  SetLength(TileDCT, cTileDCTSize);

  for sx := 0 to cTileMapWidth - 1 do
  begin
    PrevTMI := @APrevFrame^.TileMap[Y, sx];
    TMI := @AFrame^.TileMap[Y, sx];

    if PrevTMI^.FrameTileIndex >= Length(AFrame^.TilesIndexes) then
      Continue;

    // compare DCT of current tile with tile from prev frame tilemap

    PrevTile := FTiles[AFrame^.TilesIndexes[PrevTMI^.FrameTileIndex]];
    Tile_ := FTiles[AFrame^.TilesIndexes[TMI^.FrameTileIndex]];

    ComputeTileDCT(PrevTile^, True, True, PrevTMI^.HMirror, PrevTMI^.VMirror, cGammaCorrectSmoothing, AFrame^.KeyFrame^.PaletteRGB[PrevTMI^.SpritePal], PrevTileDCT);
    ComputeTileDCT(Tile_^, True, True, TMI^.HMirror, TMI^.VMirror, cGammaCorrectSmoothing, AFrame^.KeyFrame^.PaletteRGB[TMI^.SpritePal], TileDCT);

    cmp := CompareEuclidean192(TileDCT, PrevTileDCT);
    cmp := sqrt(cmp * cSqrtFactor);

    // if difference is low enough, mark the tile as smoothed for tilemap compression use

    if Abs(cmp) <= Strength then
    begin
      TMI^.GlobalTileIndex := AFrame^.TilesIndexes[PrevTMI^.FrameTileIndex];
      TMI^.FrameTileIndex := PrevTMI^.FrameTileIndex;
      TMI^.HMirror := PrevTMI^.HMirror;
      TMI^.VMirror := PrevTMI^.VMirror;
      TMI^.SpritePal := PrevTMI^.SpritePal;
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
    for sy := 0 to cTileMapHeight - 1 do
      for sx := 0 to cTileMapWidth - 1 do
        Inc(Result, Ord(FFrames[i].TileMap[sy, sx].GlobalTileIndex = ATileIndex));
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
      Inc(acc[b * ZoneCount div cTilePaletteSize]);
    end;

  Result := sqr(cTileWidth);
  for i := 0 to ZoneCount - 1 do
  begin
    Result := Min(Result, sqr(cTileWidth) - acc[i]);
    signi := acc[i] > (cTilePaletteSize div ZoneCount);
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

  PalSigni := GetTilePalZoneThres(ATile, 8, @DataLine[Result]);
  Inc(Result, 16);

  Assert(Result = cKModesFeatureCount);
end;

procedure TMainForm.DoGlobalTiling(DesiredNbTiles, RestartCount: Integer);
var
  Dataset: TByteDynArray2;
  TileIndices: TIntegerDynArray;
  StartingPoint: Integer;

  procedure DoKModes;
  var
    KModes: TKModes;
    LocCentroids: TByteDynArray2;
    LocClusters: TIntegerDynArray;
    i, j, di, DSLen: Integer;
    ActualNbTiles: Integer;
    ToMerge: TByteDynArray2;
    ToMergeIdxs: TIntegerDynArray;
    dis: UInt64;
  begin
    DSLen := Length(Dataset);

    if DSLen <= DesiredNbTiles then
      Exit;

    KModes := TKModes.Create(0, 0, True);
    try
      ActualNbTiles := KModes.ComputeKModes(Dataset, DesiredNbTiles, -StartingPoint, cTilePaletteSize, LocClusters, LocCentroids);
      Assert(Length(LocCentroids) = ActualNbTiles);
      Assert(MaxIntValue(LocClusters) = ActualNbTiles - 1);
    finally
      KModes.Free;
    end;

    SetLength(ToMerge, DSLen);
    SetLength(ToMergeIdxs, DSLen);

    // build a list of this centroid tiles

    for j := 0 to ActualNbTiles - 1 do
    begin
      di := 0;
      for i := 0 to High(TileIndices) do
      begin
        if LocClusters[i] = j then
        begin
          ToMerge[di] := Dataset[i];
          ToMergeIdxs[di] := TileIndices[i];
          Inc(di);
        end;
      end;

      // choose a tile from the centroids

      if di >= 2 then
      begin
        i := GetMinMatchingDissim(ToMerge, LocCentroids[j], di, dis);
        MergeTiles(ToMergeIdxs, di, ToMergeIdxs[i], nil);
      end;
    end;
  end;

var
  acc, i, j, signi: Integer;
  dis: Integer;
  best: Integer;
begin
  SetLength(Dataset, Length(FTiles), cKModesFeatureCount);
  SetLength(TileIndices, Length(FTiles));

  // prepare KModes dataset, one line per tile, 64 palette indexes per line
  // also choose KModes starting point

  dis := 0;
  StartingPoint := -RestartCount;
  best := MaxInt;
  for i := 0 to High(FTiles) do
  begin
    if not FTiles[i]^.Active then
      Continue;

    WriteTileDatasetLine(FTiles[i]^, Dataset[dis], signi);

    TileIndices[dis] := i;

    acc := 0;
    for j := 0 to cKModesFeatureCount - 1 do
      acc += Dataset[dis, j];

    if acc <= best then
    begin
      StartingPoint := dis;
      best := acc;
    end;

    Inc(dis);
  end;

  SetLength(Dataset, dis);
  SetLength(TileIndices, dis);

  InitMergeTiles;

  ProgressRedraw(1);

  // run the KModes algorithm, which will group similar tiles until it reaches a fixed amount of groups

  DoKModes;

  ProgressRedraw(2);

  FinishMergeTiles;

  ProgressRedraw(3);

  // put most probable tiles first

  ReindexTiles;

  ProgressRedraw(4);
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
    for y := 0 to (cTileMapHeight - 1) do
      for x := 0 to (cTileMapWidth - 1) do
        FFrames[i].TileMap[y,x].GlobalTileIndex := IdxMap[FFrames[i].TileMap[y,x].GlobalTileIndex];
end;

function CompareTilesIndexes(Item1, Item2, UserParameter:Pointer):Integer;
begin
  Result := CompareValue(PInteger(Item1)^, PInteger(Item2)^);
end;

procedure TMainForm.IndexFrameTiles(AFrame: PFrame);
var
  x, y, i, cnt, UseCount: Integer;
begin
  // build a list of tiles indexes used by the frame

  SetLength(AFrame^.TilesIndexes, cTileMapSize);

  cnt := 0;
  for i := 0 to High(FTiles) do
    if FTiles[i]^.Active then
    begin
      UseCount := 0;
      for y := 0 to (cTileMapHeight - 1) do
        for x := 0 to (cTileMapWidth - 1) do
          if AFrame^.TileMap[y, x].GlobalTileIndex = i then
          begin
            AFrame^.TilesIndexes[cnt] := i;
            Inc(UseCount);
          end;

      if UseCount <> 0 then
        Inc(cnt);
    end;

  SetLength(AFrame^.TilesIndexes, cnt);

  // sort it

  QuickSort(AFrame^.TilesIndexes[0], 0, High(AFrame^.TilesIndexes), SizeOf(AFrame^.TilesIndexes[0]), @CompareTilesIndexes);

  // point tilemap on those indexes

  for i := 0 to High(AFrame^.TilesIndexes) do
    for y := 0 to (cTileMapHeight - 1) do
      for x := 0 to (cTileMapWidth - 1) do
        if AFrame^.TileMap[y, x].GlobalTileIndex = AFrame^.TilesIndexes[i] then
          AFrame^.TileMap[y, x].FrameTileIndex := i;
end;

function TMainForm.DoExternalPCMEnc(AFN: String; Volume: Integer): String;
var
  i: Integer;
  Output, ErrOut: String;
  Process: TProcess;
begin
  Process := TProcess.Create(nil);

  Process.CurrentDirectory := ExtractFilePath(ParamStr(0));
  Process.Executable := 'pcmenc.exe';
  Process.Parameters.Add('-p 4 -dt1 ' + IntToStr(cClocksPerSample) + ' -dt2 ' + IntToStr(cClocksPerSample) + ' -dt3 ' +
    IntToStr(cClocksPerSample) + ' -cpuf ' + IntToStr(cZ80Clock) + ' -rto 3 -a ' + IntToStr(Volume) + ' -r 4096 -precision 8 -smooth 10 "' + AFN + '"');
  Process.ShowWindow := swoHIDE;
  Process.Priority := ppIdle;

  i := 0;
  internalRuncommand(Process, Output, ErrOut, i); // destroys Process

  Result := AFN + '.pcmenc';
end;

procedure TMainForm.SaveTileIndexes(ADataStream: TStream; AFrame: PFrame);
var
  j, prevTileIndex, diffTileIndex, prevDTI, sameCount, tiZ80Cycles: Integer;
  tiVBlank, vbl: Boolean;
  tileIdxStream: TMemoryStream;

  function CurrentLineJitter: Integer;
  begin
    Result := round(IfThen(tiVBlank, -cLineJitterCompensation * cCyclesPerLine, cLineJitterCompensation * cCyclesPerLine));
  end;

  procedure CountZ80Cycles(ACycleAdd: Integer);
  var
    cyPh: Integer;
  begin
    cyPh := cCyclesPerDisplayPhase[tiVBlank];
    tiZ80Cycles += ACycleAdd;
    if tiZ80Cycles > cyPh + CurrentLineJitter then
    begin
      tiZ80Cycles -= cyPh;
      tiVBlank := not tiVBlank;
      tileIdxStream.WriteByte(cTileIndexesVBlankSwitch);
      tiZ80Cycles += cTileIndexesTimings[tiVBlank, 4];
    end;
  end;

  procedure DoTileIndex;
  var
    priorCount, cyAdd: Integer;
    vbl: Boolean;
  begin
    vbl := tiVBlank;
    if sameCount = 1 then
    begin
      if vbl then
        CountZ80Cycles(cTileIndexesTimings[tiVBlank, 1]);
      tileIdxStream.WriteByte(prevDTI - 1);
      if not vbl then
        CountZ80Cycles(cTileIndexesTimings[tiVBlank, 1]);
    end
    else if sameCount <> 0 then
    begin
      // split upload in case we need to switch VBlank in the midlde of it
      priorCount := sameCount;
      cyAdd := cTileIndexesTimings[tiVBlank, 2] + priorCount * cTileIndexesTimings[tiVBlank, 3];

      while (tiZ80Cycles + cyAdd > cCyclesPerDisplayPhase[tiVBlank] + CurrentLineJitter) and (priorCount > 0) do
      begin
        Dec(priorCount);
        cyAdd := cTileIndexesTimings[tiVBlank, 2] + priorCount * cTileIndexesTimings[tiVBlank, 3];
      end;

      // compute cycles
      cyAdd := cTileIndexesTimings[tiVBlank, 2] + priorCount * cTileIndexesTimings[tiVBlank, 3] +
               cTileIndexesTimings[not tiVBlank, 2] + (sameCount - priorCount) * cTileIndexesTimings[not tiVBlank, 3];

      // in case we need to switch VBlank in the middle of the upload, add one more tile in "slow" not VBlank state
      if tiZ80Cycles + cyAdd > cCyclesPerDisplayPhase[tiVBlank] + CurrentLineJitter then
      begin
        if (priorCount > 0) and tiVBlank then
        begin
          Dec(priorCount);
          cyAdd -= cTileIndexesTimings[tiVBlank, 3];
          cyAdd += cTileIndexesTimings[not tiVBlank, 3];
        end
        else if (priorCount < sameCount) and not tiVBlank then
        begin
          Inc(priorCount);
          cyAdd += cTileIndexesTimings[tiVBlank, 3];
          cyAdd -= cTileIndexesTimings[not tiVBlank, 3];
        end;
      end;

      // if we output only one command, only one fixed cost should have been added
      if priorCount = 0 then
        cyAdd -= cTileIndexesTimings[tiVBlank, 2]
      else if priorCount = sameCount then
        cyAdd -= cTileIndexesTimings[not tiVBlank, 2];

      if priorCount > 0 then
        tileIdxStream.WriteByte(cTileIndexesRepeatStart + priorCount - 1);

      CountZ80Cycles(cyAdd);

      if sameCount - priorCount > 0 then
        tileIdxStream.WriteByte(cTileIndexesRepeatStart + sameCount - priorCount - 1);
    end;
  end;

begin
  tileIdxStream := TMemoryStream.Create;
  try
    tiZ80Cycles :=  Round((cTileIndexesInitialLine - cScreenHeight) * cCyclesPerLine);
    tiVBlank := True;

    prevTileIndex := -1;
    prevDTI := -1;
    sameCount := 0;
    for j := 0 to High(AFrame^.TilesIndexes) do
    begin
      diffTileIndex := AFrame^.TilesIndexes[j] - prevTileIndex;

      if (diffTileIndex <> 1) or (diffTileIndex <> prevDTI) or
          (diffTileIndex >= cTileIndexesMaxDiff) or (sameCount >= cTileIndexesMaxRepeat) or
          ((AFrame^.TilesIndexes[j] + cTileIndexesTileOffset) mod cTilesPerBank = 0) then // don't change bank while repeating
      begin
        DoTileIndex;
        sameCount := 1;
      end
      else
      begin
        Inc(sameCount);
      end;

      if (prevTileIndex = -1) or (diffTileIndex >= cTileIndexesMaxDiff) or (diffTileIndex < 0) or
          ((AFrame^.TilesIndexes[j] + cTileIndexesTileOffset) div cTilesPerBank <>
           (prevTileIndex + cTileIndexesTileOffset) div cTilesPerBank) then // any bank change must be a direct value
      begin
        vbl := tiVBlank;
        if vbl then
          CountZ80Cycles(cTileIndexesTimings[tiVBlank, 0]);

        tileIdxStream.WriteByte(cTileIndexesDirectValue);
        tileIdxStream.WriteWord(AFrame^.TilesIndexes[j] + cTileIndexesTileOffset);

        if not vbl then
          CountZ80Cycles(cTileIndexesTimings[tiVBlank, 0]);

        diffTileIndex := -1;
        sameCount := 0;
      end;

      prevTileIndex := AFrame^.TilesIndexes[j];
      prevDTI := diffTileIndex;
    end;

    DoTileIndex;
    tileIdxStream.WriteByte(cTileIndexesTerminator);
    tileIdxStream.WriteByte(cMaxTilesPerFrame - Length(AFrame^.TilesIndexes));

    // the whole tiles indices should stay in the same bank
    if ADataStream.Size div cBankSize <> (ADataStream.Size + tileIdxStream.Size) div cBankSize then
    begin
      ADataStream.WriteByte(1);
      while ADataStream.Size mod cBankSize <> 0 do
        ADataStream.WriteByte(0);
      DebugLn('Crossed bank limit!');
    end
    else
    begin
      ADataStream.WriteByte(0);
    end;

    tileIdxStream.Position := 0;
    ADataStream.CopyFrom(tileIdxStream, tileIdxStream.Size);

  finally
    tileIdxStream.Free;
  end;
end;

function CompareTMICache(Item1,Item2,UserParameter:Pointer):Integer;
begin
  Result := CompareValue(PInteger(Item2)^, PInteger(Item1)^);
end;

procedure TMainForm.SaveTilemap(ADataStream: TStream; AFrame: PFrame; AFrameIdx: Integer; ASkipFirst: Boolean);
var
  j, k, x, y, skipCount: Integer;
  rawTMI, tmiCacheIdx, awaitingCacheIdx, awaitingCount: Integer;
  smoothed: Boolean;
  tmi: PTileMapItem;
  rawTMIs: array[0..cTileMapSize] of Integer;
  tmiCache: array[0..4095] of packed record
    UsedCount: Integer;
    RawTMI: Integer;
  end;

  procedure DoTilemapTileCommand(DoCache, DoSkip: Boolean);
  begin
    if DoSkip and (skipCount > 0) then
    begin
      ADataStream.WriteByte(cTileMapCommandSkip or (skipCount shl 1));
      skipCount := 0;
    end;

    if DoCache and (awaitingCacheIdx <> cTileMapCacheSize) then
      if awaitingCacheIdx < 0 then
      begin
        ADataStream.WriteByte(cTileMapCommandRaw[awaitingCount] or ((-awaitingCacheIdx) shr 8));
        ADataStream.WriteByte((-awaitingCacheIdx) and $ff);
      end
      else
      begin
        ADataStream.WriteByte(cTileMapCommandCache[awaitingCount] or (awaitingCacheIdx shl 1));
      end;
  end;

begin
  for j := 0 to High(tmiCache) do
  begin
    tmiCache[j].UsedCount := 0;
    tmiCache[j].RawTMI := j;
  end;

  for y := 0 to cTileMapHeight - 1 do
    for x := 0 to cTileMapWidth - 1 do
    begin
      tmi := @AFrame^.TileMap[y, x];
      rawTMI := (tmi^.FrameTileIndex + cTileMapIndicesOffset[AFrameIdx and 1]) and $1ff;
      if tmi^.HMirror then rawTMI := rawTMI or $200;
      if tmi^.VMirror then rawTMI := rawTMI or $400;
      if tmi^.SpritePal then rawTMI := rawTMI or $800;
      rawTMIs[x + y * cTileMapWidth] := rawTMI;
      Inc(tmiCache[rawTMI].UsedCount);
    end;

  QuickSort(tmiCache[0], 0, High(tmiCache), SizeOf(tmiCache[0]), @CompareTMICache);

  for j := 0 to cTileMapCacheSize div 2 - 1 do
  begin
    k := j * 2;

    // 2:3 compression: high nibble b / high nibble a / low byte a / low byte b
    ADataStream.WriteByte(((tmiCache[k + 1].RawTMI shr 8) shl 4) or (tmiCache[k].RawTMI shr 8));
    ADataStream.WriteByte(tmiCache[k].RawTMI and $ff);
    ADataStream.WriteByte(tmiCache[k + 1].RawTMI and $ff);
  end;

  awaitingCacheIdx := cTileMapCacheSize;
  awaitingCount := 0;
  skipCount := 0;
  for j := 0 to cTileMapSize - 1 do
  begin
    smoothed := AFrame^.TileMap[j div cTileMapWidth, j mod cTileMapWidth].Smoothed;
    rawTMI := rawTMIs[j];

    tmiCacheIdx := -1;
    for k := 0 to cTileMapCacheSize -1 do
      if tmiCache[k].RawTMI = rawTMI then
      begin
        tmiCacheIdx := k;
        Break;
      end;
    if tmiCacheIdx = -1  then
      tmiCacheIdx := -rawTMI;

    if ASkipFirst then
    begin
      if smoothed and (skipCount < cTileMapMaxSkip) then
      begin
        DoTilemapTileCommand(True, False);

        Inc(skipCount);

        awaitingCacheIdx := cTileMapCacheSize;
        awaitingCount := 0;
      end
      else
      begin
        DoTilemapTileCommand(False, True);

        if tmiCacheIdx = awaitingCacheIdx then
        begin
          Inc(awaitingCount);

          if awaitingCount >= cTileMapMaxRepeat[awaitingCacheIdx < 0] then
          begin
            DoTilemapTileCommand(True, False);

            awaitingCacheIdx := cTileMapCacheSize;
            awaitingCount := 0;
          end;
        end
        else
        begin
          DoTilemapTileCommand(True, False);

          awaitingCacheIdx := tmiCacheIdx;
          awaitingCount := 1;
        end;
      end;
    end
    else
    begin
      if tmiCacheIdx = awaitingCacheIdx then
      begin
        Inc(awaitingCount);

        if awaitingCount >= cTileMapMaxRepeat[awaitingCacheIdx < 0] then
        begin
          DoTilemapTileCommand(True, False);

          awaitingCacheIdx := cTileMapCacheSize;
          awaitingCount := 0;
        end;
      end
      else
      begin
        DoTilemapTileCommand(True, False);

        if smoothed and (skipCount < cTileMapMaxSkip) then
        begin
          Inc(skipCount);

          awaitingCacheIdx := cTileMapCacheSize;
          awaitingCount := 0;
        end
        else
        begin
          DoTilemapTileCommand(False, True);

          awaitingCacheIdx := tmiCacheIdx;
          awaitingCount := 1;
        end;
      end;
    end;
  end;

  DoTilemapTileCommand(True, True);

  ADataStream.WriteByte(cTileMapTerminator);
end;

procedure TMainForm.Save(ADataStream, ASoundStream: TStream);
var pp, pp2, i, j, x, y, frameStart: Integer;
    palpx: Byte;
    prevKF: PKeyFrame;
    SkipFirst, b: Boolean;
    tilesPlanes: array[0..cTileWidth - 1, 0..3] of Byte;
    TMStream: array[Boolean] of TMemoryStream;
begin
  // leave the size of one tile for index

  for x := 0 to cTileWidth - 1 do
    ADataStream.WriteDWord(0);

  // tiles

  for i := 0 to High(FTiles) do
  begin
    FillByte(tilesPlanes[0, 0], Sizeof(tilesPlanes), 0);
    for y := 0 to cTileWidth - 1 do
    begin
      for x := 0 to cTileWidth - 1 do
      begin
        palpx := FTiles[i]^.PalPixels[y, x];
        tilesPlanes[y, 0] := tilesPlanes[y, 0] or (((palpx and 1) shl 7) shr x);
        tilesPlanes[y, 1] := tilesPlanes[y, 1] or (((palpx and 2) shl 6) shr x);
        tilesPlanes[y, 2] := tilesPlanes[y, 2] or (((palpx and 4) shl 5) shr x);
        tilesPlanes[y, 3] := tilesPlanes[y, 3] or (((palpx and 8) shl 4) shr x);
      end;
      for x := 0 to 3 do
        ADataStream.WriteByte(tilesPlanes[y, x]);
    end;
  end;

  DebugLn(['Total tiles size:'#9, ADataStream.Position]);
  pp2 := ADataStream.Position;

  // index

  frameStart := ADataStream.Position + cBankSize;
  i := ADataStream.Position;
  ADataStream.Position := 0;
  ADataStream.WriteWord(Length(FFrames));
  ADataStream.WriteWord(frameStart div cBankSize);
  ADataStream.WriteWord(frameStart mod cBankSize);
  ADataStream.Position := i;

  prevKF := nil;
  for i := 0 to High(FFrames) do
  begin
    // palette

    if FFrames[i].KeyFrame <> prevKF then
    begin
      ADataStream.WriteByte(cTilePaletteSize * 2);
      for b := False to True do
        for j := 0 to cTilePaletteSize - 1 do
          ADataStream.WriteByte(FFrames[i].KeyFrame^.PaletteIndexes[b, j]);
    end
    else
    begin
      ADataStream.WriteByte(0);
    end;

    // tiles indexes

    pp := ADataStream.Position;
    SaveTileIndexes(ADataStream, @FFrames[i]);
    //DebugLn(['TileIndexes size: ', ADataStream.Position - pp]);

    // tilemap

    for SkipFirst := False to True do
    begin
      TMStream[SkipFirst] := TMemoryStream.Create;
      SaveTileMap(TMStream[SkipFirst], @FFrames[i], i, SkipFirst);
      //DebugLn(['TM size: ', TMStream[SkipFirst].Size, ' ', SkipFirst]);
    end;

    SkipFirst := True;
    if TMStream[SkipFirst].Size > TMStream[not SkipFirst].Size then
      SkipFirst := not SkipFirst;

    TMStream[SkipFirst].Position := 0;
    ADataStream.CopyFrom(TMStream[SkipFirst], TMStream[SkipFirst].Size);

    for SkipFirst := False to True do
      TMStream[SkipFirst].Free;

    // sound

    if Assigned(ASoundStream) then
    begin
      ASoundStream.Position := 2 + Floor(cFrameSoundSize * i);
      ADataStream.CopyFrom(ASoundStream, Ceil(cFrameSoundSize));
    end;

    prevKF := FFrames[i].KeyFrame;
  end;

  DebugLn(['Total frames size:'#9, ADataStream.Position - pp2]);

  DebugLn(['Total unpadded size:'#9, ADataStream.Position]);

  while (ADataStream.Position + cBankSize) mod (cBankSize * 4) <> 0 do
    ADataStream.WriteByte($ff);

  DebugLn(['Total padded size:'#9, ADataStream.Position]);
end;

procedure TMainForm.FormCreate(Sender: TObject);
var
  r,g,b,i,mx,mn,col,prim_col,sr: Integer;
begin
  FLowMem := True;

  InitializeCriticalSection(FCS);

  FormatSettings.DecimalSeparator := '.';

{$ifdef DEBUG}
  ProcThreadPool.MaxThreadCount := 1;
  btnDebug.Visible := True;
{$else}
  SetPriorityClass(GetCurrentProcess(), IDLE_PRIORITY_CLASS);
{$endif}

  imgSource.Picture.Bitmap.Width:=cScreenWidth;
  imgSource.Picture.Bitmap.Height:=cScreenHeight;
  imgSource.Picture.Bitmap.PixelFormat:=pf32bit;

  imgDest.Picture.Bitmap.Width:=cScreenWidth;
  imgDest.Picture.Bitmap.Height:=cScreenHeight * 2;
  imgDest.Picture.Bitmap.PixelFormat:=pf32bit;

  imgTiles.Picture.Bitmap.Width:=cScreenWidth;
  imgTiles.Picture.Bitmap.Height:=cScreenHeight * 2;
  imgTiles.Picture.Bitmap.PixelFormat:=pf32bit;

  imgPalette.Picture.Bitmap.Width := cScreenWidth;
  imgPalette.Picture.Bitmap.Height := 32;
  imgPalette.Picture.Bitmap.PixelFormat:=pf32bit;

  cbxYilMixChange(nil);
  chkUseTKChange(nil);
  chkExtFTChange(nil);

  sr := (1 shl cBitsPerComp) - 1;

  for i := 0 to cTotalColors - 1 do
  begin
    col :=
       ((((i shr (cBitsPerComp * 0)) and sr) * 255 div sr) and $ff) or //R
      (((((i shr (cBitsPerComp * 1)) and sr) * 255 div sr) and $ff) shl 8) or //G
      (((((i shr (cBitsPerComp * 2)) and sr) * 255 div sr) and $ff) shl 16);  //B

    prim_col :=
      (((i shr 1) and 1) * 255) or //R
      ((((i shr 3) and 1) * 255) shl 8) or //G
      ((((i shr 5) and 1) * 255) shl 16);  //B

    FColorMap[i] := col;
    FColorMapImportance[i] := Ord(col = prim_col);
  end;

  for i := 0 to cTotalColors - 1 do
  begin
    col := FColorMap[i];
    r := col and $ff;
    g := (col shr 8) and $ff;
    b := col shr 16;

    FColorMapLuma[i] := (r*cRedMultiplier + g*cGreenMultiplier + b*cBlueMultiplier) div cLumaMultiplier;

    mx := MaxIntValue([r, g, b]);
    mn := MinIntValue([r, g, b]);

    if r = mx then FColorMapHue[i] := iDiv0((g - b) shl 7, mx - mn);
    if g = mx then FColorMapHue[i] := iDiv0((b - r) shl 7, mx - mn);
    if b = mx then FColorMapHue[i] := iDiv0((r - g) shl 7, mx - mn);
  end;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  DeleteCriticalSection(FCS);

  ClearAll;
end;

initialization
  InitLuts;
end.

