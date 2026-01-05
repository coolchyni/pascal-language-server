unit Tests.SymbolPersistence;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, fpjson, jsonparser,
  CodeToolManager, CodeCache,
  PasLS.Symbols, PasLS.ClientProfile;

type

  { TTestSymbolPersistence }

  TTestSymbolPersistence = class(TTestCase)
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
    // Phase 1: Infrastructure tests
    procedure TestWorkspacePathsInitialized;
    procedure TestNormalizePathCaseInsensitiveOnWindows;
    procedure TestIsFileInWorkspacePositive;
    procedure TestIsFileInWorkspaceNegative;

    // Phase 2: didClose behavior tests
    procedure TestUnloadFileKeepsDBSymbols;
    procedure TestUnloadFileSetsUnloadedFlag;
    procedure TestRemoveFileDeletesDBSymbols;
    procedure TestReopenUnloadedFileReloads;

    // Phase 3: didSave behavior tests
    procedure TestDidSaveUpdatesDatabase;
    procedure TestWorkspaceSymbolAfterDidSave;
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
    '  end;' + LineEnding +
    '' + LineEnding +
    'function GlobalFunc: Boolean;' + LineEnding +
    '' + LineEnding +
    'implementation' + LineEnding +
    '' + LineEnding +
    'procedure TMyClass.MethodA;' + LineEnding +
    'begin' + LineEnding +
    'end;' + LineEnding +
    '' + LineEnding +
    'function GlobalFunc: Boolean;' + LineEnding +
    'begin' + LineEnding +
    '  Result := True;' + LineEnding +
    'end;' + LineEnding +
    '' + LineEnding +
    'end.';

{ TTestSymbolPersistence }

procedure TTestSymbolPersistence.CreateTestFile(const AContent: String);
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

  ExistingBuffer := CodeToolBoss.FindFile(FTestFile);
  if ExistingBuffer <> nil then
    ExistingBuffer.Revert;
end;

procedure TTestSymbolPersistence.CleanupTestFile;
begin
  FTestCode := nil;
  if FTestFile <> '' then
    begin
    if FileExists(FTestFile) then
      DeleteFile(FTestFile);
    FTestFile := '';
    end;
end;

function TTestSymbolPersistence.ParseSymbols(const RawJSON: String): TJSONArray;
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

procedure TTestSymbolPersistence.SetUp;
begin
  inherited SetUp;
  FTestCode := nil;
  FTestFile := '';

  if SymbolManager = nil then
    SymbolManager := TSymbolManager.Create;

  TClientProfile.SelectProfile('');
  SetClientCapabilities(True);
end;

procedure TTestSymbolPersistence.TearDown;
begin
  CleanupTestFile;
  FTestCode := nil;
  TClientProfile.SelectProfile('');
  SetClientCapabilities(False);
  inherited TearDown;
end;

// Phase 1: Infrastructure tests

procedure TTestSymbolPersistence.TestWorkspacePathsInitialized;
begin
  // WorkspacePaths should be initialized (not nil) after SymbolManager creation
  AssertNotNull('WorkspacePaths should be initialized', SymbolManager.WorkspacePaths);
end;

procedure TTestSymbolPersistence.TestNormalizePathCaseInsensitiveOnWindows;
var
  Path1, Path2: String;
begin
  {$IFDEF WINDOWS}
  Path1 := SymbolManager.NormalizePath('C:\Test\Path');
  Path2 := SymbolManager.NormalizePath('c:\test\path');
  AssertEquals('Paths should be equal on Windows (case insensitive)', Path1, Path2);
  {$ELSE}
  // On Unix, paths are case-sensitive
  Path1 := SymbolManager.NormalizePath('/Test/Path');
  Path2 := SymbolManager.NormalizePath('/test/path');
  AssertTrue('Paths should be different on Unix (case sensitive)', Path1 <> Path2);
  {$ENDIF}
end;

procedure TTestSymbolPersistence.TestIsFileInWorkspacePositive;
var
  TestDir: String;
begin
  // Add a workspace path
  TestDir := ExtractFilePath(ParamStr(0));
  SymbolManager.WorkspacePaths.Clear;
  SymbolManager.WorkspacePaths.Add(SymbolManager.NormalizePath(TestDir));

  // File in workspace should return True
  AssertTrue('File in workspace should return True',
    SymbolManager.IsFileInWorkspace(TestDir + 'test.pas'));
end;

procedure TTestSymbolPersistence.TestIsFileInWorkspaceNegative;
var
  TestDir: String;
begin
  // Add a workspace path
  TestDir := ExtractFilePath(ParamStr(0));
  SymbolManager.WorkspacePaths.Clear;
  SymbolManager.WorkspacePaths.Add(SymbolManager.NormalizePath(TestDir));

  // File outside workspace should return False
  {$IFDEF WINDOWS}
  AssertFalse('File outside workspace should return False',
    SymbolManager.IsFileInWorkspace('C:\OtherDir\test.pas'));
  {$ELSE}
  AssertFalse('File outside workspace should return False',
    SymbolManager.IsFileInWorkspace('/other/dir/test.pas'));
  {$ENDIF}
end;

// Phase 2: didClose behavior tests
// NOTE: These tests require UnloadFile, IsFileUnloaded methods (Task 5+)

procedure TTestSymbolPersistence.TestUnloadFileKeepsDBSymbols;
begin
  // TODO: Implement when UnloadFile is added (Task 5+)
  Ignore('UnloadFile not yet implemented');
end;

procedure TTestSymbolPersistence.TestUnloadFileSetsUnloadedFlag;
var
  FileName: String;
begin
  // Test that UnloadFile sets the Unloaded flag (without database)
  CreateTestFile(TEST_WORKSPACE_UNIT);
  FTestCode := CodeToolBoss.LoadFile(FTestFile, True, False);
  AssertNotNull('Code buffer should be loaded', FTestCode);

  // Add file to workspace
  SymbolManager.WorkspacePaths.Clear;
  SymbolManager.WorkspacePaths.Add(SymbolManager.NormalizePath(ExtractFilePath(FTestFile)));

  // Load symbols into memory
  SymbolManager.Reload(FTestCode, True);

  // File should not be unloaded yet
  FileName := ExtractFileName(FTestFile);
  AssertFalse('File should not be unloaded initially',
    SymbolManager.IsFileUnloaded(FileName));

  // Unload the file (simulating didClose for workspace file)
  SymbolManager.UnloadFile(FileName);

  // Now the file should be marked as unloaded
  AssertTrue('File should be marked as unloaded after UnloadFile',
    SymbolManager.IsFileUnloaded(FileName));
end;

procedure TTestSymbolPersistence.TestRemoveFileDeletesDBSymbols;
var
  Result: TJSONData;
  SymbolArray: TJSONArray;
  FileName: String;
begin
  CreateTestFile(TEST_WORKSPACE_UNIT);
  FTestCode := CodeToolBoss.LoadFile(FTestFile, True, False);
  AssertNotNull('Code buffer should be loaded', FTestCode);

  // Do NOT add to workspace paths (external file)
  SymbolManager.WorkspacePaths.Clear;

  SymbolManager.Reload(FTestCode, True);

  // Verify symbols exist before remove
  Result := SymbolManager.FindWorkspaceSymbols('TMyClass');
  SymbolArray := ParseSymbols(Result.AsJSON);
  try
    AssertTrue('Should find TMyClass before remove', SymbolArray.Count > 0);
  finally
    SymbolArray.Free;
  end;

  // Remove the file (simulating didClose for external file)
  FileName := ExtractFileName(FTestFile);
  SymbolManager.RemoveFile(FileName);

  // Verify symbols are gone after remove
  Result := SymbolManager.FindWorkspaceSymbols('TMyClass');
  SymbolArray := ParseSymbols(Result.AsJSON);
  try
    AssertEquals('Should NOT find TMyClass after remove', 0, SymbolArray.Count);
  finally
    SymbolArray.Free;
  end;
end;

procedure TTestSymbolPersistence.TestReopenUnloadedFileReloads;
var
  FileName: String;
begin
  // Test that reopening an unloaded file clears the Unloaded flag
  // via Reload (which internally calls GetEntry)
  CreateTestFile(TEST_WORKSPACE_UNIT);
  FTestCode := CodeToolBoss.LoadFile(FTestFile, True, False);
  AssertNotNull('Code buffer should be loaded', FTestCode);

  // Add file to workspace
  SymbolManager.WorkspacePaths.Clear;
  SymbolManager.WorkspacePaths.Add(SymbolManager.NormalizePath(ExtractFilePath(FTestFile)));

  // Load symbols into memory (this calls GetEntry internally)
  SymbolManager.Reload(FTestCode, True);
  FileName := ExtractFileName(FTestFile);

  // File should not be unloaded yet
  AssertFalse('File should not be unloaded initially',
    SymbolManager.IsFileUnloaded(FileName));

  // Unload the file (simulating didClose for workspace file)
  SymbolManager.UnloadFile(FileName);

  // Now the file should be marked as unloaded
  AssertTrue('File should be marked as unloaded after UnloadFile',
    SymbolManager.IsFileUnloaded(FileName));

  // Reopen the file via Reload (which calls GetEntry internally)
  // GetEntry should clear the Unloaded flag and set Modified
  SymbolManager.Reload(FTestCode, True);

  // The file should no longer be marked as unloaded
  AssertFalse('File should not be unloaded after reopening via Reload',
    SymbolManager.IsFileUnloaded(FileName));
end;

// Phase 3: didSave behavior tests

procedure TTestSymbolPersistence.TestDidSaveUpdatesDatabase;
begin
  // This test validates that saving updates the database proactively
  // Will be implemented with the didSave handler changes
  CreateTestFile(TEST_WORKSPACE_UNIT);
  FTestCode := CodeToolBoss.LoadFile(FTestFile, True, False);
  AssertNotNull('Code buffer should be loaded', FTestCode);

  SymbolManager.WorkspacePaths.Clear;
  SymbolManager.WorkspacePaths.Add(SymbolManager.NormalizePath(ExtractFilePath(FTestFile)));

  // Mark as modified (simulating didChange)
  SymbolManager.FileModified(FTestCode);

  // Proactive reload (simulating didSave for workspace file)
  if SymbolManager.IsFileInWorkspace(FTestFile) then
    SymbolManager.Reload(FTestCode, True);

  // Verify symbols are in database/memory
  AssertNotNull('Symbols should be available after save',
    SymbolManager.FindWorkspaceSymbols('TMyClass'));
end;

procedure TTestSymbolPersistence.TestWorkspaceSymbolAfterDidSave;
var
  Result: TJSONData;
  SymbolArray: TJSONArray;
begin
  CreateTestFile(TEST_WORKSPACE_UNIT);
  FTestCode := CodeToolBoss.LoadFile(FTestFile, True, False);
  AssertNotNull('Code buffer should be loaded', FTestCode);

  SymbolManager.WorkspacePaths.Clear;
  SymbolManager.WorkspacePaths.Add(SymbolManager.NormalizePath(ExtractFilePath(FTestFile)));

  // Initial load
  SymbolManager.Reload(FTestCode, True);

  // Modify content (simulating edit)
  FTestCode.Source := FTestCode.Source + LineEnding + '// Modified';
  SymbolManager.FileModified(FTestCode);

  // Save triggers reload for workspace files
  if SymbolManager.IsFileInWorkspace(FTestFile) then
    SymbolManager.Reload(FTestCode, True);

  // workspace/symbol should still work
  Result := SymbolManager.FindWorkspaceSymbols('');
  SymbolArray := ParseSymbols(Result.AsJSON);
  try
    AssertTrue('workspace/symbol should return results after save', SymbolArray.Count > 0);
  finally
    SymbolArray.Free;
  end;
end;

initialization
  RegisterTest(TTestSymbolPersistence);

end.
