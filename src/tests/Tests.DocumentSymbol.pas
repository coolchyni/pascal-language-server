unit Tests.DocumentSymbol;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, fpjson, jsonparser,
  CodeToolManager, CodeCache,
  PasLS.Symbols;

type

  { TTestDocumentSymbol }

  TTestDocumentSymbol = class(TTestCase)
  private
    FTestCode: TCodeBuffer;
    FTestFile: String;
    procedure CreateTestFile(const AContent: String);
    procedure CleanupTestFile;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestSymbolExtractionHierarchical;
    procedure TestSymbolExtractionFlat;
    procedure TestForwardDeclarationSkipped;
    procedure TestSelectionRangeHasNonZeroWidth;
    procedure TestRangeValidity;
    procedure TestSectionRangeExcludesNextSection;
    procedure TestSymbolRangeExclusivity;
    procedure TestProcedureRangeIncludesSemicolon;
    procedure TestFlatModeRangeIncludesSemicolon;
    procedure TestSingleLineSymbolRangeStaysOnSameLine;
    procedure TestMethodSelectionRangePointsToName;
    procedure TestHierarchicalModeFullValidation;
    procedure TestFlatModeFullValidation;
    procedure TestEnumSymbolsHierarchical;
    procedure TestEnumSymbolsFlat;
    procedure TestTypeAliasSymbolsHierarchical;
    procedure TestTypeAliasSymbolsFlat;
  end;

implementation

const
  TEST_UNIT_WITH_PROPERTY_AND_FIELD =
    'unit TestUnit;' + LineEnding +
    '' + LineEnding +
    '{$mode objfpc}{$H+}' + LineEnding +
    '' + LineEnding +
    'interface' + LineEnding +
    '' + LineEnding +
    'type' + LineEnding +
    '  TUser = class' + LineEnding +
    '  private' + LineEnding +
    '    FName: String;' + LineEnding +
    '    FAge: Integer;' + LineEnding +
    '  public' + LineEnding +
    '    property Name: String read FName write FName;' + LineEnding +
    '    property Age: Integer read FAge write FAge;' + LineEnding +
    '    procedure PrintInfo;' + LineEnding +
    '    function GetFullName: String;' + LineEnding +
    '  end;' + LineEnding +
    '' + LineEnding +
    'implementation' + LineEnding +
    '' + LineEnding +
    'procedure TUser.PrintInfo;' + LineEnding +
    'begin' + LineEnding +
    '  writeln(FName);' + LineEnding +
    'end;' + LineEnding +
    '' + LineEnding +
    'function TUser.GetFullName: String;' + LineEnding +
    'begin' + LineEnding +
    '  Result := FName;' + LineEnding +
    'end;' + LineEnding +
    '' + LineEnding +
    'end.';

  // Test file with enum type for testing enum symbol extraction
  TEST_UNIT_WITH_ENUM =
    'unit TestEnumUnit;' + LineEnding +
    '' + LineEnding +
    '{$mode objfpc}{$H+}' + LineEnding +
    '' + LineEnding +
    'interface' + LineEnding +
    '' + LineEnding +
    'type' + LineEnding +
    '  TColor = (clRed, clGreen, clBlue);' + LineEnding +
    '  TStatus = (stPending, stActive, stDone);' + LineEnding +
    '' + LineEnding +
    '  TMyClass = class' + LineEnding +
    '  public' + LineEnding +
    '    procedure DoSomething;' + LineEnding +
    '  end;' + LineEnding +
    '' + LineEnding +
    'implementation' + LineEnding +
    '' + LineEnding +
    'procedure TMyClass.DoSomething;' + LineEnding +
    'begin' + LineEnding +
    'end;' + LineEnding +
    '' + LineEnding +
    'end.';

  // Test file with type aliases for testing type alias symbol extraction
  TEST_UNIT_WITH_TYPE_ALIAS =
    'unit TestTypeAliasUnit;' + LineEnding +
    '' + LineEnding +
    '{$mode objfpc}{$H+}' + LineEnding +
    '' + LineEnding +
    'interface' + LineEnding +
    '' + LineEnding +
    'type' + LineEnding +
    '  TMyInteger = Integer;' + LineEnding +
    '  PInteger = ^Integer;' + LineEnding +
    '  TMySet = set of Byte;' + LineEnding +
    '  TMyProc = procedure(X: Integer);' + LineEnding +
    '  TMyArray = array[0..10] of Integer;' + LineEnding +
    '' + LineEnding +
    '  TMyClass = class' + LineEnding +
    '  public' + LineEnding +
    '    procedure DoSomething;' + LineEnding +
    '  end;' + LineEnding +
    '' + LineEnding +
    'implementation' + LineEnding +
    '' + LineEnding +
    'procedure TMyClass.DoSomething;' + LineEnding +
    'begin' + LineEnding +
    'end;' + LineEnding +
    '' + LineEnding +
    'end.';

  // Full test file for comprehensive position validation
  // Based on test_symbols.pas structure
  TEST_FULL_VALIDATION_FILE =
    'unit test_symbols;' + LineEnding +                              // line 0
    '' + LineEnding +                                                 // line 1
    '// Test file' + LineEnding +                                     // line 2
    '' + LineEnding +                                                 // line 3
    '{$mode objfpc}{$H+}' + LineEnding +                              // line 4
    '' + LineEnding +                                                 // line 5
    'interface' + LineEnding +                                        // line 6
    '' + LineEnding +                                                 // line 7
    'type' + LineEnding +                                             // line 8
    '  TTestClassA = class' + LineEnding +                            // line 9: "TTestClassA" at 2-12
    '  private' + LineEnding +                                        // line 10
    '    FValue: Integer;' + LineEnding +                             // line 11: "FValue" at 4-9
    '  public' + LineEnding +                                         // line 12
    '    procedure MethodA1;' + LineEnding +                          // line 13: "MethodA1" at 14-21
    '    function MethodA2: Integer;' + LineEnding +                  // line 14: "MethodA2" at 13-20
    '  end;' + LineEnding +                                           // line 15
    '' + LineEnding +                                                 // line 16
    'procedure GlobalProc;' + LineEnding +                            // line 17: "GlobalProc" at 10-19
    '' + LineEnding +                                                 // line 18
    'implementation' + LineEnding +                                   // line 19
    '' + LineEnding +                                                 // line 20
    'procedure TTestClassA.MethodA1;' + LineEnding +                  // line 21: "MethodA1" at 22-29
    'var' + LineEnding +                                              // line 22
    '  X: Integer;' + LineEnding +                                    // line 23
    '' + LineEnding +                                                 // line 24
    '  procedure NestedProc;' + LineEnding +                          // line 25: "NestedProc" at 12-21
    '  begin' + LineEnding +                                          // line 26
    '    X := 1;' + LineEnding +                                      // line 27
    '  end;' + LineEnding +                                           // line 28
    '' + LineEnding +                                                 // line 29
    'begin' + LineEnding +                                            // line 30
    '  NestedProc;' + LineEnding +                                    // line 31
    'end;' + LineEnding +                                             // line 32
    '' + LineEnding +                                                 // line 33
    'function TTestClassA.MethodA2: Integer;' + LineEnding +          // line 34: "MethodA2" at 21-28
    'begin' + LineEnding +                                            // line 35
    '  Result := FValue;' + LineEnding +                              // line 36
    'end;' + LineEnding +                                             // line 37
    '' + LineEnding +                                                 // line 38
    'procedure GlobalProc;' + LineEnding +                            // line 39: "GlobalProc" at 10-19
    'begin' + LineEnding +                                            // line 40
    'end;' + LineEnding +                                             // line 41
    '' + LineEnding +                                                 // line 42
    'end.';                                                           // line 43

  // Test case for forward declarations - should be skipped in symbol extraction
  TEST_UNIT_WITH_FORWARD_DECLARATION =
    'unit TestForward;' + LineEnding +
    '' + LineEnding +
    '{$mode objfpc}{$H+}' + LineEnding +
    '' + LineEnding +
    'interface' + LineEnding +
    '' + LineEnding +
    'type' + LineEnding +
    '  // Forward class declaration - should be SKIPPED' + LineEnding +
    '  TMySymbol = class;' + LineEnding +
    '' + LineEnding +
    '  // Helper class using the forward declared class' + LineEnding +
    '  TSymbolHelper = class' + LineEnding +
    '  private' + LineEnding +
    '    FItem: TMySymbol;' + LineEnding +
    '  public' + LineEnding +
    '    procedure DoSomething;' + LineEnding +
    '  end;' + LineEnding +
    '' + LineEnding +
    '  // Full class declaration - should be INCLUDED' + LineEnding +
    '  TMySymbol = class' + LineEnding +
    '  private' + LineEnding +
    '    FName: String;' + LineEnding +
    '    FKind: Integer;' + LineEnding +
    '  public' + LineEnding +
    '    property Name: String read FName write FName;' + LineEnding +
    '    property Kind: Integer read FKind write FKind;' + LineEnding +
    '    procedure Initialize;' + LineEnding +
    '  end;' + LineEnding +
    '' + LineEnding +
    'implementation' + LineEnding +
    '' + LineEnding +
    '{ TSymbolHelper }' + LineEnding +
    '' + LineEnding +
    'procedure TSymbolHelper.DoSomething;' + LineEnding +
    'begin' + LineEnding +
    '  FItem := nil;' + LineEnding +
    'end;' + LineEnding +
    '' + LineEnding +
    '{ TMySymbol }' + LineEnding +
    '' + LineEnding +
    'procedure TMySymbol.Initialize;' + LineEnding +
    'begin' + LineEnding +
    '  FName := '''';' + LineEnding +
    '  FKind := 0;' + LineEnding +
    'end;' + LineEnding +
    '' + LineEnding +
    'end.';

{ TTestDocumentSymbol }

procedure TTestDocumentSymbol.CreateTestFile(const AContent: String);
var
  F: TextFile;
  ExistingBuffer: TCodeBuffer;
begin
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

procedure TTestDocumentSymbol.CleanupTestFile;
begin
  if FileExists(FTestFile) then
    DeleteFile(FTestFile);
  FTestFile := '';
end;

procedure TTestDocumentSymbol.SetUp;
begin
  inherited SetUp;
  FTestCode := nil;
  FTestFile := '';

  // Ensure SymbolManager is initialized
  if SymbolManager = nil then
    SymbolManager := TSymbolManager.Create;

  // Set hierarchical mode for tests
  SetClientCapabilities(True);
end;

procedure TTestDocumentSymbol.TearDown;
begin
  CleanupTestFile;
  FTestCode := nil;
  inherited TearDown;
end;

procedure TTestDocumentSymbol.TestSymbolExtractionHierarchical;
var
  RawJSON: String;
begin
  // Ensure hierarchical mode
  SetClientCapabilities(True);

  // Create test file
  CreateTestFile(TEST_UNIT_WITH_PROPERTY_AND_FIELD);

  // Load code buffer
  FTestCode := CodeToolBoss.LoadFile(FTestFile, True, False);
  AssertNotNull('Code buffer should be loaded', FTestCode);

  // Use SymbolManager to reload and extract symbols (public API)
  SymbolManager.Reload(FTestCode, True);

  // Get the raw JSON from SymbolManager
  RawJSON := SymbolManager.FindDocumentSymbols(FTestFile).AsJSON;

  // Verify we extracted symbols
  AssertTrue('Should have extracted symbols', RawJSON <> '');

  // Verify the extracted symbols contain our expected names
  AssertTrue('JSON should contain TUser class', Pos('"TUser"', RawJSON) > 0);
  AssertTrue('JSON should contain FName field', Pos('FName', RawJSON) > 0);
  AssertTrue('JSON should contain FAge field', Pos('FAge', RawJSON) > 0);
  AssertTrue('JSON should contain Name property', Pos('"Name"', RawJSON) > 0);
  AssertTrue('JSON should contain Age property', Pos('"Age"', RawJSON) > 0);
  AssertTrue('JSON should contain PrintInfo method', Pos('PrintInfo', RawJSON) > 0);
  AssertTrue('JSON should contain GetFullName method', Pos('GetFullName', RawJSON) > 0);

  // Check for hierarchical structure (children array)
  AssertTrue('Should have children in hierarchical mode', Pos('"children"', RawJSON) > 0);

  // Check for correct symbol kinds (note: JSON has spaces around colons)
  AssertTrue('Should have Class kind (5)', Pos('"kind" : 5', RawJSON) > 0);
  AssertTrue('Should have Field kind (8)', Pos('"kind" : 8', RawJSON) > 0);
  AssertTrue('Should have Property kind (7)', Pos('"kind" : 7', RawJSON) > 0);
  AssertTrue('Should have Method kind (6)', Pos('"kind" : 6', RawJSON) > 0);
end;

procedure TTestDocumentSymbol.TestSymbolExtractionFlat;
var
  RawJSON: String;
begin
  // Ensure flat mode
  SetClientCapabilities(False);

  // Create test file
  CreateTestFile(TEST_UNIT_WITH_PROPERTY_AND_FIELD);

  // Load code buffer
  FTestCode := CodeToolBoss.LoadFile(FTestFile, True, False);
  AssertNotNull('Code buffer should be loaded', FTestCode);

  // Use SymbolManager to reload and extract symbols (public API)
  SymbolManager.Reload(FTestCode, True);

  // Get the raw JSON from SymbolManager
  RawJSON := SymbolManager.FindDocumentSymbols(FTestFile).AsJSON;

  // Verify we extracted symbols
  AssertTrue('Should have extracted symbols', RawJSON <> '');

  // Verify the extracted symbols contain our expected names
  // In flat mode (smFlat), symbols use Class.Member naming (e.g., "TUser.Name")
  AssertTrue('JSON should contain TUser class', Pos('"TUser"', RawJSON) > 0);
  AssertTrue('JSON should contain TUser.FName field', Pos('TUser.FName', RawJSON) > 0);
  AssertTrue('JSON should contain TUser.FAge field', Pos('TUser.FAge', RawJSON) > 0);
  AssertTrue('JSON should contain TUser.Name property', Pos('TUser.Name', RawJSON) > 0);
  AssertTrue('JSON should contain TUser.Age property', Pos('TUser.Age', RawJSON) > 0);
  AssertTrue('JSON should contain TUser.PrintInfo method', Pos('TUser.PrintInfo', RawJSON) > 0);
  AssertTrue('JSON should contain TUser.GetFullName method', Pos('TUser.GetFullName', RawJSON) > 0);

  // In flat mode, should NOT have children array
  AssertTrue('Should NOT have children in flat mode', Pos('"children"', RawJSON) = 0);

  // In flat mode (smFlat), should NOT have containerName (uses Class.Member naming instead)
  AssertTrue('Should NOT have containerName in flat mode', Pos('"containerName"', RawJSON) = 0);

  // Check for correct symbol kinds (note: JSON has spaces around colons)
  AssertTrue('Should have Class kind (5)', Pos('"kind" : 5', RawJSON) > 0);
  AssertTrue('Should have Field kind (8)', Pos('"kind" : 8', RawJSON) > 0);
  AssertTrue('Should have Property kind (7)', Pos('"kind" : 7', RawJSON) > 0);
  AssertTrue('Should have Method kind (6)', Pos('"kind" : 6', RawJSON) > 0);
end;

procedure TTestDocumentSymbol.TestForwardDeclarationSkipped;
var
  RawJSON: String;
begin
  // Test forward declarations are skipped
  // Forward declaration "TMySymbol = class;" at line 8 should NOT appear
  // Full declaration "TMySymbol = class" at line 19 SHOULD appear

  SetClientCapabilities(True);  // hierarchical mode

  // Create test file with forward declarations
  CreateTestFile(TEST_UNIT_WITH_FORWARD_DECLARATION);

  // Load code buffer
  FTestCode := CodeToolBoss.LoadFile(FTestFile, True, False);
  AssertNotNull('Code buffer should be loaded', FTestCode);

  // Use SymbolManager to reload and extract symbols
  SymbolManager.Reload(FTestCode, True);

  // Get the raw JSON from SymbolManager
  RawJSON := SymbolManager.FindDocumentSymbols(FTestFile).AsJSON;

  // Verify we extracted symbols
  AssertTrue('Should have extracted symbols', RawJSON <> '');

  // Forward declaration is at line 8 (0-indexed)
  // If forward declaration was NOT skipped, we'd see "line" : 8 for TMySymbol
  // Check that line 8 does NOT appear in the JSON (no symbol starts at that line)
  AssertTrue('Forward declaration at line 8 should be skipped',
    Pos('"start" : { "character" : 2, "line" : 8', RawJSON) = 0);

  // Full declaration is at line 19, should appear
  AssertTrue('Full declaration at line 19 should be present',
    Pos('"start" : { "character" : 2, "line" : 19', RawJSON) > 0);

  // Verify child members exist (proves full declaration was extracted, not forward)
  AssertTrue('Should contain FName field', Pos('FName', RawJSON) > 0);
  AssertTrue('Should contain FKind field', Pos('FKind', RawJSON) > 0);
  AssertTrue('Should contain Name property', Pos('"Name"', RawJSON) > 0);
end;

procedure TTestDocumentSymbol.TestSelectionRangeHasNonZeroWidth;
var
  RawJSON: String;
begin
  // Test that selectionRange has non-zero width (end.character > start.character)
  // This is required for proper symbol selection in editors like Sublime Text
  // See: https://github.com/anthropics/claude-code/issues/XXX
  //
  // Previously, selectionRange was set to zero-width:
  //   "selectionRange" : { "start" : { "character" : 2, "line" : 7 }, "end" : { "character" : 2, "line" : 7 } }
  // Now it should span the symbol name:
  //   "selectionRange" : { "start" : { "character" : 2, "line" : 7 }, "end" : { "character" : 7, "line" : 7 } }
  //   (for a 5-character symbol name like "TUser")

  SetClientCapabilities(True);  // hierarchical mode

  // Create test file
  CreateTestFile(TEST_UNIT_WITH_PROPERTY_AND_FIELD);

  // Load code buffer
  FTestCode := CodeToolBoss.LoadFile(FTestFile, True, False);
  AssertNotNull('Code buffer should be loaded', FTestCode);

  // Use SymbolManager to reload and extract symbols
  SymbolManager.Reload(FTestCode, True);

  // Get the raw JSON from SymbolManager
  RawJSON := SymbolManager.FindDocumentSymbols(FTestFile).AsJSON;

  // TUser is at line 7 (0-indexed), character 2
  // TUser has 5 characters, so selectionRange.end.character should be 2 + 5 = 7
  // Check that selectionRange has proper width (not zero-width)
  AssertTrue('TUser selectionRange should have width 5 (end.char=7)',
    Pos('"selectionRange" : { "end" : { "character" : 7, "line" : 7 }, "start" : { "character" : 2, "line" : 7 } }', RawJSON) > 0);

  // FName field is at line 9 (0-indexed), character 4
  // FName has 5 characters, so selectionRange.end.character should be 4 + 5 = 9
  AssertTrue('FName selectionRange should have width 5 (end.char=9)',
    Pos('"selectionRange" : { "end" : { "character" : 9, "line" : 9 }, "start" : { "character" : 4, "line" : 9 } }', RawJSON) > 0);
end;

procedure TTestDocumentSymbol.TestRangeValidity;

  function IsValidRange(const RangeObj: TJSONObject): Boolean;
  var
    StartObj, EndObj: TJSONObject;
    StartLine, StartChar, EndLine, EndChar: Integer;
  begin
    Result := False;
    if RangeObj = nil then Exit;

    StartObj := RangeObj.FindPath('start') as TJSONObject;
    EndObj := RangeObj.FindPath('end') as TJSONObject;
    if (StartObj = nil) or (EndObj = nil) then Exit;

    StartLine := StartObj.Get('line', -1);
    StartChar := StartObj.Get('character', -1);
    EndLine := EndObj.Get('line', -1);
    EndChar := EndObj.Get('character', -1);

    // All values must be non-negative
    if (StartLine < 0) or (StartChar < 0) or (EndLine < 0) or (EndChar < 0) then
      Exit;

    // End must be >= Start
    if EndLine < StartLine then Exit;
    if (EndLine = StartLine) and (EndChar < StartChar) then Exit;

    Result := True;
  end;

  procedure ValidateSymbolRanges(const SymbolArray: TJSONArray; const Mode: String);
  var
    I: Integer;
    Symbol: TJSONObject;
    RangeObj, LocationObj: TJSONObject;
    SymbolName: String;
  begin
    for I := 0 to SymbolArray.Count - 1 do
    begin
      Symbol := SymbolArray.Items[I] as TJSONObject;
      SymbolName := Symbol.Get('name', '<unknown>');

      // Hierarchical mode: check 'range' and 'selectionRange'
      RangeObj := Symbol.FindPath('range') as TJSONObject;
      if RangeObj <> nil then
      begin
        AssertTrue(Format('%s: Symbol "%s" has invalid range', [Mode, SymbolName]),
          IsValidRange(RangeObj));
      end;

      RangeObj := Symbol.FindPath('selectionRange') as TJSONObject;
      if RangeObj <> nil then
      begin
        AssertTrue(Format('%s: Symbol "%s" has invalid selectionRange', [Mode, SymbolName]),
          IsValidRange(RangeObj));
      end;

      // Flat mode: check 'location.range'
      LocationObj := Symbol.FindPath('location') as TJSONObject;
      if LocationObj <> nil then
      begin
        RangeObj := LocationObj.FindPath('range') as TJSONObject;
        if RangeObj <> nil then
        begin
          AssertTrue(Format('%s: Symbol "%s" has invalid location.range', [Mode, SymbolName]),
            IsValidRange(RangeObj));
        end;
      end;

      // Recursively check children (hierarchical mode)
      if Symbol.FindPath('children') is TJSONArray then
        ValidateSymbolRanges(Symbol.FindPath('children') as TJSONArray, Mode);
    end;
  end;

var
  RawJSON: String;
  JSONData: TJSONData;
  SymbolArray: TJSONArray;
begin
  // Test hierarchical mode
  SetClientCapabilities(True);
  CreateTestFile(TEST_UNIT_WITH_FORWARD_DECLARATION);
  FTestCode := CodeToolBoss.LoadFile(FTestFile, True, False);
  AssertNotNull('Code buffer should be loaded', FTestCode);
  SymbolManager.Reload(FTestCode, True);
  RawJSON := SymbolManager.FindDocumentSymbols(FTestFile).AsJSON;

  JSONData := GetJSON(RawJSON);
  try
    AssertTrue('Result should be an array', JSONData is TJSONArray);
    SymbolArray := JSONData as TJSONArray;
    ValidateSymbolRanges(SymbolArray, 'Hierarchical');
  finally
    JSONData.Free;
  end;

  CleanupTestFile;

  // Test flat mode
  SetClientCapabilities(False);
  CreateTestFile(TEST_UNIT_WITH_FORWARD_DECLARATION);
  FTestCode := CodeToolBoss.LoadFile(FTestFile, True, False);
  AssertNotNull('Code buffer should be loaded (flat)', FTestCode);
  SymbolManager.Reload(FTestCode, True);
  RawJSON := SymbolManager.FindDocumentSymbols(FTestFile).AsJSON;

  JSONData := GetJSON(RawJSON);
  try
    AssertTrue('Result should be an array (flat)', JSONData is TJSONArray);
    SymbolArray := JSONData as TJSONArray;
    ValidateSymbolRanges(SymbolArray, 'Flat');
  finally
    JSONData.Free;
  end;
end;

procedure TTestDocumentSymbol.TestSectionRangeExcludesNextSection;
{ Test that interface section's range does NOT include the implementation line.
  This verifies the fix for SetNodeRange applying section-node adjustment.
  Interface range.end.line should be < implementation range.start.line }
var
  RawJSON: String;
  JSONData: TJSONData;
  SymbolArray: TJSONArray;
  I: Integer;
  Symbol, RangeObj, EndObj: TJSONObject;
  SymbolName: String;
  InterfaceFound, ImplementationFound: Boolean;
  InterfaceEndLine, ImplementationStartLine: Integer;
begin
  // Test hierarchical mode
  SetClientCapabilities(True);
  CreateTestFile(TEST_UNIT_WITH_FORWARD_DECLARATION);
  FTestCode := CodeToolBoss.LoadFile(FTestFile, True, False);
  AssertNotNull('Code buffer should be loaded', FTestCode);
  SymbolManager.Reload(FTestCode, True);
  RawJSON := SymbolManager.FindDocumentSymbols(FTestFile).AsJSON;

  JSONData := GetJSON(RawJSON);
  try
    AssertTrue('Result should be an array', JSONData is TJSONArray);
    SymbolArray := JSONData as TJSONArray;

    InterfaceFound := False;
    ImplementationFound := False;
    InterfaceEndLine := -1;
    ImplementationStartLine := -1;

    // Find interface and implementation section symbols
    for I := 0 to SymbolArray.Count - 1 do
    begin
      Symbol := SymbolArray.Items[I] as TJSONObject;
      SymbolName := Symbol.Get('name', '');

      if SymbolName = 'interface' then
      begin
        InterfaceFound := True;
        RangeObj := Symbol.FindPath('range') as TJSONObject;
        AssertNotNull('Interface should have range', RangeObj);
        EndObj := RangeObj.FindPath('end') as TJSONObject;
        AssertNotNull('Interface range should have end', EndObj);
        InterfaceEndLine := EndObj.Get('line', -1);
      end
      else if SymbolName = 'implementation' then
      begin
        ImplementationFound := True;
        RangeObj := Symbol.FindPath('range') as TJSONObject;
        AssertNotNull('Implementation should have range', RangeObj);
        RangeObj := RangeObj.FindPath('start') as TJSONObject;
        AssertNotNull('Implementation range should have start', RangeObj);
        ImplementationStartLine := RangeObj.Get('line', -1);
      end;
    end;

    AssertTrue('Interface section should be found', InterfaceFound);
    AssertTrue('Implementation section should be found', ImplementationFound);

    // The key assertion: interface end line must be LESS than implementation start line
    // This ensures sections don't overlap and interface doesn't include implementation keyword
    AssertTrue(
      Format('Interface end line (%d) should be < implementation start line (%d)',
        [InterfaceEndLine, ImplementationStartLine]),
      InterfaceEndLine < ImplementationStartLine);

  finally
    JSONData.Free;
  end;
end;

procedure TTestDocumentSymbol.TestProcedureRangeIncludesSemicolon;
{ Test that procedure/function range.end position is correct for LSP.
  The range should include the trailing semicolon, meaning:
  - range.end points PAST the semicolon (exclusive end)
  - The character at (range.end.line, range.end.character - 1) should be ';'

  This test catches the ";;" bug where replace_symbol_body duplicates semicolons
  because the range doesn't include the original semicolon. }
const
  TEST_SIMPLE_PROCEDURE =
    'unit TestProc;' + LineEnding +                         // line 0
    '' + LineEnding +                                        // line 1
    'interface' + LineEnding +                               // line 2
    '' + LineEnding +                                        // line 3
    'implementation' + LineEnding +                          // line 4
    '' + LineEnding +                                        // line 5
    'procedure DoSomething;' + LineEnding +                  // line 6
    'begin' + LineEnding +                                   // line 7
    '  writeln(''test'');' + LineEnding +                    // line 8
    'end;' + LineEnding +                                    // line 9: "end;" at cols 0-3, ';' at col 3
    '' + LineEnding +                                        // line 10
    'end.';                                                  // line 11
var
  RawJSON: String;
  JSONData: TJSONData;
  SymbolArray: TJSONArray;
  Children: TJSONArray;
  I, J: Integer;
  Symbol, RangeObj, EndObj: TJSONObject;
  SymbolName: String;
  EndLine, EndChar: Integer;
  SourceLines: TStringList;
  LastIncludedChar: Char;
  ProcFound: Boolean;
begin
  // Test hierarchical mode
  SetClientCapabilities(True);
  CreateTestFile(TEST_SIMPLE_PROCEDURE);
  FTestCode := CodeToolBoss.LoadFile(FTestFile, True, False);
  AssertNotNull('Code buffer should be loaded', FTestCode);
  SymbolManager.Reload(FTestCode, True);
  RawJSON := SymbolManager.FindDocumentSymbols(FTestFile).AsJSON;

  // Parse source to verify character positions
  SourceLines := TStringList.Create;
  try
    SourceLines.Text := TEST_SIMPLE_PROCEDURE;

    JSONData := GetJSON(RawJSON);
    try
      AssertTrue('Result should be an array', JSONData is TJSONArray);
      SymbolArray := JSONData as TJSONArray;

      ProcFound := False;

      // Find the DoSomething procedure (look in implementation children)
      for I := 0 to SymbolArray.Count - 1 do
      begin
        Symbol := SymbolArray.Items[I] as TJSONObject;
        SymbolName := Symbol.Get('name', '');

        // Look for the procedure in implementation section children
        if SymbolName = 'implementation' then
        begin
          Children := Symbol.FindPath('children') as TJSONArray;
          if Children <> nil then
            for J := 0 to Children.Count - 1 do
            begin
              Symbol := Children.Items[J] as TJSONObject;
              SymbolName := Symbol.Get('name', '');
              if SymbolName = 'DoSomething' then
              begin
                ProcFound := True;
                RangeObj := Symbol.FindPath('range') as TJSONObject;
                AssertNotNull('Procedure should have range', RangeObj);
                EndObj := RangeObj.FindPath('end') as TJSONObject;
                AssertNotNull('Range should have end', EndObj);
                EndLine := EndObj.Get('line', -1);
                EndChar := EndObj.Get('character', -1);

                // Verify we can access the source line
                AssertTrue(Format('EndLine %d should be valid', [EndLine]),
                  (EndLine >= 0) and (EndLine < SourceLines.Count));
                AssertTrue(Format('EndChar %d should be > 0 for exclusive end', [EndChar]),
                  EndChar > 0);

                // The character just before the exclusive end should be ';'
                // EndChar is 0-indexed, exclusive, so EndChar-1 is the last included char
                if EndChar <= Length(SourceLines[EndLine]) then
                  LastIncludedChar := SourceLines[EndLine][EndChar] // EndChar is 0-indexed, string is 1-indexed
                else
                  // EndChar points past line end, check previous char on same line
                  LastIncludedChar := SourceLines[EndLine][Length(SourceLines[EndLine])];

                AssertEquals(
                  Format('Last included char at line %d, col %d should be semicolon. ' +
                         'Line content: "%s"', [EndLine, EndChar-1, SourceLines[EndLine]]),
                  ';', LastIncludedChar);

                Break;
              end;
            end;
        end;
        if ProcFound then Break;
      end;

      AssertTrue('DoSomething procedure should be found', ProcFound);

    finally
      JSONData.Free;
    end;
  finally
    SourceLines.Free;
  end;
end;

procedure TTestDocumentSymbol.TestFlatModeRangeIncludesSemicolon;
{ Test that SymbolInformation (flat mode) location.range.end includes semicolon.
  This is critical for Serena's replace_symbol_body to work correctly.

  Bug history: AddFlatSymbol was not calling AdjustEndPositionForLSP,
  causing location.range.end.character to point AT the semicolon instead
  of PAST it, resulting in double semicolons when replacing symbol bodies. }
const
  TEST_SIMPLE_PROCEDURE =
    'unit TestProc;' + LineEnding +                         // line 0
    '' + LineEnding +                                        // line 1
    'interface' + LineEnding +                               // line 2
    '' + LineEnding +                                        // line 3
    'implementation' + LineEnding +                          // line 4
    '' + LineEnding +                                        // line 5
    'procedure DoSomething;' + LineEnding +                  // line 6
    'begin' + LineEnding +                                   // line 7
    '  writeln(''test'');' + LineEnding +                    // line 8
    'end;' + LineEnding +                                    // line 9: "end;" at cols 0-3, ';' at col 3
    '' + LineEnding +                                        // line 10
    'end.';                                                  // line 11
var
  RawJSON: String;
  JSONData: TJSONData;
  SymbolArray: TJSONArray;
  I: Integer;
  Symbol, LocationObj, RangeObj, EndObj: TJSONObject;
  SymbolName: String;
  EndLine, EndChar: Integer;
  SourceLines: TStringList;
  LastIncludedChar: Char;
  ProcFound: Boolean;
begin
  // Test flat mode (SymbolInformation format with location.range)
  SetClientCapabilities(False);
  CreateTestFile(TEST_SIMPLE_PROCEDURE);
  FTestCode := CodeToolBoss.LoadFile(FTestFile, True, False);
  AssertNotNull('Code buffer should be loaded', FTestCode);
  SymbolManager.Reload(FTestCode, True);
  RawJSON := SymbolManager.FindDocumentSymbols(FTestFile).AsJSON;

  // Parse source to verify character positions
  SourceLines := TStringList.Create;
  try
    SourceLines.Text := TEST_SIMPLE_PROCEDURE;

    JSONData := GetJSON(RawJSON);
    try
      AssertTrue('Result should be an array', JSONData is TJSONArray);
      SymbolArray := JSONData as TJSONArray;

      ProcFound := False;

      // In flat mode, symbols are at root level with location.range
      for I := 0 to SymbolArray.Count - 1 do
      begin
        Symbol := SymbolArray.Items[I] as TJSONObject;
        SymbolName := Symbol.Get('name', '');

        // Find DoSomething procedure
        if SymbolName = 'DoSomething' then
        begin
          ProcFound := True;

          // Flat mode uses location.range instead of range
          LocationObj := Symbol.FindPath('location') as TJSONObject;
          AssertNotNull('Procedure should have location', LocationObj);
          RangeObj := LocationObj.FindPath('range') as TJSONObject;
          AssertNotNull('Location should have range', RangeObj);
          EndObj := RangeObj.FindPath('end') as TJSONObject;
          AssertNotNull('Range should have end', EndObj);
          EndLine := EndObj.Get('line', -1);
          EndChar := EndObj.Get('character', -1);

          // Verify we can access the source line
          AssertTrue(Format('EndLine %d should be valid', [EndLine]),
            (EndLine >= 0) and (EndLine < SourceLines.Count));
          AssertTrue(Format('EndChar %d should be > 0 for exclusive end', [EndChar]),
            EndChar > 0);

          // The character just before the exclusive end should be ';'
          // EndChar is 0-indexed, exclusive, so EndChar-1 is the last included char
          // In Pascal 1-indexed string: EndChar maps to the last included char
          if EndChar <= Length(SourceLines[EndLine]) then
            LastIncludedChar := SourceLines[EndLine][EndChar]
          else
            LastIncludedChar := SourceLines[EndLine][Length(SourceLines[EndLine])];

          AssertEquals(
            Format('Flat mode: Last included char at line %d, col %d should be semicolon. ' +
                   'Line content: "%s", EndChar: %d',
                   [EndLine, EndChar-1, SourceLines[EndLine], EndChar]),
            ';', LastIncludedChar);

          Break;
        end;
      end;

      AssertTrue('DoSomething procedure should be found in flat mode', ProcFound);

    finally
      JSONData.Free;
    end;
  finally
    SourceLines.Free;
  end;
end;

procedure TTestDocumentSymbol.TestSingleLineSymbolRangeStaysOnSameLine;
{ Test that single-line symbols (fields, properties, method declarations)
  have range.start.line == range.end.line.

  Bug history: AdjustEndPositionForLSP incorrectly moved to next line when
  EndPos.X > Length(LineText), causing single-line symbols like "FName: String;"
  to have range extending to the next line. This caused incorrect highlighting
  in VS Code which uses range (not selectionRange) for symbol highlighting.

  Fix: Keep EndPos on same line by setting EndPos.X := Length(LineText) + 1
  instead of Inc(EndPos.Y); EndPos.X := 1; }

  procedure CheckSingleLineSymbol(const Symbol: TJSONObject; const Mode: String);
  var
    SymbolName: String;
    RangeObj, StartObj, EndObj, LocationObj: TJSONObject;
    StartLine, EndLine: Integer;
    Children: TJSONArray;
    I: Integer;
  begin
    SymbolName := Symbol.Get('name', '<unknown>');

    // Get range (hierarchical mode) or location.range (flat mode)
    RangeObj := Symbol.FindPath('range') as TJSONObject;
    if RangeObj = nil then
    begin
      LocationObj := Symbol.FindPath('location') as TJSONObject;
      if LocationObj <> nil then
        RangeObj := LocationObj.FindPath('range') as TJSONObject;
    end;

    if RangeObj <> nil then
    begin
      StartObj := RangeObj.FindPath('start') as TJSONObject;
      EndObj := RangeObj.FindPath('end') as TJSONObject;
      if (StartObj <> nil) and (EndObj <> nil) then
      begin
        StartLine := StartObj.Get('line', -1);
        EndLine := EndObj.Get('line', -1);

        // For field symbols (kind=8), they should be single-line
        // FName and FAge are fields that must stay on same line
        if (SymbolName = 'FName') or (SymbolName = 'FAge') then
        begin
          AssertEquals(
            Format('%s: Field "%s" range must stay on same line', [Mode, SymbolName]),
            StartLine, EndLine);
        end;
      end;
    end;

    // Recursively check children
    Children := Symbol.FindPath('children') as TJSONArray;
    if Children <> nil then
      for I := 0 to Children.Count - 1 do
        CheckSingleLineSymbol(Children.Items[I] as TJSONObject, Mode);
  end;

var
  RawJSON: String;
  JSONData: TJSONData;
  SymbolArray: TJSONArray;
  I: Integer;
begin
  // Test hierarchical mode (the mode where bug was observed)
  SetClientCapabilities(True);
  CreateTestFile(TEST_UNIT_WITH_PROPERTY_AND_FIELD);
  FTestCode := CodeToolBoss.LoadFile(FTestFile, True, False);
  AssertNotNull('Code buffer should be loaded', FTestCode);
  SymbolManager.Reload(FTestCode, True);
  RawJSON := SymbolManager.FindDocumentSymbols(FTestFile).AsJSON;

  JSONData := GetJSON(RawJSON);
  try
    AssertTrue('Result should be an array', JSONData is TJSONArray);
    SymbolArray := JSONData as TJSONArray;
    for I := 0 to SymbolArray.Count - 1 do
      CheckSingleLineSymbol(SymbolArray.Items[I] as TJSONObject, 'Hierarchical');
  finally
    JSONData.Free;
  end;

  CleanupTestFile;

  // Test flat mode as well
  SetClientCapabilities(False);
  CreateTestFile(TEST_UNIT_WITH_PROPERTY_AND_FIELD);
  FTestCode := CodeToolBoss.LoadFile(FTestFile, True, False);
  AssertNotNull('Code buffer should be loaded (flat)', FTestCode);
  SymbolManager.Reload(FTestCode, True);
  RawJSON := SymbolManager.FindDocumentSymbols(FTestFile).AsJSON;

  JSONData := GetJSON(RawJSON);
  try
    AssertTrue('Result should be an array (flat)', JSONData is TJSONArray);
    SymbolArray := JSONData as TJSONArray;
    for I := 0 to SymbolArray.Count - 1 do
      CheckSingleLineSymbol(SymbolArray.Items[I] as TJSONObject, 'Flat');
  finally
    JSONData.Free;
  end;
end;

procedure TTestDocumentSymbol.TestSymbolRangeExclusivity;
{ Test that range.end is exclusive for all symbol types:
  class, method, procedure, function, property, field.
  For multi-line symbols: end.line > start.line
  For single-line symbols: end.character > start.character
  Also verifies selectionRange has non-zero width }

  function GetRangeInfo(const RangeObj: TJSONObject; out StartLine, StartChar, EndLine, EndChar: Integer): Boolean;
  var
    StartObj, EndObj: TJSONObject;
  begin
    Result := False;
    if RangeObj = nil then Exit;
    StartObj := RangeObj.FindPath('start') as TJSONObject;
    EndObj := RangeObj.FindPath('end') as TJSONObject;
    if (StartObj = nil) or (EndObj = nil) then Exit;
    StartLine := StartObj.Get('line', -1);
    StartChar := StartObj.Get('character', -1);
    EndLine := EndObj.Get('line', -1);
    EndChar := EndObj.Get('character', -1);
    Result := (StartLine >= 0) and (StartChar >= 0) and (EndLine >= 0) and (EndChar >= 0);
  end;

  procedure CheckSymbolRange(const Symbol: TJSONObject; const Mode: String);
  var
    SymbolName: String;
    SymbolKind: Integer;
    RangeObj, SelRangeObj, LocationObj: TJSONObject;
    StartLine, StartChar, EndLine, EndChar: Integer;
    SelStartLine, SelStartChar, SelEndLine, SelEndChar: Integer;
    Children: TJSONArray;
    I: Integer;
  begin
    SymbolName := Symbol.Get('name', '<unknown>');
    SymbolKind := Symbol.Get('kind', 0);

    // Get range (hierarchical mode) or location.range (flat mode)
    RangeObj := Symbol.FindPath('range') as TJSONObject;
    if RangeObj = nil then
    begin
      LocationObj := Symbol.FindPath('location') as TJSONObject;
      if LocationObj <> nil then
        RangeObj := LocationObj.FindPath('range') as TJSONObject;
    end;

    if RangeObj <> nil then
    begin
      if GetRangeInfo(RangeObj, StartLine, StartChar, EndLine, EndChar) then
      begin
        // Range must have positive extent
        if EndLine = StartLine then
          AssertTrue(Format('%s: Symbol "%s" (kind %d) range on same line must have end.char > start.char',
            [Mode, SymbolName, SymbolKind]), EndChar > StartChar)
        else
          AssertTrue(Format('%s: Symbol "%s" (kind %d) multi-line range must have end.line >= start.line',
            [Mode, SymbolName, SymbolKind]), EndLine >= StartLine);
      end;
    end;

    // Check selectionRange (hierarchical mode only)
    SelRangeObj := Symbol.FindPath('selectionRange') as TJSONObject;
    if SelRangeObj <> nil then
    begin
      if GetRangeInfo(SelRangeObj, SelStartLine, SelStartChar, SelEndLine, SelEndChar) then
      begin
        // selectionRange should have non-zero width (typically same line)
        if SelEndLine = SelStartLine then
          AssertTrue(Format('%s: Symbol "%s" selectionRange must have width > 0',
            [Mode, SymbolName]), SelEndChar > SelStartChar);

        // selectionRange must be contained within range
        if RangeObj <> nil then
        begin
          AssertTrue(Format('%s: Symbol "%s" selectionRange.start must be >= range.start',
            [Mode, SymbolName]),
            (SelStartLine > StartLine) or ((SelStartLine = StartLine) and (SelStartChar >= StartChar)));
          AssertTrue(Format('%s: Symbol "%s" selectionRange.end must be <= range.end',
            [Mode, SymbolName]),
            (SelEndLine < EndLine) or ((SelEndLine = EndLine) and (SelEndChar <= EndChar)));
        end;
      end;
    end;

    // Recursively check children
    Children := Symbol.FindPath('children') as TJSONArray;
    if Children <> nil then
      for I := 0 to Children.Count - 1 do
        CheckSymbolRange(Children.Items[I] as TJSONObject, Mode);
  end;

var
  RawJSON: String;
  JSONData: TJSONData;
  SymbolArray: TJSONArray;
  I: Integer;
begin
  // Test hierarchical mode
  SetClientCapabilities(True);
  CreateTestFile(TEST_UNIT_WITH_PROPERTY_AND_FIELD);
  FTestCode := CodeToolBoss.LoadFile(FTestFile, True, False);
  AssertNotNull('Code buffer should be loaded', FTestCode);
  SymbolManager.Reload(FTestCode, True);
  RawJSON := SymbolManager.FindDocumentSymbols(FTestFile).AsJSON;

  JSONData := GetJSON(RawJSON);
  try
    AssertTrue('Result should be an array', JSONData is TJSONArray);
    SymbolArray := JSONData as TJSONArray;
    for I := 0 to SymbolArray.Count - 1 do
      CheckSymbolRange(SymbolArray.Items[I] as TJSONObject, 'Hierarchical');
  finally
    JSONData.Free;
  end;

  CleanupTestFile;

  // Test flat mode
  SetClientCapabilities(False);
  CreateTestFile(TEST_UNIT_WITH_PROPERTY_AND_FIELD);
  FTestCode := CodeToolBoss.LoadFile(FTestFile, True, False);
  AssertNotNull('Code buffer should be loaded (flat)', FTestCode);
  SymbolManager.Reload(FTestCode, True);
  RawJSON := SymbolManager.FindDocumentSymbols(FTestFile).AsJSON;

  JSONData := GetJSON(RawJSON);
  try
    AssertTrue('Result should be an array (flat)', JSONData is TJSONArray);
    SymbolArray := JSONData as TJSONArray;
    for I := 0 to SymbolArray.Count - 1 do
      CheckSymbolRange(SymbolArray.Items[I] as TJSONObject, 'Flat');
  finally
    JSONData.Free;
  end;
end;

procedure TTestDocumentSymbol.TestMethodSelectionRangePointsToName;
{ Test that selectionRange for methods points to the method NAME, not the
  "procedure"/"function" keyword.

  Bug history: SetNodeRange used Node.StartPos which for procedure nodes
  points to the "procedure" keyword. This caused selectionRange to highlight
  "procedure" instead of "MethodA1" in editors like Sublime Text.

  Fix: Use MoveCursorToProcName to find the actual name position. }
const
  TEST_METHOD_SELECTION =
    'unit TestMethod;' + LineEnding +                  // line 0
    '' + LineEnding +                                   // line 1
    'interface' + LineEnding +                          // line 2
    '' + LineEnding +                                   // line 3
    'type' + LineEnding +                               // line 4
    '  TMyClass = class' + LineEnding +                 // line 5
    '    procedure DoWork;' + LineEnding +              // line 6: "procedure" at 4, "DoWork" at 14
    '    function Calculate: Integer;' + LineEnding +   // line 7: "function" at 4, "Calculate" at 13
    '  end;' + LineEnding +                             // line 8
    '' + LineEnding +                                   // line 9
    'implementation' + LineEnding +                     // line 10
    '' + LineEnding +                                   // line 11
    'procedure TMyClass.DoWork;' + LineEnding +         // line 12: "procedure" at 0, "DoWork" at 19
    'begin' + LineEnding +                              // line 13
    'end;' + LineEnding +                               // line 14
    '' + LineEnding +                                   // line 15
    'function TMyClass.Calculate: Integer;' + LineEnding + // line 16: "function" at 0, "Calculate" at 18
    'begin' + LineEnding +                              // line 17
    '  Result := 42;' + LineEnding +                    // line 18
    'end;' + LineEnding +                               // line 19
    '' + LineEnding +                                   // line 20
    'end.';                                             // line 21
var
  RawJSON: String;
  JSONData: TJSONData;
  SymbolArray, Children, ClassChildren: TJSONArray;
  I, J, K: Integer;
  Symbol, ChildSymbol, MethodSymbol, SelRangeObj, StartObj: TJSONObject;
  SymbolName: String;
  SelStartChar: Integer;
  DoWorkFoundInterface, CalculateFoundInterface: Boolean;
  DoWorkFoundImpl, CalculateFoundImpl: Boolean;
begin
  // Test hierarchical mode
  SetClientCapabilities(True);
  CreateTestFile(TEST_METHOD_SELECTION);
  FTestCode := CodeToolBoss.LoadFile(FTestFile, True, False);
  AssertNotNull('Code buffer should be loaded', FTestCode);
  SymbolManager.Reload(FTestCode, True);
  RawJSON := SymbolManager.FindDocumentSymbols(FTestFile).AsJSON;

  DoWorkFoundInterface := False;
  CalculateFoundInterface := False;
  DoWorkFoundImpl := False;
  CalculateFoundImpl := False;

  JSONData := GetJSON(RawJSON);
  try
    AssertTrue('Result should be an array', JSONData is TJSONArray);
    SymbolArray := JSONData as TJSONArray;

    // Find methods in interface (class declaration) and implementation
    for I := 0 to SymbolArray.Count - 1 do
    begin
      Symbol := SymbolArray.Items[I] as TJSONObject;
      SymbolName := Symbol.Get('name', '');

      // Check interface section - class with method declarations
      if SymbolName = 'interface' then
      begin
        Children := Symbol.FindPath('children') as TJSONArray;
        if Children <> nil then
          for J := 0 to Children.Count - 1 do
          begin
            ChildSymbol := Children.Items[J] as TJSONObject;
            if ChildSymbol.Get('name', '') = 'TMyClass' then
            begin
              // Find methods inside class
              ClassChildren := ChildSymbol.FindPath('children') as TJSONArray;
              if ClassChildren <> nil then
                for K := 0 to ClassChildren.Count - 1 do
                begin
                  MethodSymbol := ClassChildren.Items[K] as TJSONObject;
                  SymbolName := MethodSymbol.Get('name', '');

                  SelRangeObj := MethodSymbol.FindPath('selectionRange') as TJSONObject;
                  if SelRangeObj <> nil then
                  begin
                    StartObj := SelRangeObj.FindPath('start') as TJSONObject;
                    if StartObj <> nil then
                    begin
                      SelStartChar := StartObj.Get('character', -1);

                      if SymbolName = 'DoWork' then
                      begin
                        DoWorkFoundInterface := True;
                        // Line 6: "    procedure DoWork;"
                        // "DoWork" starts at char 14, not char 4 (where "procedure" starts)
                        AssertEquals(
                          'Interface DoWork selectionRange.start.character should point to name',
                          14, SelStartChar);
                      end
                      else if SymbolName = 'Calculate' then
                      begin
                        CalculateFoundInterface := True;
                        // Line 7: "    function Calculate: Integer;"
                        // "Calculate" starts at char 13, not char 4 (where "function" starts)
                        AssertEquals(
                          'Interface Calculate selectionRange.start.character should point to name',
                          13, SelStartChar);
                      end;
                    end;
                  end;
                end;
              Break;
            end;
          end;
      end

      // Check implementation section - class method implementations
      else if SymbolName = 'implementation' then
      begin
        Children := Symbol.FindPath('children') as TJSONArray;
        if Children <> nil then
          for J := 0 to Children.Count - 1 do
          begin
            ChildSymbol := Children.Items[J] as TJSONObject;
            if ChildSymbol.Get('name', '') = 'TMyClass' then
            begin
              // Find methods inside implementation class container
              ClassChildren := ChildSymbol.FindPath('children') as TJSONArray;
              if ClassChildren <> nil then
                for K := 0 to ClassChildren.Count - 1 do
                begin
                  MethodSymbol := ClassChildren.Items[K] as TJSONObject;
                  SymbolName := MethodSymbol.Get('name', '');

                  SelRangeObj := MethodSymbol.FindPath('selectionRange') as TJSONObject;
                  if SelRangeObj <> nil then
                  begin
                    StartObj := SelRangeObj.FindPath('start') as TJSONObject;
                    if StartObj <> nil then
                    begin
                      SelStartChar := StartObj.Get('character', -1);

                      if SymbolName = 'DoWork' then
                      begin
                        DoWorkFoundImpl := True;
                        // Line 12: "procedure TMyClass.DoWork;"
                        // "DoWork" starts at char 19, not char 0 (where "procedure" starts)
                        AssertEquals(
                          'Implementation DoWork selectionRange.start.character should point to name',
                          19, SelStartChar);
                      end
                      else if SymbolName = 'Calculate' then
                      begin
                        CalculateFoundImpl := True;
                        // Line 16: "function TMyClass.Calculate: Integer;"
                        // "Calculate" starts at char 18, not char 0 (where "function" starts)
                        AssertEquals(
                          'Implementation Calculate selectionRange.start.character should point to name',
                          18, SelStartChar);
                      end;
                    end;
                  end;
                end;
              Break;
            end;
          end;
      end;
    end;

    AssertTrue('DoWork should be found in interface', DoWorkFoundInterface);
    AssertTrue('Calculate should be found in interface', CalculateFoundInterface);
    AssertTrue('DoWork should be found in implementation', DoWorkFoundImpl);
    AssertTrue('Calculate should be found in implementation', CalculateFoundImpl);

  finally
    JSONData.Free;
  end;
end;

procedure TTestDocumentSymbol.TestHierarchicalModeFullValidation;
{ Comprehensive test for hierarchical mode (DocumentSymbol[]).
  Validates exact line and character positions for all symbols.
  Uses TEST_FULL_VALIDATION_FILE which has precise position comments.

  Expected symbol hierarchy:
  - interface (line 6)
    - TTestClassA (line 9)
      - FValue (line 11)
      - MethodA1 (line 13)
      - MethodA2 (line 14)
    - GlobalProc (line 17)
  - implementation (line 19)
    - TTestClassA (container for methods)
      - MethodA1 (line 21)
        - NestedProc (line 25)
      - MethodA2 (line 34)
    - GlobalProc (line 39)
}

  procedure CheckSelectionRange(Symbol: TJSONObject; const SymbolName: String;
    ExpStartLine, ExpStartChar, ExpEndLine, ExpEndChar: Integer);
  var
    SelRange, StartObj, EndObj: TJSONObject;
    ActStartLine, ActStartChar, ActEndLine, ActEndChar: Integer;
  begin
    SelRange := Symbol.FindPath('selectionRange') as TJSONObject;
    AssertNotNull(Format('%s should have selectionRange', [SymbolName]), SelRange);

    StartObj := SelRange.FindPath('start') as TJSONObject;
    EndObj := SelRange.FindPath('end') as TJSONObject;
    AssertNotNull(Format('%s selectionRange should have start', [SymbolName]), StartObj);
    AssertNotNull(Format('%s selectionRange should have end', [SymbolName]), EndObj);

    ActStartLine := StartObj.Get('line', -1);
    ActStartChar := StartObj.Get('character', -1);
    ActEndLine := EndObj.Get('line', -1);
    ActEndChar := EndObj.Get('character', -1);

    AssertEquals(Format('%s selectionRange.start.line', [SymbolName]), ExpStartLine, ActStartLine);
    AssertEquals(Format('%s selectionRange.start.character', [SymbolName]), ExpStartChar, ActStartChar);
    AssertEquals(Format('%s selectionRange.end.line', [SymbolName]), ExpEndLine, ActEndLine);
    AssertEquals(Format('%s selectionRange.end.character', [SymbolName]), ExpEndChar, ActEndChar);
  end;

  function FindSymbolByName(Arr: TJSONArray; const Name: String): TJSONObject;
  var
    I: Integer;
    Obj: TJSONObject;
  begin
    Result := nil;
    if Arr = nil then Exit;
    for I := 0 to Arr.Count - 1 do
    begin
      Obj := Arr.Items[I] as TJSONObject;
      if Obj.Get('name', '') = Name then
        Exit(Obj);
    end;
  end;

var
  RawJSON: String;
  JSONData: TJSONData;
  SymbolArray, InterfaceChildren, ImplChildren, ClassChildren, MethodChildren: TJSONArray;
  InterfaceSymbol, ImplSymbol, ClassSymbol, MethodSymbol, NestedSymbol: TJSONObject;
begin
  // Test hierarchical mode
  SetClientCapabilities(True);
  CreateTestFile(TEST_FULL_VALIDATION_FILE);
  FTestCode := CodeToolBoss.LoadFile(FTestFile, True, False);
  AssertNotNull('Code buffer should be loaded', FTestCode);
  SymbolManager.Reload(FTestCode, True);
  RawJSON := SymbolManager.FindDocumentSymbols(FTestFile).AsJSON;

  JSONData := GetJSON(RawJSON);
  try
    AssertTrue('Result should be an array', JSONData is TJSONArray);
    SymbolArray := JSONData as TJSONArray;

    // Find interface section
    InterfaceSymbol := FindSymbolByName(SymbolArray, 'interface');
    AssertNotNull('Interface symbol should exist', InterfaceSymbol);
    // "interface" at line 6, char 0-8 (length 9)
    CheckSelectionRange(InterfaceSymbol, 'interface', 6, 0, 6, 9);

    // Check interface children
    InterfaceChildren := InterfaceSymbol.FindPath('children') as TJSONArray;
    AssertNotNull('Interface should have children', InterfaceChildren);

    // TTestClassA in interface at line 9
    // "  TTestClassA = class" -> "TTestClassA" at char 2-12 (length 11)
    ClassSymbol := FindSymbolByName(InterfaceChildren, 'TTestClassA');
    AssertNotNull('TTestClassA should exist in interface', ClassSymbol);
    CheckSelectionRange(ClassSymbol, 'interface.TTestClassA', 9, 2, 9, 13);

    ClassChildren := ClassSymbol.FindPath('children') as TJSONArray;
    AssertNotNull('TTestClassA should have children', ClassChildren);

    // FValue at line 11: "    FValue: Integer;" -> "FValue" at char 4-9 (length 6)
    MethodSymbol := FindSymbolByName(ClassChildren, 'FValue');
    AssertNotNull('FValue should exist', MethodSymbol);
    CheckSelectionRange(MethodSymbol, 'FValue', 11, 4, 11, 10);

    // MethodA1 at line 13: "    procedure MethodA1;" -> "MethodA1" at char 14-21 (length 8)
    MethodSymbol := FindSymbolByName(ClassChildren, 'MethodA1');
    AssertNotNull('MethodA1 should exist in interface', MethodSymbol);
    CheckSelectionRange(MethodSymbol, 'interface.MethodA1', 13, 14, 13, 22);

    // MethodA2 at line 14: "    function MethodA2: Integer;" -> "MethodA2" at char 13-20 (length 8)
    MethodSymbol := FindSymbolByName(ClassChildren, 'MethodA2');
    AssertNotNull('MethodA2 should exist in interface', MethodSymbol);
    CheckSelectionRange(MethodSymbol, 'interface.MethodA2', 14, 13, 14, 21);

    // GlobalProc at line 17: "procedure GlobalProc;" -> "GlobalProc" at char 10-19 (length 10)
    MethodSymbol := FindSymbolByName(InterfaceChildren, 'GlobalProc');
    AssertNotNull('GlobalProc should exist in interface', MethodSymbol);
    CheckSelectionRange(MethodSymbol, 'interface.GlobalProc', 17, 10, 17, 20);

    // Find implementation section
    ImplSymbol := FindSymbolByName(SymbolArray, 'implementation');
    AssertNotNull('Implementation symbol should exist', ImplSymbol);
    // "implementation" at line 19, char 0-13 (length 14)
    CheckSelectionRange(ImplSymbol, 'implementation', 19, 0, 19, 14);

    ImplChildren := ImplSymbol.FindPath('children') as TJSONArray;
    AssertNotNull('Implementation should have children', ImplChildren);

    // TTestClassA container in implementation
    ClassSymbol := FindSymbolByName(ImplChildren, 'TTestClassA');
    AssertNotNull('TTestClassA should exist in implementation', ClassSymbol);

    ClassChildren := ClassSymbol.FindPath('children') as TJSONArray;
    AssertNotNull('TTestClassA impl should have children', ClassChildren);

    // MethodA1 implementation at line 21: "procedure TTestClassA.MethodA1;"
    // "MethodA1" at char 22-29 (length 8)
    MethodSymbol := FindSymbolByName(ClassChildren, 'MethodA1');
    AssertNotNull('MethodA1 should exist in implementation', MethodSymbol);
    CheckSelectionRange(MethodSymbol, 'impl.MethodA1', 21, 22, 21, 30);

    // Check nested function: NestedProc at line 25
    // "  procedure NestedProc;" -> "NestedProc" at char 12-21 (length 10)
    MethodChildren := MethodSymbol.FindPath('children') as TJSONArray;
    AssertNotNull('MethodA1 should have children (nested)', MethodChildren);
    NestedSymbol := FindSymbolByName(MethodChildren, 'NestedProc');
    AssertNotNull('NestedProc should exist', NestedSymbol);
    CheckSelectionRange(NestedSymbol, 'NestedProc', 25, 12, 25, 22);

    // MethodA2 implementation at line 34: "function TTestClassA.MethodA2: Integer;"
    // "MethodA2" at char 21-28 (length 8)
    MethodSymbol := FindSymbolByName(ClassChildren, 'MethodA2');
    AssertNotNull('MethodA2 should exist in implementation', MethodSymbol);
    CheckSelectionRange(MethodSymbol, 'impl.MethodA2', 34, 21, 34, 29);

    // GlobalProc implementation at line 39: "procedure GlobalProc;"
    // "GlobalProc" at char 10-19 (length 10)
    MethodSymbol := FindSymbolByName(ImplChildren, 'GlobalProc');
    AssertNotNull('GlobalProc should exist in implementation', MethodSymbol);
    CheckSelectionRange(MethodSymbol, 'impl.GlobalProc', 39, 10, 39, 20);

  finally
    JSONData.Free;
  end;
end;

procedure TTestDocumentSymbol.TestFlatModeFullValidation;
{ Comprehensive test for flat mode (SymbolInformation[]).
  Validates exact line and character positions for all symbols via location.range.
  Uses TEST_FULL_VALIDATION_FILE which has precise position comments.

  In flat mode, symbols have location.range (not range/selectionRange).
  The range should span from symbol start to end (inclusive of semicolon).
}

  procedure CheckLocationRange(Symbol: TJSONObject; const SymbolName: String;
    ExpStartLine, ExpStartChar: Integer);
  var
    Location, RangeObj, StartObj: TJSONObject;
    ActStartLine, ActStartChar: Integer;
  begin
    Location := Symbol.FindPath('location') as TJSONObject;
    AssertNotNull(Format('%s should have location', [SymbolName]), Location);

    RangeObj := Location.FindPath('range') as TJSONObject;
    AssertNotNull(Format('%s location should have range', [SymbolName]), RangeObj);

    StartObj := RangeObj.FindPath('start') as TJSONObject;
    AssertNotNull(Format('%s range should have start', [SymbolName]), StartObj);

    ActStartLine := StartObj.Get('line', -1);
    ActStartChar := StartObj.Get('character', -1);

    AssertEquals(Format('%s location.range.start.line', [SymbolName]), ExpStartLine, ActStartLine);
    AssertEquals(Format('%s location.range.start.character', [SymbolName]), ExpStartChar, ActStartChar);
  end;

  function FindSymbolByName(Arr: TJSONArray; const Name: String): TJSONObject;
  var
    I: Integer;
    Obj: TJSONObject;
  begin
    Result := nil;
    if Arr = nil then Exit;
    for I := 0 to Arr.Count - 1 do
    begin
      Obj := Arr.Items[I] as TJSONObject;
      if Obj.Get('name', '') = Name then
        Exit(Obj);
    end;
  end;

var
  RawJSON: String;
  JSONData: TJSONData;
  SymbolArray: TJSONArray;
  Symbol: TJSONObject;
begin
  // Test flat mode
  SetClientCapabilities(False);
  CreateTestFile(TEST_FULL_VALIDATION_FILE);
  FTestCode := CodeToolBoss.LoadFile(FTestFile, True, False);
  AssertNotNull('Code buffer should be loaded', FTestCode);
  SymbolManager.Reload(FTestCode, True);
  RawJSON := SymbolManager.FindDocumentSymbols(FTestFile).AsJSON;

  JSONData := GetJSON(RawJSON);
  try
    AssertTrue('Result should be an array', JSONData is TJSONArray);
    SymbolArray := JSONData as TJSONArray;

    // In flat mode, symbols use ClassName.MemberName naming
    // Check interface section symbol
    Symbol := FindSymbolByName(SymbolArray, 'interface');
    AssertNotNull('interface symbol should exist', Symbol);
    CheckLocationRange(Symbol, 'interface', 6, 0);

    // TTestClassA at line 9
    Symbol := FindSymbolByName(SymbolArray, 'TTestClassA');
    AssertNotNull('TTestClassA should exist', Symbol);
    CheckLocationRange(Symbol, 'TTestClassA', 9, 2);

    // TTestClassA.FValue at line 11 (flat mode uses Class.Member naming)
    Symbol := FindSymbolByName(SymbolArray, 'TTestClassA.FValue');
    AssertNotNull('TTestClassA.FValue should exist', Symbol);
    CheckLocationRange(Symbol, 'TTestClassA.FValue', 11, 4);

    // TTestClassA.MethodA1 at line 13 (interface declaration)
    Symbol := FindSymbolByName(SymbolArray, 'TTestClassA.MethodA1');
    AssertNotNull('TTestClassA.MethodA1 should exist', Symbol);
    CheckLocationRange(Symbol, 'TTestClassA.MethodA1', 13, 4);

    // TTestClassA.MethodA2 at line 14 (interface declaration)
    Symbol := FindSymbolByName(SymbolArray, 'TTestClassA.MethodA2');
    AssertNotNull('TTestClassA.MethodA2 should exist', Symbol);
    CheckLocationRange(Symbol, 'TTestClassA.MethodA2', 14, 4);

    // GlobalProc at line 17
    Symbol := FindSymbolByName(SymbolArray, 'GlobalProc');
    AssertNotNull('GlobalProc should exist', Symbol);
    CheckLocationRange(Symbol, 'GlobalProc', 17, 0);

    // implementation section symbol
    Symbol := FindSymbolByName(SymbolArray, 'implementation');
    AssertNotNull('implementation symbol should exist', Symbol);
    CheckLocationRange(Symbol, 'implementation', 19, 0);

    // Note: In flat mode, implementation methods have different positions
    // because they start with "procedure TClassName.MethodName"
    // MethodA1 at line 21 is now a method (not TTestClassA.MethodA1 duplicate)
    // The overloadPolicy setting determines how duplicates are handled

  finally
    JSONData.Free;
  end;
end;

procedure TTestDocumentSymbol.TestEnumSymbolsHierarchical;
var
  RawJSON: String;
begin
  // This test verifies that enum types appear in hierarchical mode
  // (Bug: enums were bypassing TSymbolBuilder, missing from hierarchical output)

  // Set hierarchical mode
  SetClientCapabilities(True);

  // Create test file with enum types
  CreateTestFile(TEST_UNIT_WITH_ENUM);

  // Load code buffer
  FTestCode := CodeToolBoss.LoadFile(FTestFile, True, False);
  AssertNotNull('Code buffer should be loaded', FTestCode);

  // Use SymbolManager to reload and extract symbols
  SymbolManager.Reload(FTestCode, True);

  // Get the raw JSON from SymbolManager
  RawJSON := SymbolManager.FindDocumentSymbols(FTestFile).AsJSON;

  // Verify we extracted symbols
  AssertTrue('Should have extracted symbols', RawJSON <> '');

  // Verify enum symbols are present (kind 10 = Enum)
  AssertTrue('JSON should contain TColor enum', Pos('"TColor"', RawJSON) > 0);
  AssertTrue('JSON should contain TStatus enum', Pos('"TStatus"', RawJSON) > 0);
  AssertTrue('Should have Enum kind (10)', Pos('"kind" : 10', RawJSON) > 0);

  // Verify hierarchical structure (children array should exist)
  AssertTrue('Should have children in hierarchical mode', Pos('"children"', RawJSON) > 0);

  // Verify class also exists (to confirm other symbols still work)
  AssertTrue('JSON should contain TMyClass', Pos('"TMyClass"', RawJSON) > 0);
end;

procedure TTestDocumentSymbol.TestEnumSymbolsFlat;
var
  RawJSON: String;
begin
  // This test verifies that enum types appear in flat mode

  // Set flat mode
  SetClientCapabilities(False);

  // Create test file with enum types
  CreateTestFile(TEST_UNIT_WITH_ENUM);

  // Load code buffer
  FTestCode := CodeToolBoss.LoadFile(FTestFile, True, False);
  AssertNotNull('Code buffer should be loaded', FTestCode);

  // Use SymbolManager to reload and extract symbols
  SymbolManager.Reload(FTestCode, True);

  // Get the raw JSON from SymbolManager
  RawJSON := SymbolManager.FindDocumentSymbols(FTestFile).AsJSON;

  // Verify we extracted symbols
  AssertTrue('Should have extracted symbols', RawJSON <> '');

  // Verify enum symbols are present (kind 10 = Enum)
  AssertTrue('JSON should contain TColor enum', Pos('"TColor"', RawJSON) > 0);
  AssertTrue('JSON should contain TStatus enum', Pos('"TStatus"', RawJSON) > 0);
  AssertTrue('Should have Enum kind (10)', Pos('"kind" : 10', RawJSON) > 0);

  // Verify class also exists (to confirm other symbols still work)
  AssertTrue('JSON should contain TMyClass', Pos('"TMyClass"', RawJSON) > 0);
end;

procedure TTestDocumentSymbol.TestTypeAliasSymbolsHierarchical;
var
  RawJSON: String;
begin
  // This test verifies that type aliases appear in hierarchical mode
  // (Bug: type aliases were bypassing TSymbolBuilder, missing from hierarchical output)

  // Set hierarchical mode
  SetClientCapabilities(True);

  // Create test file with type alias types
  CreateTestFile(TEST_UNIT_WITH_TYPE_ALIAS);

  // Load code buffer
  FTestCode := CodeToolBoss.LoadFile(FTestFile, True, False);
  AssertNotNull('Code buffer should be loaded', FTestCode);

  // Use SymbolManager to reload and extract symbols
  SymbolManager.Reload(FTestCode, True);

  // Get the raw JSON from SymbolManager
  RawJSON := SymbolManager.FindDocumentSymbols(FTestFile).AsJSON;

  // Verify we extracted symbols
  AssertTrue('Should have extracted symbols', RawJSON <> '');

  // Verify type alias symbols are present (kind 26 = TypeParameter)
  AssertTrue('JSON should contain TMyInteger', Pos('"TMyInteger"', RawJSON) > 0);
  AssertTrue('JSON should contain PInteger', Pos('"PInteger"', RawJSON) > 0);
  AssertTrue('JSON should contain TMySet', Pos('"TMySet"', RawJSON) > 0);
  AssertTrue('JSON should contain TMyProc', Pos('"TMyProc"', RawJSON) > 0);
  AssertTrue('JSON should contain TMyArray', Pos('"TMyArray"', RawJSON) > 0);
  AssertTrue('Should have TypeParameter kind (26)', Pos('"kind" : 26', RawJSON) > 0);

  // Verify hierarchical structure (children array should exist)
  AssertTrue('Should have children in hierarchical mode', Pos('"children"', RawJSON) > 0);

  // Verify class also exists (to confirm other symbols still work)
  AssertTrue('JSON should contain TMyClass', Pos('"TMyClass"', RawJSON) > 0);
end;

procedure TTestDocumentSymbol.TestTypeAliasSymbolsFlat;
var
  RawJSON: String;
begin
  // This test verifies that type aliases appear in flat mode

  // Set flat mode
  SetClientCapabilities(False);

  // Create test file with type alias types
  CreateTestFile(TEST_UNIT_WITH_TYPE_ALIAS);

  // Load code buffer
  FTestCode := CodeToolBoss.LoadFile(FTestFile, True, False);
  AssertNotNull('Code buffer should be loaded', FTestCode);

  // Use SymbolManager to reload and extract symbols
  SymbolManager.Reload(FTestCode, True);

  // Get the raw JSON from SymbolManager
  RawJSON := SymbolManager.FindDocumentSymbols(FTestFile).AsJSON;

  // Verify we extracted symbols
  AssertTrue('Should have extracted symbols', RawJSON <> '');

  // Verify type alias symbols are present (kind 26 = TypeParameter)
  AssertTrue('JSON should contain TMyInteger', Pos('"TMyInteger"', RawJSON) > 0);
  AssertTrue('JSON should contain PInteger', Pos('"PInteger"', RawJSON) > 0);
  AssertTrue('JSON should contain TMySet', Pos('"TMySet"', RawJSON) > 0);
  AssertTrue('JSON should contain TMyProc', Pos('"TMyProc"', RawJSON) > 0);
  AssertTrue('JSON should contain TMyArray', Pos('"TMyArray"', RawJSON) > 0);
  AssertTrue('Should have TypeParameter kind (26)', Pos('"kind" : 26', RawJSON) > 0);

  // Verify class also exists (to confirm other symbols still work)
  AssertTrue('JSON should contain TMyClass', Pos('"TMyClass"', RawJSON) > 0);
end;

initialization
  RegisterTest(TTestDocumentSymbol);
end.
