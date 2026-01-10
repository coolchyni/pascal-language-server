unit Tests.WorkspaceSymbol;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, fpjson, jsonparser,
  CodeToolManager, CodeCache,
  PasLS.Symbols, PasLS.Settings;

type

  { TTestWorkspaceSymbol }

  TTestWorkspaceSymbol = class(TTestCase)
  private
    FTestFile: String;
    FTestCode: TCodeBuffer;
    procedure CreateTestFile(const AContent: String);
    procedure CleanupTestFile;
    function ParseSymbols(const RawJSON: String): TJSONArray;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestReturnsSymbolInformationFormat;
    procedure TestHasLocationField;
    procedure TestNoChildrenField;
    procedure TestNoSelectionRangeField;
    procedure TestQueryFilterByName;
    procedure TestQueryFilterCaseInsensitive;
    procedure TestEmptyQueryReturnsAll;
    procedure TestContainsExpectedSymbols;
  end;

implementation

const
  TEST_WORKSPACE_UNIT =
    'unit TestWorkspace;' + LineEnding +
    '' + LineEnding +
    '{$mode objfpc}{$H+}' + LineEnding +
    '' + LineEnding +
    'interface' + LineEnding +
    '' + LineEnding +
    'type' + LineEnding +
    '  TMyClass = class' + LineEnding +
    '    procedure MethodA;' + LineEnding +
    '    function MethodB: Integer;' + LineEnding +
    '  end;' + LineEnding +
    '' + LineEnding +
    '  TMyRecord = record' + LineEnding +
    '    Field1: Integer;' + LineEnding +
    '  end;' + LineEnding +
    '' + LineEnding +
    'function GlobalFunc: Boolean;' + LineEnding +
    'procedure GlobalProc;' + LineEnding +
    '' + LineEnding +
    'implementation' + LineEnding +
    '' + LineEnding +
    'procedure TMyClass.MethodA;' + LineEnding +
    'begin' + LineEnding +
    'end;' + LineEnding +
    '' + LineEnding +
    'function TMyClass.MethodB: Integer;' + LineEnding +
    'begin' + LineEnding +
    '  Result := 0;' + LineEnding +
    'end;' + LineEnding +
    '' + LineEnding +
    'function GlobalFunc: Boolean;' + LineEnding +
    'begin' + LineEnding +
    '  Result := True;' + LineEnding +
    'end;' + LineEnding +
    '' + LineEnding +
    'procedure GlobalProc;' + LineEnding +
    'begin' + LineEnding +
    'end;' + LineEnding +
    '' + LineEnding +
    'end.';

{ TTestWorkspaceSymbol }

procedure TTestWorkspaceSymbol.CreateTestFile(const AContent: String);
var
  F: TextFile;
  ExistingBuffer: TCodeBuffer;
begin
  // Use GetTempFileName for guaranteed unique filename (matches TTestDocumentSymbol pattern)
  FTestFile := GetTempFileName('', 'testunit');
  FTestFile := ChangeFileExt(FTestFile, '.pas');

  AssignFile(F, FTestFile);
  try
    Rewrite(F);
    Write(F, AContent);
  finally
    CloseFile(F);
  end;

  // Force CodeToolBoss to reload from disk if buffer already exists
  // This is necessary because GetTempFileName may reuse same filename
  // after previous test deleted the file
  ExistingBuffer := CodeToolBoss.FindFile(FTestFile);
  if ExistingBuffer <> nil then
    ExistingBuffer.Revert;
end;

procedure TTestWorkspaceSymbol.CleanupTestFile;
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

function TTestWorkspaceSymbol.ParseSymbols(const RawJSON: String): TJSONArray;
var
  JSONData: TJSONData;
begin
  Result := nil;
  if RawJSON = '' then
    Exit;
  JSONData := GetJSON(RawJSON);
  if JSONData is TJSONArray then
    Result := JSONData as TJSONArray
  else
    JSONData.Free;
end;

procedure TTestWorkspaceSymbol.SetUp;
begin
  inherited SetUp;
  FTestCode := nil;
  FTestFile := '';

  // Create SymbolManager if it doesn't exist
  if SymbolManager = nil then
    SymbolManager := TSymbolManager.Create;

  // Reset to default profile (show everything)
  ServerSettings.flatSymbolMode := False;
  ServerSettings.excludeSymbols.Clear;
  // Set hierarchical mode for tests (matches TTestDocumentSymbol pattern)
  SetClientCapabilities(True);
end;

procedure TTestWorkspaceSymbol.TearDown;
begin
  CleanupTestFile;
  FTestCode := nil;
  // Reset profile and capabilities for next test suite
  ServerSettings.flatSymbolMode := False;
  ServerSettings.excludeSymbols.Clear;
  SetClientCapabilities(False);
  inherited TearDown;
end;

procedure TTestWorkspaceSymbol.TestReturnsSymbolInformationFormat;
var
  Result: TJSONData;
  RawJSON: String;
  SymbolArray: TJSONArray;
  Symbol: TJSONObject;
begin
  CreateTestFile(TEST_WORKSPACE_UNIT);
  FTestCode := CodeToolBoss.LoadFile(FTestFile, True, False);
  if FTestCode = nil then
    Fail('LoadFile returned nil for: ' + FTestFile + ' (exists=' + BoolToStr(FileExists(FTestFile), True) + ')');
  AssertNotNull('Code buffer should be loaded', FTestCode);
  SymbolManager.Reload(FTestCode, True);

  Result := SymbolManager.FindWorkspaceSymbols('');
  AssertNotNull('FindWorkspaceSymbols should return result', Result);

  RawJSON := Result.AsJSON;
  SymbolArray := ParseSymbols(RawJSON);
  try
    AssertNotNull('Result should be a JSON array', SymbolArray);
    AssertTrue('Should have at least one symbol', SymbolArray.Count > 0);

    Symbol := SymbolArray.Items[0] as TJSONObject;
    AssertNotNull('First item should be an object', Symbol);
    AssertTrue('Should have name field', Symbol.Find('name') <> nil);
    AssertTrue('Should have kind field', Symbol.Find('kind') <> nil);
  finally
    SymbolArray.Free;
  end;
end;

procedure TTestWorkspaceSymbol.TestHasLocationField;
var
  Result: TJSONData;
  SymbolArray: TJSONArray;
  I: Integer;
  Symbol: TJSONObject;
  Location: TJSONObject;
begin
  CreateTestFile(TEST_WORKSPACE_UNIT);
  FTestCode := CodeToolBoss.LoadFile(FTestFile, True, False);
  AssertNotNull('Code buffer should be loaded', FTestCode);
  SymbolManager.Reload(FTestCode, True);

  Result := SymbolManager.FindWorkspaceSymbols('');
  SymbolArray := ParseSymbols(Result.AsJSON);
  try
    AssertNotNull('Result should be a JSON array', SymbolArray);

    for I := 0 to SymbolArray.Count - 1 do
    begin
      Symbol := SymbolArray.Items[I] as TJSONObject;
      AssertTrue('Symbol ' + IntToStr(I) + ' should have location field',
        Symbol.Find('location') <> nil);

      Location := Symbol.FindPath('location') as TJSONObject;
      AssertNotNull('location should be an object', Location);
      AssertTrue('location should have uri', Location.Find('uri') <> nil);
      AssertTrue('location should have range', Location.Find('range') <> nil);
    end;
  finally
    SymbolArray.Free;
  end;
end;

procedure TTestWorkspaceSymbol.TestNoChildrenField;
var
  Result: TJSONData;
  SymbolArray: TJSONArray;
  I: Integer;
  Symbol: TJSONObject;
begin
  CreateTestFile(TEST_WORKSPACE_UNIT);
  FTestCode := CodeToolBoss.LoadFile(FTestFile, True, False);
  AssertNotNull('Code buffer should be loaded', FTestCode);
  SymbolManager.Reload(FTestCode, True);

  Result := SymbolManager.FindWorkspaceSymbols('');
  SymbolArray := ParseSymbols(Result.AsJSON);
  try
    AssertNotNull('Result should be a JSON array', SymbolArray);

    for I := 0 to SymbolArray.Count - 1 do
    begin
      Symbol := SymbolArray.Items[I] as TJSONObject;
      AssertTrue('Symbol ' + Symbol.Get('name', '?') + ' should NOT have children field',
        Symbol.Find('children') = nil);
    end;
  finally
    SymbolArray.Free;
  end;
end;

procedure TTestWorkspaceSymbol.TestNoSelectionRangeField;
var
  Result: TJSONData;
  SymbolArray: TJSONArray;
  I: Integer;
  Symbol: TJSONObject;
begin
  CreateTestFile(TEST_WORKSPACE_UNIT);
  FTestCode := CodeToolBoss.LoadFile(FTestFile, True, False);
  AssertNotNull('Code buffer should be loaded', FTestCode);
  SymbolManager.Reload(FTestCode, True);

  Result := SymbolManager.FindWorkspaceSymbols('');
  SymbolArray := ParseSymbols(Result.AsJSON);
  try
    AssertNotNull('Result should be a JSON array', SymbolArray);

    for I := 0 to SymbolArray.Count - 1 do
    begin
      Symbol := SymbolArray.Items[I] as TJSONObject;
      AssertTrue('Symbol ' + Symbol.Get('name', '?') + ' should NOT have selectionRange field',
        Symbol.Find('selectionRange') = nil);
    end;
  finally
    SymbolArray.Free;
  end;
end;

procedure TTestWorkspaceSymbol.TestQueryFilterByName;
var
  Result: TJSONData;
  SymbolArray: TJSONArray;
  I: Integer;
  Symbol: TJSONObject;
  SymbolName: String;
  FoundMethodA, FoundMethodB: Boolean;
begin
  CreateTestFile(TEST_WORKSPACE_UNIT);
  FTestCode := CodeToolBoss.LoadFile(FTestFile, True, False);
  AssertNotNull('Code buffer should be loaded', FTestCode);
  SymbolManager.Reload(FTestCode, True);

  Result := SymbolManager.FindWorkspaceSymbols('Method');
  SymbolArray := ParseSymbols(Result.AsJSON);
  try
    AssertNotNull('Result should be a JSON array', SymbolArray);
    AssertTrue('Query "Method" should return results', SymbolArray.Count > 0);

    FoundMethodA := False;
    FoundMethodB := False;
    for I := 0 to SymbolArray.Count - 1 do
    begin
      Symbol := SymbolArray.Items[I] as TJSONObject;
      SymbolName := Symbol.Get('name', '');
      if Pos('MethodA', SymbolName) > 0 then
        FoundMethodA := True;
      if Pos('MethodB', SymbolName) > 0 then
        FoundMethodB := True;
    end;

    AssertTrue('Should find MethodA', FoundMethodA);
    AssertTrue('Should find MethodB', FoundMethodB);
  finally
    SymbolArray.Free;
  end;
end;

procedure TTestWorkspaceSymbol.TestQueryFilterCaseInsensitive;
var
  ResultUpper, ResultLower: TJSONData;
  UpperArray, LowerArray: TJSONArray;
begin
  CreateTestFile(TEST_WORKSPACE_UNIT);
  FTestCode := CodeToolBoss.LoadFile(FTestFile, True, False);
  AssertNotNull('Code buffer should be loaded', FTestCode);
  SymbolManager.Reload(FTestCode, True);

  ResultUpper := SymbolManager.FindWorkspaceSymbols('GLOBAL');
  ResultLower := SymbolManager.FindWorkspaceSymbols('global');

  UpperArray := ParseSymbols(ResultUpper.AsJSON);
  LowerArray := ParseSymbols(ResultLower.AsJSON);
  try
    AssertNotNull('Upper case query should return array', UpperArray);
    AssertNotNull('Lower case query should return array', LowerArray);

    // Both queries should find Global symbols
    AssertTrue('Upper case query should find results', UpperArray.Count > 0);
    AssertTrue('Lower case query should find results', LowerArray.Count > 0);
  finally
    UpperArray.Free;
    LowerArray.Free;
  end;
end;

procedure TTestWorkspaceSymbol.TestEmptyQueryReturnsAll;
var
  ResultEmpty, ResultWithQuery: TJSONData;
  EmptyArray, QueryArray: TJSONArray;
begin
  CreateTestFile(TEST_WORKSPACE_UNIT);
  FTestCode := CodeToolBoss.LoadFile(FTestFile, True, False);
  AssertNotNull('Code buffer should be loaded', FTestCode);
  SymbolManager.Reload(FTestCode, True);

  ResultEmpty := SymbolManager.FindWorkspaceSymbols('');
  ResultWithQuery := SymbolManager.FindWorkspaceSymbols('TMyClass');

  EmptyArray := ParseSymbols(ResultEmpty.AsJSON);
  QueryArray := ParseSymbols(ResultWithQuery.AsJSON);
  try
    AssertNotNull('Empty query should return array', EmptyArray);
    AssertNotNull('Specific query should return array', QueryArray);

    // Empty query should return more or equal symbols
    AssertTrue('Empty query should return at least as many symbols',
      EmptyArray.Count >= QueryArray.Count);
  finally
    EmptyArray.Free;
    QueryArray.Free;
  end;
end;

procedure TTestWorkspaceSymbol.TestContainsExpectedSymbols;
var
  Result: TJSONData;
  SymbolArray: TJSONArray;
  I: Integer;
  Symbol: TJSONObject;
  SymbolName: String;
  FoundClass, FoundRecord, FoundGlobalFunc, FoundGlobalProc: Boolean;
begin
  CreateTestFile(TEST_WORKSPACE_UNIT);
  FTestCode := CodeToolBoss.LoadFile(FTestFile, True, False);
  AssertNotNull('Code buffer should be loaded', FTestCode);
  SymbolManager.Reload(FTestCode, True);

  Result := SymbolManager.FindWorkspaceSymbols('');
  SymbolArray := ParseSymbols(Result.AsJSON);
  try
    AssertNotNull('Result should be a JSON array', SymbolArray);

    FoundClass := False;
    FoundRecord := False;
    FoundGlobalFunc := False;
    FoundGlobalProc := False;

    for I := 0 to SymbolArray.Count - 1 do
    begin
      Symbol := SymbolArray.Items[I] as TJSONObject;
      SymbolName := Symbol.Get('name', '');

      if SymbolName = 'TMyClass' then FoundClass := True;
      if SymbolName = 'TMyRecord' then FoundRecord := True;
      if SymbolName = 'GlobalFunc' then FoundGlobalFunc := True;
      if SymbolName = 'GlobalProc' then FoundGlobalProc := True;
    end;

    AssertTrue('Should contain TMyClass', FoundClass);
    AssertTrue('Should contain TMyRecord', FoundRecord);
    AssertTrue('Should contain GlobalFunc', FoundGlobalFunc);
    AssertTrue('Should contain GlobalProc', FoundGlobalProc);
  finally
    SymbolArray.Free;
  end;
end;

initialization
  RegisterTest(TTestWorkspaceSymbol);

end.
