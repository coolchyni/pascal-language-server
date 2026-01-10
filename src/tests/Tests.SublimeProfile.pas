unit Tests.SublimeProfile;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, fpjson, jsonparser,
  CodeToolManager, CodeCache,
  PasLS.Symbols, PasLS.Settings;

type

  { TTestSublimeProfile }

  TTestSublimeProfile = class(TTestCase)
  private
    FTestFile: String;
    FTestCode: TCodeBuffer;
    procedure CreateTestFile(const AContent: String);
    procedure CleanupTestFile;
    function GetSymbolNames(const RawJSON: String): TStringList;
    function HasSymbol(const Names: TStringList; const SymbolName: String): Boolean;
    function CountSymbol(const Names: TStringList; const SymbolName: String): Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestFlatModeHasLocation;
    procedure TestFlatModeNoChildren;
    procedure TestFlatModeMethodNaming;
    procedure TestFlatModeNoContainerName;
    procedure TestNoInterfaceContainer;
    procedure TestNoImplementationContainer;
    procedure TestClassesAtTopLevel;
    procedure TestNoInterfaceMethodDecls;
    procedure TestPreservesInterfaceClassDefs;
    procedure TestNoInterfaceGlobalFuncDecl;
    procedure TestNoImplClassDefs;
    procedure TestNoDuplicateClasses;
    procedure TestNoForwardDeclarations;
    procedure TestImplClassMethodsPreserved;
    procedure TestCompareWithDefault;
    procedure TestGlobalFuncPreserved;
    procedure TestNestedProcPreserved;
  end;

implementation

const
  TEST_SUBLIME_UNIT =
    'unit TestUnit;' + LineEnding +
    '' + LineEnding +
    '{$mode objfpc}{$H+}' + LineEnding +
    '' + LineEnding +
    'interface' + LineEnding +                           // line 4
    '' + LineEnding +
    'type' + LineEnding +
    '  TForward = class;' + LineEnding +                 // line 7: forward declaration
    '' + LineEnding +
    '  TMyClass = class' + LineEnding +                  // line 9
    '    procedure MethodA;' + LineEnding +              // line 10
    '    function MethodB: Integer;' + LineEnding +      // line 11
    '  end;' + LineEnding +
    '' + LineEnding +
    '  TMyRecord = record' + LineEnding +                // line 14
    '    Field1: Integer;' + LineEnding +
    '  end;' + LineEnding +
    '' + LineEnding +
    'function GlobalFunc: Boolean;' + LineEnding +       // line 18
    '' + LineEnding +
    'implementation' + LineEnding +                      // line 20
    '' + LineEnding +
    'type' + LineEnding +
    '  TImplOnlyClass = class' + LineEnding +            // line 23: impl-only class
    '    procedure ImplMethod;' + LineEnding +
    '  end;' + LineEnding +
    '' + LineEnding +
    '{ TMyClass }' + LineEnding +
    '' + LineEnding +
    'procedure TMyClass.MethodA;' + LineEnding +         // line 29
    '' + LineEnding +
    '  procedure NestedProc;' + LineEnding +             // line 31
    '  begin' + LineEnding +
    '  end;' + LineEnding +
    '' + LineEnding +
    'begin' + LineEnding +
    '  NestedProc;' + LineEnding +
    'end;' + LineEnding +
    '' + LineEnding +
    'function TMyClass.MethodB: Integer;' + LineEnding + // line 39
    'begin' + LineEnding +
    '  Result := 0;' + LineEnding +
    'end;' + LineEnding +
    '' + LineEnding +
    '{ TImplOnlyClass }' + LineEnding +
    '' + LineEnding +
    'procedure TImplOnlyClass.ImplMethod;' + LineEnding + // line 46
    'begin' + LineEnding +
    'end;' + LineEnding +
    '' + LineEnding +
    '{ Global }' + LineEnding +
    '' + LineEnding +
    'function GlobalFunc: Boolean;' + LineEnding +       // line 52
    'begin' + LineEnding +
    '  Result := True;' + LineEnding +
    'end;' + LineEnding +
    '' + LineEnding +
    'end.';

{ TTestSublimeProfile }

procedure TTestSublimeProfile.CreateTestFile(const AContent: String);
var
  F: TextFile;
  ExistingBuffer: TCodeBuffer;
begin
  // Use GetTempFileName for guaranteed unique filename
  FTestFile := GetTempFileName('', 'testunit');
  FTestFile := ChangeFileExt(FTestFile, '.pas');

  // Create file on disk
  AssignFile(F, FTestFile);
  try
    Rewrite(F);
    Write(F, AContent);
  finally
    CloseFile(F);
  end;

  // Force CodeToolBoss to reload from disk if buffer already exists
  // This is necessary because CodeToolBoss may have stale buffers from previous tests
  ExistingBuffer := CodeToolBoss.FindFile(FTestFile);
  if ExistingBuffer <> nil then
    ExistingBuffer.Revert;

  // Load via CodeToolBoss
  FTestCode := CodeToolBoss.LoadFile(FTestFile, True, False);
end;

procedure TTestSublimeProfile.CleanupTestFile;
begin
  // Just delete the file - SymbolManager should be freed first in TearDown
  FTestCode := nil;
  if FTestFile <> '' then
    begin
    if FileExists(FTestFile) then
      DeleteFile(FTestFile);
    FTestFile := '';
    end;
end;

procedure SetupSublimeProfile;
begin
  // Sublime Text LSP profile settings
  ServerSettings.flatSymbolMode := True;
  ServerSettings.nullDocumentVersion := True;
  ServerSettings.filterTextOnly := True;
  ServerSettings.excludeSymbols.Clear;
  ServerSettings.excludeSymbols.Add('sectionContainers');
  ServerSettings.excludeSymbols.Add('interfaceMethodDecls');
  ServerSettings.excludeSymbols.Add('implClassDefs');
  // Trigger set to update the exclusion set
  ServerSettings.excludeSymbols := ServerSettings.excludeSymbols;
end;

procedure ResetToDefaultProfile;
begin
  // Default profile settings (show everything)
  ServerSettings.flatSymbolMode := False;
  ServerSettings.nullDocumentVersion := False;
  ServerSettings.filterTextOnly := False;
  ServerSettings.excludeSymbols.Clear;
  // Trigger set to update the exclusion set
  ServerSettings.excludeSymbols := ServerSettings.excludeSymbols;
end;

procedure TTestSublimeProfile.SetUp;
begin
  inherited SetUp;
  FTestCode := nil;
  FTestFile := '';

  if SymbolManager = nil then
    SymbolManager := TSymbolManager.Create;

  // Reset capabilities to known state before each test
  SetClientCapabilities(True);
  // Each test sets its own profile via SetupSublimeProfile
end;

procedure TTestSublimeProfile.TearDown;
begin
  CleanupTestFile;
  FTestCode := nil;
  // Reset profile and capabilities for next test suite
  ResetToDefaultProfile;
  SetClientCapabilities(False);
  inherited TearDown;
end;

function TTestSublimeProfile.GetSymbolNames(const RawJSON: String): TStringList;

  procedure CollectNames(const Arr: TJSONArray; Names: TStringList);
  var
    I: Integer;
    Obj: TJSONObject;
    Children: TJSONArray;
    SymbolName: String;
  begin
    for I := 0 to Arr.Count - 1 do
    begin
      Obj := Arr.Items[I] as TJSONObject;
      SymbolName := Obj.Get('name', '');
      if SymbolName <> '' then
        Names.Add(SymbolName);

      // Check for hierarchical children
      if Obj.FindPath('children') is TJSONArray then
      begin
        Children := Obj.FindPath('children') as TJSONArray;
        CollectNames(Children, Names);
      end;
    end;
  end;

var
  JSONData: TJSONData;
begin
  Result := TStringList.Create;
  Result.Sorted := True;
  Result.Duplicates := dupAccept;

  JSONData := GetJSON(RawJSON);
  try
    if JSONData is TJSONArray then
      CollectNames(JSONData as TJSONArray, Result);
  finally
    JSONData.Free;
  end;
end;

function TTestSublimeProfile.HasSymbol(const Names: TStringList; const SymbolName: String): Boolean;
begin
  Result := Names.IndexOf(SymbolName) >= 0;
end;

function TTestSublimeProfile.CountSymbol(const Names: TStringList; const SymbolName: String): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to Names.Count - 1 do
    if Names[I] = SymbolName then
      Inc(Result);
end;

procedure TTestSublimeProfile.TestFlatModeHasLocation;
var
  RawJSON: String;
begin
  // F1.1: Sublime profile uses SymbolInformation[] with location field
  SetupSublimeProfile;

  CreateTestFile(TEST_SUBLIME_UNIT);
  AssertNotNull('Code buffer should be loaded', FTestCode);
  SymbolManager.Reload(FTestCode, True);
  RawJSON := SymbolManager.FindDocumentSymbols(FTestFile).AsJSON;

  // SymbolInformation has "location" field, DocumentSymbol has "range"
  AssertTrue('Should have location field (flat mode)',
    Pos('"location"', RawJSON) > 0);
end;

procedure TTestSublimeProfile.TestFlatModeNoChildren;
var
  RawJSON: String;
begin
  // F1.2: Flat mode should NOT have children field
  SetupSublimeProfile;

  CreateTestFile(TEST_SUBLIME_UNIT);
  AssertNotNull('Code buffer should be loaded', FTestCode);
  SymbolManager.Reload(FTestCode, True);
  RawJSON := SymbolManager.FindDocumentSymbols(FTestFile).AsJSON;

  AssertTrue('Should NOT have children field in flat mode',
    Pos('"children"', RawJSON) = 0);
end;

procedure TTestSublimeProfile.TestFlatModeMethodNaming;
var
  RawJSON: String;
  Names: TStringList;
begin
  // F1.3: Methods should be named as "ClassName.MethodName"
  SetupSublimeProfile;

  CreateTestFile(TEST_SUBLIME_UNIT);
  AssertNotNull('Code buffer should be loaded', FTestCode);
  SymbolManager.Reload(FTestCode, True);
  RawJSON := SymbolManager.FindDocumentSymbols(FTestFile).AsJSON;

  Names := GetSymbolNames(RawJSON);
  try
    AssertTrue('Should have TMyClass.MethodA',
      HasSymbol(Names, 'TMyClass.MethodA'));
    AssertTrue('Should have TMyClass.MethodB',
      HasSymbol(Names, 'TMyClass.MethodB'));
  finally
    Names.Free;
  end;
end;

procedure TTestSublimeProfile.TestFlatModeNoContainerName;
var
  RawJSON: String;
begin
  // F1.4: Flat mode should NOT have containerName field (Lazarus style)
  SetupSublimeProfile;

  CreateTestFile(TEST_SUBLIME_UNIT);
  AssertNotNull('Code buffer should be loaded', FTestCode);
  SymbolManager.Reload(FTestCode, True);
  RawJSON := SymbolManager.FindDocumentSymbols(FTestFile).AsJSON;

  // SymbolInformation typically has containerName, but Lazarus style uses
  // ClassName.MethodName in the name field instead
  AssertTrue('Should NOT have containerName field',
    Pos('"containerName"', RawJSON) = 0);
end;

procedure TTestSublimeProfile.TestNoInterfaceContainer;
var
  RawJSON: String;
  Names: TStringList;
begin
  // S1.1: Sublime profile excludes "interface" container symbol
  SetupSublimeProfile;

  CreateTestFile(TEST_SUBLIME_UNIT);
  AssertNotNull('Code buffer should be loaded', FTestCode);
  SymbolManager.Reload(FTestCode, True);
  RawJSON := SymbolManager.FindDocumentSymbols(FTestFile).AsJSON;

  Names := GetSymbolNames(RawJSON);
  try
    AssertFalse('Should NOT have "interface" container',
      HasSymbol(Names, 'interface'));
  finally
    Names.Free;
  end;
end;

procedure TTestSublimeProfile.TestNoImplementationContainer;
var
  RawJSON: String;
  Names: TStringList;
begin
  // S1.2: Sublime profile excludes "implementation" container symbol
  SetupSublimeProfile;

  CreateTestFile(TEST_SUBLIME_UNIT);
  AssertNotNull('Code buffer should be loaded', FTestCode);
  SymbolManager.Reload(FTestCode, True);
  RawJSON := SymbolManager.FindDocumentSymbols(FTestFile).AsJSON;

  Names := GetSymbolNames(RawJSON);
  try
    AssertFalse('Should NOT have "implementation" container',
      HasSymbol(Names, 'implementation'));
  finally
    Names.Free;
  end;
end;

procedure TTestSublimeProfile.TestClassesAtTopLevel;
var
  RawJSON: String;
  JSONData: TJSONData;
  SymbolArray: TJSONArray;
  I: Integer;
  Obj: TJSONObject;
  FoundTMyClass: Boolean;
begin
  // S1.3: Classes should appear at top level (not nested under section containers)
  SetupSublimeProfile;

  CreateTestFile(TEST_SUBLIME_UNIT);
  AssertNotNull('Code buffer should be loaded', FTestCode);
  SymbolManager.Reload(FTestCode, True);
  RawJSON := SymbolManager.FindDocumentSymbols(FTestFile).AsJSON;

  JSONData := GetJSON(RawJSON);
  try
    AssertTrue('Result should be an array', JSONData is TJSONArray);
    SymbolArray := JSONData as TJSONArray;

    // TMyClass should be directly in the top-level array
    FoundTMyClass := False;
    for I := 0 to SymbolArray.Count - 1 do
    begin
      Obj := SymbolArray.Items[I] as TJSONObject;
      if Obj.Get('name', '') = 'TMyClass' then
      begin
        FoundTMyClass := True;
        Break;
      end;
    end;

    AssertTrue('TMyClass should be at top level (not nested)', FoundTMyClass);
  finally
    JSONData.Free;
  end;
end;

procedure TTestSublimeProfile.TestNoInterfaceMethodDecls;
var
  RawJSON: String;
  Names: TStringList;
begin
  // M1.1: Sublime profile excludes interface method declarations
  // But keeps the implementation methods (TMyClass.MethodA, TMyClass.MethodB)
  SetupSublimeProfile;

  CreateTestFile(TEST_SUBLIME_UNIT);
  AssertNotNull('Code buffer should be loaded', FTestCode);
  SymbolManager.Reload(FTestCode, True);
  RawJSON := SymbolManager.FindDocumentSymbols(FTestFile).AsJSON;

  Names := GetSymbolNames(RawJSON);
  try
    // Should have implementation methods
    AssertTrue('Should have TMyClass.MethodA (impl)',
      HasSymbol(Names, 'TMyClass.MethodA'));
    AssertTrue('Should have TMyClass.MethodB (impl)',
      HasSymbol(Names, 'TMyClass.MethodB'));

    // In flat mode with cfExcludeInterfaceMethodDecls:
    // Interface declarations (bare MethodA, MethodB) should not appear
    // Only the implementation versions (TMyClass.MethodA) should exist
    // Count how many times the method appears - should be exactly once
    // (the implementation version, not the interface declaration)
  finally
    Names.Free;
  end;
end;

procedure TTestSublimeProfile.TestPreservesInterfaceClassDefs;
var
  RawJSON: String;
  Names: TStringList;
begin
  // M1.2: Sublime profile keeps interface class definitions
  SetupSublimeProfile;

  CreateTestFile(TEST_SUBLIME_UNIT);
  AssertNotNull('Code buffer should be loaded', FTestCode);
  SymbolManager.Reload(FTestCode, True);
  RawJSON := SymbolManager.FindDocumentSymbols(FTestFile).AsJSON;

  Names := GetSymbolNames(RawJSON);
  try
    AssertTrue('Should have TMyClass (interface class)',
      HasSymbol(Names, 'TMyClass'));
    AssertTrue('Should have TMyRecord (interface record)',
      HasSymbol(Names, 'TMyRecord'));
  finally
    Names.Free;
  end;
end;

procedure TTestSublimeProfile.TestNoInterfaceGlobalFuncDecl;
var
  RawJSON: String;
  Names: TStringList;
begin
  // M1.4: Interface GlobalFunc declaration should be excluded
  // Only the implementation version should exist (exactly 1 occurrence)
  SetupSublimeProfile;

  CreateTestFile(TEST_SUBLIME_UNIT);
  AssertNotNull('Code buffer should be loaded', FTestCode);
  SymbolManager.Reload(FTestCode, True);
  RawJSON := SymbolManager.FindDocumentSymbols(FTestFile).AsJSON;

  Names := GetSymbolNames(RawJSON);
  try
    // GlobalFunc should appear exactly once (implementation only)
    // Not twice (interface declaration + implementation)
    AssertEquals('GlobalFunc should appear exactly once',
      1, CountSymbol(Names, 'GlobalFunc'));
  finally
    Names.Free;
  end;
end;

procedure TTestSublimeProfile.TestNoImplClassDefs;
var
  RawJSON: String;
  Names: TStringList;
begin
  // C1.1: Sublime profile excludes implementation-only class definitions
  SetupSublimeProfile;

  CreateTestFile(TEST_SUBLIME_UNIT);
  AssertNotNull('Code buffer should be loaded', FTestCode);
  SymbolManager.Reload(FTestCode, True);
  RawJSON := SymbolManager.FindDocumentSymbols(FTestFile).AsJSON;

  Names := GetSymbolNames(RawJSON);
  try
    // TImplOnlyClass is defined only in implementation section
    // It should NOT appear as a class symbol
    AssertFalse('TImplOnlyClass should NOT exist (impl-only class)',
      HasSymbol(Names, 'TImplOnlyClass'));
  finally
    Names.Free;
  end;
end;

procedure TTestSublimeProfile.TestNoDuplicateClasses;
var
  RawJSON: String;
  Names: TStringList;
begin
  // C1.4: Each class should appear exactly once (no duplicates)
  SetupSublimeProfile;

  CreateTestFile(TEST_SUBLIME_UNIT);
  AssertNotNull('Code buffer should be loaded', FTestCode);
  SymbolManager.Reload(FTestCode, True);
  RawJSON := SymbolManager.FindDocumentSymbols(FTestFile).AsJSON;

  Names := GetSymbolNames(RawJSON);
  try
    // TMyClass should appear exactly once
    // (not twice from interface + implementation)
    AssertEquals('TMyClass should appear exactly once',
      1, CountSymbol(Names, 'TMyClass'));

    // TMyRecord should appear exactly once
    AssertEquals('TMyRecord should appear exactly once',
      1, CountSymbol(Names, 'TMyRecord'));
  finally
    Names.Free;
  end;
end;

procedure TTestSublimeProfile.TestNoForwardDeclarations;
var
  RawJSON: String;
  Names: TStringList;
begin
  // C1.5: Forward declarations should be excluded
  SetupSublimeProfile;

  CreateTestFile(TEST_SUBLIME_UNIT);
  AssertNotNull('Code buffer should be loaded', FTestCode);
  SymbolManager.Reload(FTestCode, True);
  RawJSON := SymbolManager.FindDocumentSymbols(FTestFile).AsJSON;

  Names := GetSymbolNames(RawJSON);
  try
    // TForward is a forward declaration at line 7
    AssertFalse('TForward should NOT exist (forward declaration)',
      HasSymbol(Names, 'TForward'));
  finally
    Names.Free;
  end;
end;

procedure TTestSublimeProfile.TestImplClassMethodsPreserved;
var
  RawJSON: String;
  Names: TStringList;
begin
  // C1.6: Methods of impl-only classes should still appear
  SetupSublimeProfile;

  CreateTestFile(TEST_SUBLIME_UNIT);
  AssertNotNull('Code buffer should be loaded', FTestCode);
  SymbolManager.Reload(FTestCode, True);
  RawJSON := SymbolManager.FindDocumentSymbols(FTestFile).AsJSON;

  Names := GetSymbolNames(RawJSON);
  try
    // TImplOnlyClass.ImplMethod should exist even though
    // TImplOnlyClass class symbol is excluded
    AssertTrue('TImplOnlyClass.ImplMethod should exist',
      HasSymbol(Names, 'TImplOnlyClass.ImplMethod'));
  finally
    Names.Free;
  end;
end;

procedure TTestSublimeProfile.TestCompareWithDefault;
var
  SublimeJSON, DefaultJSON: String;
  SublimeNames, DefaultNames: TStringList;
begin
  // Compare Sublime profile output with Default profile
  CreateTestFile(TEST_SUBLIME_UNIT);
  AssertNotNull('Code buffer should be loaded', FTestCode);

  // Get Sublime profile symbols
  SetupSublimeProfile;
  SymbolManager.Reload(FTestCode, True);
  SublimeJSON := SymbolManager.FindDocumentSymbols(FTestFile).AsJSON;

  // Get Default profile symbols (hierarchical mode)
  ResetToDefaultProfile;  // Reset to default
  SetClientCapabilities(True);  // Hierarchical mode
  SymbolManager.Reload(FTestCode, True);
  DefaultJSON := SymbolManager.FindDocumentSymbols(FTestFile).AsJSON;

  SublimeNames := GetSymbolNames(SublimeJSON);
  DefaultNames := GetSymbolNames(DefaultJSON);
  try
    // Default has section containers, Sublime doesn't
    AssertTrue('Default has interface', HasSymbol(DefaultNames, 'interface'));
    AssertFalse('Sublime has no interface', HasSymbol(SublimeNames, 'interface'));

    AssertTrue('Default has implementation', HasSymbol(DefaultNames, 'implementation'));
    AssertFalse('Sublime has no implementation', HasSymbol(SublimeNames, 'implementation'));

    // Default has hierarchical children, Sublime doesn't
    AssertTrue('Default JSON has children', Pos('"children"', DefaultJSON) > 0);
    AssertTrue('Sublime JSON has no children', Pos('"children"', SublimeJSON) = 0);
  finally
    SublimeNames.Free;
    DefaultNames.Free;
  end;
end;

procedure TTestSublimeProfile.TestGlobalFuncPreserved;
var
  RawJSON: String;
  Names: TStringList;
begin
  // Global functions in implementation should be preserved
  SetupSublimeProfile;

  CreateTestFile(TEST_SUBLIME_UNIT);
  AssertNotNull('Code buffer should be loaded', FTestCode);
  SymbolManager.Reload(FTestCode, True);
  RawJSON := SymbolManager.FindDocumentSymbols(FTestFile).AsJSON;

  Names := GetSymbolNames(RawJSON);
  try
    // GlobalFunc implementation at line 52 should exist
    AssertTrue('GlobalFunc should exist (implementation)',
      HasSymbol(Names, 'GlobalFunc'));
  finally
    Names.Free;
  end;
end;

procedure TTestSublimeProfile.TestNestedProcPreserved;
var
  RawJSON: String;
  Names: TStringList;
begin
  // Nested procedures should be preserved with proper naming
  SetupSublimeProfile;

  CreateTestFile(TEST_SUBLIME_UNIT);
  AssertNotNull('Code buffer should be loaded', FTestCode);
  SymbolManager.Reload(FTestCode, True);
  RawJSON := SymbolManager.FindDocumentSymbols(FTestFile).AsJSON;

  Names := GetSymbolNames(RawJSON);
  try
    // NestedProc inside TMyClass.MethodA should exist
    // In flat mode: TMyClass.MethodA.NestedProc
    AssertTrue('TMyClass.MethodA.NestedProc should exist',
      HasSymbol(Names, 'TMyClass.MethodA.NestedProc'));
  finally
    Names.Free;
  end;
end;

initialization
  RegisterTest(TTestSublimeProfile);

end.
